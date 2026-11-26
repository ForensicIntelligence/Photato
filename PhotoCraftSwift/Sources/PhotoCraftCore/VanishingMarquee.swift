import Foundation

/// A rectangle in a rectified Vanishing Point plane. Bounds are plane fractions.
public struct VanishingMarquee: Codable, Equatable, Sendable {
  public var plane: Int
  public var lower: PathPoint
  public var upper: PathPoint
  /// Optional for existing programs, which use the anchor plane alone.
  public var wrap: Bool?

  public init(plane: Int, lower: PathPoint, upper: PathPoint, wrap: Bool? = nil) {
    self.plane = plane
    self.lower = lower
    self.upper = upper
    self.wrap = wrap
  }

  public var center: PathPoint { lower.interpolated(to:upper,at:0.5) }
  var width: Double { upper.x-lower.x }
  var height: Double { upper.y-lower.y }
  var hasValidBounds: Bool {
    VanishingSettings.validPoint(lower) && VanishingSettings.validPoint(upper) && width > 0 && height > 0
  }

  public func translated(_ delta: PathPoint) -> Self {
    .init(plane:plane,lower:.init(lower.x+delta.x,lower.y+delta.y),upper:.init(upper.x+delta.x,upper.y+delta.y),wrap:wrap)
  }

  public func scaled(by factor: Double) -> Self {
    .init(plane:plane,lower:center.interpolated(to:lower,at:factor),upper:center.interpolated(to:upper,at:factor),wrap:wrap)
  }

  public func point(_ unit: PathPoint) -> PathPoint {
    .init(lower.x+unit.x*width,lower.y+unit.y*height)
  }

  /// Movement between planes keeps physical extent and the pointer's offset within the rectangle.
  public func moved(from: PathPoint, to: PathPoint, plane newPlane: Int, scene: VanishingScene,
    constrained: Bool = false, angle: Double = 0) -> Self?
  {
    guard scene.frames.indices.contains(plane),scene.frames.indices.contains(newPlane) else { return nil }
    let frame = scene.frames[plane], target = scene.frames[newPlane]
    if wrap == true,scene.measurementRoot(for:plane) == scene.measurementRoot(for:newPlane) {
      let startPlane = scene.marqueePlane(at:from,relativeTo:plane) ?? plane
      let anchor = scene.marqueeLayout[plane]
      let a = anchor.uv(scene.marqueeLayout[startPlane].point(scene.frames[startPlane].uv(from)))
      let b = anchor.uv(scene.marqueeLayout[newPlane].point(target.uv(to)))
      var dx = b.x-a.x,dy = b.y-a.y
      if constrained {
        if abs(dx*anchor.size.x) >= abs(dy*anchor.size.y) { dy = 0 } else { dx = 0 }
      }
      let rect = translated(.init(dx,dy))
      return rect.hasValidBounds ? rect : nil
    }
    if plane == newPlane {
      let a = frame.metric(from), b = frame.metric(to)
      var dx = b.x-a.x, dy = b.y-a.y
      if constrained {
        if abs(dx) >= abs(dy) { dy = 0 } else { dx = 0 }
      }
      let result = translated(.init(dx/frame.width,dy/frame.height))
      return result.projectedCorners(in:scene,angle:angle) == nil ? nil : result
    }

    let start = frame.uv(from), end = target.uv(to)
    let originalScale = scene.measurementMetric(for:plane), newScale = scene.measurementMetric(for:newPlane)
    let sx = originalScale.x/newScale.x, sy = originalScale.y/newScale.y
    let rect = Self(plane:newPlane,lower:.init(end.x+(lower.x-start.x)*sx,end.y+(lower.y-start.y)*sy),
      upper:.init(end.x+(upper.x-start.x)*sx,end.y+(upper.y-start.y)*sy),wrap:wrap)
    return rect.projectedCorners(in:scene,angle:angle) == nil ? nil : rect
  }

  public func projectedCorners(in scene: VanishingScene, angle: Double = 0) -> [PathPoint]? {
    guard hasValidBounds,scene.frames.indices.contains(plane),angle.isFinite else { return nil }
    let frame = scene.frames[plane]
    let map = frame.map.m
    let corners = [lower,.init(upper.x,lower.y),upper,.init(lower.x,upper.y)]
      .map { rotated($0,frame:frame,angle:angle) }
    for corner in corners {
      let visibleSide = (map[6]*0.5+map[7]*0.5+map[8]).sign
      let denominator = map[6]*corner.x+map[7]*corner.y+map[8]
      guard abs(denominator) > 1e-10,denominator.sign == visibleSide else { return nil }
    }
    let projected = corners.map(frame.point)
    return PerspectiveSettings.validQuad(projected) ? projected : nil
  }

