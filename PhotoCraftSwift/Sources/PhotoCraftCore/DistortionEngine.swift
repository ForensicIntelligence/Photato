import Foundation

/// Inverse-map formulas translated from PhotoCraft distort.rs/distort2.rs (MIT OR Apache-2.0).
/// Photoshop numerical equivalence is not implied by the source translation.
public enum DistortionEngine {
  static let tau=Double.pi*2
  static func hash(_ x:UInt32,_ y:UInt32,_ seed:UInt32)->Double {
    var h=(x &* 0x8da6b343) ^ (y &* 0xd8163841) ^ (7 &* 0xcb1ab31f) ^ (seed &* 0x9e3779b9)
    h ^= h>>16;h=h &* 0x7feb352d;h ^= h>>15;h=h &* 0x846ca68b;h ^= h>>16
    return Double(h>>8)/16777216
  }
  static func shape(_ phase:Double,_ type:DistortionSettings.Wave)->Double {
    var p=phase.truncatingRemainder(dividingBy:tau)/tau;if p<0 { p+=1 }
    switch type { case .sine:return sin(phase);case .triangle:return 1-4*abs(p-0.5);case .square:return p<0.5 ? 1:-1 }
  }
  public static func curve(_ points:[DistortionSettings.Point],at t:Double)->Double {
    guard let first=points.first,let last=points.last else{return 0}
    if t<=first.position {return first.offset};if t>=last.position{return last.offset}
    let i=(0..<(points.count-1)).first{t<=points[$0+1].position} ?? 0
    let a=points[i],b=points[i+1],p=points[max(0,i-1)],q=points[min(points.count-1,i+2)],span=b.position-a.position
    let u=(t-a.position)/span,u2=u*u,u3=u2*u
    let m1=i>0 ? (b.offset-p.offset)/(b.position-p.position)*span:b.offset-a.offset
    let m2=i+2<points.count ? (q.offset-a.offset)/(q.position-a.position)*span:b.offset-a.offset
    return (2*u3-3*u2+1)*a.offset+(u3-2*u2+u)*m1+(-2*u3+3*u2)*b.offset+(u3-u2)*m2
  }
  struct Mapping {
    let kind:RasterFilter.Kind,s:DistortionSettings,w:Int,h:Int
    var rows=[Double](),columns=[Double](),mapBytes=[UInt8](),sourceSamples=[Float]()
    let reference:IntRect
    let transform:Transform2D
    let inverse:Transform2D
    init(_ kind:RasterFilter.Kind,_ s:DistortionSettings,_ w:Int,_ h:Int,reference:IntRect?=nil,transform:Transform2D = .identity)throws {
      self.kind=kind;self.s=s;self.w=w;self.h=h;self.reference=reference ?? IntRect(x:0,y:0,width:w,height:h);self.transform=transform;self.inverse=try transform.inverted()
      if let map=s.source?.map{sourceSamples=map.values}
      if let map=s.map {mapBytes=Array(map.samples)}
      if kind == .shear { rows=(0..<h).map{curve(s.points,at:(Double($0)+0.5)/Double(h))*Double(w)/2} }
      if kind == .wave {
        rows=Array(repeating:0,count:h);columns=Array(repeating:0,count:w)
        for i in 0..<s.generators {
          try Task.checkCancellation()
          let length=s.wavelengthMin+(s.wavelengthMax-s.wavelengthMin)*hash(UInt32(i),1,s.seed)
          let amplitude=s.amplitudeMin+(s.amplitudeMax-s.amplitudeMin)*hash(UInt32(i),2,s.seed)
          let p=hash(UInt32(i),3,s.seed)*tau,q=hash(UInt32(i),4,s.seed)*tau
          for y in 0..<h {rows[y]+=amplitude*shape(tau*(Double(y)+0.5)/length+p,s.waveType)}
          for x in 0..<w {columns[x]+=amplitude*shape(tau*(Double(x)+0.5)/length+q,s.waveType)}
        }
        rows=rows.map{$0/Double(s.generators)*s.horizontalScale/100};columns=columns.map{$0/Double(s.generators)*s.verticalScale/100}
      }
    }
    func point(_ x:Double,_ y:Double)->(Double,Double) {
      let cx=Double(w)/2,cy=Double(h)/2,rr=min(cx,cy),dx=x-cx,dy=y-cy,r=hypot(dx,dy)
      switch kind {
      case .shear:return (x-rows[min(h-1,max(0,Int(y)))],y)
      case .wave:return (x+rows[min(h-1,max(0,Int(y)))],y+columns[min(w-1,max(0,Int(x)))])
      case .displace:
        if let map=s.source?.map {
          let q=transform.point(x,y)
          guard Float(q.x).isFinite,Float(q.y).isFinite else{return(.nan,.nan)}
          let lx=Float(q.x)-Float(reference.x),ly=Float(q.y)-Float(reference.y),mw=Float(map.width),mh=Float(map.height)
          let u=s.fit == .stretchToFit ? lx/Float(max(1,reference.width))*mw:lx-floor(lx/mw)*mw
          let v=s.fit == .stretchToFit ? ly/Float(max(1,reference.height))*mh:ly-floor(ly/mh)*mh
          guard u.isFinite,v.isFinite else{return(.nan,.nan)}
          func sample(_ channel:Int)->Float {
            let fx=u-0.5,fy=v-0.5,px=floor(fx),py=floor(fy),a=fx-px,b=fy-py
            // Clamp before converting possibly huge finite source geometry to Int.
            func at(_ xx:Float,_ yy:Float)->Float {let ix=Int(min(Float(map.width-1),max(0,xx))),iy=Int(min(Float(map.height-1),max(0,yy)));return sourceSamples[(iy*map.width+ix)*map.channels+channel]}
            let top=at(px,py)+(at(px+1,py)-at(px,py))*a,bottom=at(px,py+1)+(at(px+1,py+1)-at(px,py+1))*a
            return top+(bottom-top)*b
          }
          let dx=(sample(0)-0.5)*2*(Float(s.horizontalScale)/100*128),dy=(sample(map.channels-1)-0.5)*2*(Float(s.verticalScale)/100*128)
          let local=inverse.point(Double(Float(q.x)+dx),Double(Float(q.y)+dy));return(local.x,local.y)
        }
        guard let map=s.map else{return (x,y)}
        let u=s.fit == .stretchToFit ? x/Double(w)*Double(map.width):x.truncatingRemainder(dividingBy:Double(map.width))
        let v=s.fit == .stretchToFit ? y/Double(h)*Double(map.height):y.truncatingRemainder(dividingBy:Double(map.height))
        func sample(_ channel:Int)->Double {
          let fx=u-0.5,fy=v-0.5,x0=Int(floor(fx)),y0=Int(floor(fy)),a=fx-floor(fx),b=fy-floor(fy)
          func get(_ xx:Int,_ yy:Int)->Double {Double(mapBytes[(min(map.height-1,max(0,yy))*map.width+min(map.width-1,max(0,xx)))*map.channels+channel])}
          let top=get(x0,y0)*(1-a)+get(x0+1,y0)*a,bottom=get(x0,y0+1)*(1-a)+get(x0+1,y0+1)*a
          return top*(1-b)+bottom*b
        }
        return (x+(sample(0)-128)*s.horizontalScale/100,y+(sample(map.channels-1)-128)*s.verticalScale/100)
      case .twirl:
        if r>=rr{return(x,y)};let t=s.angle*Double.pi/180*(1-r/rr);return(cx+dx*cos(t)-dy*sin(t),cy+dx*sin(t)+dy*cos(t))
      case .pinch:
        if r>=rr || r==0{return(x,y)};let rs=rr*pow(r/rr,1-s.amount/200);return(cx+dx*rs/r,cy+dy*rs/r)
      case .spherize:
        func sphere(_ v:Double)->Double { let target=s.amount>=0 ? asin(min(1,v))*2/Double.pi:sin(v*Double.pi/2);return v+abs(s.amount)/100*(target-v) }
        switch s.sphereMode {
        case .horizontalOnly:return(cx+(dx<0 ? -1:1)*cx*sphere(abs(dx)/cx),y)
        case .verticalOnly:return(x,cy+(dy<0 ? -1:1)*cy*sphere(abs(dy)/cy))
        case .normal:if r>=rr || r==0{return(x,y)};let rs=rr*sphere(r/rr);return(cx+dx*rs/r,cy+dy*rs/r)
        }
      case .ripple:
        let length:Double=s.rippleSize == .small ? 8:s.rippleSize == .medium ? 16:32,amp=s.amount/100*length/8
        return(x+amp*sin(tau*y/length),y+amp*sin(tau*x/length))
      case .polarCoordinates:
        if s.polarMode == .rectangularToPolar {var theta=atan2(dx,-dy);if theta<0{theta+=tau};return(theta/tau*Double(w),r/rr*Double(h))}
        let theta=x/Double(w)*tau,rad=y/Double(h)*rr;return(cx+rad*sin(theta),cy-rad*cos(theta))
      case .zigzag:
        if r>=rr || r==0{return(x,y)};let k=max(0.5,s.ridges),rn=r/rr,v=sin(tau*k*rn)*(1-rn)*s.amount/100
        let radial=s.zigzagStyle == .aroundCenter ? 0:v*rr/(s.zigzagStyle == .pondRipples ? 8*k:4*k)
        let angular=s.zigzagStyle == .outFromCenter ? 0:v*Double.pi/(s.zigzagStyle == .pondRipples ? 4*k:2*k)
        let th=atan2(dy,dx)+angular,rs=max(0,r+radial);return(cx+rs*cos(th),cy+rs*sin(th))
      default:return(x,y)
      }
    }
  }
  private static func sourceSample(_ source:Surface,at local:(Double,Double),mapping:Mapping,settings:DistortionSettings)throws->Pixel {
    let q=mapping.transform.point(local.0,local.1),fx=Float(q.x)-0.5,fy=Float(q.y)-0.5
    guard fx.isFinite,fy.isFinite else{throw CraftError.invalid("Nonfinite source displacement coordinates.")}
    let floorX=floor(fx),floorY=floor(fy),a=fx-floorX,b=fy-floorY
    let x0=Int(min(Double(Int32.max),max(Double(Int32.min),Double(floorX)))),y0=Int(min(Double(Int32.max),max(Double(Int32.min),Double(floorY))))
    let area=mapping.reference
    func pixel(_ x:Int,_ y:Int)throws->Pixel {
      var xx=x,yy=y
      if x<area.x || y<area.y || x>=area.x+area.width || y>=area.y+area.height {
        switch settings.edge {
        case .transparent:return .clear
        case .repeatEdge:xx=min(area.x+area.width-1,max(area.x,x));yy=min(area.y+area.height-1,max(area.y,y))
        case .wrapAround:xx=area.x+((x-area.x)%area.width+area.width)%area.width;yy=area.y+((y-area.y)%area.height+area.height)%area.height
        }
      }
      let p=mapping.inverse.point(Double(xx)+0.5,Double(yy)+0.5)
      guard p.x.isFinite,p.y.isFinite else{throw CraftError.invalid("Nonfinite source sampling transform.")}
      if p.x<0 || p.y<0 || p.x>=Double(source.width) || p.y>=Double(source.height){return .clear}
      return source.depth == .f32 ? source.linearPixel(x:Int(floor(p.x)),y:Int(floor(p.y))):source.pixel(x:Int(floor(p.x)),y:Int(floor(p.y)))
    }
    let weights:[Float]=[(1-a)*(1-b),a*(1-b),(1-a)*b,a*b],dx=[0,1,0,1],dy=[0,0,1,1]
    var rgb=SIMD3<Float>.zero,alpha:Float=0
    for i in 0..<4 where weights[i]>0 {
      let p=try pixel(x0+dx[i],y0+dy[i]);guard p.isFinite else{throw CraftError.invalid("Nonfinite displacement input.")}
      for c in 0..<3{rgb[c]+=p.rgb[c]*p.a*weights[i]};alpha+=p.a*weights[i]
    }
    let value=alpha>0 ? Pixel(rgb.x/alpha,rgb.y/alpha,rgb.z/alpha,alpha):Pixel(rgb.x,rgb.y,rgb.z,alpha)
    guard value.isFinite else{throw CraftError.invalid("Nonfinite displacement result.")};return value
  }
  public static func render(_ source:Surface,kind:RasterFilter.Kind,settings:DistortionSettings,referenceBounds:IntRect?=nil,pixelToDocument:Transform2D = .identity)throws->Surface {
    try settings.validate(kind:kind)
    guard source.width<=RasterFilterEngine.maximumPixels/source.height else {throw CraftError.unsupported("Distortion filters support up to 8,388,608 pixels.")}
    if settings.isIdentity(kind){return source}
    let reference=referenceBounds ?? IntRect(x:0,y:0,width:source.width,height:source.height)
    guard reference.width>0,reference.height>0,reference.width<=Surface.maxDimension,reference.height<=Surface.maxDimension,reference.x>=Int(Int32.min),reference.y>=Int(Int32.min),reference.x<=Int(Int32.max)-reference.width,reference.y<=Int(Int32.max)-reference.height else{throw CraftError.invalid("Invalid displacement reference bounds.")}
    let map=try Mapping(kind,settings,source.width,source.height,reference:reference,transform:pixelToDocument),w=source.width,h=source.height,linear=source.depth == .f32
    var result=source
    let wrap=[RasterFilter.Kind.displace,.wave,.shear].contains(kind) && settings.edge == .wrapAround
    let transparent=kind == .polarCoordinates || settings.edge == .transparent
    func pixel(_ x:Int,_ y:Int)->Pixel {
      if transparent && (x<0 || y<0 || x>=w || y>=h){return .clear}
      let xx=wrap ? ((x%w)+w)%w:min(w-1,max(0,x)),yy=wrap ? ((y%h)+h)%h:min(h-1,max(0,y))
      return linear ? source.linearPixel(x:xx,y:yy):source.pixel(x:xx,y:yy)
    }
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let q=map.point(Double(x)+0.5,Double(y)+0.5)
      guard q.0.isFinite,q.1.isFinite,abs(q.0)<Double(Int.max/2),abs(q.1)<Double(Int.max/2) else{throw CraftError.invalid("Displacement coordinates exceed the supported numeric range.")}
      if abs(q.0-Double(x)-0.5)<1e-12 && abs(q.1-Double(y)-0.5)<1e-12 {continue}
      if settings.source != nil {
        let value=try sourceSample(source,at:q,mapping:map,settings:settings)
        if linear{result.setLinearPixel(x:x,y:y,value)}else{result.setPixel(x:x,y:y,value)};continue
      }
      let fx=q.0-0.5,fy=q.1-0.5,x0=Int(floor(fx)),y0=Int(floor(fy)),a=fx-floor(fx),b=fy-floor(fy)
      let values=[pixel(x0,y0),pixel(x0+1,y0),pixel(x0,y0+1),pixel(x0+1,y0+1)],weights=[(1-a)*(1-b),a*(1-b),(1-a)*b,a*b]
      var sum=SIMD4<Double>.zero
      for i in 0..<4 {let p=values[i];guard p.isFinite else{throw CraftError.invalid("Nonfinite distortion input.")};let k=weights[i]*Double(p.a);sum+=SIMD4(Double(p.r)*k,Double(p.g)*k,Double(p.b)*k,k)}
      let value=sum.w>1e-15 ? Pixel(Float(sum.x/sum.w),Float(sum.y/sum.w),Float(sum.z/sum.w),Float(sum.w)):.clear
      guard value.isFinite else{throw CraftError.invalid("Nonfinite distortion result.")}
      if linear{result.setLinearPixel(x:x,y:y,value)}else{result.setPixel(x:x,y:y,value)}
    }}
    return result
  }
  static func apply(_ settings:DistortionSettings,kind:RasterFilter.Kind,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws {
    let matrix=document.layers[index].coordinateTransform,reference=document.selection.flatMap{$0.width>0 && $0.height>0 ? $0:nil} ?? IntRect(x:0,y:0,width:document.width,height:document.height)
    let edited=try render(source,kind:kind,settings:settings,referenceBounds:settings.source == nil ? nil:reference,pixelToDocument:settings.source == nil ? .identity:matrix),protect=document.isTransparencyLocked(layerID),linear=document.depth == .f32
    var result=source
    for y in 0..<source.height {try Task.checkCancellation();for x in 0..<source.width {
      let q=matrix.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)))
      if coverage<=0{continue}
      let before=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      var after=linear ? edited.linearPixel(x:x,y:y):edited.pixel(x:x,y:y)
      if before==after{continue};if protect{if before.a==0{continue};after.a=before.a}
      let value=before.mixing(after,coverage:coverage)
      if linear{result.setLinearPixel(x:x,y:y,value)}else{result.setPixel(x:x,y:y,value)}
    }}
    document.layers[index].content = .raster(result)
  }
}
