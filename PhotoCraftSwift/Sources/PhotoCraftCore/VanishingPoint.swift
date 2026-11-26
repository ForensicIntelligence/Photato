import Foundation

public struct VanishingPlane:Codable,Equatable,Sendable {
  public enum Edge:String,Codable,CaseIterable,Sendable { case top,right,bottom,left }
  public var corners:[PathPoint]=[]
  public var parent:Int?
  public var edge:Edge = .top
  public var angle=90.0
  public var depth=1.0

  /// Explicit direction of a calibrated hinge. Nil keeps the native automatic choice.
  public var rotationSign: Double?
  /// Keep the measured corners until the parent or the hinge is edited.
  public struct Calibration: Codable, Equatable, Sendable {
    public var corners: [PathPoint]
    public var parentCorners: [PathPoint]
    public var angle: Double
    public var depth: Double
    public var rotationSign: Double
  }
  public var calibration: Calibration?

  public init(corners:[PathPoint]) { self.corners=corners }
  public init(parent:Int,edge:Edge,angle:Double=90,depth:Double=1) { self.parent=parent;self.edge=edge;self.angle=angle;self.depth=depth }
}
/// Endpoints use the plane's rectified coordinates, with (0,0) at its first corner.
public struct VanishingMeasurement: Codable, Equatable, Sendable {
  public var plane: Int
  public var start: PathPoint
  public var end: PathPoint

  public init(plane: Int, start: PathPoint, end: PathPoint) {
    self.plane = plane
    self.start = start
    self.end = end
  }
}

/// A connected set of planes shares one scale. Independent roots can be calibrated separately.
public struct VanishingMeasurementScale: Codable, Equatable, Sendable {
  public var root: Int
  public var pixelsPerUnit: Double
  public var linkedToGrid: Bool

  public init(root: Int, pixelsPerUnit: Double, linkedToGrid: Bool = false) {
    self.root = root
    self.pixelsPerUnit = pixelsPerUnit
    self.linkedToGrid = linkedToGrid
  }
}

public struct VanishingSettings:Codable,Equatable,Sendable {
  public static let defaultGridSize = 100.0
  public static let gridSizeRange = 1.0...1000.0
  public var planes:[VanishingPlane]=[]
  /// The document's grid spacing. Earlier archives omit the default value.
  public var gridSize: Double?
  public var effectiveGridSize: Double { gridSize ?? Self.defaultGridSize }
  public static let maximumMeasurements = 512
  public static let measurementScaleRange = 1e-9...1e12
  public static let defaultMeasurementScale = 100.0
  /// Optional fields keep legacy archive and command payloads readable.
  public var measurements: [VanishingMeasurement]?
  public var measurementScales: [VanishingMeasurementScale]?

  public func measurementScale(for root: Int) -> VanishingMeasurementScale {
    measurementScales?.first { $0.root == root }
      ?? .init(root: root, pixelsPerUnit: Self.defaultMeasurementScale)
  }

  public mutating func setMeasurementScale(_ scale: VanishingMeasurementScale) {
    var scales = (measurementScales ?? []).filter { $0.root != scale.root }
    if scale.linkedToGrid || scale.pixelsPerUnit != Self.defaultMeasurementScale { scales.append(scale) }
    measurementScales = scales.isEmpty ? nil : scales.sorted { $0.root < $1.root }
  }