  public func contains(_ point: PathPoint, in scene: VanishingScene, angle: Double = 0, clip: Bool = false) -> Bool {
    guard scene.frames.indices.contains(plane) else { return false }
    let unit: PathPoint
    if wrap == true {
      guard let face = scene.marqueePlane(at:point,relativeTo:plane) ?? (clip ? nil : plane) else { return false }
      unit = wrappedUnit(point,on:face,in:scene,angle:angle)
    } else {
      unit = unitPoint(point,frame:scene.frames[plane],angle:angle)
    }
    return (0...1).contains(unit.x) && (0...1).contains(unit.y)
  }

  func unitPoint(_ point: PathPoint, frame: VanishingScene.Frame, angle: Double) -> PathPoint {
    let uv = rotated(frame.uv(point),frame:frame,angle:-angle)
    return .init((uv.x-lower.x)/width,(uv.y-lower.y)/height)
  }

  private func rotated(_ point: PathPoint, frame: VanishingScene.Frame, angle: Double) -> PathPoint {
    guard angle != 0 else { return point }
    let radians = angle * .pi / 180, c = cos(radians), s = sin(radians)
    let midpoint = center
    let x = (point.x-midpoint.x)*frame.width, y = (point.y-midpoint.y)*frame.height
    return .init(midpoint.x+(x*c-y*s)/frame.width,midpoint.y+(x*s+y*c)/frame.height)
  }
}

extension VanishingScene {
  public func marquee(plane: Int, from start: PathPoint, to end: PathPoint, square: Bool,
    wrap: Bool = false) -> VanishingMarquee?
  {
    guard frames.indices.contains(plane) else { return nil }
    if wrap && hasMarqueeNeighbors(plane) {
      let anchor = marqueeLayout[plane], endPlane = marqueePlane(at:end,relativeTo:plane) ?? plane
      let a = frames[plane].uv(start)
      let b = anchor.uv(marqueeLayout[endPlane].point(frames[endPlane].uv(end)))
      var dx = (b.x-a.x)*anchor.size.x,dy = (b.y-a.y)*anchor.size.y
      if square {
        let extent = max(abs(dx),abs(dy))
        dx = dx < 0 ? -extent : extent
        dy = dy < 0 ? -extent : extent
      }
      let end = PathPoint(a.x+dx/anchor.size.x,a.y+dy/anchor.size.y)
      let rect = VanishingMarquee(plane:plane,lower:.init(min(a.x,end.x),min(a.y,end.y)),
        upper:.init(max(a.x,end.x),max(a.y,end.y)),wrap:true)
      return rect.hasValidBounds ? rect : nil
    }
    let frame = frames[plane]
    let a = frame.metric(start)
    var b = frame.metric(end)
    if square {
      let dx = b.x-a.x, dy = b.y-a.y, extent = max(abs(dx),abs(dy))
      b = .init(a.x+(dx < 0 ? -extent : extent),a.y+(dy < 0 ? -extent : extent))
    }
    let rect = VanishingMarquee(plane:plane,lower:.init(min(a.x,b.x)/frame.width,min(a.y,b.y)/frame.height),
      upper:.init(max(a.x,b.x)/frame.width,max(a.y,b.y)/frame.height))
    return rect.projectedCorners(in:self) == nil ? nil : rect
  }

  public func hasMarqueeNeighbors(_ plane: Int) -> Bool {
    frames.indices.contains(plane) && frames.indices.contains { $0 != plane && measurementRoot(for:$0) == measurementRoot(for:plane) }
  }

  public func marqueePlane(at point: PathPoint, relativeTo plane: Int) -> Int? {
    guard frames.indices.contains(plane) else { return nil }
    return frames.indices.reversed().first { measurementRoot(for:$0) == measurementRoot(for:plane) && frames[$0].contains(point) }
  }

