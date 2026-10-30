import Foundation

// Counter-based randomness follows PhotoCraft paint/rng.rs; input chunking never changes jitter.
enum BrushRandom {
  static func mix(_ value:UInt64)->UInt64 {
    var z=value &+ 0x9E3779B97F4A7C15;z=(z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9;z=(z ^ (z >> 27)) &* 0x94D049BB133111EB;return z ^ (z >> 31)
  }
  static func value(_ seed:UInt64,_ index:UInt64,_ stream:UInt64)->Double {
    Double(mix(seed ^ mix(index &* 0xD1B54A32D192ED03 ^ stream &* 0x8CB92BA72F3D8DD7)) >> 40)/16777216
  }
  static func pixel(_ x:Int,_ y:Int,_ seed:UInt64)->Double {
    let key=UInt64(UInt32(truncatingIfNeeded:x)) << 32 | UInt64(UInt32(truncatingIfNeeded:y));return Double(mix(key ^ seed &* 0xA24BAED4963EE407) >> 40)/16777216
  }
}
extension StrokePoint {
  func interpolated(to b:Self,by t:Double)->Self {
    func v(_ a:Double?,_ b:Double?,_ d:Double=0)->Double { (a ?? d)+((b ?? d)-(a ?? d))*t }
    return .init(x:x+(b.x-x)*t,y:y+(b.y-y)*t,pressure:pressure+(b.pressure-pressure)*Float(t),tiltX:v(tiltX,b.tiltX),tiltY:v(tiltY,b.tiltY),rotation:v(rotation,b.rotation),wheel:v(wheel,b.wheel,1),time:v(time,b.time))
  }
  func validatedBrushInput() throws {
    guard x.isFinite,y.isFinite,abs(x)<=1_000_000,abs(y)<=1_000_000,pressure.isFinite,(0...1).contains(pressure) else { throw CraftError.invalid("Invalid brush point.") }
    for (value,range) in [(tiltX,-90.0...90),(tiltY,-90.0...90),(rotation,-360.0...360),(wheel,0.0...1),(time,0.0...3_600_000)] {
      if let value { guard value.isFinite,range.contains(value) else { throw CraftError.invalid("Invalid brush tablet sample or timestamp.") } }
    }
  }
}
struct BrushStep {
  var point:StrokePoint
  var direction:Double
  var initialDirection:Double
  var index:UInt64
}
struct BrushDab {
  var x:Double,y:Double,radius:Double,angle:Double,roundness:Double
  var flipX:Bool,flipY:Bool
  var flow:Double,opacity:Double,color:Pixel,depth:Double
  var projectionAngle=0.0,projectionScale=1.0
}
/// Tracks the same smoothing geometry used by the painter without raster work.
/// Native input uses this to stop its clock once a held stroke has caught up.
public struct BrushSmoothingCursor {
  private var smoother: BrushSmoother
  public init(settings: BrushSmoothing, zoom: Double) {
    smoother = BrushSmoother(settings: settings, zoom: zoom)
  }
  public mutating func append(_ point: StrokePoint) { _ = smoother.push(point) }
  public var needsStationarySample: Bool {
    let settings = smoother.settings
    guard settings.amount > 0, settings.catchUp, !settings.pulledString,
      let position = smoother.position, let target = smoother.last else { return false }
    return hypot(target.x - position.x, target.y - position.y) > 0.01
  }
}
private struct BrushSmoother {
  let settings:BrushSmoothing
  let zoom:Double
  var position:StrokePoint?
  var last:StrokePoint?
  mutating func push(_ p:StrokePoint)->[StrokePoint] {
    let prior=last;last=p
    guard settings.amount>0 else { position=p;return [p] }
    guard let pos=position else { position=p;return [p] }
    if settings.pulledString {
      let length=settings.amount*100/(settings.adjustForZoom ? zoom:1),distance=hypot(p.x-pos.x,p.y-pos.y)
      guard distance>length else { return [] }
      var next=p;let k=(distance-length)/distance;next.x=pos.x+(p.x-pos.x)*k;next.y=pos.y+(p.y-pos.y)*k;position=next;return [next]
    }
    let dt=(p.time ?? 0)-(prior?.time ?? 0),n=settings.catchUp && dt>0 ? Int(min(64,max(1,(dt/16).rounded()))):1
    var out:[StrokePoint]=[],current=pos
    for _ in 0..<n { var q=p;let k=1-min(0.95,settings.amount);q.x=current.x+(p.x-current.x)*k;q.y=current.y+(p.y-current.y)*k;out.append(q);current=q }
    position=current;return out
  }
  mutating func finish()->[StrokePoint] {
    guard settings.amount>0,settings.catchUpOnEnd,let p=position,let last,p.x != last.x || p.y != last.y else { return [] };position=last;return [last]
  }
}
private struct BrushWalker {
  var last:StrokePoint?
  var first:StrokePoint?
  var nextAt=0.0
  var initial:Double?
  var direction=0.0
  var index:UInt64=0
  var interval:Double?
  var timeAccum=0.0
  var speed:Double?
  var speedAccum=0.0
  mutating func emit(_ p:StrokePoint,_ out:inout [BrushStep])throws {
    guard index<200_000 else { throw CraftError.invalid("Brush stroke exceeds 200,000 spacing steps.") }
    if index % 256 == 0 { try Task.checkCancellation() }
    out.append(.init(point:p,direction:direction,initialDirection:initial ?? direction,index:index));index += 1
  }
  mutating func push(_ p:StrokePoint,length:(StrokePoint)->Double)throws->[BrushStep] {
    guard let a=last else { last=p;first=p;nextAt=length(p);return [] }
    var out:[BrushStep]=[];let dx=p.x-a.x,dy=p.y-a.y,len=hypot(dx,dy)
    if len>1e-9 { direction=atan2(-dy,dx);if initial==nil { initial=direction } }
    if let f=first { first=nil;try emit(f,&out) }
    if len>1e-9 {
      if let speed {
        let dt=(p.time ?? 0)-(a.time ?? 0)
        if dt>0 {
          speedAccum += dt;let maxCount=Int(max(1,ceil(len/0.5)));var n=0
          while speedAccum>=speed && n<maxCount { speedAccum -= speed;try emit(a.interpolated(to:p,by:min(1,max(0,(dt-speedAccum)/dt))),&out);n += 1 }
          if n==maxCount { speedAccum.formTruncatingRemainder(dividingBy:speed) }
        } else { try emit(p,&out) }
      } else {
        while nextAt<=len+1e-9 { let q=a.interpolated(to:p,by:min(1,nextAt/len));try emit(q,&out);nextAt += max(0.25,length(q)) };nextAt -= len
      }
    }
    if let interval {
      let dt=(p.time ?? 0)-(a.time ?? 0)
      if dt>0 { timeAccum += dt;while timeAccum>=interval { timeAccum -= interval;try emit(a.interpolated(to:p,by:min(1,max(0,(dt-timeAccum)/dt))),&out) } }
    }
    last=p;return out
  }
  mutating func finish()throws->[BrushStep] { var out:[BrushStep]=[];if let f=first { first=nil;try emit(f,&out) };return out }
}
enum BrushDynamics {
  static func control(_ c:BrushControl,_ fade:Int,_ s:BrushStep)->Double {
    let p=s.point
    switch c {
    case .off,.initialDirection,.direction:return 1
    case .fade:return 1-min(1,Double(s.index)/Double(fade))
    case .penPressure:return Double(p.pressure)
    case .penTilt:return 1-min(1,hypot(p.tiltX ?? 0,p.tiltY ?? 0)/90)
    case .stylusWheel:return p.wheel ?? 1
    case .rotation:return ((p.rotation ?? 0).truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)/360
    }
  }
  static func angle(_ c:BrushControl,_ fade:Int,_ s:BrushStep)->Double {
    let p=s.point
    switch c {
    case .off:return 0
    case .fade:return 360*min(1,Double(s.index)/Double(fade))
    case .penPressure:return 360*Double(p.pressure)
    case .penTilt:return atan2(-(p.tiltY ?? 0),p.tiltX ?? 0)*180 / .pi
    case .stylusWheel:return 360*(p.wheel ?? 1)
    case .rotation:return p.rotation ?? 0
    case .initialDirection:return s.initialDirection*180 / .pi
    case .direction:return s.direction*180 / .pi
    }
  }
  static func scalar(_ d:BrushDynamic,_ s:BrushStep,_ r:Double)->Double {
    guard d.jitter>0 || d.control != .off else { return 1 }
    return max(d.minimum,(d.minimum+(1-d.minimum)*control(d.control,d.fadeSteps,s))*(1-d.jitter*r))
  }
  static func diameter(_ brush:Brush,_ b:BrushSettings,_ s:BrushStep)->Double {
    if b.shape.enabled && b.shape.size.control != .off { let d=b.shape.size;return brush.size*(d.minimum+(1-d.minimum)*control(d.control,d.fadeSteps,s)) }
    return brush.size*(b.pressureSize ? Double(s.point.pressure):1)
  }
  static func color(_ brush:Brush,_ b:BrushSettings,_ s:BrushStep,_ index:UInt64)->Pixel {
    let d=b.colorDynamics,fg=brush.color,bg=brush.backgroundColor ?? .white
    func r(_ stream:UInt64)->Double { BrushRandom.value(b.seed,index,stream) }
    let base=d.foregroundBackground.control == .off ? 0:1-control(d.foregroundBackground.control,d.foregroundBackground.fadeSteps,s)
    let t=min(1,max(0,base+(1-base)*d.foregroundBackground.jitter*r(11)))
    let red=Double(fg.r)+(Double(bg.r)-Double(fg.r))*t,green=Double(fg.g)+(Double(bg.g)-Double(fg.g))*t,blue=Double(fg.b)+(Double(bg.b)-Double(fg.b))*t
    let mx=max(red,max(green,blue)),mn=min(red,min(green,blue)),delta=mx-mn
    var h=0.0
    if delta>0 { if mx==red { h=((green-blue)/delta).truncatingRemainder(dividingBy:6) } else if mx==green { h=(blue-red)/delta+2 } else { h=(red-green)/delta+4 };h /= 6 }
    h += (2*r(12)-1)*d.hue/2;h=h-floor(h)
    var sat=min(1,max(0,(mx>0 ? delta/mx:0)+(2*r(13)-1)*d.saturation));sat=d.purity>=0 ? sat+(1-sat)*d.purity:sat*(1+d.purity)
    let v=min(1,max(0,mx+(2*r(14)-1)*d.brightness)),h6=h*6,f=h6-floor(h6),p=v*(1-sat),q=v*(1-sat*f),z=v*(1-sat*(1-f))
    let values:[Double]
    switch Int(floor(h6)) { case 0:values=[v,z,p];case 1:values=[q,v,p];case 2:values=[p,v,z];case 3:values=[p,q,v];case 4:values=[z,p,v];default:values=[v,p,q] }
    return Pixel(Float(values[0]),Float(values[1]),Float(values[2]),fg.a+(bg.a-fg.a)*Float(t))
  }
}
/// Incremental geometry generator. Canvas previews and final/API strokes use the same seed and samples.
struct BrushDabGenerator {
  let brush:Brush
  let settings:BrushSettings
  private var smoother:BrushSmoother
  private var walker:BrushWalker
  private var dualWalker=BrushWalker()
  private var nextIndex:UInt64=0
  private var dualIndex:UInt64=0
  private var strokeColor:Pixel?
  init(_ brush:Brush) {
    self.brush=brush;let b=brush.settings ?? .init();settings=b
    smoother=BrushSmoother(settings:b.smoothing,zoom:b.zoom)
    walker=BrushWalker(interval:b.buildUp ? 1000/b.buildUpRate:nil,speed:b.spacingEnabled ? nil:8)
  }
  private mutating func build(_ s:BrushStep)throws->[BrushDab] {
    let b=settings,sd=b.shape,sc=b.scattering
    let count=sc.enabled ? max(1,Int((Double(sc.count)*BrushDynamics.scalar(sc.countJitter,s,BrushRandom.value(b.seed,s.index,8))).rounded())):1
    guard nextIndex+UInt64(count)<=200_000 else { throw CraftError.invalid("Brush stroke exceeds 200,000 dabs.") }
    var out:[BrushDab]=[]
    for _ in 0..<count {
      let i=nextIndex;nextIndex += 1
      func r(_ st:UInt64)->Double { BrushRandom.value(b.seed,i,st) }
      var diameter=BrushDynamics.diameter(brush,b,s),angle=b.angle,roundness=b.roundness,fx=b.flipX,fy=b.flipY
      if sd.enabled {
        diameter *= max(sd.size.minimum,1-sd.size.jitter*r(1));angle += BrushDynamics.angle(sd.angle.control,sd.angle.fadeSteps,s)+(2*r(2)-1)*sd.angle.jitter*180
        roundness=max(0.01,roundness*BrushDynamics.scalar(sd.roundness,s,r(3)))
        if sd.flipX && r(4)<0.5 { fx.toggle() };if sd.flipY && r(5)<0.5 { fy.toggle() }
      }
      guard diameter>0 else { continue }
      var projectionAngle=0.0,projectionScale=1.0
      if sd.enabled {
        let tilt=min(90,hypot(s.point.tiltX ?? 0,s.point.tiltY ?? 0))
        if sd.size.control == .penTilt { roundness=max(0.01,roundness*(1-sd.tiltScale*0.5*tilt/90)) }
        if sd.projection { angle += s.point.rotation ?? 0;projectionAngle=atan2(-(s.point.tiltY ?? 0),s.point.tiltX ?? 0);projectionScale=max(0.05,cos(tilt * .pi/180)) }
      }
      let radius=max(0.25,diameter/2);var x=s.point.x,y=s.point.y
      if sc.enabled {
        let amount=sc.amount.jitter*BrushDynamics.control(sc.amount.control,sc.amount.fadeSteps,s)*radius,ox=(2*r(6)-1)*amount,oy=(2*r(7)-1)*amount
        if sc.bothAxes { x += ox;y += oy } else { x += sin(s.direction)*ox;y += cos(s.direction)*ox }
      }
      var opacity=b.transfer.enabled ? BrushDynamics.scalar(b.transfer.opacity,s,r(9)):1
      if b.pressureOpacity && !(b.transfer.enabled && b.transfer.opacity.control != .off) { opacity *= Double(s.point.pressure) }
      let flow=b.flow*(b.transfer.enabled ? BrushDynamics.scalar(b.transfer.flow,s,r(10)):1)
      var color=brush.color
      if b.colorDynamics.enabled {
        if b.colorDynamics.perTip { color=BrushDynamics.color(brush,b,s,i) }
        else { if strokeColor==nil { strokeColor=BrushDynamics.color(brush,b,s,0) };color=strokeColor! }
      }
      let depth=b.texture.depth*(b.texture.enabled && b.texture.eachTip ? BrushDynamics.scalar(b.texture.depthJitter,s,r(15)):1)
      out.append(.init(x:x,y:y,radius:radius,angle:angle * .pi/180,roundness:roundness,flipX:fx,flipY:fy,flow:flow,opacity:opacity,color:color,depth:depth,projectionAngle:projectionAngle,projectionScale:projectionScale))
    }
    return out
  }
  private mutating func buildDual(_ s:BrushStep)throws->[BrushDab] {
    let b=settings.dual;guard dualIndex+UInt64(b.count)<=200_000 else { throw CraftError.invalid("Dual brush stroke is too long.") };var out:[BrushDab]=[]
    for _ in 0..<b.count {
      let i=dualIndex;dualIndex += 1;let seed=settings.seed ^ 0xD0A1,radius=b.size/2
      let ox=(2*BrushRandom.value(seed,i,16)-1)*b.scatter*radius,oy=(2*BrushRandom.value(seed,i,17)-1)*b.scatter*radius
      let x=s.point.x+(b.bothAxes ? ox:sin(s.direction)*ox),y=s.point.y+(b.bothAxes ? oy:cos(s.direction)*ox)
      out.append(.init(x:x,y:y,radius:radius,angle:b.angle * .pi/180,roundness:b.roundness,flipX:b.flip && BrushRandom.value(seed,i,18)<0.5,flipY:false,flow:1,opacity:1,color:.black,depth:1))
    }
    return out
  }
  private mutating func walk(_ samples:[StrokePoint])throws->([BrushDab],[BrushDab]) {
    var primary:[BrushDab]=[],dual:[BrushDab]=[];let b=settings,brush=self.brush
    for var p in samples {
      if b.pose.enabled { if b.pose.overrideTilt { p.tiltX=b.pose.tiltX;p.tiltY=b.pose.tiltY };if b.pose.overrideRotation { p.rotation=b.pose.rotation };if b.pose.overridePressure { p.pressure=Float(b.pose.pressure) } }
      let steps=try walker.push(p) { q in max(0.5,max(1,BrushDynamics.diameter(brush,b,.init(point:q,direction:0,initialDirection:0,index:0)))*b.spacing) }
      for s in steps { primary += try build(s) }
      if b.dual.enabled { let ds=try dualWalker.push(p) { _ in max(0.5,b.dual.size*b.dual.spacing) };for s in ds { dual += try buildDual(s) } }
    }
    return (primary,dual)
  }
  mutating func push(_ samples:[StrokePoint])throws->([BrushDab],[BrushDab]) {
    var output:([BrushDab],[BrushDab])=([],[])
    for p in samples { let smoothed=smoother.push(p);let d=try walk(smoothed);output.0 += d.0;output.1 += d.1 }
    return output
  }
  mutating func finish(includingReleaseTail: Bool = true)throws->([BrushDab],[BrushDab]) {
    let end=includingReleaseTail ? smoother.finish() : [];var out=try walk(end)
    let steps=try walker.finish();for s in steps { out.0 += try build(s) }
    if settings.dual.enabled { let steps=try dualWalker.finish();for s in steps { out.1 += try buildDual(s) } }
    return out
  }
}
