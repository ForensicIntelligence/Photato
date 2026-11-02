import Foundation
import PhotoCraftCore

/// Original effect gradient geometry and premultiplied wrapping pattern paint.
struct SourceEffectSampler:Sendable {
  let document:CraftDocument
  let anchor:PathPoint
  static func layout(_ placement:GradientPlacement,frame:IntRect)->GradientPlacement {
    var p=placement
    guard p.style == .linear || p.style == .reflected else {return p}
    let w=Double(max(1,frame.width)),h=Double(max(1,frame.height)),cx=Double(frame.x)+w/2+Double(p.offsetX)*w,cy=Double(frame.y)+h/2+Double(p.offsetY)*h
    func chord(_ angle:Double)->Double {max(1,min(w/max(abs(cos(angle)),1e-6),h/max(abs(sin(angle)),1e-6)))}
    let a=Double(p.angle)*Double.pi/180,half=chord(a)*Double(max(p.scale,1e-3))/2,dx=cos(a)*half,dy = -sin(a)*half
    func snap(_ x:Double)->Double {floor(x+1e-4)}
    let end=PathPoint(snap(cx+dx),snap(cy+dy)),start=p.style == .reflected ? PathPoint(cx,cy):PathPoint(snap(cx-dx),snap(cy-dy))
    let mid=p.style == .reflected ? PathPoint(cx,cy):PathPoint((start.x+end.x)/2,(start.y+end.y)/2),vx=end.x-start.x,vy=end.y-start.y,length=hypot(vx,vy)
    if length<0.5{return p};let angle=atan2(-vy,vx),span=p.style == .reflected ? 2*length:length
    p.angle=Float(angle*180/Double.pi);p.scale=Float(span/chord(angle));p.offsetX += Float((mid.x-cx)/w);p.offsetY += Float((mid.y-cy)/h);return p
  }
  static func coordinate(_ p:GradientPlacement,frame:IntRect,x:Float,y:Float)->Float {
    let w=Float(max(frame.width,1)),h=Float(max(frame.height,1)),cx=Float(frame.x)+w/2+p.offsetX*w,cy=Float(frame.y)+h/2+p.offsetY*h,a=p.angle*(Float.pi/180),s=sin(a),c=cos(a),dx=x-cx,dy=y-cy
    let along=dx*c-dy*s,across=dx*s+dy*c,extent=max(1,sqrt((c*w)*(c*w)+(s*h)*(s*h)))*max(p.scale,1e-3),chord=max(1,min(w/max(abs(c),1e-6),h/max(abs(s),1e-6)))*max(p.scale,1e-3),corner=0.5*(c-s)
    let t:Float
    switch p.style {
    case .linear:t=(along-corner)/chord+0.5
    case .reflected:t=abs((along-corner)/(chord/2))
    case .radial:t=sqrt(dx*dx+dy*dy)/(extent/2)
    case .diamond:t=(abs(along)+abs(across))/(extent/2)
    case .angle:let turn=(a-atan2(-dy,dx))/(2*Float.pi),r=turn.truncatingRemainder(dividingBy:1);t=r<0 ? r+1:r
    }
    return p.reverse ? 1-unit(t):unit(t)
  }
  static func gradient(_ gradient:EffectGradient,frame:IntRect,x:Float,y:Float)->Pixel {
    let t=coordinate(layout(gradient.placement,frame:frame),frame:frame,x:x,y:y),stops=gradient.stops
    let rgb:SIMD3<Float>
    if stops.isEmpty {rgb=SIMD3(repeating:t)}
    else if stops.count==1 || t<=stops[0].location {rgb=stops[0].color.rgb}
    else if let i=(1..<stops.count).first(where:{t<=stops[$0].location}) {let a=stops[i-1],b=stops[i],k=b.location>a.location ? (t-a.location)/(b.location-a.location):0;rgb=a.color.rgb+(b.color.rgb-a.color.rgb)*k}
    else {rgb=stops.last!.color.rgb}
    let opacity=gradient.opacityStops,alpha:Float
    if opacity.isEmpty {alpha=1}
    else if opacity.count==1 || t<=opacity[0][0] {alpha=opacity[0][1]}
    else if let i=(1..<opacity.count).first(where:{t<=opacity[$0][0]}) {let a=opacity[i-1],b=opacity[i],k=b[0]>a[0] ? (t-a[0])/(b[0]-a[0]):0;alpha=a[1]+(b[1]-a[1])*k}
    else {alpha=opacity.last![1]}
    return Pixel(rgb.x,rgb.y,rgb.z,alpha)
  }

}

