import Foundation
import PhotoCraftCore

/// Photoshop image resource 4000 stores perspective planes as relations of four rays.
enum PSDVanishingPoint {
  static let id = 4000
  static let importedKey = "psdVanishingPoint"
  private static let maximumPayload = 64 * 1024
  private static let parallelOffset = 0.25

  private struct Cursor {
    let words: [Substring]
    var offset = 0
    mutating func next() throws -> Substring {
      guard words.indices.contains(offset) else { throw invalid() }
      defer { offset += 1 }
      return words[offset]
    }
    mutating func integer<T: FixedWidthInteger>(_ type: T.Type = Int.self) throws -> T {
      guard let value = T(try next()) else { throw invalid() }
      return value
    }
    mutating func number() throws -> Double {
      guard let value = Double(try next()), value.isFinite else { throw invalid() }
      return value
    }
    mutating func point() throws -> PathPoint { try .init(number(), number()) }
  }

  private struct Ray {
    let origin: PathPoint
    let vanisher: PathPoint
    let endpoint: Bool
    let axis: Int
    let tag: Int

    var line: SIMD3<Double> {
      let dx = vanisher.x-origin.x, dy = vanisher.y-origin.y
      let length = hypot(dx,dy)
      return length > 0 ? .init(dy/length,-dx/length,(dx*origin.y-dy*origin.x)/length) : .zero
    }
  }

  private struct Plane {
    let grid: Double
    let identity: UInt32
    let parent: UInt32
    let angle: Double?
    let calibrationAxis: Int?
    let calibrationPoint: PathPoint?
    let rays: [Int: Ray]

    var recordedFold: Double? {
      guard let angle else { return nil }
      // The stored orientation starts a quarter turn away from coplanar.
      let difference = abs(90-angle).truncatingRemainder(dividingBy:360)
      return min(difference,360-difference)
    }

    func hasRightAngleGuide(relativeTo parent: Plane) -> Bool {
      guard let angle, let axis = calibrationAxis, let guide = calibrationPoint,
        abs(angle) == 90 || recordedFold == 90,
        !parent.rays.values.contains(where: { $0.axis == axis }) else { return false }
      let across = rays.values.filter { $0.axis == axis }
      // Older Photato exports regularize parallel directions with a small
      // corner offset. Their transverse rays can miss the normal slightly.
      return across.count == 2 && across.allSatisfy {
        !$0.endpoint && PSDVanishingPoint.distance($0.vanisher,guide) <= 2
      }
    }

    func vanishingPoint(axis: Int) -> PathPoint? {
      let directions = rays.values.filter { $0.axis == axis && !$0.endpoint }
      guard directions.count == 2, directions[0].vanisher == directions[1].vanisher else { return nil }
      return directions[0].vanisher
    }

    /// The principal point is the orthocenter of three finite orthogonal
    /// vanishing points. Use the camera recorded by the guide even when the
    /// principal point is off-center in the document.
    func recordedCamera(relativeTo parent: Plane) -> (center: PathPoint, focal: Double)? {
      guard let childAxis = calibrationAxis, let guide = calibrationPoint,
        let across = vanishingPoint(axis:childAxis),
        recordedFold != 90 || across == guide else { return nil }
      let parentAxes = Set(parent.rays.values.map(\.axis))
      let sharedAxes = parentAxes.intersection(rays.values.map(\.axis))
      guard sharedAxes.count == 1, let commonAxis = sharedAxes.first,
        childAxis != commonAxis, !parentAxes.contains(childAxis),
        let parentAxis = parentAxes.subtracting(sharedAxes).first,
        let a = parent.vanishingPoint(axis:parentAxis),
        let c = parent.vanishingPoint(axis:commonAxis),
        vanishingPoint(axis:commonAxis) == c else { return nil }

      // Take the first altitude from a as the origin for the intersection.
      let sx = guide.x-c.x, sy = guide.y-c.y, tx = a.x-c.x, ty = a.y-c.y
      let determinant = sx*ty-sy*tx
      guard abs(determinant) > 1e-8 * hypot(sx,sy) * hypot(tx,ty) else { return nil }
      let altitude = ((guide.x-a.x)*tx+(guide.y-a.y)*ty)/determinant
      let center = PathPoint(a.x-sy*altitude,a.y+sx*altitude)
      let square = -((a.x-center.x)*(guide.x-center.x)+(a.y-center.y)*(guide.y-center.y))
      guard max(abs(center.x),abs(center.y)) <= 1_000_000, square.isFinite, square > 1 else { return nil }
      return (center,sqrt(square))
    }