  /// Advance an aligned donor by the same displacement in the unfolded layout.
  public func linkedStampSource(_ source: PathPoint, plane sourcePlane: Int,
    from start: PathPoint, on startPlane: Int, to end: PathPoint, on endPlane: Int
  ) -> (point: PathPoint, plane: Int)? {
    guard frames.indices.contains(sourcePlane),frames.indices.contains(startPlane),frames.indices.contains(endPlane),
      measurementRoot(for:startPlane) == measurementRoot(for:endPlane) else { return nil }
    let destination = VanishingSurfaceChart(scene:self,anchor:startPlane)
    let donor = VanishingSurfaceChart(scene:self,anchor:sourcePlane)
    let a = destination.coordinates(start,on:startPlane), b = destination.coordinates(end,on:endPlane)
    let sample = donor.coordinates(source,on:sourcePlane)
    return donor.image(.init(sample.x+b.x-a.x,sample.y+b.y-a.y))
  }
}

/// A rectified face in a shared layout. Linked planes use the same axis directions,
/// and the full length of the shared edge is identical in both faces.
struct VanishingMarqueeFace: Sendable {
  var origin: PathPoint
  var size: PathPoint
  var end: PathPoint { point(.init(1,1)) }
  var isValid: Bool {
    origin.x.isFinite && origin.y.isFinite && end.x.isFinite && end.y.isFinite && size.x > 0 && size.y > 0
  }

  func point(_ uv: PathPoint) -> PathPoint { .init(origin.x+uv.x*size.x,origin.y+uv.y*size.y) }
  func uv(_ point: PathPoint) -> PathPoint { .init((point.x-origin.x)/size.x,(point.y-origin.y)/size.y) }
  func contains(_ point: PathPoint) -> Bool {
    let uv = uv(point)
    return (-1e-9...1+1e-9).contains(uv.x) && (-1e-9...1+1e-9).contains(uv.y)
  }

  static func layout(planes: [VanishingPlane], metrics: [PathPoint]) -> [Self] {
    var faces: [Self] = []
    for (index,plane) in planes.enumerated() {
      let metric = metrics[index]
      guard let parent = plane.parent else {
        faces.append(.init(origin:.init(0,0),size:metric))
        continue
      }
      let base = faces[parent]
      switch plane.edge {
      case .left,.right:
        let width = base.size.y*(metric.x/metric.y)
        let x = plane.edge == .right ? base.end.x : base.origin.x-width
        faces.append(.init(origin:.init(x,base.origin.y),size:.init(width,base.size.y)))
      case .top,.bottom:
        let height = base.size.x*(metric.y/metric.x)
        let y = plane.edge == .bottom ? base.end.y : base.origin.y-height
        faces.append(.init(origin:.init(base.origin.x,y),size:.init(base.size.x,height)))
      }
    }
    return faces
  }

  /// Split a convex polygon into its interior and non-overlapping exterior strips.
  func split(_ polygon: [PathPoint]) -> (interior: [PathPoint], exterior: [[PathPoint]]) {
    var interior = polygon
    var exterior: [[PathPoint]] = []
    let maximum = end
    let boundaries: [(PathPoint) -> Double] = [
      { $0.x-origin.x },{ maximum.x-$0.x },{ $0.y-origin.y },{ maximum.y-$0.y }
    ]
    for distance in boundaries {
      guard !interior.isEmpty else { break }
      let outside = clip(interior) { -distance($0) }
      if !outside.isEmpty { exterior.append(outside) }
      interior = clip(interior,distance:distance)
    }
    return (interior,exterior)
  }

  private func clip(_ polygon: [PathPoint], distance: (PathPoint) -> Double) -> [PathPoint] {
    guard var previous = polygon.last else { return [] }
    var polygonAtEdge: [PathPoint] = []
    var before = distance(previous)
    for point in polygon {
      let after = distance(point)
      if before*after < 0 {
        polygonAtEdge.append(previous.interpolated(to:point,at:before/(before-after)))
      }
      if after >= 0 { polygonAtEdge.append(point) }
      before = after
      previous = point
    }
    guard polygonAtEdge.count >= 3 else { return [] }
    let first = polygonAtEdge[0]
    let area = (1..<(polygonAtEdge.count-1)).reduce(0.0) { area,index in
      let a = polygonAtEdge[index],b = polygonAtEdge[index+1]
      return area+(a.x-first.x)*(b.y-first.y)-(a.y-first.y)*(b.x-first.x)
    }
    return area > 0 ? polygonAtEdge : []
  }
}

