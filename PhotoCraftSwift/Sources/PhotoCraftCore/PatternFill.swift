import Foundation

/// An editable, document-owned pattern. Placement is in document coordinates.
public struct PatternFill: Codable, Equatable, Sendable {
  public var patternID: String
  public var placement: PatternPlacement
  public var linked: Bool
  /// Retains canvas transformations that cannot be expressed by uniform scale and rotation.
  public var geometry: Transform2D?
  public init(
    patternID: String, placement: PatternPlacement = PatternPlacement(), linked: Bool = true
  ) {
    self.patternID = patternID
    self.placement = placement
    self.linked = linked
  }
  public func validate() throws {
    guard !patternID.isEmpty, patternID.utf8.count <= 255 else {
      throw CraftError.invalid("Invalid pattern reference.")
    }
    try placement.validate()
    try geometry?.validated()
  }
  public mutating func transform(by delta: Transform2D) throws {
    let combined = delta * (geometry ?? .identity)
    try combined.validated()
    geometry = combined == .identity ? nil : combined
  }
  public mutating func move(x: Int, y: Int) throws {
    guard linked else { return }
    try transform(by: .translation(Double(x), Double(y)))
  }
  /// Resolve an affine canvas transform into Photoshop's uniform placement when possible.
  public func flattenedPlacement() throws -> PatternPlacement {
    guard let geometry else { return placement }
    let scale = hypot(geometry.a, geometry.b)
    guard scale > 0,
      abs(geometry.c + geometry.b) <= 1e-9 * max(1, scale),
      abs(geometry.d - geometry.a) <= 1e-9 * max(1, scale)
    else {
      throw CraftError.unsupported(
        "Rasterize this pattern fill before exporting its nonuniform or reflected transform to PSD."
      )
    }
    let origin = geometry.point(Double(placement.phaseX), Double(placement.phaseY))
    var result = placement
    result.phaseX = Float(origin.x)
    result.phaseY = Float(origin.y)
    result.scale *= Float(scale)
    result.angle -= Float(atan2(geometry.b, geometry.a) * 180 / .pi)
    try result.validate()
    return result
  }
}

extension CraftDocument {
  public func pattern(_ id: String) -> RasterPattern? { patterns?.first { $0.id == id } }
  /// Copies a preset into this document. Conflicting IDs are remapped without changing older layers.
  @discardableResult public mutating func installPattern(_ pattern: RasterPattern) throws -> String
  {
    try pattern.validate()
    if let old = self.pattern(pattern.id) {
      if old.name == pattern.name,
        try old.surface.changedTileBounds(comparedTo: pattern.surface) == nil
      {
        return old.id
      }
      let replacement = try RasterPattern(
        name: pattern.name, surface: pattern.surface, id: UUID().uuidString)
      patterns = (patterns ?? []) + [replacement]
      return replacement.id
    }
    patterns = (patterns ?? []) + [pattern]
    return pattern.id
  }
}

extension Layer {
  public var isCanvasFill: Bool {
    switch content {
    case .fill, .patternFill, .gradientFill: true
    default: false
    }
  }
  public mutating func movePattern(x: Int, y: Int) throws {
    guard case .patternFill(var fill) = content else { return }
    try fill.move(x: x, y: y)
    content = .patternFill(fill)
  }
}
