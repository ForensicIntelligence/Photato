import Foundation

/// Bézier geometry uses document pixels with positive Y downward, as in PhotoCraft.
public struct PathPoint: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public init(_ x: Double, _ y: Double) {
    self.x = x
    self.y = y
  }
  public func transformed(_ t: Transform2D) -> Self {
    let q = t.point(x, y)
    return Self(q.x, q.y)
  }
  public func interpolated(to p: Self, at t: Double) -> Self {
    Self(x + (p.x - x) * t, y + (p.y - y) * t)
  }
}
public struct PathKnot: Codable, Equatable, Sendable {
  public var anchor: PathPoint
  public var incoming: PathPoint
  public var outgoing: PathPoint
  public var smooth: Bool
  public init(
    _ anchor: PathPoint, incoming: PathPoint? = nil, outgoing: PathPoint? = nil,
    smooth: Bool = false
  ) {
    self.anchor = anchor
    self.incoming = incoming ?? anchor
    self.outgoing = outgoing ?? anchor
    self.smooth = smooth
  }
  public func transformed(_ t: Transform2D) -> Self {
    Self(
      anchor.transformed(t), incoming: incoming.transformed(t),
      outgoing: outgoing.transformed(t), smooth: smooth)
  }
  public mutating func moveAnchor(to p: PathPoint) {
    self = transformed(.translation(p.x - anchor.x, p.y - anchor.y))
  }
  public mutating func moveHandle(incoming isIncoming: Bool, to p: PathPoint, independent: Bool) {
    let other = isIncoming ? outgoing : incoming
    let distance = hypot(other.x - anchor.x, other.y - anchor.y)
    let length = hypot(p.x - anchor.x, p.y - anchor.y)
    if isIncoming { incoming = p } else { outgoing = p }
    if independent { smooth = false }
    if smooth && length > 1e-9 {
      let opposite = PathPoint(
        anchor.x - (p.x - anchor.x) * distance / length,
        anchor.y - (p.y - anchor.y) * distance / length)
      if isIncoming { outgoing = opposite } else { incoming = opposite }
    }
  }
}
public enum PathOperation: String, Codable, CaseIterable, Sendable {
  case combine = "Combine"
  case subtract = "Subtract"
  case intersect = "Intersect"
  case exclude = "Exclude"
  case join = "Join"
}
public enum PathFillRule: String, Codable, CaseIterable, Sendable {
  case nonZero = "Nonzero"
  case evenOdd = "Even-Odd"
}
public struct PathComponent: Codable, Equatable, Sendable {
  public var knots: [PathKnot]
  public var closed: Bool
  public var operation: PathOperation
  public init(knots: [PathKnot] = [], closed: Bool = false, operation: PathOperation = .combine) {
    self.knots = knots
    self.closed = closed
    self.operation = operation
  }
  /// De Casteljau subdivision preserves the curve exactly, including the closing segment.
  public mutating func split(segment: Int, at t: Double) throws {
    guard t.isFinite, t > 0, t < 1, knots.count >= 2, segment >= 0,
      segment < (closed ? knots.count : knots.count - 1), knots.count < VectorPath.maxKnots
    else { throw CraftError.invalid("Invalid path segment or anchor limit.") }
    let next = (segment + 1) % knots.count
    let a = knots[segment]
    let b = knots[next]
    let p = a.anchor.interpolated(to: a.outgoing, at: t)
    let q = a.outgoing.interpolated(to: b.incoming, at: t)
    let r = b.incoming.interpolated(to: b.anchor, at: t)
    let s = p.interpolated(to: q, at: t)
    let u = q.interpolated(to: r, at: t)
    knots[segment].outgoing = p
    knots[next].incoming = r
    knots.insert(
      PathKnot(s.interpolated(to: u, at: t), incoming: s, outgoing: u, smooth: true),
      at: segment + 1)
  }
  public func point(segment: Int, at t: Double) -> PathPoint? {
    guard knots.count >= 2, segment >= 0, segment < (closed ? knots.count : knots.count - 1)
    else { return nil }
    let a = knots[segment]
    let b = knots[(segment + 1) % knots.count]
    let p = a.anchor.interpolated(to: a.outgoing, at: t)
    let q = a.outgoing.interpolated(to: b.incoming, at: t)
    let r = b.incoming.interpolated(to: b.anchor, at: t)
    return p.interpolated(to: q, at: t).interpolated(to: q.interpolated(to: r, at: t), at: t)
  }
}
public struct VectorPath: Codable, Equatable, Sendable {
  // Bound the native boolean solver's input as well as document storage.
  public static let maxKnots = 4096
  public var components: [PathComponent]
  public var fillRule: PathFillRule
  public var inverted: Bool
  public init(
    components: [PathComponent] = [], fillRule: PathFillRule = .nonZero,
    inverted: Bool = false
  ) {
    self.components = components
    self.fillRule = fillRule
    self.inverted = inverted
  }
  public var knotCount: Int { components.reduce(0) { $0 + $1.knots.count } }
  public var isEmpty: Bool { components.allSatisfy { $0.knots.isEmpty } }
  public func validate() throws {
    guard components.count <= 256, knotCount <= Self.maxKnots,
      components.flatMap(\.knots).allSatisfy({ knot in
        [knot.anchor, knot.incoming, knot.outgoing].allSatisfy {
          $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000
        }
      })
    else { throw CraftError.invalid("Path geometry exceeds the supported limits.") }
  }
  public func transformed(_ t: Transform2D) -> Self {
    var result = self
    for i in result.components.indices {
      result.components[i].knots = result.components[i].knots.map { $0.transformed(t) }
    }
    return result
  }
}
public struct NamedPath: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var path: VectorPath
  public var isWorkPath: Bool
  public init(name: String = "Work Path", path: VectorPath = VectorPath(), isWorkPath: Bool = true)
  {
    id = UUID()
    self.name = name
    self.path = path
    self.isWorkPath = isWorkPath
  }
}
public struct VectorMask: Codable, Equatable, Sendable {
  public var path: VectorPath
  public var enabled = true
  public var linked = true
  public var density: Float = 1
  public var feather: Double = 0
  public init(path: VectorPath = VectorPath()) { self.path = path }
  public func validate() throws {
    try path.validate()
    guard density.isFinite, (0...1).contains(density), feather.isFinite, (0...100).contains(feather)
    else {
      throw CraftError.invalid("Invalid vector mask properties; feather supports 0–100 pixels.")
    }
  }
}
extension CraftDocument {
  mutating func transformSavedPaths(by t: Transform2D) {
    vanishingPoint=vanishingPoint?.transformed(t)
    guard var paths else { return }
    for i in paths.indices { paths[i].path = paths[i].path.transformed(t) }
    self.paths = paths
  }
}