  public func withDisplayMetadata(from other: Self) -> Self {
    var result = self
    result.gridSize = other.gridSize
    result.measurements = other.measurements
    result.measurementScales = other.measurementScales
    return result
  }
  /// Camera focal length in pixels. Zero infers it from the first plane and any
  /// usable right-angle hinge, or uses the longer canvas side.
  public var focalLength=0.0
  public var center:PathPoint?
  public init() {}
  public func validate() throws {
    guard Self.gridSizeRange.contains(effectiveGridSize) else {
      throw CraftError.invalid("Grid Size must be between 1 and 1,000.")
    }
    guard planes.count<=32,focalLength.isFinite,focalLength>=0,center.map({Self.validPoint($0)}) ?? true else { throw CraftError.invalid("Invalid Vanishing Point camera or plane count.") }
    for (i,p) in planes.enumerated() {
      guard p.angle.isFinite, (0...180).contains(p.angle), p.depth.isFinite, p.depth > 0,
        p.rotationSign.map({ $0 == 1 || $0 == -1 }) ?? true else {
        throw CraftError.invalid("Invalid related plane angle, depth or orientation.")
      }
      if let parent = p.parent {
        guard (0..<i).contains(parent), p.corners.isEmpty else {
          throw CraftError.invalid("A related plane must reference an earlier plane and omit corners.")
        }
        if let geometry = p.calibration {
          guard PerspectiveSettings.validQuad(geometry.corners), PerspectiveSettings.validQuad(geometry.parentCorners),
            (0...180).contains(geometry.angle), geometry.depth.isFinite, geometry.depth > 0,
            geometry.rotationSign == 1 || geometry.rotationSign == -1 else {
            throw CraftError.invalid("Invalid connected plane calibration.")
          }
          let (parentA,parentB,_) = VanishingScene.edgeIndices(p.edge)
          let (outerA,outerB) = VanishingScene.outsideIndices(p.edge)
          guard geometry.corners[(outerA+3)%4] == geometry.parentCorners[parentA],
            geometry.corners[(outerB+1)%4] == geometry.parentCorners[parentB] else {
            throw CraftError.invalid("Measured related planes must retain the parent edge.")
          }
        }
      } else {
        guard p.calibration == nil, p.rotationSign == nil, PerspectiveSettings.validQuad(p.corners) else {
          throw CraftError.invalid("A plane requires four finite convex corners.")
        }
        _ = try PerspectiveMap.homography(p.corners)
      }
    }
    try validateMeasurements()
  }
  private func validateMeasurements() throws {
    let measurements = measurements ?? []
    guard measurements.count <= Self.maximumMeasurements, measurements.allSatisfy({
      planes.indices.contains($0.plane) && Self.validPoint($0.start) && Self.validPoint($0.end) && $0.start != $0.end
    }) else { throw CraftError.invalid("Invalid Vanishing Point measurement endpoints.") }
    let scales = measurementScales ?? []
    guard scales.count <= planes.count, Set(scales.map(\.root)).count == scales.count,
      scales.allSatisfy({ planes.indices.contains($0.root) && planes[$0.root].parent == nil
        && Self.measurementScaleRange.contains($0.pixelsPerUnit) }) else {
      throw CraftError.invalid("Invalid Vanishing Point measurement scale.")
    }
  }