    func corners() throws -> [PathPoint] {
      try [(3,5),(5,7),(7,1),(1,3)].map { a,b in
        let l = rays[a]!.line, r = rays[b]!.line
        let w = l.x*r.y-l.y*r.x
        guard abs(w)>1e-12 else { throw invalid() }
        let point = PathPoint((l.y*r.z-l.z*r.y)/w,(l.z*r.x-l.x*r.z)/w)
        guard point.x.isFinite, point.y.isFinite else { throw invalid() }
        return point
      }
    }

    func rootCorners(restoreSquare: Bool) throws -> [PathPoint] {
      let ring = try corners()
      let sides = [5,7,1,3]
      let widthAxis = min(rays[1]!.axis,rays[7]!.axis)
      let cross = (ring[1].x-ring[0].x)*(ring[2].y-ring[0].y)-(ring[1].y-ring[0].y)*(ring[2].x-ring[0].x)
      let step = cross > 0 ? 1 : -1
      let candidates = (0..<4).filter { rays[sides[step>0 ? $0 : ($0+3)%4]]!.axis == widthAxis }
      guard let start = candidates.min(by:{ ring[$0].x+ring[$0].y < ring[$1].x+ring[$1].y }) else { throw invalid() }
      let q = (0..<4).map { ring[(start+4+$0*step)%4] }
      guard restoreSquare, let marker = calibrationPoint,
        let across = direction(from: marker, to: q[2]),
        let down = direction(from: q[1], to: q[2]),
        abs(across.x*down.x + across.y*down.y) < 1e-6 else { return q }
      // The square-to-camera record offsets the top-right and bottom-left ray
      // origins. The calibration point still gives the original bottom-left.
      let outside = offset(marker, by: across, distance: -parallelOffset)
      guard distance(outside, q[3]) < 1e-5 else { return q }
      let upperRight = offset(q[1], by: down, distance: parallelOffset)
      let upperLeft = PathPoint(upperRight.x+marker.x-q[2].x,upperRight.y+marker.y-q[2].y)
      guard distance(q[0], upperLeft) < parallelOffset else { return q }
      return [upperLeft, upperRight, q[2], marker]
    }
  }

  private struct Measurement {
    let plane: UInt32
    let start: PathPoint
    let end: PathPoint
  }

  private struct Resource {
    let planes: [Plane]
    let footer: [String]
    let relationGridIndices: [Int]
    let footerIndex: Int
    let measurements: [Measurement]
    let scales: [VanishingMeasurementScale]
    var gridSize: Double? {
      let precise = footer.dropFirst().first.flatMap(Double.init)
      let size = precise ?? planes.first?.grid ?? VanishingSettings.defaultGridSize
      return VanishingSettings.gridSizeRange.contains(size)
        && size != VanishingSettings.defaultGridSize ? size : nil
    }
  }

  private static func invalid() -> CraftError { .invalid("Invalid Photoshop perspective plane resource.") }

  private static func distance(_ a: PathPoint, _ b: PathPoint) -> Double {
    hypot(a.x-b.x,a.y-b.y)
  }

  private static func direction(from a: PathPoint, to b: PathPoint) -> PathPoint? {
    let length = distance(a,b)
    guard length > 1 else { return nil }
    return .init((b.x-a.x)/length,(b.y-a.y)/length)
  }

