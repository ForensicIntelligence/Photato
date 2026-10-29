import Foundation

public struct VanishingPlane:Codable,Equatable,Sendable {
  public enum Edge:String,Codable,CaseIterable,Sendable { case top,right,bottom,left }
  public var corners:[PathPoint]=[]
  public var parent:Int?
  public var edge:Edge = .top
  public var angle=90.0
  public var depth=1.0
  public init(corners:[PathPoint]) { self.corners=corners }
  public init(parent:Int,edge:Edge,angle:Double=90,depth:Double=1) { self.parent=parent;self.edge=edge;self.angle=angle;self.depth=depth }
}
public struct VanishingSettings:Codable,Equatable,Sendable {
  public var planes:[VanishingPlane]=[]
  /// Camera focal length in pixels; zero infers it from the first plane.
  public var focalLength=0.0
  public var center:PathPoint?
  public init() {}
  public func validate() throws {
    guard planes.count<=32,focalLength.isFinite,(0...100_000).contains(focalLength),center.map({Self.validPoint($0)}) ?? true else { throw CraftError.invalid("Invalid Vanishing Point camera or plane count.") }
    for (i,p) in planes.enumerated() {
      guard p.angle.isFinite,(0...180).contains(p.angle),p.depth.isFinite,(0.05...20).contains(p.depth) else { throw CraftError.invalid("Invalid related plane angle or depth.") }
      if let parent=p.parent { guard (0..<i).contains(parent),p.corners.isEmpty else { throw CraftError.invalid("A related plane must reference an earlier plane and omit corners.") } }
      else { guard PerspectiveSettings.validQuad(p.corners) else { throw CraftError.invalid("A plane requires four finite convex corners.") };_ = try PerspectiveMap.homography(p.corners) }
    }
  }
  static func validPoint(_ p:PathPoint)->Bool { p.x.isFinite && p.y.isFinite && abs(p.x)<=1_000_000 && abs(p.y)<=1_000_000 }
  public var estimatedBytes:Int { planes.count*192+128 }
  public func transformed(_ t:Transform2D)->Self {
    var s=self;for i in s.planes.indices { s.planes[i].corners=s.planes[i].corners.map{$0.transformed(t)} }
    if let center { s.center=center.transformed(t) };s.focalLength *= (hypot(t.a,t.b)+hypot(t.c,t.d))/2;return s
  }
}

