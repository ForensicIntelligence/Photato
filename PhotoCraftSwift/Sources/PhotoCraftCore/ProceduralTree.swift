import Foundation

extension ProceduralGeometry {
  final class TreeContext {
    let kind:TreeKind,spec:TreeSettings,bark:SIMD3<Float>,leaf:SIMD3<Float>,light:Point,centre:Point,leafPixels:Float
    var rng:RNG,branches=[Primitive](),leaves=[(Float,Primitive)]()
    init(_ spec:TreeSettings,width:Int,height:Int) {
      self.spec=spec;kind=trees[spec.baseTreeType-1];let h=Float(height)*spec.size,base=Point(Float(width)*spec.x,Float(height)*spec.y)
      let angle:Float=[180,225,270,315,0][spec.lightDirection-1]*(ProceduralGeometry.sourcePi/180)
      bark=spec.customBranchColor ? spec.branchesColor.rgb:kind.bark;leaf=spec.defaultLeaves ? kind.leafColor:spec.leavesColor.rgb
      rng=RNG(spec.seed,0x7ee+UInt64(spec.baseTreeType));light=Point(cos(angle),sin(angle));centre=Point(base.x,base.y-h*0.65);leafPixels=max(0.6,h*0.012*spec.leavesSize/100)
    }
    func lightAt(_ p:Point)->Float {
      if spec.flatShading{return 1};let d=p-centre,l=max(length(d),1)
      return 0.78+0.32*((d.x*light.x+d.y*light.y)/l)+0.12*rng.sym()
    }
    func addLeaf(_ p:Point,_ dir:Float)throws {
      try Task.checkCancellation();let s=leafPixels*rng.range(0.7,1.2),ang=dir+rng.sym()*1.2,k=lightAt(p),col=leaf,primitive:Primitive
      switch kind.leaf {
      case .none:return
      case .round:primitive = .ellipse(p,s,s*0.85,ang,shade(col,k*1.1),shade(col,k*0.8))
      case .oval:primitive = .ellipse(p,s*1.2,s*0.55,ang,shade(col,k*1.1),shade(col,k*0.8))
      case .long:primitive = .ellipse(p,s*1.6,s*0.28,ang,shade(col,k*1.1),shade(col,k*0.8))
      case .heart:primitive = .ellipse(p,s*0.9,s*1.1,ang,shade(col,k*1.1),shade(col,k*0.75))
      case .needle:
        for j in 0..<7 {let a=ang+(Float(j)/6-0.5)*2.4+rng.sym()*0.15,l=s*rng.range(1.1,1.7),q=p+Point(cos(a)*l,sin(a)*l),kk=k+0.1*rng.sym()
          leaves.append((kk,.capsule(p,q,max(s*0.1,0.45),max(s*0.05,0.3),shade(col,kk*0.85),shade(col,kk*1.1))))};return
      case .blossom:primitive = .ellipse(p,s*0.75,s*0.75,0,shade(col,k*1.08),shade(col,k*0.85))
      case .frond:primitive = .ellipse(p,s*1.6,s*0.3,ang,shade(col,k),shade(col,k*0.8))
      }
      leaves.append((k+rng.f()*0.05,primitive))
      if let accent=kind.accent,rng.f()<0.12 {let q=p+Point(rng.sym()*s,rng.sym()*s),r=max(s*0.45,1);leaves.append((k+1,.ellipse(q,r,r,0,shade(accent,k*1.15),shade(accent,k*0.75))))}
    }
    func limb(_ p:Point,_ angle:Float,_ len:Float,_ r0:Float,_ r1:Float,_ depth:Float)throws->(Point,Float) {
      try Task.checkCancellation();let segs=min(10,max(2,Int(len/6))),droop=kind.droop*depth,col=shade(bark,0.9+0.2*depth)
      var q=p,a=angle
      for k in 0..<segs {
        let t0=Float(k)/Float(segs),t1=Float(k+1)/Float(segs);a+=kind.wiggle*rng.sym()*0.25
        let diff=atan2(sin(ProceduralGeometry.sourcePi/2-a),cos(ProceduralGeometry.sourcePi/2-a));a+=diff*droop*0.12
        let step=len/Float(segs),nq=q+Point(cos(a)*step,sin(a)*step),ra=r0+(r1-r0)*t0,rb=r0+(r1-r0)*t1
        branches.append(.capsule(q,nq,ra,rb,col,col))
        if depth>0.99,kind.leaf != .none,k>0,rng.f()<spec.leavesAmount/100*0.9 {try addLeaf(nq,a)}
        q=nq
      };return(q,a)
    }
    func branch(_ p:Point,_ angle:Float,_ len:Float,_ r:Float,_ level:Int)throws {
      try Task.checkCancellation();guard branches.count+leaves.count<maximumPrimitives else{throw CraftError.unsupported("Tree geometry exceeds200,000 primitives.")}
      let depth=Float(level)/Float(max(kind.levels,1)),endRadius=r*0.62,(end,a)=try limb(p,angle,len,r,endRadius,depth)
      if level>=kind.levels {
        if kind.leaf != .none {for _ in 0..<Int((spec.leavesAmount/100*9).rounded()) {let d=len*0.5*rng.f(),th=rng.f()*(ProceduralGeometry.sourcePi*2);try addLeaf(end+Point(cos(th)*d,sin(th)*d),a)}};return
      }
      let spread=kind.spread*(ProceduralGeometry.sourcePi/180),n=kind.children
      for c in 0..<n {let side:Float=n==1 ? 0:Float(c)/Float(n-1)*2-1,ca=a+side*spread+rng.sym()*spread*0.35,cl=len*kind.ratio*rng.range(0.8,1.1),cr=endRadius*rng.range(0.75,0.95);try branch(end,ca,cl,cr,level+1)}
    }
  }
  static func integerPower(_ x:Float,_ n:Int)->Float {var x=x,n=n,result:Float=1;while n>0 {if n&1==1 {result*=x};n>>=1;if n>0{x*=x}};return result}
  static func tree(_ spec:TreeSettings,width:Int,height:Int)throws->[Primitive] {
    try spec.validate();let t=TreeContext(spec,width:width,height:height),kind=t.kind,h=Float(height)*spec.size,base=Point(Float(width)*spec.x,Float(height)*spec.y)
    let up = -ProceduralGeometry.sourcePi/2,r0=max(h*kind.thick*(spec.branchesThickness/100),0.8),bh=spec.branchesHeight/100,bark=t.bark
    switch kind.habit {
    case .branching:
      let trunk=min(h*kind.trunk*bh,h*0.92),(top,a)=try t.limb(base,up,max(trunk,1),r0,r0*0.75,0)
      var geo:Float=0;for k in 0..<kind.levels{geo+=integerPower(kind.ratio,k)}
      let first=max(h-trunk,h*0.08)/max(geo,0.5)*1.05,n=max(kind.children,2)
      for c in 0..<n {let side=Float(c)/Float(n-1)*2-1,sp=kind.spread*(ProceduralGeometry.sourcePi/180)*0.8,ca=a+side*sp+t.rng.sym()*0.15,fl=first*t.rng.range(0.85,1.05);try t.branch(top,ca,fl,r0*0.7,1)}
    case .conifer:
      let (top,_)=try t.limb(base,up,h,r0,r0*0.1,0),start=min(h*kind.trunk*bh,h*0.8),whorls=Int(14*min(2.5,max(0.6,sqrt(h/300)))),spread=kind.spread*(ProceduralGeometry.sourcePi/180)
      for k in 0..<whorls {
        let f=Float(k)/Float(whorls),y=base.y-start-(h-start)*f,x=base.x+(top.x-base.x)*((base.y-y)/h),span=(h-start)*0.42*pow(1-f,0.9)+h*0.03
        for side:Float in [-1,1] {let ang=up+side*spread+t.rng.sym()*0.1;try t.branch(Point(x,y),ang,span,max(r0*0.35*(1-f),0.6),kind.levels)
          if kind.levels>=2 {let a=ang+side*0.5,mid=Point(x+cos(a)*span*0.5,y+sin(a)*span*0.5);try t.branch(mid,ang+side*0.6,span*0.4,max(r0*0.15,0.5),kind.levels)}
        }
      }
    case .palm:
      let trunk=max(h*kind.trunk*min(bh,1.15),1),lean=t.rng.sym()*kind.wiggle;var p=base
      for k in 0..<12 {let f=Float(k)/12,a=up+lean*f,q=p+Point(cos(a)*trunk/12,sin(a)*trunk/12),r=r0*(1-0.35*f),ring=shade(bark,k%2==0 ? 1:0.85);t.branches.append(.capsule(p,q,r,r*0.97,ring,ring));p=q}
      let fronds=kind.children,flen=h*0.38*sqrt(max(10,spec.leavesSize)/100)
      for k in 0..<fronds {
        try Task.checkCancellation();var ang=up+(Float(k)/Float(fronds)-0.5)*ProceduralGeometry.sourcePi*1.7+t.rng.sym()*0.2,q=p
        let leaflets=Int((spec.leavesAmount/100*3).rounded())
        for s in 0..<10 {
          let d=ProceduralGeometry.sourcePi/2-ang;ang+=0.06*atan2(sin(d),cos(d))
          let nq=q+Point(cos(ang)*flen/10,sin(ang)*flen/10),k2=t.lightAt(nq)
          t.leaves.append((k2-0.1,.capsule(q,nq,max(r0*0.15,0.6),max(r0*0.1,0.4),shade(t.leaf,k2*0.8),shade(t.leaf,k2*0.8))))
          for j in 0..<leaflets {let along=Float(j)/Float(leaflets),at=q+(nq-q)*along
            for side:Float in [-1,1] {let la=ang+side*1.1,ll=flen*0.22*(1-Float(s)/10*0.7),tip=at+Point(cos(la)*ll,sin(la)*ll+ll*0.25);t.leaves.append((k2,.capsule(at,tip,max(ll*0.08,0.5),0.3,shade(t.leaf,k2),shade(t.leaf,k2*0.9))))}
          };q=nq
        }
      }
      if let accent=kind.accent {for _ in 0..<4 {let c=p+Point(t.rng.sym()*r0*2,t.rng.f()*r0*2);t.leaves.append((2,.disc(c,r0*1.1,shade(accent,1))))}}
    case .bamboo:
      let stalks=kind.children
      for k in 0..<stalks {
        let x=base.x+(Float(k)-Float(stalks-1)/2)*r0*5+t.rng.sym()*r0,hh=h*t.rng.range(0.7,1),a=up+t.rng.sym()*kind.spread*(ProceduralGeometry.sourcePi/180)*0.5
        var p=Point(x,base.y)
        for j in 0..<8 {
          try Task.checkCancellation();let q=p+Point(cos(a)*hh/8,sin(a)*hh/8)
          t.branches.append(.capsule(p,q,r0,r0,shade(bark,1),shade(bark,0.85)))
          t.branches.append(.capsule(Point(q.x-r0*1.1,q.y),Point(q.x+r0*1.1,q.y),r0*0.25,r0*0.25,shade(bark,0.7),shade(bark,0.7)))
          if j>=8/3 {for _ in 0..<Int((spec.leavesAmount/100*4).rounded()) {let side:Float=t.rng.f()<0.5 ? -1:1,la=a+side*t.rng.range(0.6,1.4),ll=t.leafPixels*2.2;try t.addLeaf(q+Point(cos(la)*ll,sin(la)*ll),la)}};p=q
        }
      }
    }
    // Stable ordering retains source insertion order for equally lit primitives.
    t.leaves.sort{$0.0<$1.0};guard t.branches.count+t.leaves.count<=maximumPrimitives else{throw CraftError.unsupported("Tree geometry exceeds its budget.")}
    return t.branches+t.leaves.map(\.1)
  }
}