  static func validPoint(_ p:PathPoint)->Bool { p.x.isFinite && p.y.isFinite && abs(p.x)<=1_000_000 && abs(p.y)<=1_000_000 }
  public var estimatedBytes: Int {
    planes.reduce(128) { $0 + ($1.calibration == nil ? 192 : 320) }
      + (measurements?.count ?? 0) * 48 + (measurementScales?.count ?? 0) * 32
  }
  public func transformed(_ t:Transform2D)->Self {
    var s = self
    for i in s.planes.indices {
      s.planes[i].corners = s.planes[i].corners.map { $0.transformed(t) }
      if var measured = s.planes[i].calibration {
        measured.corners = measured.corners.map { $0.transformed(t) }
        measured.parentCorners = measured.parentCorners.map { $0.transformed(t) }
        s.planes[i].calibration = measured
      }
    }
    if let center { s.center = center.transformed(t) }
    s.focalLength *= (hypot(t.a,t.b)+hypot(t.c,t.d))/2
    return s
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
  private let measurementRoots: [Int]
  private let measurementMetrics: [PathPoint]
  let marqueeLayout: [VanishingMarqueeFace]
  static func dot(_ a:SIMD3<Double>,_ b:SIMD3<Double>)->Double { a.x*b.x+a.y*b.y+a.z*b.z }
  static func cross(_ a:SIMD3<Double>,_ b:SIMD3<Double>)->SIMD3<Double> { .init(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x) }
  static func length(_ a:SIMD3<Double>)->Double { sqrt(dot(a,a)) }
  static func unit(_ a:SIMD3<Double>)->SIMD3<Double> { a/max(1e-300,length(a)) }
  static func meet(_ a:PathPoint,_ b:PathPoint,_ c:PathPoint,_ d:PathPoint)->SIMD3<Double> { cross(cross(.init(a.x,a.y,1),.init(b.x,b.y,1)),cross(.init(c.x,c.y,1),.init(d.x,d.y,1))) }
  public static func inferredFocal(_ q:[PathPoint],center:PathPoint)->Double? {
    guard q.count==4 else { return nil };let a=meet(q[0],q[1],q[3],q[2]),b=meet(q[0],q[3],q[1],q[2]);guard abs(a.z)>1e-9,abs(b.z)>1e-9 else { return nil }
    let f2 = -((a.x/a.z-center.x)*(b.x/b.z-center.x)+(a.y/a.z-center.y)*(b.y/b.z-center.y));return f2.isFinite && f2>1 ? sqrt(f2):nil
  }

  /// Orthogonal directions on either side of a nearly parallel hinge supply a
  /// better camera constraint than that hinge's very distant vanishing point.
  public static func inferredOrthogonalHingeFocal(parent: [PathPoint], child: [PathPoint],
    edge: VanishingPlane.Edge, center: PathPoint, canvasSide: Int) -> Double?
  {
    guard parent.count == 4, child.count == 4, canvasSide > 0 else { return nil }
    let alongWidth = edge == .top || edge == .bottom
    func directions(_ q: [PathPoint]) -> (along: SIMD3<Double>, across: SIMD3<Double>) {
      let horizontal = meet(q[0],q[1],q[3],q[2])
      let vertical = meet(q[0],q[3],q[1],q[2])
      return alongWidth ? (horizontal,vertical) : (vertical,horizontal)
    }
    let a = directions(parent), b = directions(child)
    let horizon = 64 * Double(canvasSide)
    func distant(_ p: SIMD3<Double>) -> Bool {
      let distance = hypot(p.x-center.x*p.z,p.y-center.y*p.z)
      return distance.isFinite && distance > horizon * abs(p.z)
    }
    guard distant(a.along), distant(b.along),
      a.across.z != 0, b.across.z != 0,
      !distant(a.across), !distant(b.across) else { return nil }
    let ax = a.across.x/a.across.z-center.x, ay = a.across.y/a.across.z-center.y
    let bx = b.across.x/b.across.z-center.x, by = b.across.y/b.across.z-center.y
    let square = -(ax*bx+ay*by)
    guard square.isFinite, square > 1 else { return nil }
    let focal = sqrt(square)
    func cameraDirection(_ point: SIMD3<Double>) -> SIMD3<Double> {
      unit(.init((point.x-center.x*point.z)/focal,(point.y-center.y*point.z)/focal,point.z))
    }
    // A right-angle constraint is usable only if both transverse axes are
    // consistent with the projected hinge direction at that camera.
    let firstAlong = cameraDirection(a.along), secondAlong = cameraDirection(b.along)
    let firstAcross = unit(.init(ax/focal,ay/focal,1))
    let secondAcross = unit(.init(bx/focal,by/focal,1))
    guard abs(dot(firstAlong,firstAcross)) < 0.01, abs(dot(firstAlong,secondAcross)) < 0.01,
      abs(dot(secondAlong,firstAcross)) < 0.01, abs(dot(secondAlong,secondAcross)) < 0.01 else { return nil }
    return focal
  }

  static func frame(_ q:[PathPoint],focal:Double,center:PathPoint) throws -> Frame {
    guard PerspectiveSettings.validQuad(q) else { throw CraftError.invalid("Related plane is degenerate.") }
    let h=try PerspectiveMap.homography(q);guard let inverse=h.inverse() else { throw CraftError.invalid("Singular perspective plane.") }
    func ray(_ p:PathPoint)->SIMD3<Double> { .init((p.x-center.x)/focal,(p.y-center.y)/focal,1) }
    func direction(_ a:PathPoint,_ b:PathPoint,_ c:PathPoint,_ d:PathPoint)->SIMD3<Double> { let v=meet(a,b,c,d);return abs(v.z)<1e-9*max(1,abs(v.x)+abs(v.y)) ? unit(.init(v.x,v.y,0)):unit(ray(.init(v.x/v.z,v.y/v.z))) }
    var normal = unit(cross(direction(q[0], q[1], q[3], q[2]), direction(q[0], q[3], q[1], q[2])))
    let rays = q.map(ray)
    // Orient the plane from a visible corner. The optical axis can cross the
    // horizon even when all four corner rays lie on the same side of it.
    if dot(normal, rays[0]) < 0 { normal = -normal }
    let points = try rays.map { ray -> SIMD3<Double> in
      let distance = dot(normal, ray)
      guard distance > 1e-8 else { throw CraftError.invalid("Plane crosses the camera horizon.") }
      return ray / distance
    }
    let width=(length(points[1]-points[0])+length(points[2]-points[3]))/2,height=(length(points[3]-points[0])+length(points[2]-points[1]))/2
    guard width.isFinite,height.isFinite,min(width,height)>1e-9,max(width,height)<1e9 else { throw CraftError.invalid("Invalid plane metric.") }
    return Frame(corners:q,points:points,width:width,height:height,map:h,inverse:inverse)
  }
  static func edgeIndices(_ edge: VanishingPlane.Edge) -> (Int, Int, Int) {
    switch edge {
    case .top: (0,1,3)
    case .right: (1,2,0)
    case .bottom: (2,3,1)
    case .left: (3,0,2)
    }
  }

  static func outsideIndices(_ edge: VanishingPlane.Edge) -> (Int, Int) {
    switch edge {
    case .top: (0,1)
    case .right: (1,2)
    case .bottom: (2,3)
    case .left: (3,0)
    }
  }

  static func rotated(_ outward: SIMD3<Double>, about axis: SIMD3<Double>, by angle: Double) -> SIMD3<Double> {
    let c = cos(angle), s = sin(angle)
    return outward*c + cross(axis,outward)*s + axis*(dot(axis,outward)*(1-c))
  }

  /// Calibrate a related plane from measured projected corners at the current camera.
  public func calibratedPlane(parent index: Int, edge: VanishingPlane.Edge, corners: [PathPoint],
    angleFromCoplanar: Double? = nil) throws -> VanishingPlane
  {
    guard frames.indices.contains(index) else { throw CraftError.invalid("Missing parent perspective plane.") }
    let parent = frames[index]
    let (ia, ib, ic) = Self.edgeIndices(edge)
    let (ua, ub) = Self.outsideIndices(edge)
    let a = parent.points[ia], b = parent.points[ib], inward = parent.points[ic] - a
    let axis = Self.unit(b-a), outward = -Self.unit(inward)
    let child = try Self.frame(corners, focal: focal, center: center)
    let ca = child.points[(ua+3)%4], cb = child.points[(ub+1)%4]
    let scale = (Self.length(a)/Self.length(ca)+Self.length(b)/Self.length(cb))/2
    let displacement = (child.points[ua]*scale-a + child.points[ub]*scale-b)/2
    let free = displacement-axis*Self.dot(displacement,axis)
    let inferred = acos(min(1,max(-1,Self.dot(Self.unit(free),outward))))
    let angle = angleFromCoplanar.map { abs($0) * .pi/180 } ?? inferred
    guard angle.isFinite, (0...Double.pi).contains(angle) else {
      throw CraftError.invalid("Invalid measured related-plane angle.")
    }
    func ray(_ p: PathPoint) -> SIMD3<Double> {
      .init((p.x-center.x)/focal,(p.y-center.y)/focal,1)
    }
    var best: (length: Double, sign: Double, residual: Double)?
    for sign in [1.0,-1.0] {
      let direction = Self.rotated(outward, about: axis, by: sign*angle)
      let ra = ray(corners[ua]), rb = ray(corners[ub])
      let da = Self.cross(direction,ra), db = Self.cross(direction,rb)
      let ca = Self.cross(a,ra), cb = Self.cross(b,rb)
      let length = -(Self.dot(da,ca)+Self.dot(db,cb))/(Self.dot(da,da)+Self.dot(db,db))
      let r = Self.length(ca+da*length)+Self.length(cb+db*length)
      if length.isFinite, length>0, r.isFinite, best.map({ r < $0.residual }) ?? true {
        best = (length,sign,r)
      }
    }
    guard let best else { throw CraftError.invalid("Unable to calibrate the measured related plane.") }
    var plane = VanishingPlane(parent:index,edge:edge,angle:max(0,180-angle*180/Double.pi),
      depth:best.length/Self.length(inward))
    plane.rotationSign = best.sign
    plane.calibration = .init(corners:corners,parentCorners:parent.corners,angle:plane.angle,
      depth:plane.depth,rotationSign:best.sign)
    return plane
  }

  static func related(_ plane:VanishingPlane,from frame:Frame,focal:Double,center:PathPoint) throws -> [PathPoint] {
    if let geometry = plane.calibration, geometry.parentCorners == frame.corners,
      geometry.angle == plane.angle, geometry.depth == plane.depth, geometry.rotationSign == plane.rotationSign {
      return geometry.corners
    }
    let (ia,ib,ic) = edgeIndices(plane.edge)
    let a=frame.points[ia],b=frame.points[ib],axis=unit(b-a),inward=frame.points[ic]-a
    let out = -unit(inward), len=length(inward)*plane.depth, angle=(180-plane.angle) * .pi/180
    func project(_ p:SIMD3<Double>)->PathPoint? { guard p.z>1e-8 else { return nil };let q=PathPoint(center.x+focal*p.x/p.z,center.y+focal*p.y/p.z);return VanishingSettings.validPoint(q) ? q:nil }
    var best:(Double,[PathPoint])?
    for sign in plane.rotationSign.map({[$0]}) ?? [1.0,-1.0] {
      let rot=rotated(out,about:axis,by:sign*angle),a2=a+rot*len,b2=b+rot*len
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
    let canvasSide = max(width,height)
    let calibratedHingeFocal = settings.planes.lazy.compactMap { plane -> Double? in
      guard settings.focalLength == 0, plane.parent == 0, plane.angle == 90,
        let calibration = plane.calibration, calibration.angle == plane.angle,
        calibration.depth == plane.depth, calibration.rotationSign == plane.rotationSign,
        calibration.parentCorners == settings.planes[0].corners else { return nil }
      return Self.inferredOrthogonalHingeFocal(parent:calibration.parentCorners,child:calibration.corners,
        edge:plane.edge,center:cameraCenter,canvasSide:canvasSide)
    }.first
    let cameraFocal = settings.focalLength > 0 ? settings.focalLength :
      (calibratedHingeFocal ?? settings.planes.first.flatMap { Self.inferredFocal($0.corners,center:cameraCenter) }
        ?? Double(canvasSide))
    center=cameraCenter;focal=cameraFocal
    var resolved: [Frame] = [], roots: [Int] = []
    for (index, plane) in settings.planes.enumerated() {
      let corners = try plane.parent.map {
        try Self.related(plane, from: resolved[$0], focal: cameraFocal, center: cameraCenter)
      } ?? plane.corners
      resolved.append(try Self.frame(corners, focal: cameraFocal, center: cameraCenter))
      roots.append(plane.parent.map { roots[$0] } ?? index)
    }
    frames = resolved
    measurementRoots = roots
    var metrics = Array(repeating:PathPoint(0,0),count:resolved.count)
    var factors = Array(repeating:0.0,count:resolved.count)
    var measurementFrames = resolved
    for root in settings.planes.indices where roots[root] == root {
      let members = settings.planes.indices.filter { roots[$0] == root }
      let inferred = Self.inferredFocal(resolved[root].corners,center:cameraCenter)
      let fromHinge = members.lazy.compactMap { index -> Double? in
        let plane = settings.planes[index]
        guard let parent = plane.parent, plane.angle == 90 else { return nil }
        return Self.inferredOrthogonalHingeFocal(parent:resolved[parent].corners,child:resolved[index].corners,
          edge:plane.edge,center:cameraCenter,canvasSide:canvasSide)
      }.first
      let preferred = root == 0 && settings.focalLength > 0 && fromHinge != nil ? cameraFocal :
        (fromHinge ?? inferred ?? (root == 0 ? cameraFocal : Double(canvasSide)))
      let focal: Double
      if preferred != cameraFocal, let local = try? members.map({
        try Self.frame(resolved[$0].corners,focal:preferred,center:cameraCenter)
      }) {
        focal = preferred
        for (index,frame) in zip(members,local) { measurementFrames[index] = frame }
      } else {
        focal = cameraFocal
      }
      let origin = measurementFrames[root].points
      let normal = Self.unit(Self.cross(origin[1]-origin[0],origin[3]-origin[0]))
      // Normalize the scale on the optical axis. For edge-on planes, use
      // the depth of a visible corner instead.
      let normalization = abs(normal.z) > 1e-9 ? abs(normal.z) : 1/origin[0].z
      for index in members {
        let plane = settings.planes[index], frame = measurementFrames[index]
        let factor: Double
        if let parent = plane.parent {
          let (parentA, _, _) = Self.edgeIndices(plane.edge)
          let (outsideA, _) = Self.outsideIndices(plane.edge)
          // Reconcile the depths of two independently normalized camera
          // intersections along their shared hinge.
          factor = factors[parent] * measurementFrames[parent].points[parentA].z / frame.points[(outsideA+3)%4].z
        } else {
          factor = focal * normalization
        }
        factors[index] = factor
        metrics[index] = .init(frame.width*factor,frame.height*factor)
      }
    }
    measurementMetrics = metrics
    marqueeLayout = VanishingMarqueeFace.layout(planes:settings.planes,metrics:metrics)
    for measurement in settings.measurements ?? [] where measurementDistance(measurement) == nil {
      throw CraftError.invalid("A measurement collapses or crosses the camera horizon.")
    }
  }
  public func plane(at point:PathPoint)->Int? { frames.indices.reversed().first{frames[$0].contains(point)} }

  public func measurementRoot(for plane: Int) -> Int { measurementRoots[plane] }

  public func measurementMetric(for plane: Int) -> PathPoint { measurementMetrics[plane] }

  public func gridIntervals(for plane: Int, settings: VanishingSettings) -> PathPoint {
    let scale = settings.measurementScale(for: measurementRoots[plane])
    if scale.linkedToGrid {
      let metric = measurementMetrics[plane]
      return .init(scale.pixelsPerUnit*frames[plane].width/metric.x,
        scale.pixelsPerUnit*frames[plane].height/metric.y)
    }
    let interval = settings.effectiveGridSize / focal
    return .init(interval,interval)
  }

  public func measurement(plane: Int, from start: PathPoint, to end: PathPoint) -> VanishingMeasurement? {
    guard frames.indices.contains(plane) else { return nil }
    let frame = frames[plane]
    let line = VanishingMeasurement(plane: plane, start: frame.uv(start), end: frame.uv(end))
    return measurementDistance(line) == nil ? nil : line
  }

  public func measurementDistance(_ line: VanishingMeasurement) -> Double? {
    guard frames.indices.contains(line.plane) else { return nil }
    let frame = frames[line.plane]
    let m = frame.map.m
    let visibleSide = (m[6] * 0.5 + m[7] * 0.5 + m[8]).sign
    for point in [line.start, line.end] {
      let w = m[6] * point.x + m[7] * point.y + m[8]
      guard VanishingSettings.validPoint(point), abs(w) > 1e-10, w.sign == visibleSide,
        VanishingSettings.validPoint(frame.point(point)) else { return nil }
    }
    let metric = measurementMetrics[line.plane]
    let distance = hypot((line.end.x-line.start.x)*metric.x,(line.end.y-line.start.y)*metric.y)
    return distance.isFinite && distance > 1e-8 ? distance : nil
  }

  public func measurementScale(calibrating index: Int, to length: Double,
    settings: VanishingSettings) throws -> VanishingMeasurementScale
  {
    let lines = settings.measurements ?? []
    guard lines.indices.contains(index), length.isFinite, length > 0,
      let distance = measurementDistance(lines[index]) else {
      throw CraftError.invalid("Select an existing measurement and enter a positive length.")
    }
    let root = measurementRoot(for:lines[index].plane)
    var scale = settings.measurementScale(for:root)
    scale.pixelsPerUnit = distance / length
    guard VanishingSettings.measurementScaleRange.contains(scale.pixelsPerUnit) else {
      throw CraftError.invalid("Vanishing Point measurement scale is out of range.")
    }
    return scale
  }

  public func measurementLength(_ line: VanishingMeasurement, settings: VanishingSettings) -> Double? {
    guard let distance = measurementDistance(line) else { return nil }
    let scale = settings.measurementScale(for: measurementRoots[line.plane])
    let length = distance / scale.pixelsPerUnit
    return length.isFinite ? length : nil
  }
}

public struct VanishingOperation:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable { case paste,clone,brush,marquee }
  public enum Heal: String, Codable, CaseIterable, Sendable { case off, luminance, on }
  public struct CanvasPaste: Codable, Equatable, Sendable {
    public static let sizeRange = 0.001...Double(Surface.maxDimension)
    public var origin: PathPoint
    public var width: Double
    public var height: Double

    public init(origin: PathPoint, width: Double, height: Double) {
      self.origin = origin
      self.width = width
      self.height = height
    }

    var isValid: Bool {
      VanishingSettings.validPoint(origin) && Self.sizeRange.contains(width) && Self.sizeRange.contains(height)
    }
  }
  public var kind:Kind
  public var plane=0
  public var at=PathPoint(0.25,0.25)
  public var width=0.5
  /// An independent paste height in units of plane width. Omission preserves source aspect ratio.
  public var pasteHeight: Double?
  /// A paste in document pixels before it is moved onto a perspective plane.
  public var canvasPaste: CanvasPaste?
  public var flip: Bool?
  public var flop: Bool?
  public var angle=0.0
  public var source:Surface?
  public var marquee: VanishingMarqueeTransfer?
  /// An optional perspective selection limiting a Brush or Stamp destination.
  public var strokeSelection: VanishingMarquee?
  /// Use the first and last points of a Brush or Stamp drag.
  public var straightStroke: Bool?
  var strokePoints: [PathPoint] {
    guard straightStroke == true, let first = points.first, let last = points.last else { return points }
    return first == last ? [first] : [first,last]
  }
  public var sourcePoint:PathPoint?
  /// Keep the donor's projection when an aligned source moves outside its face.
  public var sourcePlane: Int?
  public var points:[PathPoint]=[]
  public var diameter=40.0
  public var hardness=50.0
  public var opacity=100.0
  public var color=Pixel.black
  public var clip=true
  /// Continue painting across related faces. Omission retains existing single-plane edits.
  public var wrap: Bool?
  public var heal: Heal?
  public init(_ kind:Kind) { self.kind=kind }
}

public struct VanishingPasteGeometry: Sendable {
  public let origin: PathPoint
  public let width: Double
  public let height: Double
  private let cosine: Double
  private let sine: Double
  private let frame: VanishingScene.Frame?

