import Foundation

public struct PerspectivePlane: Codable, Equatable, Sendable {
  public var source:[PathPoint]
  public var destination:[PathPoint]
  public init(source:[PathPoint],destination:[PathPoint]?=nil) { self.source=source;self.destination=destination ?? source }
}
public struct PerspectiveEdgeLock: Codable, Equatable, Sendable {
  public enum Axis:String,Codable,CaseIterable,Sendable { case horizontal,vertical }
  public var plane:Int
  public var edge:Int
  public var axis:Axis
  public init(plane:Int,edge:Int,axis:Axis) { self.plane=plane;self.edge=edge;self.axis=axis }
}
/// Linked-plane model derived from PhotoCraft algo/perspective.rs (MIT OR Apache-2.0).
public struct PerspectiveSettings: Codable, Equatable, Sendable {
  public enum Straighten:String,Codable,CaseIterable,Sendable { case horizontal,vertical,auto }
  public var planes:[PerspectivePlane]=[]
  public var locks:[PerspectiveEdgeLock]=[]
  public var interpolation:Resampling = .bicubic
  public init() {}
  public var isIdentity:Bool { planes.allSatisfy{$0.source == $0.destination} }
  public var estimatedBytes:Int { planes.count*128+locks.count*24 }
  static func near(_ a:PathPoint,_ b:PathPoint)->Bool { abs(a.x-b.x)<=0.5 && abs(a.y-b.y)<=0.5 }
  public var linkedCorners:[[Int]] {
    var groups=[[Int]]()
    for i in 0..<(planes.count*4) {
      let p=planes[i/4].source[i%4]
      if let g=groups.firstIndex(where:{Self.near(planes[$0[0]/4].source[$0[0]%4],p)}) { groups[g].append(i) } else { groups.append([i]) }
    };return groups
  }
  static func validQuad(_ q:[PathPoint])->Bool {
    guard q.count == 4,q.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1_000_000 && abs($0.y)<=1_000_000}) else { return false }
    let crosses=(0..<4).map { k -> Double in let a=q[k],b=q[(k+1)%4],c=q[(k+2)%4];return (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x) }
    return crosses.allSatisfy{$0>1e-8} || crosses.allSatisfy{$0 < -1e-8}
  }
  public func validate() throws {
    guard planes.count<=16,planes.allSatisfy({Self.validQuad($0.source) && Self.validQuad($0.destination)}),locks.count<=64,
      locks.allSatisfy({planes.indices.contains($0.plane) && (0..<4).contains($0.edge)}),Set(locks.map{$0.plane*4+$0.edge}).count == locks.count else { throw CraftError.invalid("Perspective Warp requires up to16 finite convex planes and unique edge locks.") }
    let normalized=normalized()
    guard normalized.planes.allSatisfy({Self.validQuad($0.source) && Self.validQuad($0.destination)}) else { throw CraftError.invalid("Linked corners or locked edges collapse a Perspective plane.") }
    for p in normalized.planes { _ = try PerspectiveMap.homography(p.source);_ = try PerspectiveMap.homography(p.destination) }
  }
  public func normalized(preferred:Int?=nil)->Self {
    var result=self
    for g in linkedCorners {
      let source=g.reduce(PathPoint(0,0)) { a,i in let p=planes[i/4].source[i%4];return PathPoint(a.x+p.x/Double(g.count),a.y+p.y/Double(g.count)) }
      let destination:PathPoint
      if let preferred,g.contains(preferred) { destination=planes[preferred/4].destination[preferred%4] }
      else { destination=g.reduce(PathPoint(0,0)) { a,i in let p=planes[i/4].destination[i%4];return PathPoint(a.x+p.x/Double(g.count),a.y+p.y/Double(g.count)) } }
      for i in g { result.planes[i/4].source[i%4]=source;result.planes[i/4].destination[i%4]=destination }
    }
    let groups=result.linkedCorners,n=groups.count
    if n == 0 { return result }
    for axis in PerspectiveEdgeLock.Axis.allCases {
      var parent=Array(0..<n)
      func find(_ i:Int)->Int { var k=i;while parent[k] != k { parent[k]=parent[parent[k]];k=parent[k] };return k }
      for lock in locks where lock.axis == axis {
        guard let a=groups.firstIndex(where:{$0.contains(lock.plane*4+lock.edge)}),let b=groups.firstIndex(where:{$0.contains(lock.plane*4+(lock.edge+1)%4)}) else { continue }
        let aa=find(a),bb=find(b);parent[bb]=aa
      }
      let roots=(0..<n).map{find($0)}
      for root in Set(roots) {
        let corners=(0..<n).filter{roots[$0] == root}.map{groups[$0][0]}
        let coordinate:Double
        if let preferred,let i=groups.firstIndex(where:{$0.contains(preferred)}),roots[i] == root { let p=result.planes[preferred/4].destination[preferred%4];coordinate=axis == .horizontal ? p.y:p.x }
        else { coordinate=corners.reduce(0) { sum,i in let p=result.planes[i/4].destination[i%4];return sum+(axis == .horizontal ? p.y:p.x)/Double(corners.count) } }
        for g in 0..<n where roots[g] == root { for i in groups[g] { if axis == .horizontal { result.planes[i/4].destination[i%4].y=coordinate } else { result.planes[i/4].destination[i%4].x=coordinate } } }
      }
    };return result
  }
  public func straightened(_ mode:Straighten)->Self {
    var result=normalized();let groups=result.linkedCorners
    func group(_ p:Int,_ c:Int)->Int { groups.firstIndex{$0.contains(p*4+c)}! }
    var points=groups.map{result.planes[$0[0]/4].destination[$0[0]%4]}
    for p in planes.indices { for e in 0..<4 {
      let a=group(p,e),b=group(p,(e+1)%4),pa=points[a],pb=points[b],dx=abs(pb.x-pa.x),dy=abs(pb.y-pa.y)
      if dy<=dx && (mode == .horizontal || mode == .auto) { let y=(pa.y+pb.y)/2;points[a].y=y;points[b].y=y }
      else if dx<dy && (mode == .vertical || mode == .auto) { let x=(pa.x+pb.x)/2;points[a].x=x;points[b].x=x }
    } }
    for (g,p) in zip(groups,points) { for i in g { result.planes[i/4].destination[i%4]=p } };return result.normalized()
  }
  public func movingCorner(plane:Int,corner:Int,to point:PathPoint,layout:Bool,snap:Double=0)->Self {
    guard planes.indices.contains(plane),(0..<4).contains(corner) else { return self }
    var result=normalized();let index=plane*4+corner,group=result.linkedCorners.first{$0.contains(index)} ?? [index]
    var target=point
    if layout && snap>0 {
      let other=(0..<(planes.count*4)).filter{!group.contains($0) && $0/4 != plane}.map{result.planes[$0/4].source[$0%4]}
      if let nearest=other.min(by:{hypot($0.x-point.x,$0.y-point.y)<hypot($1.x-point.x,$1.y-point.y)}),hypot(nearest.x-point.x,nearest.y-point.y)<=snap { target=nearest }
    }
    for i in group {
      if layout { let old=result.planes[i/4].source[i%4];result.planes[i/4].source[i%4]=target;result.planes[i/4].destination[i%4].x += target.x-old.x;result.planes[i/4].destination[i%4].y += target.y-old.y }
      else { result.planes[i/4].destination[i%4]=target }
    };return result.normalized(preferred:index)
  }
  public func transformed(_ matrix:Transform2D)->Self {
    let canonical=normalized();var result=canonical
    for i in canonical.planes.indices { result.planes[i].source=canonical.planes[i].source.map{$0.transformed(matrix)};result.planes[i].destination=canonical.planes[i].destination.map{$0.transformed(matrix)} }
    result.locks=canonical.locks.compactMap { lock in
      let x=lock.axis == .horizontal ? matrix.a:matrix.c,y=lock.axis == .horizontal ? matrix.b:matrix.d
      var value=lock
      if abs(y)<=1e-9*max(1,abs(x)) { value.axis = .horizontal } else if abs(x)<=1e-9*max(1,abs(y)) { value.axis = .vertical } else { return nil }
      return value
    };return result
  }
  public static func decodeJSON(_ data:Data) throws -> Self {
    guard data.count<=65536,var object=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(object.keys).isSubset(of:["planes","locks","interpolation","straighten"]) else { throw CraftError.invalid("Invalid Perspective Warp settings.") }
    let straighten:Straighten?
    if let raw=object.removeValue(forKey:"straighten") { guard let text=raw as? String,let mode=Straighten(rawValue:text) else { throw CraftError.invalid("Unknown Perspective straighten mode.") };straighten=mode } else { straighten=nil }
    let defaults=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    for (k,v) in defaults where object[k] == nil { object[k]=v }
    guard var planes=object["planes"] as? [[String:Any]],planes.count<=16,let locks=object["locks"] as? [[String:Any]],locks.allSatisfy({Set($0.keys)==["plane","edge","axis"]}) else { throw CraftError.invalid("Invalid Perspective planes or locks.") }
    for i in planes.indices {
      guard Set(planes[i].keys).isSubset(of:["source","destination"]),let source=planes[i]["source"] as? [[String:Any]],source.count == 4,source.allSatisfy({Set($0.keys)==["x","y"]}) else { throw CraftError.invalid("Perspective source requires four points.") }
      if planes[i]["destination"] == nil { planes[i]["destination"]=source }
      guard let destination=planes[i]["destination"] as? [[String:Any]],destination.count == 4,destination.allSatisfy({Set($0.keys)==["x","y"]}) else { throw CraftError.invalid("Perspective destination requires four points.") }
    };object["planes"]=planes
    var value=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:object));try value.validate();value=value.normalized()
    if let straighten { value=value.straightened(straighten) };try value.validate();return value
  }
}