extension SourceEffectSampler {
  struct PatternShader:Sendable {
    let surface:Surface?
    let origin:PathPoint
    let cosine:Double,sine:Double,inverseScale:Double
    init(_ pattern:EffectPattern,sampler:SourceEffectSampler) {
      surface=pattern.patternID.flatMap{sampler.document.pattern($0)?.surface}
      let base=pattern.linked ? sampler.anchor:PathPoint(0,0)
      origin=PathPoint(base.x+pattern.phase.x,base.y+pattern.phase.y)
      let a=Double(pattern.angle)*Double.pi/180;cosine=cos(a);sine=sin(a);inverseScale=pattern.scale>1e-3 ? 1/Double(pattern.scale):1
    }
    func sample(x:Double,y:Double)->Pixel {
      guard let tile=surface else {return .clear}
      let dx=x-origin.x,dy=y-origin.y,u=(dx*cosine-dy*sine)*inverseScale-0.5,v=(dx*sine+dy*cosine)*inverseScale-0.5,x0=Int(floor(u)),y0=Int(floor(v)),fx=Float(u-floor(u)),fy=Float(v-floor(v));var result=SIMD4<Float>.zero
      func wrap(_ i:Int,_ n:Int)->Int {let x=i%n;return x<0 ? x+n:x}
      for(dy,wy)in [(0,1-fy),(1,fy)] where wy != 0 {for(dx,wx)in [(0,1-fx),(1,fx)] where wx != 0 {
        let xx=wrap(x0+dx,tile.width),yy=wrap(y0+dy,tile.height),p=tile.depth == .f32 ? tile.linearPixel(x:xx,y:yy):tile.pixel(x:xx,y:yy),k=wx*wy
        result += SIMD4(p.r*p.a,p.g*p.a,p.b*p.a,p.a)*k
      }}
      guard result.w>0 else{return .clear};return Pixel(result.x/result.w,result.y/result.w,result.z/result.w,min(result.w,1))
    }
  }
  struct GradientShader:Sendable {
    let gradient:EffectGradient
    let placement:GradientPlacement
    let frame:IntRect
    init(_ gradient:EffectGradient,frame:IntRect){self.gradient=gradient;self.frame=frame;placement=SourceEffectSampler.layout(gradient.placement,frame:frame)}
    private func index(_ count:Int,_ at:(Int)->Float,_ t:Float)->Int {
      var lo=1,hi=count-1
      while lo<hi {let m=(lo+hi)/2;if t<=at(m){hi=m}else{lo=m+1}};return lo
    }
    func sample(x:Int,y:Int)->Pixel {
      let t=SourceEffectSampler.coordinate(placement,frame:frame,x:Float(x)+0.5,y:Float(y)+0.5),stops=gradient.stops
      let rgb:SIMD3<Float>
      if stops.isEmpty {rgb=SIMD3(repeating:t)}
      else if stops.count==1 || t<=stops[0].location {rgb=stops[0].color.rgb}
      else if t>stops.last!.location {rgb=stops.last!.color.rgb}
      else {let i=index(stops.count,{stops[$0].location},t),a=stops[i-1],b=stops[i],k=b.location>a.location ? (t-a.location)/(b.location-a.location):0;rgb=a.color.rgb+(b.color.rgb-a.color.rgb)*k}
      let opacity=gradient.opacityStops,alpha:Float
      if opacity.isEmpty {alpha=1}
      else if opacity.count==1 || t<=opacity[0][0] {alpha=opacity[0][1]}
      else if t>opacity.last![0] {alpha=opacity.last![1]}
      else {let i=index(opacity.count,{opacity[$0][0]},t),a=opacity[i-1],b=opacity[i],k=b[0]>a[0] ? (t-a[0])/(b[0]-a[0]):0;alpha=a[1]+(b[1]-a[1])*k}
      return Pixel(rgb.x,rgb.y,rgb.z,alpha)
    }
  }
  enum Shader {
    case color(Pixel),gradient(GradientShader),pattern(PatternShader),legacyGradient(GradientFillSampler),legacyPattern(PatternFillSampler)
    func sample(x:Int,y:Int)->Pixel {switch self {case .color(let c):return Pixel(c.r,c.g,c.b,1);case .gradient(let g):return g.sample(x:x,y:y);case .pattern(let p):return p.sample(x:Double(x)+0.5,y:Double(y)+0.5);case .legacyGradient(let g):return g.sample(x:x,y:y);case .legacyPattern(let p):return p.sample(x:Double(x)+0.5,y:Double(y)+0.5)}}
  }
  func prepare(_ effect:LayerEffect,advanced:LayerEffectAdvanced,frame:IntRect)->Shader {
    if let paint=advanced.paint {
      if let g=paint.gradient {return .gradient(GradientShader(g,frame:frame))}
      if let p=paint.pattern {return .pattern(PatternShader(p,sampler:self))}
    }
    return .color(effect.color)
  }
}