  public init?(_ operation: VanishingOperation, frame: VanishingScene.Frame?) {
    guard operation.kind == .paste, let source = operation.source else { return nil }
    if let placement = operation.canvasPaste {
      origin = placement.origin
      width = placement.width
      height = placement.height
      self.frame = nil
    } else {
      guard let frame else { return nil }
      origin = .init(operation.at.x * frame.width, operation.at.y * frame.height)
      width = operation.width * frame.width
      height = operation.pasteHeight.map { $0 * frame.width } ?? width * Double(source.height) / Double(source.width)
      self.frame = frame
    }
    guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
    let radians = operation.angle * .pi / 180
    cosine = cos(radians)
    sine = sin(radians)
  }

  public func point(_ unit: PathPoint) -> PathPoint {
    let x = unit.x * width, y = unit.y * height
    return .init(origin.x+x*cosine-y*sine,origin.y+x*sine+y*cosine)
  }

  public func unit(at point: PathPoint) -> PathPoint {
    let dx = point.x-origin.x, dy = point.y-origin.y
    return .init((dx*cosine+dy*sine)/width,(-dx*sine+dy*cosine)/height)
  }

  public func metric(_ imagePoint: PathPoint) -> PathPoint { frame?.metric(imagePoint) ?? imagePoint }