public struct VanishingScene:Sendable {
  public struct Frame:Sendable {
    public let corners:[PathPoint]
    public let points:[SIMD3<Double>]
    public let width:Double,height:Double
    let map:PhotoHomography,inverse:PhotoHomography
    public func point(_ uv:PathPoint)->PathPoint { let p=map.apply(.init(uv.x,uv.y));return .init(p.x,p.y) }
    public func uv(_ p:PathPoint)->PathPoint { let p=inverse.apply(.init(p.x,p.y));return .init(p.x,p.y) }
    public func metric(_ p:PathPoint)->PathPoint { let p=uv(p);return .init(p.x*width,p.y*height) }
    public func projected(_ m:PathPoint)->PathPoint { point(.init(m.x/width,m.y/height)) }
    public func contains(_ p:PathPoint)->Bool { let p=uv(p);return (-1e-8...1+1e-8).contains(p.x) && (-1e-8...1+1e-8).contains(p.y) }
  }
  public let focal:Double
  public let center:PathPoint
  public let frames:[Frame]
  static func dot(_ a:SIMD3<Double>,_ b:SIMD3<Double>)->Double { a.x*b.x+a.y*b.y+a.z*b.z }
  static func cross(_ a:SIMD3<Double>,_ b:SIMD3<Double>)->SIMD3<Double> { .init(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) }
  static func length(_ a:SIMD3<Double>)->Double { sqrt(dot(a,a)) }
  static func unit(_ a:SIMD3<Double>)->SIMD3<Double> { a/max(1e-300,length(a)) }
  static func meet(_ a:PathPoint,_ b:PathPoint,_ c:PathPoint,_ d:PathPoint)->SIMD3<Double> { cross(cross(.init(a.x,a.y,1),.init(b.x,b.y,1)),cross(.init(c.x,c.y,1),.init(d.x,d.y,1))) }
  public static func inferredFocal(_ q:[PathPoint],center:PathPoint)->Double? {
    guard q.count==4 else { return nil };let a=meet(q[0],q[1],q[3],q[2]),b=meet(q[0],q[3],q[1],q[2]);guard abs(a.z)>1e-9,abs(b.z)>1e-9 else { return nil }
    let f2 = -((a.x/a.z-center.x)*(b.x/b.z-center.x)+(a.y/a.z-center.y)*(b.y/b.z-center.y));return f2.isFinite && f2>1 ? sqrt(f2):nil
  }
  static func frame(_ q:[PathPoint],focal:Double,center:PathPoint) throws -> Frame {
    guard PerspectiveSettings.validQuad(q) else { throw CraftError.invalid("Related plane is degenerate.") }
    let h=try PerspectiveMap.homography(q);guard let inverse=h.inverse() else { throw CraftError.invalid("Singular perspective plane.") }
    func ray(_ p:PathPoint)->SIMD3<Double> { .init((p.x-center.x)/focal,(p.y-center.y)/focal,1) }
    func direction(_ a:PathPoint,_ b:PathPoint,_ c:PathPoint,_ d:PathPoint)->SIMD3<Double> { let v=meet(a,b,c,d);return abs(v.z)<1e-9*max(1,abs(v.x)+abs(v.y)) ? unit(.init(v.x,v.y,0)):unit(ray(.init(v.x/v.z,v.y/v.z))) }
    var normal=unit(cross(direction(q[0],q[1],q[3],q[2]),direction(q[0],q[3],q[1],q[2])));if normal.z<0 { normal = -normal }
    let points=try q.map { p -> SIMD3<Double> in let r=ray(p),d=dot(normal,r);guard d>1e-8 else { throw CraftError.invalid("Plane crosses the camera horizon.") };return r/d }
    let width=(length(points[1]-points[0])+length(points[2]-points[3]))/2,height=(length(points[3]-points[0])+length(points[2]-points[1]))/2
    guard width.isFinite,height.isFinite,min(width,height)>1e-9,max(width,height)<1e9 else { throw CraftError.invalid("Invalid plane metric.") }
    return Frame(corners:q,points:points,width:width,height:height,map:h,inverse:inverse)
  }
  static func related(_ plane:VanishingPlane,from frame:Frame,focal:Double,center:PathPoint) throws -> [PathPoint] {
    let ia:Int,ib:Int,ic:Int
    switch plane.edge { case .top:(ia,ib,ic)=(0,1,3);case .right:(ia,ib,ic)=(1,2,0);case .bottom:(ia,ib,ic)=(2,3,1);case .left:(ia,ib,ic)=(3,0,2) }
    let a=frame.points[ia],b=frame.points[ib],axis=unit(b-a),inward=frame.points[ic]-a,out = -unit(inward),len=length(inward)*plane.depth,angle=(180-plane.angle) * .pi/180
    func project(_ p:SIMD3<Double>)->PathPoint? { guard p.z>1e-8 else { return nil };let q=PathPoint(center.x+focal*p.x/p.z,center.y+focal*p.y/p.z);return VanishingSettings.validPoint(q) ? q:nil }
    var best:(Double,[PathPoint])?
    for sign in [1.0,-1.0] {
      let c=cos(sign*angle),s=sin(sign*angle),rot=out*c+cross(axis,out)*s+axis*(dot(axis,out)*(1-c)),a2=a+rot*len,b2=b+rot*len
      guard let pa=project(a),let pb=project(b),let pa2=project(a2),let pb2=project(b2) else { continue }
      var normal=unit(cross(b-a,a2-a));if dot(normal,a)>0 { normal = -normal };let score=dot(normal,inward),q:[PathPoint]
      switch plane.edge { case .top:q=[pa2,pb2,pb,pa];case .right:q=[pa,pa2,pb2,pb];case .bottom:q=[pb,pa,pa2,pb2];case .left:q=[pb2,pb,pa,pa2] }
      guard PerspectiveSettings.validQuad(q) else { continue };if best==nil || score>best!.0 { best=(score,q) }
    }
    guard let best else { throw CraftError.invalid("Related plane lies behind the camera or collapses; adjust its angle.") };return best.1
  }
  public init(_ settings:VanishingSettings,width:Int,height:Int) throws {
    try settings.validate();guard width>0,height>0 else { throw CraftError.invalid("Invalid Vanishing Point canvas.") }
    let cameraCenter=settings.center ?? PathPoint(Double(width)/2,Double(height)/2)
    let cameraFocal=settings.focalLength>0 ? settings.focalLength:(settings.planes.first.flatMap{Self.inferredFocal($0.corners,center:cameraCenter)} ?? Double(max(width,height)))
    center=cameraCenter;focal=cameraFocal
    var resolved=[Frame]()
    for p in settings.planes { let q=try p.parent.map { try Self.related(p,from:resolved[$0],focal:cameraFocal,center:cameraCenter) } ?? p.corners;resolved.append(try Self.frame(q,focal:cameraFocal,center:cameraCenter)) };frames=resolved
  }
  public func plane(at point:PathPoint)->Int? { frames.indices.reversed().first{frames[$0].contains(point)} }
}

