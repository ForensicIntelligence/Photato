import Foundation

extension ProceduralGeometry {
  static func flameColor(_ t:Float,_ custom:Color?)->Color {
    let alpha=pow(1-t,0.7)*0.9+0.1*(1-t),k=clamp(t)
    if let custom {
      let base=rgb(custom),core=base*0.4+SIMD3<Float>(repeating:0.6),rim=base*0.6
      let rgb=k<0.35 ? core+(base-core)*(k/0.35):base+(rim-base)*((k-0.35)/0.65)
      return Color(rgb.x,rgb.y,rgb.z,alpha*custom.w)
    }
    let stops:[(Float,SIMD3<Float>)]=[(0,SIMD3(1,0.98,0.85)),(0.2,SIMD3(1,0.86,0.35)),(0.45,SIMD3(1,0.55,0.08)),(0.75,SIMD3(0.9,0.25,0.02)),(1,SIMD3(0.6,0.08,0))]
    var rgb=stops[4].1
    for i in 0..<4 where k<=stops[i+1].0 {let u=(k-stops[i].0)/(stops[i+1].0-stops[i].0);rgb=stops[i].1+(stops[i+1].1-stops[i].1)*u;break}
    return Color(rgb.x,rgb.y,rgb.z,alpha)
  }
  static func drawFlame(_ out:inout [Primitive],_ spine:Spine,_ width:Float,_ spec:FlameSettings,_ rng:inout RNG)throws {
    let len=spine.total;guard len>=1 else{return}
    let lines=Int((spec.flameLines*0.6+3).rounded()),segs=min(160,max([6,10,16,24,36][spec.quality],Int(len/12)))
    guard out.count+6+lines*segs<=maximumPrimitives else{throw CraftError.unsupported("Flame geometry exceeds200,000 primitives; increase Interval or reduce complexity.")}
    var turb=spec.turbulent/100,jag=spec.jag/100
    switch spec.flameStyle {case .violent:turb=min(2,turb*1.8+0.2);jag=min(2,jag*1.8+0.15);case .flat:turb*=0.35;jag*=0.35;case .normal:break}
    let shape=spec.randomizeShapes ? FlameSettings.Shape.allCases[Int(rng.next()%5)]:spec.flameShape
    let opacity=spec.opacity/100,half=max(width,1)/2,seed=rng.next(),custom=spec.useCustomColor ? color(spec.color):nil
    func sway(_ u:Float)->Float {turb*half*1.6*fbm(u*1.7,seed ^ 0x5a5a)*pow(u,1.4)}
    for k in 0..<6 {
      let u=Float(k)/6*0.75+0.05,(p,d)=spine.at(u*len),o=sway(u),c=flameColor(u,custom),r=half*(1.25-u)+2
      out.append(.ellipse(p+Point(-d.y,d.x)*o,r,r*1.2,atan2(d.y,d.x),Color(c.x,c.y,c.z,0.16*opacity),Color(c.x,c.y*0.6,c.z*0.3,0)).softened(max(r,2),.add))
    }
    let lineRadius=min(10,max(0.8,half/Float(lines)*2.2))
    for li in 0..<lines {
      try Task.checkCancellation()
      let lane:Float=lines==1 ? 0:Float(li)/Float(lines-1)*2-1,lseed=seed ^ (UInt64(li) &* 0x517cc1b727220a)
      let start=(spec.flameBottomAlignment/100)*rng.f()*0.4,reach=(1-0.55*pow(abs(lane),1.5))*rng.range(0.7,1)
      let end=min(1,max(start+0.05,start+reach*(1-start))),lr=lineRadius*rng.range(0.6,1.3)
      var previous:(Point,Float,Float)?
      for k in 0...segs {
        let u=start+(end-start)*Float(k)/Float(segs),s=u*len,(p,d)=spine.at(s),normal=Point(-d.y,d.x)
        let spread:Float
        switch shape {case .parallel:spread=1-0.6*u;case .toCenter:spread=1-u;case .spread:spread=1+u;case .oval:spread=sin(ProceduralGeometry.sourcePi*(0.15+0.85*u))*1.3;case .pointed:spread=(1-u)*(1-u)}
        let flick=turb*half*0.5*fbm(s/(len*0.2+6)+Float(li)*0.37,lseed)*u+jag*half*0.25*noise(s/5,lseed ^ 0x77)*u
        let offset=lane*half*spread+sway(u)+flick,q=p+normal*offset,r=lr*(1-u*0.75),fade=clamp((u-start)/max(end-start,1e-3))
        func faded(_ c:Color,_ at:Float)->Color {var c=c;c.w=c.w*opacity*(1-fade*fade*fade)*sqrt(clamp((at-start)/0.08));return c}
        if let prev=previous {out.append(.capsule(prev.0,q,prev.1,r,faded(flameColor(prev.2,custom),prev.2),faded(flameColor(u,custom),u)).softened(1+lr*0.6,.lighten))}
        previous=(q,r,u)
      }
    }
  }
  static func flame(_ spec:FlameSettings,paths:[[Point]])throws->[Primitive] {
    try spec.validate();var out=[Primitive](),rng=RNG(spec.seed,0xf1a3)
    guard paths.count<=256,paths.reduce(0,{$0+$1.count})<=100_000 else{throw CraftError.unsupported("Flame path exceeds the geometry budget.")}
    for path in paths where !path.isEmpty {
      try Task.checkCancellation();let spine=Spine(path),total=spine.total
      guard path.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1e6 && abs($0.y)<=1e6}),total.isFinite else{throw CraftError.invalid("Invalid Flame path coordinates.")}
      if spec.flameType == .oneFlameAlongPath && path.count>=2 && total>=1 {
        try drawFlame(&out,spine,spec.width,spec,&rng)
      } else if spec.flameType == .candleLight || spec.flameType == .oneFlameAlongPath {
        let base=path[0],h=min(spec.length,400),candle=Spine([base,Point(base.x,base.y-h)])
        var c=spec;c.flameShape = .oval;c.turbulent*=0.3;c.jag*=0.2
        try drawFlame(&out,candle,max(spec.width*0.6,4),c,&rng)
        let core=flameColor(0.05,spec.useCustomColor ? color(spec.color):nil)
        out.append(.ellipse(Point(base.x,base.y-h*0.28),max(spec.width*0.12,1.5),h*0.22,0,Color(core.x,core.y,core.z,0.9*spec.opacity/100),Color(core.x,core.y,core.z,0)).softened(2,.add))
      } else {
        let first=path[0],last=path.last!,closed=path.count>2 && abs(first.x-last.x)<1 && abs(first.y-last.y)<1
        let countF=spec.adjustIntervalForLoops && closed ? max(1,(total/spec.interval).rounded()):floor(total/spec.interval)+1
        guard countF<=4096 else{throw CraftError.unsupported("Flame placement exceeds4,096 instances; increase Interval.")}
        let count=Int(countF),step=spec.adjustIntervalForLoops && closed ? total/Float(count):spec.interval
        for k in 0..<count {
          let (p,d)=spine.at(Float(k)*step),direction:Point
          switch spec.flameType {case .multipleFlamesPathDirections:direction=d;case .multipleFlamesOneDirection:let a=spec.angle*(ProceduralGeometry.sourcePi/180);direction=Point(sin(a),-cos(a));default:direction=Point(d.y,-d.x)}
          let variation:Float=spec.flameType == .multipleFlamesVariousLength ? 0.7:0
          let len=spec.randomizeLength || variation>0 ? spec.length*rng.range(1-max(variation,0.4),1+max(variation,0.4)*0.5):spec.length
          try drawFlame(&out,Spine([p,p+direction*len]),spec.width,spec,&rng)
        }
      }
    };guard out.count<=maximumPrimitives else{throw CraftError.unsupported("Flame geometry exceeds its budget.")};return out
  }
}
