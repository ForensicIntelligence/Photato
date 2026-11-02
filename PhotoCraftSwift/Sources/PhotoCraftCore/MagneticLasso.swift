import Foundation

public struct MagneticLassoSettings:Codable,Equatable,Sendable {
  public var width:Double=10
  public var contrast:Double=10
  public var frequency:Double=57
  public var stylusPressure=false
  public var antiAlias=true
  public var feather:Double=0
  public init(){}
  public func validate()throws {
    guard width.isFinite,(1...256).contains(width),contrast.isFinite,(1...100).contains(contrast),frequency.isFinite,(0...100).contains(frequency),feather.isFinite,(0...100).contains(feather) else {throw CraftError.invalid("Invalid Magnetic Lasso settings.")}
  }
}
public struct MagneticLassoEvent:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable {case move,anchor,freehand,straight,remove,width}
  public var kind:Kind
  public var point:SelectionPoint?
  public var pressure:Double
  public var width:Double?
  public init(_ kind:Kind,point:SelectionPoint?=nil,pressure:Double=0,width:Double?=nil){self.kind=kind;self.point=point;self.pressure=pressure;self.width=width}
  public func validate()throws {
    guard pressure.isFinite,(0...1).contains(pressure) else {throw CraftError.invalid("Invalid Magnetic Lasso pressure.")}
    if kind == .remove {guard point==nil,width==nil else {throw CraftError.invalid("Remove has no point or width.")};return}
    if kind == .width {guard point==nil,let width,width.isFinite,(1...256).contains(width) else {throw CraftError.invalid("Width event requires1–256 pixels.")};return}
    guard width==nil,let p=point,p.x.isFinite,p.y.isFinite,abs(p.x)<=1_000_000,abs(p.y)<=1_000_000 else {throw CraftError.invalid("Magnetic Lasso requires finite image coordinates.")}
  }
}
/// Independent gradient ridge tracer; numerical Photoshop equivalence is not established.
public struct MagneticLassoTrace:Sendable {
  public private(set) var settings:MagneticLassoSettings
  public private(set) var points:[SelectionPoint]=[]
  public private(set) var anchors:[Int]=[]
  public private(set) var cursor:SelectionPoint?
  public init(settings:MagneticLassoSettings)throws {try settings.validate();self.settings=settings}
  public mutating func append(_ event:MagneticLassoEvent,image:Surface)throws {
    try Task.checkCancellation();try event.validate()
    if event.kind == .width {settings.width=event.width!;return}
    if event.kind == .remove {
      if anchors.count>1 {anchors.removeLast()}
      if let last=anchors.last {points=Array(points.prefix(last+1));cursor=points.last};return
    }
    let point=event.point!
    guard point.x>=0,point.y>=0,point.x<Double(image.width),point.y<Double(image.height) else {throw CraftError.invalid("Trace inside the document canvas.")}
    if points.isEmpty {points=[point];anchors=[0];cursor=point;return}
    let previous=cursor ?? points.last!,dx=point.x-previous.x,dy=point.y-previous.y,distance=hypot(dx,dy)
    if event.kind == .move,distance>0 {
      let radius=settings.width*(settings.stylusPressure ? max(0.1,1-event.pressure*0.9):1)
      let count=max(1,Int(ceil(distance/max(1,radius/2))))
      guard count<=100_000,points.count+count<=250_000 else {throw CraftError.unsupported("Magnetic Lasso trace point limit exceeded.")}
      for i in 1...count {try Task.checkCancellation();let t=Double(i)/Double(count),p=SelectionPoint(previous.x+dx*t,previous.y+dy*t)
        let snapped=snap(p,normal:SelectionPoint(-dy/distance,dx/distance),radius:radius,image:image)
        if points.last != snapped {points.append(snapped);anchorIfNeeded()}
      }
    }else if points.last != point {
      guard points.count<250_000 else {throw CraftError.unsupported("Magnetic Lasso trace point limit exceeded.")}
      points.append(point)
    }
    cursor=point
    if event.kind == .anchor || event.kind == .straight {if anchors.last != points.count-1 {anchors.append(points.count-1)}}
  }
  private mutating func anchorIfNeeded() {
    guard let last=anchors.last,let p=points.last else{return}
    let spacing=2+(100-settings.frequency)*0.75
    if hypot(p.x-points[last].x,p.y-points[last].y)>=spacing {anchors.append(points.count-1)}
  }
  private func snap(_ point:SelectionPoint,normal:SelectionPoint,radius:Double,image:Surface)->SelectionPoint {
    var best=point,bestScore = -Double.infinity
    let r=max(1,Int(ceil(radius)))
    func gradient(_ x:Int,_ y:Int)->Double {
      func at(_ x:Int,_ y:Int)->Pixel {image.pixel(x:min(image.width-1,max(0,x)),y:min(image.height-1,max(0,y)))}
      let a=at(x-1,y),b=at(x+1,y),c=at(x,y-1),d=at(x,y+1)
      let horizontal=max(abs(a.r-b.r),abs(a.g-b.g),abs(a.b-b.b)),vertical=max(abs(c.r-d.r),abs(c.g-d.g),abs(c.b-d.b))
      return min(1,Double(max(horizontal,vertical)))
    }
    for offset in -r...r {
      let x=point.x+normal.x*Double(offset),y=point.y+normal.y*Double(offset)
      guard x>=0,y>=0,x<Double(image.width),y<Double(image.height) else{continue}
      let value=gradient(Int(x),Int(y));guard value>=settings.contrast/100 else{continue}
      let score=value-abs(Double(offset))/Double(r)*0.2
      if score>bestScore {bestScore=score;best=SelectionPoint(x,y)}
    }
    return best
  }
  public func mask(image:Surface,straight:Bool=false)throws->SelectionMask {
    guard points.count>=3 else {throw CraftError.invalid("Magnetic Lasso needs at least three points.")}
    var trace=self
    if !straight,let first=points.first {try trace.append(.init(.move,point:first),image:image)}
    return try SelectionMask.make(.polygon(trace.points),width:image.width,height:image.height,antiAlias:settings.antiAlias).feathered(radius:settings.feather)
  }
  public static func replay(_ events:[MagneticLassoEvent],image:Surface,settings:MagneticLassoSettings)throws->Self {
    guard !events.isEmpty,events.count<=100_000 else {throw CraftError.invalid("Magnetic Lasso supports1–100000 trace events.")}
    var trace=try Self(settings:settings)
    for event in events {try trace.append(event,image:image)}
    return trace
  }
}