public struct VanishingOperation:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable { case paste,clone,brush }
  public var kind:Kind
  public var plane=0
  public var at=PathPoint(0.25,0.25)
  public var width=0.5
  public var angle=0.0
  public var source:Surface?
  public var sourcePoint:PathPoint?
  public var points:[PathPoint]=[]
  public var diameter=40.0
  public var hardness=50.0
  public var opacity=100.0
  public var color=Pixel.black
  public var clip=true
  public init(_ kind:Kind) { self.kind=kind }
}
public struct VanishingProgram:Codable,Equatable,Sendable {
  public var settings=VanishingSettings()
  public var operations:[VanishingOperation]=[]
  public var newLayer=false
  public init() {}
  public func validate() throws {
    try settings.validate();guard operations.count<=256,operations.reduce(0,{$0+$1.points.count})<=16384,operations.reduce(0,{$0+($1.source?.allocatedBytes ?? 0)})<=134_217_728 else { throw CraftError.unsupported("Vanishing Point exceeds the operation or source memory limit.") }
    for op in operations {
      guard settings.planes.indices.contains(op.plane),VanishingSettings.validPoint(op.at),op.width.isFinite,(0.001...20).contains(op.width),op.angle.isFinite,(-360...360).contains(op.angle),op.diameter.isFinite,(1...2000).contains(op.diameter),op.hardness.isFinite,(0...100).contains(op.hardness),op.opacity.isFinite,(0...100).contains(op.opacity),op.color.isFinite,(0...1).contains(op.color.a),op.points.count<=4096,op.points.allSatisfy({VanishingSettings.validPoint($0)}),op.sourcePoint.map({VanishingSettings.validPoint($0)}) ?? true else { throw CraftError.invalid("Invalid Vanishing Point operation.") }
      if op.kind == .paste { guard let source=op.source,source.width<=WarpRaster.maximumPixels/source.height,op.points.isEmpty,op.sourcePoint==nil else { throw CraftError.invalid("Paste requires bounded source pixels.") };try source.validated() }
      else { guard op.source==nil,!op.points.isEmpty,op.kind != .clone || op.sourcePoint != nil else { throw CraftError.invalid("Painting requires points; cloning also requires a source point.") } }
    }
  }
}