struct VanishingSurfaceChart {
  struct Piece {
    let plane: Int
    let chart: [PathPoint]
    let corners: [PathPoint]
    let xExtent: ClosedRange<Double>
    let yExtent: ClosedRange<Double>

    init(plane: Int, chart: [PathPoint], corners: [PathPoint]) {
      self.plane = plane
      self.chart = chart
      self.corners = corners
      xExtent = corners.map(\.x).min()!...corners.map(\.x).max()!
      yExtent = corners.map(\.y).min()!...corners.map(\.y).max()!
    }

    func contains(_ point: PathPoint) -> Bool {
      guard xExtent.contains(point.x),yExtent.contains(point.y) else { return false }
      var negative = false,positive = false
      for index in corners.indices {
        let a = corners[index],b = corners[(index+1)%corners.count]
        let side = (b.x-a.x)*(point.y-a.y)-(b.y-a.y)*(point.x-a.x)
        negative = negative || side < -1e-8
        positive = positive || side > 1e-8
        if negative && positive { return false }
      }
      return true
    }

    func distance(_ point: PathPoint) -> Double {
      contains(point) ? 0 : VanishingSurfaceChart.boundaryDistance(point,corners:corners)
    }
  }

  struct StrokePoint {
    let point: PathPoint
    let plane: Int
  }

  let scene: VanishingScene
  let anchor: Int
  let faces: [Int]

  init(scene: VanishingScene, anchor: Int) {
    self.scene = scene
    self.anchor = anchor
    let root = scene.measurementRoot(for:anchor)
    faces = scene.frames.indices.filter { scene.measurementRoot(for:$0) == root }
  }

  private static func boundaryDistance(_ point: PathPoint, corners: [PathPoint]) -> Double {
    corners.indices.reduce(Double.infinity) { nearest,i in
      let a = corners[i], b = corners[(i+1)%corners.count]
      let dx = b.x-a.x,dy = b.y-a.y,square = dx*dx+dy*dy
      guard square > 0 else { return min(nearest,hypot(point.x-a.x,point.y-a.y)) }
      let fraction = min(1,max(0,((point.x-a.x)*dx+(point.y-a.y)*dy)/square))
      return min(nearest,hypot(point.x-a.x-fraction*dx,point.y-a.y-fraction*dy))
    }
  }

  private func visibleFace(at point: PathPoint) -> Int? {
    faces.reversed().first { scene.frames[$0].contains(point) }
  }

  func face(at point: PathPoint) -> Int {
    if let visible = visibleFace(at:point) { return visible }
    return faces.reversed().min { a,b in
      Self.boundaryDistance(point,corners:scene.frames[a].corners)
        < Self.boundaryDistance(point,corners:scene.frames[b].corners)
    } ?? anchor
  }

  func coordinates(_ image: PathPoint, on plane: Int) -> PathPoint {
    scene.marqueeLayout[plane].point(scene.frames[plane].uv(image))
  }

  /// Invert each screen segment on the face it traverses. Linked edges share
  /// a chart coordinate, while a projected overlap can require a pen-up break.
  func strokePath(_ points: [PathPoint], charge: (Int) throws -> Void) throws -> [StrokePoint?] {
    guard let first = points.first else { return [] }
    var last = coordinates(first,on:anchor)
    var plane = anchor
    var rectified: [StrokePoint?] = [.init(point:last,plane:plane)]
    for (start,end) in zip(points,points.dropFirst()) {
      try Task.checkCancellation()
      try charge(faces.count * 8)
      let dx = end.x-start.x, dy = end.y-start.y
      var changes = [0.0,1.0]
      for plane in faces {
        let corners = scene.frames[plane].corners
        for i in corners.indices {
          let a = corners[i], b = corners[(i+1)%corners.count]
          let ex = b.x-a.x, ey = b.y-a.y, determinant = dx*ey-dy*ex
          guard abs(determinant) > 1e-12 else { continue }
          let t = ((a.x-start.x)*ey-(a.y-start.y)*ex)/determinant
          let u = ((a.x-start.x)*dy-(a.y-start.y)*dx)/determinant
          if t > 0 && t < 1 && (0...1).contains(u) { changes.append(t) }
        }
      }
      changes.sort()
      for (a,b) in zip(changes,changes.dropFirst()) where b-a > 1e-10 {
        // Outside the group, keep extending the last face that the cursor left.
        plane = visibleFace(at:start.interpolated(to:end,at:(a+b)/2)) ?? plane
        let begin = coordinates(start.interpolated(to:end,at:a),on:plane)
        let tolerance = 1e-8 * max(1,abs(begin.x),abs(begin.y),abs(last.x),abs(last.y))
        if hypot(last.x-begin.x,last.y-begin.y) > tolerance {
          rectified.append(nil)
          rectified.append(.init(point:begin,plane:plane))
        }
        last = coordinates(start.interpolated(to:end,at:b),on:plane)
        rectified.append(.init(point:last,plane:plane))
        guard rectified.count <= 32768 else { throw CraftError.unsupported("Perspective stroke crosses too many surface boundaries.") }
      }
    }
    return rectified
  }

