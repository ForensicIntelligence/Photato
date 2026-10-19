import Foundation

public enum GradientStyle: String, CaseIterable, Codable, Sendable {
  case linear = "Linear"
  case radial = "Radial"
  case angle = "Angle"
  case reflected = "Reflected"
  case diamond = "Diamond"
}

/// Photoshop angle convention: counterclockwise degrees from the positive x axis.
/// Scale is a fraction (1 = 100%); offsets are fractions of the reference frame.
public struct GradientPlacement: Codable, Equatable, Sendable {
  public var style: GradientStyle = .linear
  public var angle: Float = 90
  public var scale: Float = 1
  public var offsetX: Float = 0
  public var offsetY: Float = 0
  public var reverse = false
  public init() {}
  public func validate() throws {
    guard angle.isFinite, abs(angle) <= 360_000, scale.isFinite,
      (0.000001...100_000).contains(scale), offsetX.isFinite, offsetY.isFinite,
      abs(offsetX) <= 1_000_000, abs(offsetY) <= 1_000_000
    else { throw CraftError.invalid("Invalid gradient placement.") }
  }
  static func validateFrame(_ frame: IntRect) throws {
    guard (1...1_000_000).contains(frame.width), (1...1_000_000).contains(frame.height),
      (-1_000_000...1_000_000).contains(frame.x), (-1_000_000...1_000_000).contains(frame.y)
    else { throw CraftError.invalid("Invalid gradient reference frame.") }
  }
  static func units(angle: Float, width: Float, height: Float) -> (chord: Float, length: Float) {
    let a = angle * (Float(Double.pi / 180))
    let s = sin(a)
    let c = cos(a)
    let cw = c * width
    let sh = s * height
    return (
      max(1, min(width / max(abs(c), 1e-6), height / max(abs(s), 1e-6))),
      max(1, sqrt(cw * cw + sh * sh))
    )
  }
  /// Source-derived whole-pixel endpoint layout for fill layers and layer effects.
  /// Tool drags can use unsnapped geometry by preparing GradientField with snapEndpoints: false.
  public func snapped(in frame: IntRect) throws -> Self {
    try validate()
    try Self.validateFrame(frame)
    guard style == .linear || style == .reflected else { return self }
    let w = Double(frame.width)
    let h = Double(frame.height)
    let cx = Double(frame.x) + w / 2 + Double(offsetX) * w
    let cy = Double(frame.y) + h / 2 + Double(offsetY) * h
    func chord(_ a: Double) -> Double {
      max(1, min(w / max(abs(cos(a)), 1e-6), h / max(abs(sin(a)), 1e-6)))
    }
    let a = Double(angle) * (.pi / 180)
    let half = chord(a) * Double(max(scale, 0.001)) / 2
    let dx = cos(a) * half
    let dy = -sin(a) * half
    let endX = floor(cx + dx + 0.0001)
    let endY = floor(cy + dy + 0.0001)
    let startX = style == .reflected ? cx : floor(cx - dx + 0.0001)
    let startY = style == .reflected ? cy : floor(cy - dy + 0.0001)
    let midX = style == .reflected ? cx : (startX + endX) / 2
    let midY = style == .reflected ? cy : (startY + endY) / 2
    let vx = endX - startX
    let vy = endY - startY
    let length = hypot(vx, vy)
    guard length >= 0.5 else { return self }
    let a2 = atan2(-vy, vx)
    var result = self
    result.angle = Float(a2 * (180 / .pi))
    result.scale = Float((style == .reflected ? 2 * length : length) / chord(a2))
    result.offsetX += Float((midX - cx) / w)
    result.offsetY += Float((midY - cy) / h)
    return result
  }
  private func reach(in frame: IntRect) -> Float {
    let units = Self.units(angle: angle, width: Float(frame.width), height: Float(frame.height))
    switch style {
    case .linear: return units.chord
    case .reflected: return units.chord / 2
    default: return units.length / 2
    }
  }
  public func handles(in frame: IntRect) throws -> (start: PathPoint, end: PathPoint) {
    try validate()
    try Self.validateFrame(frame)
    let cx = Float(frame.x) + Float(frame.width) / 2 + offsetX * Float(frame.width)
    let cy = Float(frame.y) + Float(frame.height) / 2 + offsetY * Float(frame.height)
    let a = angle * (Float(Double.pi / 180))
    let length = reach(in: frame) * max(scale, 0.001)
    let dx = cos(a) * length
    let dy = -sin(a) * length
    if style == .linear {
      return (
        .init(Double(cx - dx / 2), Double(cy - dy / 2)),
        .init(Double(cx + dx / 2), Double(cy + dy / 2))
      )
    }
    return (.init(Double(cx), Double(cy)), .init(Double(cx + dx), Double(cy + dy)))
  }
  public mutating func setHandles(start: PathPoint, end: PathPoint, in frame: IntRect) throws {
    try validate()
    try Self.validateFrame(frame)
    guard [start.x, start.y, end.x, end.y].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 })
    else {
      throw CraftError.invalid("Invalid gradient handles.")
    }
    let sx = Float(start.x)
    let sy = Float(start.y)
    let ex = Float(end.x)
    let ey = Float(end.y)
    let dx = ex - sx
    let dy = ey - sy
    let length = hypot(dx, dy)
    var result = self
    if length > 0.0001 { result.angle = atan2(-dy, dx) * (Float(180 / Double.pi)) }
    let cx = style == .linear ? (sx + ex) / 2 : sx
    let cy = style == .linear ? (sy + ey) / 2 : sy
    result.offsetX = (cx - Float(frame.x) - Float(frame.width) / 2) / Float(frame.width)
    result.offsetY = (cy - Float(frame.y) - Float(frame.height) / 2) / Float(frame.height)
    result.scale = max(length, 0.5) / result.reach(in: frame)
    try result.validate()
    self = result
  }
}