  private static func offset(_ p: PathPoint, by d: PathPoint, distance: Double) -> PathPoint {
    .init(p.x+d.x*distance,p.y+d.y*distance)
  }

  private static func signedDistance(_ point: PathPoint, from origin: PathPoint, along axis: PathPoint) -> Double {
    (point.x-origin.x)*axis.x + (point.y-origin.y)*axis.y
  }

  private static func decimal(_ value: Double) -> String {
    if value.isFinite, abs(value) < 1e15, value == value.rounded() { return String(Int64(value)) }
    return String(format:"%.12g",locale:Locale(identifier:"en_US_POSIX"),value)
  }

  private static func updatingFooter(in data: Data, resource: Resource, sizes: [Double],
    measurementFooter: [String]? = nil) throws -> Data
  {
    guard let source = String(data:data,encoding:.ascii) else { throw invalid() }
    let words = source.split(whereSeparator: \.isWhitespace)
    let legacy = sizes.map { decimal(max(1,$0.rounded(.towardZero))) }
    var replacements = Array(zip(resource.relationGridIndices,legacy))
    if measurementFooter == nil {
      replacements += sizes.enumerated().map { (resource.footerIndex+1+$0.offset,decimal($0.element)) }
    }
    var text = "", last = source.startIndex
    for (index, value) in replacements {
      let token = words[index]
      text += source[last..<token.startIndex] + value
      last = token.endIndex
    }
    if let measurementFooter {
      text += source[last..<words[resource.footerIndex].startIndex]
      text += measurementFooter.joined(separator:"\n") + "\n"
    } else {
      text += source[last...]
    }
    return Data(text.utf8)
  }

  private static func gridSizes(for settings: VanishingSettings, previous: Resource?) -> [Double] {
    let roots = settings.planes.indices.filter { settings.planes[$0].parent == nil }
    let oldSizes = previous?.footer.dropFirst().prefix(roots.count).compactMap(Double.init) ?? []
    return roots.enumerated().map { ordinal, root in
      let scale = settings.measurementScale(for:root)
      if scale.linkedToGrid { return scale.pixelsPerUnit }
      if previous?.gridSize == settings.gridSize, oldSizes.indices.contains(ordinal) {
        return oldSizes[ordinal]
      }
      return settings.effectiveGridSize
    }
  }

  private static func measurementFooter(_ settings: VanishingSettings, scene: VanishingScene,
    sizes: [Double], label: (Int) -> UInt32) -> [String]
  {
    let roots = settings.planes.indices.filter { settings.planes[$0].parent == nil }
    let lines = settings.measurements ?? []
    var tokens = ["201"] + sizes.map(decimal) + [String(lines.count)]
    for root in roots {
      for line in lines where scene.measurementRoot(for:line.plane) == root {
        let frame = scene.frames[line.plane]
        let a = frame.point(line.start), b = frame.point(line.end)
        tokens += [String(label(line.plane)),decimal(a.x),decimal(a.y),decimal(b.x),decimal(b.y)]
      }
    }
    for root in roots {
      let scale = settings.measurementScale(for:root)
      tokens += [decimal(scale.pixelsPerUnit),scale.linkedToGrid ? "1" : "0"]
    }
    return tokens
  }

  private static func isVanishingPoint(_ block: PSDImageResources.Block) -> Bool {
    guard block.id == id, block.data.count >= 7,
      let prefix = String(data:block.data.prefix(4),encoding:.ascii)?.lowercased() else { return false }
    return prefix == "tnaf" || prefix == "fant"
  }

