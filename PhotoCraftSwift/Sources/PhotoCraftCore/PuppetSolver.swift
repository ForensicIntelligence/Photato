import Foundation

/// Cotangent ARAP/ASAP local-global solve; native translation of algo/puppet.rs.
public struct PuppetSolver: Sendable {
  public let mesh:PuppetMesh
  private let weights:[[Double]],bindings:[Binding],pinTriangles:[[Int]],anchored:[Bool],matrix:Matrix,pinWeight:Double
  private struct Binding:Sendable { let vertices:[Int],weights:[Double] }
  private static func distance(_ a:PathPoint,_ b:PathPoint)->Double { pow(a.x-b.x,2)+pow(a.y-b.y,2) }
  private static func bind(_ mesh:PuppetMesh,_ p:PathPoint)->Binding {
    for t in mesh.triangles {
      let a=mesh.vertices[t[0]],b=mesh.vertices[t[1]],c=mesh.vertices[t[2]],det=(b.x-a.x)*(c.y-a.y)-(c.x-a.x)*(b.y-a.y)
      if abs(det)<1e-12 { continue }
      let v=((p.x-a.x)*(c.y-a.y)-(c.x-a.x)*(p.y-a.y))/det,w=((b.x-a.x)*(p.y-a.y)-(p.x-a.x)*(b.y-a.y))/det,u=1-v-w
      if min(u,v,w)>=(-1e-9) { return Binding(vertices:t,weights:[u,v,w]) }
    }
    let i=mesh.vertices.indices.min{distance(mesh.vertices[$0],p)<distance(mesh.vertices[$1],p)} ?? 0
    return Binding(vertices:[i,i,i],weights:[1,0,0])
  }
  public init(mesh:PuppetMesh,pins:[PuppetPin]) throws {
    guard !mesh.vertices.isEmpty,mesh.vertices.count<=PuppetMesh.maximumVertices,mesh.triangles.count<=16384,
      mesh.vertices.allSatisfy({$0.x.isFinite && $0.y.isFinite}),mesh.triangles.allSatisfy({$0.count == 3 && $0.allSatisfy{mesh.vertices.indices.contains($0)}}) else { throw CraftError.invalid("Puppet mesh is empty or invalid.") }
    var settings=PuppetSettings();settings.pins=pins;try settings.validate()
    self.mesh=mesh
    func cot(_ a:PathPoint,_ b:PathPoint,_ c:PathPoint)->Double { let ux=b.x-a.x,uy=b.y-a.y,vx=c.x-a.x,vy=c.y-a.y,cross=abs(ux*vy-uy*vx);return cross<1e-12 ? 0:(ux*vx+uy*vy)/cross }
    weights=mesh.triangles.map { t in let a=mesh.vertices[t[0]],b=mesh.vertices[t[1]],c=mesh.vertices[t[2]];return [0.5*cot(a,b,c),0.5*cot(b,c,a),0.5*cot(c,a,b)] }
    bindings=pins.map{Self.bind(mesh,$0.source)}
    let n=mesh.vertices.count;var parent=Array(0..<n)
    func find(_ v:Int)->Int { var i=v;while parent[i] != i { parent[i]=parent[parent[i]];i=parent[i] };return i }
    for t in mesh.triangles { for k in 1...2 { let a=find(t[0]),b=find(t[k]);if a != b { parent[a]=b } } }
    var pinned=Set<Int>();for binding in bindings { for v in binding.vertices { pinned.insert(find(v)) } };anchored=(0..<n).map{!pinned.contains(find($0))}
    pinTriangles=bindings.enumerated().map { k,b in
      guard pins[k].rotation != nil else { return [] }
      let vertex=b.vertices.min{Self.distance(mesh.vertices[$0],pins[k].source)<Self.distance(mesh.vertices[$1],pins[k].source)}!
      return mesh.triangles.indices.filter{mesh.triangles[$0].contains(vertex)}
    }
    var rows=[[Int:Double]](repeating:[:],count:n),sum=0.0
    func add(_ i:Int,_ j:Int,_ value:Double) { rows[i][j,default:0] += value }
    for (t,w) in zip(mesh.triangles,weights) { for k in 0..<3 { let i=t[(k+1)%3],j=t[(k+2)%3];add(i,i,w[k]);add(j,j,w[k]);add(i,j,-w[k]);add(j,i,-w[k]);sum += 2*w[k] } }
    pinWeight=1e4*max(1,sum/Double(n))
    for b in bindings { for i in 0..<3 { for j in 0..<3 { add(b.vertices[i],b.vertices[j],pinWeight*b.weights[i]*b.weights[j]) } } }
    for i in 0..<n where anchored[i] { add(i,i,pinWeight) }
    matrix=try Matrix(rows)
  }
  public func solve(pins:[PuppetPin],mode:PuppetSettings.Mode,iterations:Int=40) throws -> [PathPoint] {
    guard pins.count == bindings.count,(1...40).contains(iterations) else { throw CraftError.invalid("Puppet solver pin set changed.") }
    var settings=PuppetSettings();settings.pins=pins;try settings.validate()
    var points=mesh.vertices
    let rotated=pins.indices.compactMap { i -> (PathPoint,Double)? in
      guard let angle=pins[i].rotation else { return nil };let b=bindings[i]
      let point=PathPoint(zip(b.vertices,b.weights).reduce(0){$0+mesh.vertices[$1.0].x*$1.1},zip(b.vertices,b.weights).reduce(0){$0+mesh.vertices[$1.0].y*$1.1})
      return (point,angle)
    }
    var rotations=mesh.triangles.map { t -> [Double] in
      guard !rotated.isEmpty else { return [1,0,0,1] }
      let center=PathPoint(t.reduce(0){$0+mesh.vertices[$1].x}/3,t.reduce(0){$0+mesh.vertices[$1].y}/3)
      var sum=0.0,angle=0.0
      for pin in rotated { let w=1/(Self.distance(pin.0,center)+1);sum += w;angle += w*pin.1 * .pi/180 }
      let a=angle/sum;return [cos(a),-sin(a),sin(a),cos(a)]
    }
    points=try global(rotations,pins: pins,initial:points)
    for _ in 0..<iterations {
      try Task.checkCancellation();rotations=local(points,mode:mode,pins:pins);points=try global(rotations,pins:pins,initial:points)
    }
    guard points.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1_000_000 && abs($0.y)<=1_000_000}) else { throw CraftError.invalid("Puppet deformation exceeds supported coordinates.") };return points
  }
  private func local(_ points:[PathPoint],mode:PuppetSettings.Mode,pins:[PuppetPin])->[[Double]] {
    var rotations=zip(mesh.triangles,weights).map { t,w -> [Double] in
      var s=[Double](repeating:0,count:4),norm=0.0
      for k in 0..<3 { let i=t[(k+1)%3],j=t[(k+2)%3],dx=points[i].x-points[j].x,dy=points[i].y-points[j].y,ex=mesh.vertices[i].x-mesh.vertices[j].x,ey=mesh.vertices[i].y-mesh.vertices[j].y
        s[0] += w[k]*dx*ex;s[1] += w[k]*dx*ey;s[2] += w[k]*dy*ex;s[3] += w[k]*dy*ey;norm += w[k]*(ex*ex+ey*ey)
      }
      let c=s[0]+s[3],sn=s[2]-s[1],angle=atan2(sn,c),ratio=hypot(c,sn)/max(1e-12,norm)
      var scale=mode == .rigid ? 1:mode == .normal ? sqrt(ratio):ratio
      if !scale.isFinite || scale<=0 { scale=1 };return [scale*cos(angle),-scale*sin(angle),scale*sin(angle),scale*cos(angle)]
    }
    for (i,triangles) in pinTriangles.enumerated() { if let angle=pins[i].rotation { let a=angle * .pi/180;for t in triangles { rotations[t]=[cos(a),-sin(a),sin(a),cos(a)] } } };return rotations
  }
  private func global(_ rotations:[[Double]],pins:[PuppetPin],initial:[PathPoint]) throws -> [PathPoint] {
    let n=mesh.vertices.count;var bx=[Double](repeating:0,count:n),by=bx
    for index in mesh.triangles.indices { let t=mesh.triangles[index],w=weights[index],r=rotations[index]
      for k in 0..<3 { let i=t[(k+1)%3],j=t[(k+2)%3],x=mesh.vertices[i].x-mesh.vertices[j].x,y=mesh.vertices[i].y-mesh.vertices[j].y
        let rx=w[k]*(r[0]*x+r[1]*y),ry=w[k]*(r[2]*x+r[3]*y);bx[i] += rx;by[i] += ry;bx[j] -= rx;by[j] -= ry
      }
    }
    for (b,pin) in zip(bindings,pins) { for k in 0..<3 { bx[b.vertices[k]] += pinWeight*b.weights[k]*pin.destination.x;by[b.vertices[k]] += pinWeight*b.weights[k]*pin.destination.y } }
    for i in 0..<n where anchored[i] { bx[i] += pinWeight*mesh.vertices[i].x;by[i] += pinWeight*mesh.vertices[i].y }
    let x=try matrix.solve(bx,initial:initial.map(\.x)),y=try matrix.solve(by,initial:initial.map(\.y));return zip(x,y).map{PathPoint($0,$1)}
  }
  public func drawOrder(pins:[PuppetPin])->[Int] {
    guard !pins.isEmpty,pins.contains(where:{$0.depth != 0}) else { return Array(mesh.triangles.indices) }
    let depths=mesh.triangles.map { t -> Int in let center=PathPoint(t.reduce(0){$0+mesh.vertices[$1].x}/3,t.reduce(0){$0+mesh.vertices[$1].y}/3);return pins.min{Self.distance($0.source,center)<Self.distance($1.source,center)}!.depth }
    return mesh.triangles.indices.sorted{depths[$0] == depths[$1] ? $0<$1:depths[$0]<depths[$1]}
  }
  private struct Matrix:Sendable {
    let rows:[[(Int,Double)]]
    let diagonal:[Double]
    let band:Int
    let factor:[Double]?
    init(_ input:[[Int:Double]]) throws {
      rows=input.map{$0.sorted{$0.key<$1.key}.map{($0.key,$0.value)}};diagonal=input.enumerated().map{$0.element[$0.offset] ?? 1}
      let n=rows.count;var p=0
      for i in rows.indices { for (j,_) in rows[i] { p=max(p,abs(i-j)) } };band=p
      guard Double(n)*Double(p+1)*Double(p+1)<=134_217_728 else { throw CraftError.unsupported("Puppet solver exceeds its factorization work budget.") }
      let w=p+1;var l=[Double](repeating:0,count:n*w),valid=true
      for i in 0..<n { for (j,v) in rows[i] where j<=i { l[i*w+j+p-i]=v } }
      factorization: for i in 0..<n {
        try Task.checkCancellation();let lo=max(0,i-p)
        for j in lo...i { var sum=l[i*w+j+p-i]
          for k in max(lo,j-p)..<j { sum -= l[i*w+k+p-i]*l[j*w+k+p-j] }
          if i == j { if sum<=0 || !sum.isFinite { valid=false;break factorization };l[i*w+p]=sqrt(sum) }
          else { l[i*w+j+p-i]=sum/l[j*w+p] }
        }
      };factor=valid ? l:nil
    }
    func solve(_ b:[Double],initial:[Double]) throws -> [Double] {
      let n=b.count,p=band,w=p+1
      if let l=factor {
        var y=b,x=initial
        for i in 0..<n { if i%128 == 0 { try Task.checkCancellation() };var sum=y[i];for k in max(0,i-p)..<i { sum -= l[i*w+k+p-i]*y[k] };y[i]=sum/l[i*w+p] }
        for i in (0..<n).reversed() { var sum=y[i];for k in (i+1)..<min(n,i+p+1) { sum -= l[k*w+i+p-k]*x[k] };x[i]=sum/l[i*w+p] };return x
      }
      func multiply(_ x:[Double])->[Double] { rows.map { row in row.reduce(0){$0+$1.1*x[$1.0]} } }
      func dot(_ x:[Double],_ y:[Double])->Double { zip(x,y).reduce(0){$0+$1.0*$1.1} }
      var x=initial,r=zip(b,multiply(initial)).map(-),z=zip(r,diagonal).map(/),direction=z,rz=dot(r,z)
      let bn=max(1e-30,sqrt(dot(b,b)))
      for _ in 0..<min(2000,max(50,4*n)) {
        try Task.checkCancellation();if sqrt(dot(r,r))<=1e-12*bn { break }
        let ap=multiply(direction),pap=dot(direction,ap);if abs(pap)<1e-300 { break };let alpha=rz/pap
        for i in 0..<n { x[i] += alpha*direction[i];r[i] -= alpha*ap[i];z[i]=r[i]/diagonal[i] }
        let next=dot(r,z),beta=next/rz;rz=next;for i in 0..<n { direction[i]=z[i]+beta*direction[i] }
      };return x
    }
  }
}
