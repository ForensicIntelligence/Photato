import Foundation

/// Editable fill controls. Stops are captured when applied; a fill never depends on UI colors.
public struct GradientFill: Codable, Equatable, Sendable {
  public var gradient: GradientDefinition
  public var placement: GradientPlacement
  public var aligned: Bool
  public var dither: Bool
  public init(
    gradient: GradientDefinition = .blackToWhite, placement: GradientPlacement = .init(),
    aligned: Bool = true, dither: Bool = true
  ) {
    self.gradient = gradient
    self.placement = placement
    self.aligned = aligned
    self.dither = dither
  }
  public func validate() throws {
    try gradient.validate()
    try placement.validate()
    for stop in gradient.colors {
      switch stop.color {
      case .foreground, .background:
        throw CraftError.invalid(
          "Capture foreground and background colors before adding a gradient fill.")
      default: break
      }
    }
  }
  public func frame(for layer: Layer, width: Int, height: Int) throws -> IntRect {
    aligned
      ? try layer.fillFrame(width: width, height: height)
      : IntRect(x: 0, y: 0, width: width, height: height)
  }
  /// Artboard fills use the containing board as their canvas. Mask-based alignment
  /// is intersected with that frame so extracting a board preserves its appearance.
  public func frame(for layer: Layer, in document: CraftDocument) throws -> IntRect {
    let canvas = try frame(for: layer, width: document.width, height: document.height)
    guard let board = document.artboard(containing: layer.id)?.artboardBounds else { return canvas }
    guard aligned else { return board }
    let x0 = max(board.x, canvas.x), y0 = max(board.y, canvas.y)
    let x1 = min(board.x + board.width, canvas.x + canvas.width), y1 = min(board.y + board.height, canvas.y + canvas.height)
    return x1 > x0 && y1 > y0 ? IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) : board
  }
  /// Carry the editable angle/relative center through canvas turns and flips. Positive
  /// axis scaling keeps fractional offsets unchanged; fills adapt to their new frame.
  /// This is a parameter transform, not an affine warp of a rasterized gradient.
  public mutating func transform(by delta: Transform2D) throws {
    try delta.validated()
    let radians = Double(placement.angle) * .pi / 180
    let x = delta.a * cos(radians) - delta.c * sin(radians)
    let y = delta.b * cos(radians) - delta.d * sin(radians)
    var angle = atan2(-y, x) * 180 / .pi
    if abs(angle - angle.rounded()) < 1e-6 { angle = angle.rounded() }
    placement.angle = Float(angle <= -180 ? angle + 360 : angle)
    let sx = hypot(delta.a, delta.b)
    let sy = hypot(delta.c, delta.d)
    let ox = Double(placement.offsetX)
    let oy = Double(placement.offsetY)
    placement.offsetX = Float(delta.a / sx * ox + delta.c / sy * oy)
    placement.offsetY = Float(delta.b / sx * ox + delta.d / sy * oy)
    try validate()
  }
}

extension Layer {
  /// Source fill_frame: revealed pixel-mask bounds, intersected with vector control bounds.
  /// Density and feather change coverage, not the reference frame. Empty/inverted masks
  /// retain the canvas frame. All bounds are clipped before converting to integers.
  public func fillFrame(width: Int, height: Int) throws -> IntRect {
    var frame = (x0: 0.0, y0: 0.0, x1: Double(width), y1: Double(height))
    func intersect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
      let clipped = (max(frame.x0, x0), max(frame.y0, y0), min(frame.x1, x1), min(frame.y1, y1))
      if clipped.2 > clipped.0, clipped.3 > clipped.1 { frame = clipped }
    }
    if let mask, effectiveMaskProperties.enabled, effectiveMaskProperties.outside == 0 {
      var x0 = mask.width
      var y0 = mask.height
      var x1 = 0
      var y1 = 0
      for y in 0..<mask.height {
        try Task.checkCancellation()
        for x in 0..<mask.width where mask.pixel(x: x, y: y).r > 0 {
          x0 = min(x0, x)
          y0 = min(y0, y)
          x1 = max(x1, x + 1)
          y1 = max(y1, y + 1)
        }
      }
      if x1 > x0, y1 > y0 {
        let t = maskCoordinateTransform
        let corners = [
          t.point(Double(x0), Double(y0)), t.point(Double(x1), Double(y0)),
          t.point(Double(x0), Double(y1)), t.point(Double(x1), Double(y1)),
        ]
        intersect(
          floor(corners.map(\.x).min()!), floor(corners.map(\.y).min()!),
          ceil(corners.map(\.x).max()!), ceil(corners.map(\.y).max()!))
      }
    }
    if let mask = vectorMask, mask.enabled {
      let exteriorFilled: Bool
      if mask.path.components.first?.operation == .subtract {
        exteriorFilled = try VectorPathGeometry.filledRegion(mask.path).inverted
      } else {
        exteriorFilled = mask.path.inverted
      }
      if !exteriorFilled {
        let points = mask.path.components.flatMap(\.knots).flatMap {
          [$0.anchor, $0.incoming, $0.outgoing]
        }
        if !points.isEmpty {
          intersect(
            floor(points.map(\.x).min()!), floor(points.map(\.y).min()!),
            ceil(points.map(\.x).max()!), ceil(points.map(\.y).max()!))
        }
      }
    }
    return IntRect(
      x: Int(frame.x0), y: Int(frame.y0), width: Int(frame.x1 - frame.x0),
      height: Int(frame.y1 - frame.y0))
  }
}