  private static func decode(_ data: Data) throws -> Resource {
    guard data.count <= maximumPayload, let source = String(data:data,encoding:.ascii) else { throw invalid() }
    var input = Cursor(words:source.split(whereSeparator: \.isWhitespace))
    let header = try input.next().dropFirst(4)
    guard let version = Int(header), version == 101 || version == 203 else { throw invalid() }
    let relations: Int = try input.integer()
    guard (1...32).contains(relations) else { throw invalid() }
    var planes: [Plane] = []
    var identities = Set<UInt32>()
    var relationGridIndices: [Int] = []
    for _ in 0..<relations {
      try Task.checkCancellation()
      relationGridIndices.append(input.offset)
      let grid = try input.number()
      let count: Int = try input.integer()
      guard grid > 0, count > 0, count <= 32-planes.count else { throw invalid() }
      var family = Set<UInt32>()
      for index in 0..<count {
        let identity = try input.integer(UInt32.self)
        let parent = try input.integer(UInt32.self)
        guard identity != 0, identities.insert(identity).inserted,
          index == 0 ? parent == 0 : family.contains(parent) else { throw invalid() }
        family.insert(identity)
        let angle: Double?, calibrationAxis: Int?, calibrationPoint: PathPoint?
        if version == 203 {
          let degrees = try input.number()
          let selector: Int = try input.integer()
          calibrationPoint = try input.point()
          guard (0...2).contains(selector), (-180...360).contains(degrees) else { throw invalid() }
          angle = index == 0 ? nil : degrees
          calibrationAxis = index == 0 ? nil : selector
        } else {
          angle = nil
          calibrationAxis = nil
          calibrationPoint = nil
        }
        var rays: [Int: Ray] = [:]
        for _ in 0..<4 {
          let origin = try input.point(), vanisher = try input.point()
          let endpoint: Int = try input.integer()
          let axis: Int = try input.integer()
          let tag: Int = try input.integer()
          guard (0...1).contains(endpoint), (0...2).contains(axis), [1,3,5,7].contains(tag),
            rays[tag] == nil, origin != vanisher else { throw invalid() }
          rays[tag] = .init(origin:origin,vanisher:vanisher,endpoint:endpoint == 1,axis:axis,tag:tag)
        }
        guard rays[1]!.axis == rays[5]!.axis, rays[3]!.axis == rays[7]!.axis,
          rays[1]!.axis != rays[7]!.axis else { throw invalid() }
        planes.append(.init(grid:grid,identity:identity,parent:parent,angle:angle,
          calibrationAxis:calibrationAxis,calibrationPoint:calibrationPoint,rays:rays))
      }
    }
    let footerIndex = input.offset
    let footer = input.words.dropFirst(footerIndex).map(String.init)
    var measurements: [Measurement] = [], scales: [VanishingMeasurementScale] = []
    if !footer.isEmpty {
      guard version == 203, try input.next() == "201" else { throw invalid() }
      for _ in 0..<relations { guard try input.number() > 0 else { throw invalid() } }
      let count: Int = try input.integer()
      guard (0...VanishingSettings.maximumMeasurements).contains(count) else { throw invalid() }
      for _ in 0..<count {
        let owner = try input.integer(UInt32.self)
        guard identities.contains(owner) else { throw invalid() }
        measurements.append(try .init(plane:owner,start:input.point(),end:input.point()))
      }
      for index in planes.indices where planes[index].parent == 0 {
        let scale = try input.number()
        let linked: Int = try input.integer()
        guard VanishingSettings.measurementScaleRange.contains(scale), (0...1).contains(linked) else {
          throw invalid()
        }
        if linked == 1 || scale != VanishingSettings.defaultMeasurementScale {
          scales.append(.init(root:index,pixelsPerUnit:scale,linkedToGrid:linked == 1))
        }
      }
      guard input.offset == input.words.count else { throw invalid() }
    }
    return Resource(planes:planes,footer:footer,relationGridIndices:relationGridIndices,
      footerIndex:footerIndex,measurements:measurements,scales:scales)
  }

  private static func points(_ edge: VanishingPlane.Edge) -> (parentA: Int,parentB: Int,childA: Int,childB: Int) {
    switch edge {
    case .top: (0,1,3,2)
    case .right: (1,2,0,3)
    case .bottom: (2,3,1,0)
    case .left: (3,0,2,1)
    }
  }