  public func imagePoint(_ unit: PathPoint) -> PathPoint {
    let metricPoint = point(unit)
    return frame?.projected(metricPoint) ?? metricPoint
  }

  func isInsidePlane(_ imagePoint: PathPoint) -> Bool { frame?.contains(imagePoint) ?? true }

  public func projectedCorners() -> [PathPoint]? {
    let corners = [PathPoint(0,0),.init(1,0),.init(1,1),.init(0,1)].map(imagePoint)
    return PerspectiveSettings.validQuad(corners) ? corners : nil
  }
}

public struct VanishingProgram:Codable,Equatable,Sendable {
  public var settings=VanishingSettings()
  public var operations:[VanishingOperation]=[]
  public var newLayer=false
  /// An opt-in write for this edit. Editable lines remain with the document.
  public var renderMeasurements: Bool?
  var drawsMeasurements: Bool { renderMeasurements == true && !(settings.measurements?.isEmpty ?? true) }
  public init() {}
  public func validate() throws {
    try settings.validate();guard operations.count<=256,operations.reduce(0,{$0+$1.points.count})<=16384,operations.reduce(0,{$0+($1.source?.allocatedBytes ?? 0)})<=134_217_728 else { throw CraftError.unsupported("Vanishing Point exceeds the operation or source memory limit.") }
    for op in operations {
      let placementIsValid = op.canvasPaste?.isValid ?? settings.planes.indices.contains(op.plane)
      guard placementIsValid,VanishingSettings.validPoint(op.at),op.width.isFinite,(0.001...20).contains(op.width),op.angle.isFinite,(-360...360).contains(op.angle),op.diameter.isFinite,(1...2000).contains(op.diameter),op.hardness.isFinite,(0...100).contains(op.hardness),op.opacity.isFinite,(0...100).contains(op.opacity),op.color.isFinite,(0...1).contains(op.color.a),op.points.count<=4096,op.points.allSatisfy({VanishingSettings.validPoint($0)}),op.sourcePoint.map({VanishingSettings.validPoint($0)}) ?? true else { throw CraftError.invalid("Invalid Vanishing Point operation.") }
      if op.kind != .paste, op.canvasPaste != nil || op.pasteHeight != nil || op.flip != nil || op.flop != nil {
        throw CraftError.invalid("Paste transforms require a pasted source.")
      }
      switch op.kind {
      case .paste:
        guard op.wrap == nil,op.sourcePlane == nil,op.strokeSelection == nil,op.straightStroke == nil,op.marquee == nil,let source=op.source,source.width<=WarpRaster.maximumPixels/source.height,
          op.points.isEmpty,op.sourcePoint==nil,op.pasteHeight.map({ (0.001...20).contains($0) }) ?? true else {
          throw CraftError.invalid("Paste requires bounded source pixels and dimensions.")
        }
        try source.validated()
      case .marquee:
        guard op.wrap == nil,op.sourcePlane == nil,op.strokeSelection == nil,op.straightStroke == nil,let patch = op.marquee,patch.destination.plane == op.plane,settings.planes.indices.contains(patch.source.plane),
          patch.source.hasValidBounds,patch.destination.hasValidBounds,VanishingMarqueeTransfer.featherRange.contains(patch.feather),
          op.source == nil,op.points.isEmpty,op.sourcePoint == nil else { throw CraftError.invalid("Invalid perspective marquee patch.") }
      case .brush,.clone:
        guard op.marquee == nil,op.source==nil,!op.points.isEmpty,op.kind != .clone || op.sourcePoint != nil else { throw CraftError.invalid("Painting requires points; cloning also requires a source point.") }
        if let selection = op.strokeSelection {
          guard settings.planes.indices.contains(selection.plane),selection.hasValidBounds else {
            throw CraftError.invalid("Invalid perspective stroke selection.")
          }
        }
        if let plane = op.sourcePlane {
          guard op.kind == .clone,op.wrap == true,settings.planes.indices.contains(plane) else {
            throw CraftError.invalid("Invalid linked Stamp source plane.")
          }
        }
      }
    }
  }
}
