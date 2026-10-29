import Foundation

extension ProceduralGeometry {
  struct Border {
    var x:Float,y:Float,w:Float,h:Float
    var total:Float {2*(w+h)}
    func at(_ s0:Float)->(Point,Point,Point) {
      var s=s0.truncatingRemainder(dividingBy:total);if s<0{s+=abs(total)}
      if s<w {return(Point(x+s,y),Point(1,0),Point(0,1))}
      if s<w+h{return(Point(x+w,y+s-w),Point(0,1),Point(-1,0))}
      if s<2*w+h{return(Point(x+w-(s-w-h),y+h),Point(-1,0),Point(0,-1))}
      return(Point(x,y+h-(s-2*w-h)),Point(0,-1),Point(1,0))
    }
  }
  static func flower(_ out:inout [Primitive],_ c:Point,_ r:Float,_ petals:Int,_ petal:Color,_ centre:Color,_ rotation:Float) {
    for k in 0..<petals {let a=rotation+Float(k)/Float(petals)*(ProceduralGeometry.sourcePi*2),p=c+Point(cos(a)*r*0.55,sin(a)*r*0.55);out.append(.ellipse(p,r*0.5,r*0.26,a,petal,shade(rgb(petal),0.8)))}
    out.append(.ellipse(c,r*0.28,r*0.28,0,centre,shade(rgb(centre),0.75)))
  }
  static func leaf(_ out:inout [Primitive],_ p:Point,_ angle:Float,_ len:Float,_ color:Color) {
    let c=p+Point(cos(angle)*len*0.5,sin(angle)*len*0.5);out.append(.ellipse(c,len*0.5,len*0.22,angle,shade(rgb(color),1.12),shade(rgb(color),0.8)))
  }
  static func star(_ out:inout [Primitive],_ c:Point,_ r:Float,_ points:Int,_ color:Color,_ rotation:Float) {
    for k in 0..<points {let a=rotation+Float(k)/Float(points)*(ProceduralGeometry.sourcePi*2);out.append(.capsule(c,c+Point(cos(a)*r,sin(a)*r),r*0.28,0.4,color,color))}
  }
  static func pictureFrame(_ spec:PictureFrameSettings,width:Int,height:Int)throws->[Primitive] {
    try spec.validate();var out=[Primitive]()
    let short=max(Float(min(width,height)),8),margin=short*spec.margin/100,unit=short*(0.008+spec.size/100*0.05)
    let thick=max(unit*0.04+short*0.00012*spec.thickness,0.6),spacing=unit*(4-3.2*spec.arrangement/100),inset=margin+unit
    let b=Border(x:inset,y:inset,w:max(Float(width)-2*inset,1),h:max(Float(height)-2*inset,1)),total=b.total
    let countF=max(4,(total/spacing).rounded()),pathF=max(8,ceil(total/2))
    guard countF<8192,pathF*Float(spec.lines)<Float(maximumPrimitives)/2 else{throw CraftError.unsupported("Picture Frame geometry exceeds its budget; reduce canvas aspect ratio or density.")}
    let count=Int(countF),step=total/Float(count),style=PictureFrameSettings.styles[spec.frame-1],lines=spec.lines
    var rng=RNG(spec.seed,0xf8a3e+UInt64(spec.frame))
    let vine=color(spec.vineColor),fl=color(spec.flowerColor),lf=color(spec.leafColor),white=Color(1,1,1,1),yellow=Color(0.98,0.82,0.2,1)
    func wave(_ s:Float,_ amplitude:Float,_ wavelength:Float)->Float {amplitude*sin(s/wavelength*(ProceduralGeometry.sourcePi*2))}
    func vinePath(_ out:inout [Primitive],_ amplitude:Float,_ wavelength:Float,_ color:Color,_ r:Float)throws {
      let n=Int(max(8,ceil(total/3)));var previous:Point?
      for k in 0...n {try Task.checkCancellation();let s=Float(k)/Float(n)*total,(p,_,normal)=b.at(s),q=p+normal*wave(s,amplitude,wavelength)
        if let previous {out.append(.capsule(previous,q,r,r,color,color))};previous=q}
    }
    switch style {
    case "vineWithFlowers","vineWithLeaves","ivy","roses","daisies","berries":
      let amplitude=unit*0.5,wavelength=step*2;try vinePath(&out,amplitude,wavelength,vine,thick)
      for k in 0..<count {
        try Task.checkCancellation();let s=Float(k)*step+step*0.5,(p,t,normal)=b.at(s),q=p+normal*wave(s,amplitude,wavelength),side:Float=k%2==0 ? 1:-1
        let ta=atan2(t.y,t.x),la=ta+side*0.9+rng.sym()*0.3,ll=unit*rng.range(0.9,1.2)
        switch style {
        case "vineWithFlowers":leaf(&out,q,la,ll,lf);if k%2==0 {flower(&out,q+normal*unit*0.7*side,unit*0.65,5,fl,yellow,rng.f()*6.3)}
        case "vineWithLeaves":leaf(&out,q,la,ll,lf);leaf(&out,q,ta-side*0.9,ll*0.8,lf)
        case "ivy":for j in 0..<3 {let a=la+(Float(j)-1)*0.7;leaf(&out,q,a,ll*0.75,shade(rgb(lf),0.75+0.15*Float(j)))}
        case "roses":leaf(&out,q,la,ll,lf);if k%3==0 {let r=unit*0.7;for (j,f) in [Float(1),0.75,0.5,0.28].enumerated(){out.append(.ellipse(q,r*f,r*f*0.9,rng.f()*3,shade(rgb(fl),0.75+0.1*Float(j)),shade(rgb(fl),0.55)))}}
        case "daisies":leaf(&out,q,la,ll*0.8,lf);if k%2==1{flower(&out,q,unit*0.6,12,white,yellow,rng.f())}
        default:leaf(&out,q,la,ll,lf);for _ in 0..<3 {let c=q+Point(rng.sym()*unit*0.4,rng.sym()*unit*0.4);out.append(.ellipse(c,unit*0.2,unit*0.2,0,shade(rgb(fl),1.2),shade(rgb(fl),0.6)))}
        }
      }
    case "bamboo":
      for edge in 0..<4 {
        let s0:Float,l:Float
        switch edge {case 0:s0=0;l=b.w;case 1:s0=b.w;l=b.h;case 2:s0=b.w+b.h;l=b.w;default:s0=2*b.w+b.h;l=b.h}
        let (a,_,_)=b.at(s0+0.01),(z,_,_)=b.at(s0+l-0.01),joints=Int(max(1,(l/(spacing*2)).rounded()))
        for j in 0..<joints {try Task.checkCancellation();let f0=Float(j)/Float(joints),f1=Float(j+1)/Float(joints),p0=a+(z-a)*f0,p1=a+(z-a)*f1
          out.append(.capsule(p0,p1,unit*0.35,unit*0.35,vine,shade(rgb(vine),0.8)));out.append(.disc(p1,unit*0.4,shade(rgb(vine),0.7)))}
        for _ in 0..<max(1,joints/2) {let f=rng.f(),p=a+(z-a)*f;leaf(&out,p,rng.f()*6.3,unit*1.4,lf)}
      }
    case "waves","zigzag","doubleLine","rope":
      for li in 0..<lines {
        let offset=(Float(li)-Float(lines-1)/2)*thick*4,n=Int(max(8,ceil(total/2)));var previous:Point?
        for k in 0...n {
          try Task.checkCancellation();let s=Float(k)/Float(n)*total,(p,_,normal)=b.at(s),o:Float
          if style=="waves" {o=offset+wave(s+Float(li)*step*0.25,unit*0.4,step)}
          else if style=="zigzag" {let ph=(s/step).truncatingRemainder(dividingBy:1);o=offset+unit*0.4*(4*abs(ph-0.5)-1)}else{o=offset}
          let q=p+normal*o
          if style=="rope" {if k%2==0 {let (_,t,_)=b.at(s);out.append(.ellipse(q,unit*0.45,unit*0.2,atan2(t.y,t.x)+0.7,shade(rgb(vine),1.1),shade(rgb(vine),0.65)))}}
          else if let previous {out.append(.capsule(previous,q,thick,thick,vine,vine))};previous=q
        }
        if style=="doubleLine" {
          let inner=Border(x:b.x+unit*0.6+offset,y:b.y+unit*0.6+offset,w:b.w-2*(unit*0.6+offset),h:b.h-2*(unit*0.6+offset))
          guard inner.total != 0 else{throw CraftError.invalid("Frame inner border has zero perimeter; reduce line count or thickness.")}
          for e in 0..<4 {let (p,_,_)=inner.at([0,inner.w,inner.w+inner.h,2*inner.w+inner.h][e]),(q,_,_)=inner.at([inner.w,inner.w+inner.h,2*inner.w+inner.h,inner.total-0.001][e]);out.append(.capsule(p,q,thick*0.6,thick*0.6,vine,vine))}
        }
      }
      if style=="doubleLine" {for e in 0..<4 {let (p,_,_)=b.at([0,b.w,b.w+b.h,2*b.w+b.h][e]);out.append(.ellipse(p,unit*0.45,unit*0.45,ProceduralGeometry.sourcePi/4,fl,fl))}}
    case "dots","scallops","snowflakes","stars","hearts":
      for k in 0..<count {
        try Task.checkCancellation();let s=Float(k)*step,(p,t,normal)=b.at(s),ta=atan2(t.y,t.x)
        switch style {
        case "dots":let r=unit*(k%2==0 ? 0.4:0.22);out.append(.ellipse(p,r,r,0,shade(rgb(fl),1.15),shade(rgb(fl),0.75)))
        case "scallops":let (c0,_,_)=b.at(s-step*0.5),mid=(c0+p)/2,r=step*0.5
          func point(_ a:Float)->Point {Point(mid.x-t.x*r*cos(a)-normal.x*r*sin(a),mid.y-t.y*r*cos(a)-normal.y*r*sin(a))}
          for j in 0..<8 {out.append(.capsule(point(ProceduralGeometry.sourcePi*Float(j)/8),point(ProceduralGeometry.sourcePi*Float(j+1)/8),thick,thick,vine,vine))}
        case "snowflakes":let r=unit*0.6,c=Color(0.85,0.92,1,1)
          for j in 0..<6 {let a=ta+Float(j)*(ProceduralGeometry.sourcePi/3),e=p+Point(cos(a)*r,sin(a)*r);out.append(.capsule(p,e,max(thick*0.6,0.6),max(thick*0.4,0.5),c,c))
            let m=p+Point(cos(a)*r*0.6,sin(a)*r*0.6)
            for side:Float in [-0.7,0.7] {let end=m+Point(cos(a+side)*r*0.3,sin(a+side)*r*0.3);out.append(.capsule(m,end,max(thick*0.4,0.5),0.4,c,c))}
          }
        case "stars":star(&out,p,unit*0.55,5,k%2==0 ? yellow:fl,ta-ProceduralGeometry.sourcePi/2)
        default:let r=unit*0.3,l=Point(p.x-t.x*r*0.8-normal.x*r*0.3,p.y-t.y*r*0.8-normal.y*r*0.3),right=Point(p.x+t.x*r*0.8-normal.x*r*0.3,p.y+t.y*r*0.8-normal.y*r*0.3),tip=p+normal*r*1.6
          out.append(.capsule(l,tip,r,0.6,fl,fl));out.append(.capsule(right,tip,r,0.6,fl,fl))
        }
      }
    default:break
    }
    guard out.count<=maximumPrimitives else{throw CraftError.unsupported("Frame geometry exceeds200,000 primitives.")}
    let fade=spec.fade/100
    if fade>0 {let centre=Point(Float(width)/2,Float(height)/2)
      for i in out.indices {let c=out[i].origin-centre,edge=clamp(max(abs(c.x)/(b.w/2),abs(c.y)/(b.h/2))),k=clamp(1-fade*(1-edge)*8);out[i].c0.w*=k;out[i].c1.w*=k}
    };return out
  }
}