  private static func linkedCorners(_ ring: [PathPoint], parent: [PathPoint])
    throws -> (VanishingPlane.Edge,[PathPoint])
  {
    func distance(_ a: PathPoint,_ b: PathPoint) -> Double { hypot(a.x-b.x,a.y-b.y) }
    var best: (edge: VanishingPlane.Edge, corners: [PathPoint], distance: Double)?
    for edge in VanishingPlane.Edge.allCases {
      let p = points(edge)
      for first in 0..<4 {
        for order in [1,-1] {
          var q=(0..<4).map { ring[(first+4+order*$0)%4] }
          let a=parent[p.parentA], b=parent[p.parentB]
          let error=distance(a,q[p.childA])+distance(b,q[p.childB])
          if best.map({error < $0.distance}) ?? true {
            q[p.childA]=a
            q[p.childB]=b
            best=(edge,q,error)
          }
        }
      }
    }
    let maximum = (parent+ring).reduce(0.0) { max($0,abs($1.x),abs($1.y)) }
    guard let best, best.distance <= max(0.06,maximum*0.000012) else { throw invalid() }
    return (best.edge,best.corners)
  }

  private static func settings(_ resource: Resource, width: Int, height: Int) throws -> VanishingSettings {
    var result = VanishingSettings()
    result.gridSize = resource.gridSize
    let canvasCenter = PathPoint(Double(width)/2,Double(height)/2)
    let parents = Set(resource.planes.map(\.parent))
    let rootRecords = resource.planes.filter { $0.parent == 0 }
    let roots = try rootRecords.map {
      try $0.rootCorners(restoreSquare: !parents.contains($0.identity))
    }
    let canvasSide = max(width,height)
    func hingeFocal(_ link: (VanishingPlane.Edge,[PathPoint]), parent: [PathPoint], center: PathPoint) -> Double? {
      VanishingScene.inferredOrthogonalHingeFocal(parent:parent,child:link.1,edge:link.0,
        center:center,canvasSide:canvasSide)
    }
    let cameraFromHinge = rootRecords.first.flatMap { first in
      var single = VanishingSettings()
      single.planes = [.init(corners:roots[0])]
      return resource.planes.lazy.compactMap { item -> (center: PathPoint, focal: Double)? in
        guard item.parent == first.identity,
          let ring = try? item.corners(),
          let link = try? linkedCorners(ring,parent:roots[0]) else { return nil }
        if let recorded = item.recordedCamera(relativeTo:first), let fold = item.recordedFold {
          var trial = single
          trial.center = recorded.center
          trial.focalLength = recorded.focal
          if let scene = try? VanishingScene(trial,width:width,height:height),
            let measured = try? scene.calibratedPlane(parent:0,edge:link.0,corners:link.1),
            abs(180-measured.angle-fold) < 0.25 {
            return recorded
          }
        }
        guard item.hasRightAngleGuide(relativeTo:first) else { return nil }
        return hingeFocal(link,parent:roots[0],center:canvasCenter).map { (canvasCenter,$0) }
      }.first
    }
    let center = cameraFromHinge?.center ?? canvasCenter
    result.center = center
    result.focalLength = cameraFromHinge?.focal
      ?? roots.lazy.compactMap { VanishingScene.inferredFocal($0,center:center) }.first
      ?? Double(canvasSide)
    var indices: [UInt32:Int] = [:]
    let records = Dictionary(uniqueKeysWithValues: resource.planes.map { ($0.identity,$0) })
    var rootIndex = 0
    for item in resource.planes {
      try Task.checkCancellation()
      let plane: VanishingPlane
      if item.parent == 0 {
        plane = .init(corners:roots[rootIndex])
        rootIndex += 1
      } else {
        guard let parent = indices[item.parent], let parentRecord = records[item.parent] else { throw invalid() }
        let scene = try VanishingScene(result,width:width,height:height)
        let parentCorners = scene.frames[parent].corners
        let link = try linkedCorners(item.corners(),parent:parentCorners)
        let orthogonal = item.hasRightAngleGuide(relativeTo:parentRecord)
          && hingeFocal(link,parent:parentCorners,center:center) != nil
        let measured = try? scene.calibratedPlane(parent:parent,edge:link.0,corners:link.1)
        let recordedFold: Double? = item.recordedFold.flatMap { fold in
          guard let measured, abs(180-measured.angle-fold) < 0.25 else { return nil }
          return fold
        }
        let legacyAngle = item.angle.flatMap { abs($0) <= 180 ? $0 : nil }
        plane = try scene.calibratedPlane(parent:parent,edge:link.0,corners:link.1,
          angleFromCoplanar:recordedFold ?? (orthogonal ? 90 : legacyAngle))
      }
      indices[item.identity]=result.planes.count
      result.planes.append(plane)
    }
    let scene = try VanishingScene(result,width:width,height:height)
    if !resource.measurements.isEmpty {
      result.measurements = try resource.measurements.map { line in
        guard let plane = indices[line.plane],
          let measurement = scene.measurement(plane:plane,from:line.start,to:line.end) else { throw invalid() }
        return measurement
      }
    }
    result.measurementScales = resource.scales.isEmpty ? nil : resource.scales
    try result.validate()
    return result
  }