public struct PerspectiveMap:Sendable {
  private struct PlaneMap:Sendable { let source:PhotoHomography,inverse:PhotoHomography,destination:PhotoHomography,quad:[PathPoint],shared:[Int?] }
  private let maps:[PlaneMap]
  static func homography(_ q:[PathPoint]) throws -> PhotoHomography {
    let a=q[0],b=q[1],c=q[2],d=q[3],sx=a.x-b.x+c.x-d.x,sy=a.y-b.y+c.y-d.y
    if abs(sx)<1e-12 && abs(sy)<1e-12 { return PhotoHomography([b.x-a.x,d.x-a.x,a.x,b.y-a.y,d.y-a.y,a.y,0,0,1]) }
    let dx1=b.x-c.x,dx2=d.x-c.x,dy1=b.y-c.y,dy2=d.y-c.y,den=dx1*dy2-dx2*dy1
    guard abs(den)>1e-12 else { throw CraftError.invalid("Degenerate Perspective plane.") }
    let g=(sx*dy2-dx2*sy)/den,h=(dx1*sy-sx*dy1)/den
    let result=PhotoHomography([b.x-a.x+g*b.x,d.x-a.x+h*d.x,a.x,b.y-a.y+g*b.y,d.y-a.y+h*d.y,a.y,g,h,1])
    guard [1,1+g,1+h,1+g+h].allSatisfy({$0>1e-10}),result.inverse() != nil else { throw CraftError.invalid("Perspective plane crosses a projective horizon.") };return result
  }
  public init(_ settings:PerspectiveSettings) throws {
    try settings.validate();let planes=settings.normalized().planes
    guard !planes.isEmpty else { throw CraftError.invalid("Draw a Perspective plane first.") }
    maps=try planes.enumerated().map { i,p in
      let source=try Self.homography(p.source),destination=try Self.homography(p.destination)
      guard let inverse=source.inverse() else { throw CraftError.invalid("Singular Perspective plane.") }
      let shared:[Int?]=(0..<4).map { k in
        let a=p.source[k],b=p.source[(k+1)%4]
        return planes.indices.first { j in j != i && (0..<4).contains { e in let c=planes[j].source[e],d=planes[j].source[(e+1)%4];return (PerspectiveSettings.near(a,c) && PerspectiveSettings.near(b,d)) || (PerspectiveSettings.near(a,d) && PerspectiveSettings.near(b,c)) } }
      };return PlaneMap(source:source,inverse:inverse,destination:destination,quad:p.source,shared:shared)
    }
  }
  private func locate(_ p:PathPoint)->(Int,PhotoPoint) {
    var best=Double.infinity,index=0,uv=PhotoPoint.zero
    for (i,m) in maps.enumerated() {
      let q=m.inverse.apply(PhotoPoint(p.x,p.y))
      if q.x>=(-1e-9),q.x<=1+1e-9,q.y>=(-1e-9),q.y<=1+1e-9 { return (i,q) }
      var distance=Double.infinity
      for k in 0..<4 { let a=m.quad[k],b=m.quad[(k+1)%4],dx=b.x-a.x,dy=b.y-a.y,l=dx*dx+dy*dy,t=l>0 ? max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/l)):0;distance=min(distance,hypot(a.x+t*dx-p.x,a.y+t*dy-p.y)) }
      if distance<best { best=distance;index=i;uv=q }
    };return (index,uv)
  }
  public func point(_ p:PathPoint)->PathPoint {
    let (i,q)=locate(p),m=maps[i];var out=m.destination.apply(q)
    let u=max(0,min(1,q.x)),v=max(0,min(1,q.y)),edges:[(PhotoPoint,Double)]=[(PhotoPoint(u,0),1-v),(PhotoPoint(1,v),u),(PhotoPoint(u,1),v),(PhotoPoint(0,v),1-u)]
    for k in 0..<4 { guard let j=m.shared[k],edges[k].1>0 else { continue };let e=edges[k].0,w=edges[k].1,mine=m.destination.apply(e),other=maps[j],theirs=other.destination.apply(other.inverse.apply(m.source.apply(e)));out += (theirs-mine)*(0.5*w) }
    return PathPoint(out.x,out.y)
  }
  public func planePoint(_ plane:Int,u:Double,v:Double,warped:Bool)->PathPoint {
    let p=maps[plane].source.apply(PhotoPoint(u,v)),source=PathPoint(p.x,p.y);return warped ? point(source):source
  }
  var singleTransform:PhotoHomography? { maps.count == 1 ? maps[0].destination*maps[0].inverse:nil }
}