  func image(_ point: PathPoint) -> (point: PathPoint, plane: Int)? {
    func distance(to plane: Int) -> Double {
      let face = scene.marqueeLayout[plane]
      let dx = max(face.origin.x-point.x,0,point.x-face.end.x)
      let dy = max(face.origin.y-point.y,0,point.y-face.end.y)
      return hypot(dx,dy)
    }
    // A donor beyond an outside edge continues the adjacent face's perspective.
    let plane = faces.reversed().first { scene.marqueeLayout[$0].contains(point) }
      ?? faces.min { distance(to:$0) < distance(to:$1) }
      ?? anchor
    let uv = scene.marqueeLayout[plane].uv(point)
    return project(uv,on:plane).map { ($0,plane) }
  }

  func projectedPieces(_ polygon: [PathPoint], clip: Bool, extending extensionPlane: Int? = nil,
    charge: (Int) throws -> Void = { _ in }
  ) throws -> [Piece] {
    guard polygon.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
      faces.allSatisfy({ scene.marqueeLayout[$0].isValid }) else {
      throw CraftError.invalid("Invalid linked-surface projection.")
    }
    func piece(_ part: [PathPoint], on plane: Int) throws -> Piece {
      let face = scene.marqueeLayout[plane]
      let corners = try part.map { point in
        guard let image = project(face.uv(point),on:plane) else {
          throw CraftError.invalid("Operation crosses a projective horizon.")
        }
        return image
      }
      return Piece(plane:plane,chart:part,corners:corners)
    }
    var pieces: [Piece] = []
    for plane in faces.reversed() {
      try charge(polygon.count * 4)
      let part = scene.marqueeLayout[plane].split(polygon).interior
      if !part.isEmpty { pieces.append(try piece(part,on:plane)) }
    }
    if !clip {
      var uncovered = [polygon]
      for plane in faces {
        try charge(4 * uncovered.reduce(0) { $0+$1.count })
        uncovered = uncovered.flatMap { scene.marqueeLayout[plane].split($0).exterior }
      }
      for part in uncovered { pieces.append(try piece(part,on:extensionPlane ?? anchor)) }
    }
    return pieces
  }

  private func project(_ uv: PathPoint, on plane: Int) -> PathPoint? {
    let frame = scene.frames[plane],m = frame.map.m
    let side = (m[6]*0.5+m[7]*0.5+m[8]).sign
    let w = m[6]*uv.x+m[7]*uv.y+m[8]
    guard abs(w) > 1e-10,w.sign == side else { return nil }
    let point = frame.point(uv)
    return VanishingSettings.validPoint(point) ? point : nil
  }
}

struct ProjectedVanishingMarquee {
  let pieces: [VanishingSurfaceChart.Piece]
  let featherEdges: [[PathPoint]]
  let outline: [[PathPoint]]