  static func read(_ resources: [PSDImageResources.Block], width: Int, height: Int) throws -> VanishingSettings? {
    let candidates = resources.filter(isVanishingPoint)
    guard candidates.count == 1 else { return nil }
    do { return try settings(decode(candidates[0].data),width:width,height:height) }
    catch let error as CancellationError { throw error }
    catch { return nil } // Unrecognized versions and geometry stay intact as opaque resources.
  }

  private struct Axis {
    let vanisher: PathPoint?
    let label: Int
  }

  private static func projectedDirection(_ vector: SIMD3<Double>, scene: VanishingScene) -> PathPoint? {
    guard abs(vector.z) > 1e-10 * max(1,abs(vector.x),abs(vector.y)) else { return nil }
    let result = PathPoint(scene.center.x+scene.focal*vector.x/vector.z,scene.center.y+scene.focal*vector.y/vector.z)
    return result.x.isFinite && result.y.isFinite ? result : nil
  }

  private static func axisDirections(_ corners: [PathPoint]) -> [SIMD3<Double>] {
    func product(_ a: SIMD3<Double>,_ b: SIMD3<Double>) -> SIMD3<Double> {
      .init(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x)
    }
    func line(_ a: PathPoint,_ b: PathPoint) -> SIMD3<Double> {
      product(.init(a.x,a.y,1),.init(b.x,b.y,1))
    }
    return [product(line(corners[0],corners[1]),line(corners[3],corners[2])),
            product(line(corners[0],corners[3]),line(corners[1],corners[2]))]
  }

  private static func vanishingPoint(_ value: SIMD3<Double>) -> PathPoint? {
    guard abs(value.z) > 1e-12 * max(1,abs(value.x),abs(value.y)) else { return nil }
    return .init(value.x/value.z,value.y/value.z)
  }

  private static func rays(_ q: [PathPoint], axes: [Axis]) -> [Ray] {
    func distance(_ p: PathPoint,_ vp: PathPoint) -> Double { hypot(p.x-vp.x,p.y-vp.y) }
    func edge(_ start: Int,_ axis: Int) -> Int { start % 2 == axis ? start : (start+3)%4 }
    func farther(_ start: Int,_ axis: Int) -> Bool {
      guard let vp = axes[axis].vanisher else { return true }
      let first=edge(start,axis), second=(first+1)%4
      let other = first == start ? second : first
      return distance(q[start],vp) >= distance(q[other],vp)
    }
    let primary = [2,1,3,0].first { farther($0,0) && farther($0,1) } ?? 2
    var output: [Ray] = []
    for axis in 0..<2 {
      let axisRecord=axes[axis]
      let base=edge(primary,axis)
      let firstTag = axisRecord.label < axes[1-axis].label ? 1 : 7
      for (side,tag) in [(base,firstTag),((base+2)%4,firstTag == 1 ? 5 : 3)] {
        let next=(side+1)%4
        let start = tag == firstTag ? primary : (farther(side,axis) ? side : next)
        let end = start == side ? next : side
        output.append(Ray(origin:q[start],vanisher:axisRecord.vanisher ?? q[end],
          endpoint:axisRecord.vanisher == nil,axis:axisRecord.label,tag:tag))
      }
    }
    return [1,5,7,3].compactMap { tag in output.first { $0.tag == tag } }
  }