/// Immutable, prepared gradient geometry: no trigonometry or stop preparation per pixel.
public struct GradientField: Sendable {
  private let style: GradientStyle
  private let reverse: Bool
  private let angle: Float
  private let sine: Float
  private let cosine: Float
  private let centerX: Float
  private let centerY: Float
  private let chord: Float
  private let length: Float
  public init(_ placement: GradientPlacement, frame: IntRect, snapEndpoints: Bool = true) throws {
    try placement.validate()
    try GradientPlacement.validateFrame(frame)
    let p = try snapEndpoints ? placement.snapped(in: frame) : placement
    style = p.style
    reverse = p.reverse
    angle = p.angle * (Float(Double.pi / 180))
    sine = sin(angle)
    cosine = cos(angle)
    centerX = Float(frame.x) + Float(frame.width) / 2 + p.offsetX * Float(frame.width)
    centerY = Float(frame.y) + Float(frame.height) / 2 + p.offsetY * Float(frame.height)
    let units = GradientPlacement.units(
      angle: p.angle, width: Float(frame.width), height: Float(frame.height))
    chord = units.chord * max(p.scale, 0.001)
    length = units.length * max(p.scale, 0.001)
  }
  /// x/y are pixel centers in document coordinates; linear/reflected use the source's corner phase.
  public func parameter(x: Float, y: Float) -> Float {
    guard x.isFinite, y.isFinite, abs(x) <= 1e9, abs(y) <= 1e9 else { return 0 }
    let dx = x - centerX
    let dy = y - centerY
    let along = dx * cosine - dy * sine
    let across = dx * sine + dy * cosine
    let corner = 0.5 * (cosine - sine)
    let t: Float
    switch style {
    case .linear: t = (along - corner) / chord + 0.5
    case .reflected: t = abs((along - corner) / (chord / 2))
    case .radial: t = sqrt(dx * dx + dy * dy) / (length / 2)
    case .diamond: t = (abs(along) + abs(across)) / (length / 2)
    case .angle:
      let raw = (angle - atan2(-dy, dx)) / (Float(2 * Double.pi))
      let remainder = raw.truncatingRemainder(dividingBy: 1)
      t = remainder < 0 ? remainder + 1 : remainder
    }
    return reverse ? 1 - unit(t) : unit(t)
  }
}