  init?(rect: VanishingMarquee, scene: VanishingScene, angle: Double, clip: Bool) {
    guard rect.hasValidBounds,angle.isFinite,scene.frames.indices.contains(rect.plane) else { return nil }
    let anchor = scene.marqueeLayout[rect.plane]
    let layout = VanishingSurfaceChart(scene:scene,anchor:rect.plane)
    let faces = layout.faces
    let polygon = [rect.lower,.init(rect.upper.x,rect.lower.y),rect.upper,.init(rect.lower.x,rect.upper.y)]
      .map { anchor.point(rect.rotate($0,size:anchor.size,angle:angle)) }
    guard let pieces = try? layout.projectedPieces(polygon,clip:clip) else { return nil }
    self.pieces = pieces
    var featherEdges: [[PathPoint]] = []
    var outline: [[PathPoint]] = []
    for piece in pieces {
      for i in piece.chart.indices {
        let j = (i+1)%piece.chart.count
        let a = piece.chart[i],b = piece.chart[j]
        let projected = [piece.corners[i],piece.corners[j]]
        let u = rect.unitFromChart(a,anchor:anchor,angle:angle),v = rect.unitFromChart(b,anchor:anchor,angle:angle)
        let isSelectionEdge = [0.0,1.0].contains { edge in
          (abs(u.x-edge) < 1e-8 && abs(v.x-edge) < 1e-8) || (abs(u.y-edge) < 1e-8 && abs(v.y-edge) < 1e-8)
        }
        if isSelectionEdge {
          featherEdges.append(projected)
          outline.append(projected)
        } else if clip {
          // A real clipping edge remains visible. An internal hinge is not a selection edge.
          let dx = (b.x-a.x)/anchor.size.x,dy = (b.y-a.y)/anchor.size.y
          let length = hypot(dx,dy)
          guard length > 0 else { continue }
          let midpoint = a.interpolated(to:b,at:0.5)
          let outside = PathPoint(midpoint.x+dy/length*anchor.size.x*1e-7,midpoint.y-dx/length*anchor.size.y*1e-7)
          if !faces.contains(where:{ scene.marqueeLayout[$0].contains(outside) }) { outline.append(projected) }
        }
      }
    }
    self.outline = outline
    self.featherEdges = featherEdges
  }

}

extension VanishingMarquee {
  fileprivate func rotate(_ point: PathPoint, size: PathPoint, angle: Double) -> PathPoint {
    guard angle != 0 else { return point }
    let radians = angle * .pi / 180,c = cos(radians),s = sin(radians),midpoint = center
    let x = (point.x-midpoint.x)*size.x,y = (point.y-midpoint.y)*size.y
    return .init(midpoint.x+(x*c-y*s)/size.x,midpoint.y+(x*s+y*c)/size.y)
  }

  fileprivate func unitFromChart(_ point: PathPoint, anchor: VanishingMarqueeFace, angle: Double) -> PathPoint {
    let uv = rotate(anchor.uv(point),size:anchor.size,angle:-angle)
    return .init((uv.x-lower.x)/width,(uv.y-lower.y)/height)
  }

  func wrappedUnit(_ point: PathPoint, on face: Int, in scene: VanishingScene, angle: Double) -> PathPoint {
    let chartPoint = scene.marqueeLayout[face].point(scene.frames[face].uv(point))
    return unitFromChart(chartPoint,anchor:scene.marqueeLayout[plane],angle:angle)
  }

  func wrappedPoint(_ uv: PathPoint, in scene: VanishingScene, clip: Bool) -> PathPoint? {
    let anchor = scene.marqueeLayout[plane]
    let point = anchor.point(uv),root = scene.measurementRoot(for:plane)
    let face = scene.frames.indices.reversed().first {
      scene.measurementRoot(for:$0) == root && scene.marqueeLayout[$0].contains(point)
    } ?? (clip ? nil : plane)
    guard let face else { return nil }
    return scene.frames[face].point(scene.marqueeLayout[face].uv(point))
  }

  public func imageCenter(in scene: VanishingScene) -> PathPoint? {
    guard scene.frames.indices.contains(plane) else { return nil }
    return wrap == true ? wrappedPoint(center,in:scene,clip:false) : scene.frames[plane].point(center)
  }

  public func outlineSegments(in scene: VanishingScene, angle: Double, clip: Bool) -> [[PathPoint]]? {
    if wrap == true { return ProjectedVanishingMarquee(rect:self,scene:scene,angle:angle,clip:clip)?.outline }
    return projectedCorners(in:scene,angle:angle).map { corners in
      corners.indices.map { [corners[$0],corners[($0+1)%corners.count]] }
    }
  }
}

public struct VanishingMarqueeTransfer: Codable, Equatable, Sendable {
  public var source: VanishingMarquee
  public var destination: VanishingMarquee
  public var feather: Double

  public init(source: VanishingMarquee, destination: VanishingMarquee, feather: Double = 1) {
    self.source = source
    self.destination = destination
    self.feather = feather
  }

  public static let featherRange = 0.0...200.0
}