  private static func encode(_ document: VanishingSettings, width: Int, height: Int, previous: Resource?) throws -> Data {
    let original = try VanishingScene(document,width:width,height:height)
    let roots = document.planes.indices.filter { document.planes[$0].parent == nil }
    var projected = document
    var squareMarkers: [Int:PathPoint] = [:]
    for index in roots {
      let q = original.frames[index].corners
      let vanishing = axisDirections(q).map(vanishingPoint)
      let parallelAcross = vanishing[0] == nil, parallelDown = vanishing[1] == nil
      guard parallelAcross || parallelDown,
        let across = direction(from:q[3],to:q[2]),
        let down = direction(from:q[1],to:q[2]) else { continue }
      if parallelAcross && parallelDown {
        // A front-facing rectangle uses the same quarter-pixel convention as
        // Photoshop's square-to-camera plane preset.
        guard abs(across.x*down.x + across.y*down.y) < 1e-6 else { continue }
        squareMarkers[index] = q[3]
      }
      if parallelAcross {
        // Keep the known vanishing point on the unmodified pair of edges.
        // The distant point must tend away from it relative to the camera.
        if let finite = vanishing[1], signedDistance(finite,from:original.center,along:across) < 0,
          let opposite = direction(from:q[0],to:q[3]) {
          projected.planes[index].corners[0] = offset(q[0],by:opposite,distance:-parallelOffset)
        } else {
          projected.planes[index].corners[1] = offset(q[1],by:down,distance:-parallelOffset)
        }
      }
      if parallelDown {
        if let finite = vanishing[0], signedDistance(finite,from:original.center,along:down) < 0,
          let opposite = direction(from:q[0],to:q[1]) {
          projected.planes[index].corners[0] = offset(q[0],by:opposite,distance:-parallelOffset)
        } else {
          projected.planes[index].corners[3] = offset(q[3],by:across,distance:-parallelOffset)
        }
      }
    }
    projected.focalLength = original.focal
    projected.center = original.center
    let scene = projected.planes == document.planes ? original
      : try VanishingScene(projected,width:width,height:height)
    let sizes = gridSizes(for:document,previous:previous)
    let legacy = previous?.planes.filter { $0.parent == 0 }.map(\.grid) ?? []
    let gridChanged = previous?.gridSize != document.gridSize
    var tokens = ["tNaF203",String(roots.count)]
    var labels: [Int:[Int]] = [:]
    func visit(_ node: Int) -> [Int] {
      [node] + document.planes.indices.filter { document.planes[$0].parent == node }.flatMap(visit)
    }
    // Photoshop's point reader consumes a blank line following each pair.
    func point(_ p: PathPoint) { tokens += [decimal(p.x),decimal(p.y),""] }
    for (ordinal,root) in roots.enumerated() {
      let family = visit(root)
      tokens += [decimal(!gridChanged && legacy.indices.contains(ordinal)
        && !document.measurementScale(for:root).linkedToGrid
        ? legacy[ordinal] : max(1,sizes[ordinal].rounded(.towardZero))),String(family.count)]
      for index in family {
        try Task.checkCancellation()
        let plane=document.planes[index], q=scene.frames[index].corners
        let vanishing = axisDirections(q).map(vanishingPoint)
        let axes: [Int]
        tokens += [String(index+1),String(plane.parent.map{$0+1} ?? 0)]
        if let parent=plane.parent, let parentAxes=labels[parent] {
          let seam: Int
          switch plane.edge {
          case .top,.bottom: seam=0
          case .left,.right: seam=1
          }
          let next=(0...2).first { !parentAxes.contains($0) }!
          axes = seam==0 ? [parentAxes[0],next] : [next,parentAxes[1]]
          let measured = try scene.calibratedPlane(parent:parent,edge:plane.edge,corners:q,
            angleFromCoplanar:180-plane.angle)
          let signed=(180-plane.angle)*(plane.rotationSign ?? measured.rotationSign ?? 1)
          let orientation = 90-signed
          let p=scene.frames[parent].points
          let h=p[1]-p[0], v=p[3]-p[0]
          let normal=SIMD3(h.y*v.z-h.z*v.y,h.z*v.x-h.x*v.z,h.x*v.y-h.y*v.x)
          tokens += [decimal(orientation < 0 ? orientation+360 : orientation),String(next)]
          point(projectedDirection(normal,scene:scene) ?? vanishing[1-seam] ?? q[(seam+1)%4])
        } else {
          axes=[0,1]
          tokens += ["-1","0"]
          point(squareMarkers[index] ?? vanishing[0] ?? q[1])
        }
        labels[index]=axes
        let records = rays(q,axes:(0..<2).map{ Axis(vanisher:vanishing[$0],label:axes[$0]) })
        for ray in records {
          point(ray.origin)
          point(ray.vanisher)
          tokens += [ray.endpoint ? "1" : "0",String(ray.axis),String(ray.tag)]
        }
      }
    }
    tokens += measurementFooter(document,scene:original,sizes:sizes) { UInt32($0+1) }
    return Data((tokens.joined(separator:"\n")+"\n").utf8)
  }

