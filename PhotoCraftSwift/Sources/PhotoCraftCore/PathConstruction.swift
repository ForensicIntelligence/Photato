import Foundation

/// Native curve construction. Least-squares cubic fitting follows the approach used by
/// PhotoCraft's vector/trace.rs; inputs and recursive work are bounded independently.
public enum PathConstruction {
  public static let maxSamples = 100_000
  private static func add(_ a:PathPoint,_ b:PathPoint)->PathPoint{.init(a.x+b.x,a.y+b.y)}
  private static func sub(_ a:PathPoint,_ b:PathPoint)->PathPoint{.init(a.x-b.x,a.y-b.y)}
  private static func mul(_ a:PathPoint,_ s:Double)->PathPoint{.init(a.x*s,a.y*s)}
  private static func dot(_ a:PathPoint,_ b:PathPoint)->Double{a.x*b.x+a.y*b.y}
  private static func unit(_ a:PathPoint)->PathPoint{let l=hypot(a.x,a.y);return l>1e-12 ? mul(a,1/l):.init(0,0)}
  private static func distance(_ a:PathPoint,_ b:PathPoint)->Double{hypot(a.x-b.x,a.y-b.y)}
  public static func fitted(_ samples:[PathPoint],tolerance:Double,closed:Bool=false)throws->PathComponent {
    guard tolerance.isFinite,(0.5...10).contains(tolerance),samples.count<=maxSamples,
      samples.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1_000_000 && abs($0.y)<=1_000_000})
    else{throw CraftError.invalid("Curve Fit must be 0.5–10 pixels; at most 100,000 finite samples are supported.")}
    var points:[PathPoint]=[]
    for p in samples where points.last.map({distance($0,p)>1e-8}) ?? true{points.append(p)}
    if closed,points.count>1,distance(points[0],points.last!)<1e-8{points.removeLast()}
    guard points.count >= (closed ? 3:2) else{throw CraftError.invalid("Draw at least two distinct points (three for a closed path).")}
    // Preserve distinct sharp turns while fitting smooth runs, including the closing seam.
    var corners:[Int]=[]
    if closed {
      let n=points.count
      for i in 0..<n {
        var a=(i+n-1)%n,b=(i+1)%n,steps=0
        while distance(points[a],points[i])<1.5 && (a+n-1)%n != i && steps<64 {a=(a+n-1)%n;steps += 1}
        steps=0
        while distance(points[b],points[i])<1.5 && (b+1)%n != i && steps<64 {b=(b+1)%n;steps += 1}
        let u=unit(sub(points[i],points[a])),v=unit(sub(points[b],points[i]))
        if dot(u,v)<0.5 {if corners.last.map({distance(points[$0],points[i])>=1.5}) ?? true{corners.append(i)}}
      }
      if corners.count>1,distance(points[corners[0]],points[corners.last!])<1.5{corners.removeLast()}
    }
    var curves:[[PathPoint]]=[],smooth:[Bool]=[],visits=0
    func fit(_ p:[PathPoint],_ t1:PathPoint,_ t2:PathPoint,_ depth:Int)throws {
      try Task.checkCancellation();visits += p.count
      guard visits<=8_000_000,curves.count<VectorPath.maxKnots else{throw CraftError.invalid("Path fitting exceeds its work or anchor limit. Increase Curve Fit.")}
      let first=p[0],last=p.last!,length=distance(first,last)
      var u=[Double](repeating:0,count:p.count)
      for i in 1..<p.count{u[i]=u[i-1]+distance(p[i],p[i-1])}
      let total=u.last!;if total>0{u=u.map{$0/total}}
      var c00=0.0,c01=0.0,c11=0.0,x0=0.0,x1=0.0
      for i in p.indices {
        let t=u[i],v=1-t,b0=v*v*v,b1=3*t*v*v,b2=3*t*t*v,b3=t*t*t
        let a=mul(t1,b1),b=mul(t2,b2),q=sub(p[i],add(mul(first,b0+b1),mul(last,b2+b3)))
        c00 += dot(a,a);c01 += dot(a,b);c11 += dot(b,b);x0 += dot(a,q);x1 += dot(b,q)
      }
      let det=c00*c11-c01*c01
      var alpha=abs(det)>1e-15 ? (x0*c11-x1*c01)/det:0,beta=abs(det)>1e-15 ? (c00*x1-c01*x0)/det:0
      if !alpha.isFinite || !beta.isFinite || alpha<length*1e-6 || beta<length*1e-6{alpha=length/3;beta=length/3}
      let curve=[first,add(first,mul(t1,alpha)),add(last,mul(t2,beta)),last]
      var error=0.0,split=p.count/2
      if p.count>2 {for i in 1..<(p.count-1){let t=u[i],v=1-t,q=add(add(mul(curve[0],v*v*v),mul(curve[1],3*t*v*v)),add(mul(curve[2],3*t*t*v),mul(curve[3],t*t*t))),d=distance(q,p[i]);if d>error{error=d;split=i}}}
      if p.count==2 || error<=tolerance*0.5 {curves.append(curve);smooth.append(true);return}
      guard depth<40 else{throw CraftError.invalid("Path fitting did not converge. Increase Curve Fit.")}
      var tangent=unit(sub(p[split-1],p[split+1]));if hypot(tangent.x,tangent.y)<0.5{tangent=unit(sub(p[split-1],p[split]))}
      try fit(Array(p[...split]),t1,tangent,depth+1);try fit(Array(p[split...]),mul(tangent,-1),t2,depth+1)
    }
    if closed && !corners.isEmpty {
      for c in corners.indices {
        var run=[points[corners[c]]],i=(corners[c]+1)%points.count;let end=corners[(c+1)%corners.count]
        while i != end{run.append(points[i]);i=(i+1)%points.count};run.append(points[end]);let start=curves.count
        try fit(run,unit(sub(run[1],run[0])),unit(sub(run[run.count-2],run.last!)),0);smooth[start]=false
      }
    }else {
      var run=points;if closed{run.append(points[0])}
      let tangent=closed ? unit(sub(points[1],points.last!)):unit(sub(points[1],points[0]))
      try fit(run,tangent,closed ? mul(tangent,-1):unit(sub(run[run.count-2],run.last!)),0)
    }
    var knots=curves.enumerated().map{i,c in PathKnot(c[0],incoming:i>0 ? curves[i-1][2]:(closed ? curves.last![2]:c[0]),outgoing:c[1],smooth:smooth[i])}
    if !closed{knots.append(PathKnot(curves.last![3],incoming:curves.last![2]));knots[0].smooth=false}
    let result=PathComponent(knots:knots,closed:closed);try VectorPath(components:[result]).validate();return result
  }
  /// Centripetal chord tangents keep curvature anchors interpolating their clicked positions.
  public static func curvature(_ input:PathComponent)throws->PathComponent {
    var result=input;let n=input.knots.count
    for i in 0..<n {
      let knot=input.knots[i],p=knot.anchor
      guard knot.smooth,n>1 else{result.knots[i].incoming=p;result.knots[i].outgoing=p;continue}
      let prev=input.knots[(i+n-1)%n].anchor,next=input.knots[(i+1)%n].anchor
      if !input.closed && i==0{result.knots[i].incoming=p;result.knots[i].outgoing=p.interpolated(to:next,at:1/3)}
      else if !input.closed && i==n-1{result.knots[i].incoming=p.interpolated(to:prev,at:1/3);result.knots[i].outgoing=p}
      else{let tangent=unit(sub(next,prev));result.knots[i].incoming=add(p,mul(tangent,-distance(prev,p)/3));result.knots[i].outgoing=add(p,mul(tangent,distance(next,p)/3))}
    }
    try VectorPath(components:[result]).validate();return result
  }
  /// Adaptive subdivision used by brush path strokes, with bounded arc-length sampling.
  public static func flattened(_ component:PathComponent,tolerance:Double=0.25)throws->[PathPoint] {
    try VectorPath(components:[component]).validate();guard let first=component.knots.first else{return []}
    var result=[first.anchor]
    func flatten(_ a:PathPoint,_ b:PathPoint,_ c:PathPoint,_ d:PathPoint,_ depth:Int)throws {
      try Task.checkCancellation();guard result.count<maxSamples else{throw CraftError.invalid("Path stroke exceeds 100,000 samples.")}
      let chord=distance(a,d),polygon=distance(a,b)+distance(b,c)+distance(c,d)
      if depth>=24 || polygon-chord<=tolerance{result.append(d);return}
      let ab=a.interpolated(to:b,at:0.5),bc=b.interpolated(to:c,at:0.5),cd=c.interpolated(to:d,at:0.5),abc=ab.interpolated(to:bc,at:0.5),bcd=bc.interpolated(to:cd,at:0.5),mid=abc.interpolated(to:bcd,at:0.5)
      try flatten(a,ab,abc,mid,depth+1);try flatten(mid,bcd,cd,d,depth+1)
    }
    if component.knots.count>1{for i in 0..<(component.closed ? component.knots.count:component.knots.count-1){let a=component.knots[i],b=component.knots[(i+1)%component.knots.count];try flatten(a.anchor,a.outgoing,b.incoming,b.anchor,0)}}
    return result
  }
}
