import Foundation

public enum BlurGalleryEngine {
  typealias Sample = SIMD4<Double>
  static func smooth(_ a:Double,_ b:Double,_ x:Double)->Double { let t=max(0,min(1,(x-a)/max(1e-9,b-a)));return t*t*(3-2*t) }
  static func ellipse(_ p:BlurGallerySettings.Pin,_ x:Double,_ y:Double,_ w:Int,_ h:Int)->(Double,Double,Double) {
    let ss=Double(min(w,h)),a=p.angle * .pi/180,dx=x-p.x*Double(w),dy=y-p.y*Double(h)
    let u=(dx*cos(a)+dy*sin(a))/(p.radiusX*ss),v=(-dx*sin(a)+dy*cos(a))/(p.radiusY*ss),m=2+p.roundness*0.06
    return (pow(pow(abs(u),m)+pow(abs(v),m),1/m),u,v)
  }
  /// Rust-source field weighting and focus profiles, evaluated at source pixel centers.
  public static func amount(_ settings:BlurGallerySettings, mode:BlurGallerySettings.Mode, x:Double,y:Double,width:Int,height:Int)->Double {
    let pins=settings.pins(mode)
    guard !pins.isEmpty else { return 0 }
    switch mode {
    case .field:
      var sum=0.0,total=0.0
      for p in pins { let dx=x-p.x*Double(width),dy=y-p.y*Double(height),weight=1/(dx*dx+dy*dy+1);sum += weight*p.blur;total += weight };return sum/total
    case .iris:
      return pins.map { p in p.blur*smooth(p.feather,1,ellipse(p,x,y,width,height).0) }.min() ?? 0
    case .tiltShift:
      return pins.map { p in let a=p.angle * .pi/180,d=abs((x-p.x*Double(width))*sin(a)+(y-p.y*Double(height))*cos(a))/Double(min(width,height));return p.blur*smooth(p.focus,p.focus+p.transition,d) }.min() ?? 0
    case .spin: return pins.map { p in p.blurAngle*(1-smooth(p.feather,1,ellipse(p,x,y,width,height).0)) }.max() ?? 0
    case .path:return 0
    }
  }
  static func sample(_ input:[Sample],_ w:Int,_ h:Int,_ x:Double,_ y:Double)->Sample {
    let x=max(0,min(Double(w-1),x)),y=max(0,min(Double(h-1),y)),x0=Int(x),y0=Int(y),x1=min(w-1,x0+1),y1=min(h-1,y0+1),fx=x-Double(x0),fy=y-Double(y0)
    return (input[y0*w+x0]*(1-fx)+input[y0*w+x1]*fx)*(1-fy)+(input[y1*w+x0]*(1-fx)+input[y1*w+x1]*fx)*fy
  }
  static func variable(_ input:[Sample],_ w:Int,_ h:Int,_ amounts:[Double]) throws -> [Sample] {
    let maximum=(amounts.max() ?? 0)*0.6
    guard maximum>=0.3 else { return input }
    let levels=[0.0]+(0..<6).map { maximum/pow(2,Double(5-$0)) }
    var result=[Sample](repeating:.zero,count:input.count)
    for (k,sigma) in levels.enumerated() {
      try Task.checkCancellation()
      let data=k==0 ? input:try RasterFilterEngine.gaussian(input,w,h,sigma)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        let i=y*w+x,s=amounts[i]*0.6
        let weight:Double
        if k>0,s>=levels[k-1],s<=sigma { weight=(s-levels[k-1])/max(1e-9,sigma-levels[k-1]) }
        else if k+1<levels.count,s>=sigma,s<=levels[k+1] { weight=(levels[k+1]-s)/max(1e-9,levels[k+1]-sigma) }
        else if k==levels.count-1,s>=sigma { weight=1 } else { weight=0 }
        result[i] += data[i]*weight
      } }
    }
    return result
  }
  public static func pathPoints(_ path:BlurGallerySettings.MotionPath)->[PathPoint] {
    guard path.curved,path.points.count>2 else { return path.points }
    var result=[PathPoint]()
    for i in 0..<(path.points.count-1) {
      let p0=path.points[max(0,i-1)],p1=path.points[i],p2=path.points[i+1],p3=path.points[min(path.points.count-1,i+2)]
      for j in 0..<8 { let t=Double(j)/8,t2=t*t,t3=t2*t
        func coordinate(_ a:Double,_ b:Double,_ c:Double,_ d:Double)->Double { 0.5*(2*b+(-a+c)*t+(2*a-5*b+4*c-d)*t2+(-a+3*b-3*c+d)*t3) }
        result.append(.init(coordinate(p0.x,p1.x,p2.x,p3.x),coordinate(p0.y,p1.y,p2.y,p3.y)))
      }
    }
    result.append(path.points.last!);return result
  }
  struct Segment { let a:PathPoint,b:PathPoint,speed:Double,taper:Double,t0:Double,t1:Double,centered:Bool }
  static func segments(_ settings:BlurGallerySettings,_ w:Int,_ h:Int)->[Segment] {
    var result=[Segment]()
    for path in settings.paths {
      let points=pathPoints(path).map{PathPoint($0.x*Double(w),$0.y*Double(h))},lengths=zip(points,points.dropFirst()).map{hypot($1.x-$0.x,$1.y-$0.y)},total=max(1e-9,lengths.reduce(0,+));var run=0.0
      for i in lengths.indices { defer { run += lengths[i] };if lengths[i]>1e-9 { result.append(.init(a:points[i],b:points[i+1],speed:path.speed,taper:path.taper/100,t0:run/total,t1:(run+lengths[i])/total,centered:path.centered)) } }
    };return result
  }
  static func motion(_ input:[Sample],_ w:Int,_ h:Int,_ settings:BlurGallerySettings,_ mode:BlurGallerySettings.Mode,coverage:inout [Double]) throws -> [Sample] {
    var result=input;let segs=mode == .path ? segments(settings,w,h):[]
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let i=y*w+x,fx=Double(x)+0.5,fy=Double(y)+0.5
      if mode == .path {
        var dx=0.0,dy=0.0,length=0.0,ws=0.0,bias=0.0
        for seg in segs {
          let sx=seg.b.x-seg.a.x,sy=seg.b.y-seg.a.y,l2=sx*sx+sy*sy,t=max(0,min(1,((fx-seg.a.x)*sx+(fy-seg.a.y)*sy)/l2)),ox=fx-seg.a.x-sx*t,oy=fy-seg.a.y-sy*t,weight=1/(ox*ox+oy*oy+1),l=sqrt(l2)
          dx += weight*sx/l;dy += weight*sy/l;length += weight*seg.speed*(1-seg.taper*(seg.t0+(seg.t1-seg.t0)*t));bias += weight*(seg.centered ? 0.5:1);ws += weight
        }
        guard ws>0,hypot(dx,dy)>1e-9 else { continue };length /= ws
        guard length>=0.5 else { continue };let norm=hypot(dx,dy),steps=min(64,max(2,Int(ceil(length/1.5))+1));var sum=Sample.zero
        for j in 0..<steps { let offset=length*(Double(j)/Double(steps-1)-bias/ws);sum += sample(input,w,h,Double(x)+dx/norm*offset,Double(y)+dy/norm*offset) }
        result[i]=sum/Double(steps);coverage[i]=max(coverage[i],min(1,length/15))
      } else {
        for p in settings.spin where p.blurAngle>0 {
          let (e,u,v)=ellipse(p,fx,fy,w,h);if e>=1 { continue }
          let ss=Double(min(w,h)),theta=p.blurAngle * .pi/180,steps=min(64,max(2,Int(ceil(theta*e*max(p.radiusX,p.radiusY)*ss/2)))),angle=p.angle * .pi/180
          func arc(_ phi:Double)->Sample {
            let ru=u*cos(phi)-v*sin(phi),rv=u*sin(phi)+v*cos(phi),lx=ru*p.radiusX*ss,ly=rv*p.radiusY*ss
            return sample(input,w,h,p.x*Double(w)+lx*cos(angle)-ly*sin(angle)-0.5,p.y*Double(h)+lx*sin(angle)+ly*cos(angle)-0.5)
          }
          let strength=settings.strobeStrength/100
          var sum=Sample.zero
          if strength<1 {
            for j in 0..<steps { sum += arc(theta*(Double(j)/Double(steps-1)-0.5))*(1-strength)/Double(steps) }
          }
          if strength>0 {
            let duration=settings.strobeDuration * .pi/180,exposures=duration>0 ? 5:1
            for flash in 0..<settings.strobeFlashes {
              let center=settings.strobeFlashes==1 ? 0.0:theta*(Double(flash)/Double(settings.strobeFlashes-1)-0.5)
              for j in 0..<exposures {
                let offset=exposures==1 ? 0:duration*(Double(j)/Double(exposures-1)-0.5)
                sum += arc(center+offset)*strength/Double(settings.strobeFlashes*exposures)
              }
            }
          }
          let k=1-smooth(p.feather,1,e);result[i]=result[i]*(1-k)+sum*k;coverage[i]=max(coverage[i],k)
        }
      }
    } };return result
  }
  static func process(_ input:[Sample],width w:Int,height h:Int,settings s:BlurGallerySettings) throws -> (pixels:[Sample],coverage:[Double]) {
    try s.validate();var result=input,coverage=[Double](repeating:0,count:input.count)
    if s.isIdentity { return (input,coverage) }
    // Bokeh gain precedes lens sampling so highlights spread with the blur.
    if s.lightBokeh>0 {
      for i in result.indices where result[i].w>0 { let p=result[i],a=p.w,r=p.x/a,g=p.y/a,b=p.z/a,l=0.2126*r+0.7152*g+0.0722*b,k=smooth(s.lightMin,max(s.lightMin+1e-6,s.lightMax),l),gain=1+k*s.lightBokeh/10,sat=1+k*s.bokehColor/100
        result[i]=Sample((l+(r-l)*sat)*gain*a,(l+(g-l)*sat)*gain*a,(l+(b-l)*sat)*gain*a,a)
      }
    }
    for mode in BlurGallerySettings.Mode.allCases where s.enabled.contains(mode) {
      if mode == .path || mode == .spin { result=try motion(result,w,h,s,mode,coverage:&coverage) }
      else {
        var amounts=[Double](repeating:0,count:input.count)
        for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let i=y*w+x;amounts[i]=amount(s,mode:mode,x:Double(x)+0.5,y:Double(y)+0.5,width:w,height:h);coverage[i]=max(coverage[i],min(1,amounts[i]/15)) } }
        result=try variable(result,w,h,amounts)
      }
    }
    var random=RasterFilterEngine.NoiseRandom(state:UInt64(s.seed))
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let i=y*w+x,k=coverage[i]
      if k<=0 { result[i]=input[i];continue }
      if s.noiseAmount>0,result[i].w>0 {
        let p=result[i],a=p.w,light=(0.2126*p.x+0.7152*p.y+0.0722*p.z)/a,attenuation=1-s.noiseHighlights/100*smooth(0.5,1,light)
        func noise(_ channel:UInt64)->Double {
          if s.noise == .grain {
            let cell=UInt64(max(0,Int(Double(x)/s.noiseSize))) &+ UInt64(max(0,Int(Double(y)/s.noiseSize))) &* 1_000_003
            var grain=RasterFilterEngine.NoiseRandom(state:UInt64(s.seed) &+ cell &+ channel &* 97)
            return grain.noise(.gaussian)*(1-s.noiseRoughness/100)+random.noise(.gaussian)*s.noiseRoughness/100
          }
          return random.noise(s.noise == .uniform ? .uniform:.gaussian)
        }
        let mono=noise(0),color=s.noiseColor/100,g=mono*(1-color)+noise(1)*color,b=mono*(1-color)+noise(2)*color,m=s.noiseAmount/100*k*attenuation*a
        result[i] += Sample(mono*m,g*m,b*m,0)
      }
    } }
    return (result,coverage)
  }
}
