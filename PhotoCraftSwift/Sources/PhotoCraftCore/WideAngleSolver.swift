import Foundation

public struct WideAngleMesh:Sendable {
  public var columns:Int
  public var rows:Int
  public var width:Int
  public var height:Int
  public var inputs:[PathPoint]
  public var vertices:[PathPoint]
  public var curves:[[PathPoint]]
  public var references:[(constraint:Int,segment:Int)]
  public var residual:Double
  public var triangles:[[Int]] {
    var result=[[Int]]();for j in 0..<rows { for i in 0..<columns { let a=j*(columns+1)+i;result += [[a,a+1,a+columns+2],[a,a+columns+2,a+columns+1]] } };return result
  }
  func weights(_ p:PathPoint)->[(Int,Double)] {
    let gx=max(0,min(Double(columns)-1e-9,p.x/Double(width)*Double(columns))),gy=max(0,min(Double(rows)-1e-9,p.y/Double(height)*Double(rows))),i=Int(gx),j=Int(gy),tx=gx-Double(i),ty=gy-Double(j),a=j*(columns+1)+i
    return [(a,(1-tx)*(1-ty)),(a+1,tx*(1-ty)),(a+columns+1,(1-tx)*ty),(a+columns+2,tx*ty)]
  }
  public func point(_ p:PathPoint)->PathPoint { weights(p).reduce(.init(0,0)) { .init($0.x+vertices[$1.0].x*$1.1,$0.y+vertices[$1.0].y*$1.1) } }
  public func input(at p:PathPoint)->PathPoint? {
    for t in triangles { let a=vertices[t[0]],b=vertices[t[1]],c=vertices[t[2]],det=(b.x-a.x)*(c.y-a.y)-(c.x-a.x)*(b.y-a.y)
      if abs(det)<1e-10 { continue };let v=((p.x-a.x)*(c.y-a.y)-(p.y-a.y)*(c.x-a.x))/det,w=((b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x))/det,u=1-v-w
      if min(u,v,w) >= -1e-8 { return .init(inputs[t[0]].x*u+inputs[t[1]].x*v+inputs[t[2]].x*w,inputs[t[0]].y*u+inputs[t[1]].y*v+inputs[t[2]].y*w) }
    };return nil
  }
}
public enum WideAngleSolver {
  private final class Cache:@unchecked Sendable {
    struct Entry { let settings:WideAngleSettings;let width:Int;let height:Int;let mesh:WideAngleMesh }
    let lock=NSLock()
    var entries=[Entry]()
    func get(_ s:WideAngleSettings,_ width:Int,_ height:Int)->WideAngleMesh? { lock.lock();defer { lock.unlock() };return entries.first{$0.settings==s && $0.width==width && $0.height==height}?.mesh }
    func put(_ s:WideAngleSettings,_ mesh:WideAngleMesh) { lock.lock();defer { lock.unlock() };entries.removeAll{$0.settings==s && $0.width==mesh.width && $0.height==mesh.height};entries.insert(.init(settings:s,width:mesh.width,height:mesh.height,mesh:mesh),at:0);if entries.count>2 { entries.removeLast() } }
  }
  private static let cache=Cache()
  public static func solve(_ settings:WideAngleSettings,width:Int,height:Int) throws -> WideAngleMesh {
    try settings.validate();guard width>0,height>0,width<=WarpRaster.maximumPixels/height else { throw CraftError.unsupported("Wide Angle supports up to8,388,608 source pixels.") }
    try Task.checkCancellation();if let result=cache.get(settings,width,height) { return result }
    let camera=WideAngleCamera(settings,width:width,height:height),cell=max(8,Double(max(width,height))/48),nx=max(2,min(96,Int((Double(width)/cell).rounded()))),ny=max(2,min(96,Int((Double(height)/cell).rounded()))),count=(nx+1)*(ny+1)
    let input=(0..<count).map { PathPoint(Double($0%(nx+1))*Double(width)/Double(nx),Double($0/(nx+1))*Double(height)/Double(ny)) }
    var curves=[[PathPoint]](),references=[(constraint:Int,segment:Int)]()
    for (index,constraint) in settings.constraints.enumerated() { for segment in 0..<constraint.segmentCount {
      let a=constraint.points[segment],b=constraint.points[(segment+1)%constraint.points.count]
      curves.append(try camera.arc(.init(a.x*Double(width),a.y*Double(height)),.init(b.x*Double(width),b.y*Double(height))));references.append((index,segment))
    } }
    var mesh=WideAngleMesh(columns:nx,rows:ny,width:width,height:height,inputs:input,vertices:input,curves:curves,references:references,residual:0)
    if !curves.isEmpty {
      var normals=curves.map { c -> PathPoint in let a=c.first!,b=c.last!,length=max(1e-9,hypot(b.x-a.x,b.y-a.y));return .init(-(b.y-a.y)/length,(b.x-a.x)/length) }
      var shape=LeastSquares(count*2)
      var triangles=mesh.triangles
      for j in 0..<ny { for i in 0..<nx { let a=j*(nx+1)+i;triangles += [[a,a+1,a+nx+1],[a+1,a+nx+2,a+nx+1]] } }
      for t in triangles { try Task.checkCancellation();for rotation in 0..<3 {
        let i0=t[rotation],i1=t[(rotation+1)%3],i2=t[(rotation+2)%3],p0=input[i0],p1=input[i1],p2=input[i2],ex=p2.x-p1.x,ey=p2.y-p1.y,l2=ex*ex+ey*ey,dx=p0.x-p1.x,dy=p0.y-p1.y,u=(dx*ex+dy*ey)/l2,v=(-dx*ey+dy*ex)/l2
        shape.add([(2*i0,1),(2*i1,-1+u),(2*i2,-u),(2*i2+1,v),(2*i1+1,-v)],rhs:0,weight:1)
        shape.add([(2*i0+1,1),(2*i1+1,-1+u),(2*i2+1,-u),(2*i2,-v),(2*i1,v)],rhs:0,weight:1)
      } }
      for (i,p) in input.enumerated() { shape.add([(2*i,1)],rhs:p.x,weight:0.02);shape.add([(2*i+1,1)],rhs:p.y,weight:0.02) }
      for round in 0..<4 {
        try Task.checkCancellation();var system=shape
        for (k,curve) in curves.enumerated() {
          let ref=references[k],constraint=settings.constraints[ref.constraint],orientation=constraint.orientation(ref.segment),angle=constraint.angle(ref.segment) * .pi/180
          let normal:PathPoint
          switch orientation { case .horizontal:normal = .init(0,1);case .vertical:normal = .init(1,0);case .angle:normal = .init(-sin(angle),cos(angle));case .free:normal=normals[k] }
          let first=mesh.weights(curve[0])
          for q in curve.dropFirst() {
            var row=[(Int,Double)]();for (i,w) in mesh.weights(q) { row += [(2*i,normal.x*w),(2*i+1,normal.y*w)] };for (i,w) in first { row += [(2*i,-normal.x*w),(2*i+1,-normal.y*w)] };system.add(row,rhs:0,weight:10)
          }
        }
        let solved=try system.solve(mesh.vertices.flatMap{[$0.x,$0.y]},iterations:400+200*round);mesh.vertices=(0..<count).map{.init(solved[2*$0],solved[2*$0+1])}
        var changed=false,hasFree=false
        for (k,curve) in curves.enumerated() {
          let ref=references[k];guard settings.constraints[ref.constraint].orientation(ref.segment) == .free else { continue };hasFree=true
          let a=mesh.point(curve.first!),b=mesh.point(curve.last!),length=max(1e-9,hypot(b.x-a.x,b.y-a.y)),n=PathPoint(-(b.y-a.y)/length,(b.x-a.x)/length)
          changed = changed || abs(n.x-normals[k].x)+abs(n.y-normals[k].y)>1e-3;normals[k]=n
        }
        if !hasFree || round>0 && !changed { break }
      }
    }
    let factor=settings.scale/100,cx=Double(width)/2,cy=Double(height)/2
    mesh.vertices=mesh.vertices.map{.init(cx+($0.x-cx)*factor,cy+($0.y-cy)*factor)}
    guard mesh.vertices.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1_000_000 && abs($0.y)<=1_000_000}) else { throw CraftError.invalid("Wide Angle solution exceeds supported coordinates.") }
    for curve in curves { let points=curve.map{mesh.point($0)},a=points.first!,b=points.last!,dx=b.x-a.x,dy=b.y-a.y,length=max(1e-9,hypot(dx,dy));for p in points { mesh.residual=max(mesh.residual,abs((p.x-a.x)*dy-(p.y-a.y)*dx)/length) } }
    try Task.checkCancellation();cache.put(settings,mesh);return mesh
  }
  /// Sparse normal equations with diagonal-preconditioned CG. Coalesced rows keep
  /// repeated bilinear vertex weights mathematically correct and deterministic.
  private struct LeastSquares {
    var rows:[[Int:Double]]
    var rhs:[Double]
    init(_ count:Int) { rows=Array(repeating:[:],count:count);rhs=Array(repeating:0,count:count) }
    mutating func add(_ coefficients:[(Int,Double)],rhs target:Double,weight:Double) {
      var combined=[Int:Double]();for (i,v) in coefficients { combined[i,default:0] += v*weight }
      let entries=combined.filter{abs($0.value)>1e-16}.sorted{$0.key<$1.key}
      for (i,a) in entries { rhs[i] += a*target*weight;for (j,b) in entries { rows[i][j,default:0] += a*b } }
    }
    func solve(_ initial:[Double],iterations:Int) throws -> [Double] {
      let count=rhs.count,diagonal=(0..<count).map{max(1e-12,rows[$0][$0] ?? 0)}
      var offsets=[0],indices=[Int](),values=[Double]()
      for row in rows { for (j,v) in row.sorted(by:{$0.key<$1.key}) { indices.append(j);values.append(v) };offsets.append(indices.count) }
      func multiply(_ p:[Double])->[Double] { var result=Array(repeating:0.0,count:count);for i in 0..<count { var sum=0.0;for k in offsets[i]..<offsets[i+1] { sum += values[k]*p[indices[k]] };result[i]=sum };return result }
      func dot(_ a:[Double],_ b:[Double])->Double { zip(a,b).reduce(0){$0+$1.0*$1.1} }
      var x=initial,r=zip(rhs,multiply(initial)).map(-),z=zip(r,diagonal).map(/),direction=z,rz=dot(r,z);let initialError=max(1e-30,rz)
      for _ in 0..<iterations {
        try Task.checkCancellation();if rz<=initialError*1e-20 { break };let product=multiply(direction),denominator=dot(direction,product);if denominator<=1e-300 { break };let alpha=rz/denominator
        for i in 0..<count { x[i] += alpha*direction[i];r[i] -= alpha*product[i];z[i]=r[i]/diagonal[i] }
        let next=dot(r,z),beta=next/rz;rz=next;for i in 0..<count { direction[i]=z[i]+beta*direction[i] }
      };return x
    }
  }
}