  /// Preserve the original recognized record when the edit only changes pixels.
  static func applying(to data: Data, document: CraftDocument) throws -> Data {
    let hasImportedPlane = document.sourceMetadata?[importedKey] != nil
    guard document.vanishingPoint != nil || hasImportedPlane else { return data }
    let blocks = try PSDImageResources.blocks(data)
    let candidates = blocks.filter(isVanishingPoint)
    guard let settings = document.vanishingPoint, !settings.planes.isEmpty else {
      if !hasImportedPlane { return data }
      return blocks.filter { !isVanishingPoint($0) }.reduce(into:Data()) { $0.append($1.raw) }
    }
    guard candidates.count <= 1,
      !blocks.contains(where:{ $0.id == id && !isVanishingPoint($0) }) else {
      throw CraftError.unsupported("The PSD already contains an unrecognized perspective resource.")
    }
    let existing = candidates.first
    let previous: Resource?
    if let existing {
      do { previous = try decode(existing.data) }
      catch let error as CancellationError { throw error }
      catch { throw CraftError.unsupported("The PSD perspective resource can't be edited in this version.") }
    } else {
      previous = nil
    }
    if let existing, let previous {
      let original = try self.settings(previous,width:document.width,height:document.height)
      if original == settings { return data }
      if original.withDisplayMetadata(from:settings) == settings, !previous.footer.isEmpty {
        let sizes = gridSizes(for:settings,previous:previous)
        let metadataChanged = original.measurements != settings.measurements
          || original.measurementScales != settings.measurementScales
        let footer: [String]?
        if metadataChanged {
          let scene = try VanishingScene(settings,width:document.width,height:document.height)
          footer = measurementFooter(settings,scene:scene,sizes:sizes) { previous.planes[$0].identity }
        } else {
          footer = nil
        }
        let payload = try updatingFooter(in:existing.data,resource:previous,sizes:sizes,measurementFooter:footer)
        let block = try PSDImageResources.replacing(existing,id:id,payload:payload)
        return blocks.reduce(into:Data()) { $0.append(isVanishingPoint($1) ? block : $1.raw) }
      }
    }
    let payload = try encode(settings,width:document.width,height:document.height,previous:previous)
    let block = try PSDImageResources.replacing(existing,id:id,payload:payload)
    return blocks.filter { !isVanishingPoint($0) }.reduce(into:Data()) { $0.append($1.raw) } + block
  }
}
