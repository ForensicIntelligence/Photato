import Foundation

public enum CloneSampling: String, CaseIterable, Codable, Sendable {
  case current = "Current Layer"
  case currentAndBelow = "Current & Below"
  case all = "All Layers"
}

public struct CloneBrush: Codable, Equatable, Sendable {
  public var size: Double = 30
  public var hardness: Float = 0.8
  public var opacity: Float = 1
  public var flow: Float = 1
  public var spacing: Double = 0.25
  public var pressureSize = true
  public var pressureOpacity = false
  public var mode: BlendMode = .normal
  public init() {}
  public func validate() throws {
    guard size.isFinite, (1...2048).contains(size), spacing.isFinite,
      (0.01...10).contains(spacing),
      [hardness, opacity, flow].allSatisfy({ $0.isFinite && (0...1).contains($0) })
    else { throw CraftError.invalid("Invalid Clone Stamp brush settings.") }
  }
}

public struct CloneMapping: Codable, Equatable, Sendable {
  public var source: PathPoint
  public var anchor: PathPoint
  public var width: Double = 100
  public var height: Double = 100
  public var rotation: Double = 0
  public var flipHorizontal = false
  public var flipVertical = false
  public init(source: PathPoint, anchor: PathPoint) {
    self.source = source
    self.anchor = anchor
  }
  public func transform() throws -> Transform2D {
    guard
      [source.x, source.y, anchor.x, anchor.y].allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
      width.isFinite, height.isFinite, (1...1000).contains(width), (1...1000).contains(height),
      rotation.isFinite, abs(rotation) <= 360_000
    else { throw CraftError.invalid("Invalid Clone Source transform.") }
    let forward =
      Transform2D.rotation(-rotation)
      * .scale(width / 100 * (flipHorizontal ? -1 : 1), height / 100 * (flipVertical ? -1 : 1))
    let inverse = try forward.inverted()
    // Source identity translations use the source port's integer pixel offset.
    if inverse == .identity {
      return .translation((source.x - anchor.x).rounded(), (source.y - anchor.y).rounded())
    }
    return .translation(source.x, source.y) * inverse * .translation(-anchor.x, -anchor.y)
  }
}

/// Immutable pre-stroke sample, in its own pixel grid. Mapping is in document coordinates.
public struct CloneSample: Equatable, Sendable {
  public let surface: Surface
  public let transform: Transform2D
  public let outside: Pixel
  public let origin: RetouchSampleOrigin?
  public init(surface: Surface, transform: Transform2D = .identity, outside: Pixel = .clear,
    origin: RetouchSampleOrigin? = nil) {
    self.surface = surface
    self.transform = transform
    self.outside = outside
    self.origin = origin
  }
}

public struct CloneStroke: Sendable {
  public var source: CloneSample
  public var mapping: CloneMapping
  public var brush: CloneBrush
  public var points: [StrokePoint]
  public var mask = false
  public init(
    source: CloneSample, mapping: CloneMapping, brush: CloneBrush, points: [StrokePoint],
    mask: Bool = false
  ) {
    self.source = source
    self.mapping = mapping
    self.brush = brush
    self.points = points
    self.mask = mask
  }
}

public enum ClonePainter {
  /// Float documents interpolate premultiplied linear-light samples, matching
  /// their compositing domain; integer documents interpolate encoded samples.
  public static func sample(
    _ source: Surface, x: Double, y: Double, nearest: Bool, linear: Bool,
    outside: Pixel, grayscale: Bool
  ) -> Pixel {
    guard x.isFinite, y.isFinite, abs(x) < 10_000_000, abs(y) < 10_000_000 else { return .clear }
    func pixel(_ x: Int, _ y: Int) -> Pixel {
      let p =
        x < 0 || y < 0 || x >= source.width || y >= source.height
        ? outside : source.pixel(x: x, y: y)
      // Pixel masks store scalar coverage in red; their stored alpha is not coverage.
      return grayscale ? Pixel(unit(p.r), unit(p.r), unit(p.r)) : p
    }
    if nearest { return pixel(Int(floor(x)), Int(floor(y))) }
    let fx = x - 0.5
    let fy = y - 0.5
    let ix = Int(floor(fx))
    let iy = Int(floor(fy))
    let tx = Float(fx - floor(fx))
    let ty = Float(fy - floor(fy))
    func pm(_ x: Int, _ y: Int) -> SIMD4<Float> {
      let raw = pixel(x, y)
      let p = linear ? SRGBTransfer.linear(raw) : raw
      return SIMD4(p.r * p.a, p.g * p.a, p.b * p.a, p.a)
    }
    let value =
      (pm(ix, iy) * (1 - tx) + pm(ix + 1, iy) * tx) * (1 - ty)
      + (pm(ix, iy + 1) * (1 - tx) + pm(ix + 1, iy + 1) * tx) * ty
    guard value.w > 1e-8 else { return .clear }
    let result = Pixel(value.x / value.w, value.y / value.w, value.z / value.w, unit(value.w))
    return linear ? SRGBTransfer.encoded(result) : result
  }
  /// Native translation of PhotoCraft's round-tip smoothstep falloff.
  public static func coverage(distance: Float, radius: Float, hardness: Float) -> Float {
    if distance >= radius + 0.5 { return 0 }
    let edge = unit(radius + 0.5 - distance)
    let inner = radius * unit(hardness)
    if distance <= inner || radius - inner < 0.001 { return edge }
    let t = unit((distance - inner) / (radius - inner))
    return edge * (1 - t * t * (3 - 2 * t))
  }
  @discardableResult public static func paint(
    _ stroke: CloneStroke, on surface: inout Surface, transform: Transform2D,
    selection: IntRect? = nil, selectionMask: SelectionMask? = nil
  ) throws -> Bool {
    let sourceMapping = try prepare(stroke)
    return try paintPrepared(
      stroke, on: &surface, transform: transform,
      sourceMapping: sourceMapping, selection: selection, selectionMask: selectionMask)
  }
  static func prepare(_ stroke: CloneStroke) throws -> Transform2D {
    try Task.checkCancellation()
    try stroke.brush.validate()
    try stroke.source.surface.validated()
    guard stroke.source.outside.isFinite, (0...1).contains(stroke.source.outside.a) else {
      throw CraftError.invalid("Invalid Clone Stamp source outside value.")
    }
    guard !stroke.points.isEmpty, stroke.points.count <= 100_000 else {
      throw CraftError.invalid("Invalid Clone Stamp stroke size.")
    }
    for p in stroke.points {
      guard p.x.isFinite, p.y.isFinite, abs(p.x) <= 1_000_000, abs(p.y) <= 1_000_000,
        p.pressure.isFinite, (0...1).contains(p.pressure)
      else { throw CraftError.invalid("Invalid Clone Stamp sample.") }
    }
    return try stroke.source.transform.inverted() * stroke.mapping.transform()
  }
  @discardableResult static func paintPrepared(
    _ stroke: CloneStroke, on surface: inout Surface, transform: Transform2D,
    sourceMapping: Transform2D, selection: IntRect?, selectionMask: SelectionMask?,
    preserveTransparency: Bool = false
  ) throws -> Bool {
    let coverage = try strokeCoverage(stroke, surface: surface, transform: transform)
    return try applyCoverage(
      stroke, on: &surface, transform: transform,
      sourceMapping: sourceMapping, selection: selection, selectionMask: selectionMask,
      coverage: coverage, preserveTransparency: preserveTransparency)
  }
  static func strokeCoverage(_ stroke: CloneStroke, surface: Surface, transform: Transform2D) throws -> RetouchCoverage {
    let coverage = try RetouchCoverageAccumulator(width: surface.width, height: surface.height,
      transform: transform, brush: stroke.brush)
    try coverage.append(stroke.points)
    return coverage.snapshot()
  }
  static func applyCoverage(
    _ stroke: CloneStroke, on surface: inout Surface,
    transform: Transform2D, sourceMapping: Transform2D, selection: IntRect?,
    selectionMask: SelectionMask?, coverage: RetouchCoverage,
    preserveTransparency: Bool = false, backdrop: Surface? = nil
  ) throws -> Bool {
    let map = sourceMapping * transform
    let nearest =
      map.a == 1 && map.b == 0 && map.c == 0 && map.d == 1
      && map.tx == map.tx.rounded() && map.ty == map.ty.rounded()
    let original = backdrop ?? surface
    let brush = stroke.brush
    let columns = coverage.columns
    let tiles = coverage.tiles
    var result = surface
    var changed = false
    for (key, values) in tiles {
      try Task.checkCancellation()
      let ox = (key % columns) * 64
      let oy = (key / columns) * 64
      for i in values.indices where values[i] > 0 {
        let x = ox + i % 64
        let y = oy + i / 64
        guard x < surface.width, y < surface.height else { continue }
        let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
        let dx = Int(floor(q.x))
        let dy = Int(floor(q.y))
        if let selection, !selection.contains(dx, dy) { continue }
        let opacity = values[i] * brush.opacity * (selectionMask?.coverage(x: dx, y: dy) ?? 1)
        guard opacity > 0 else { continue }
        let at = map.point(Double(x) + 0.5, Double(y) + 0.5)
        var ink = sample(
          stroke.source.surface, x: at.x, y: at.y, nearest: nearest,
          linear: surface.depth == .f32 && !stroke.mask,
          outside: stroke.source.outside, grayscale: stroke.mask)
        guard ink.a > 0 else { continue }
        var before = original.pixel(x: x, y: y)
        if preserveTransparency && !stroke.mask && before.a <= 0 { continue }
        if stroke.mask {
          ink = Pixel(unit(ink.r), unit(ink.r), unit(ink.r), ink.a)
          before = Pixel(unit(before.r), unit(before.r), unit(before.r))
        }
        let out: Pixel
        if preserveTransparency && !stroke.mask {
          if surface.depth == .f32 {
            out = SRGBTransfer.encoded(ProtectedPixels.composite(brush.mode,
              backdrop: SRGBTransfer.linear(before), source: SRGBTransfer.linear(ink),
              opacity: opacity, x: dx, y: dy))
          } else {
            out = ProtectedPixels.composite(brush.mode, backdrop: before, source: ink,
              opacity: opacity, x: dx, y: dy)
          }
        } else if brush.mode == .normal && opacity == 1 && ink.a == 1 {
          out = ink
        } else if surface.depth == .f32 && !stroke.mask {
          out = SRGBTransfer.encoded(
            brush.mode.composite(
              backdrop: SRGBTransfer.linear(before), source: SRGBTransfer.linear(ink),
              opacity: opacity, x: dx, y: dy))
        } else {
          out = brush.mode.composite(backdrop: before, source: ink, opacity: opacity, x: dx, y: dy)
        }
        guard out.isFinite else {
          throw CraftError.invalid("Clone Stamp produced a non-finite sample.")
        }
        let stored = out.quantized(surface.depth)
        if !stored.hasSameBits(as: surface.pixel(x: x, y: y)) {
          result.setPixel(x: x, y: y, stored)
          changed = true
        }
      }
    }
    try Task.checkCancellation()
    if changed { surface = result }
    return changed
  }
}

/// Shared immutable round-tip coverage for Clone Stamp and Healing Brush.
struct RetouchCoverage {
  let width: Int
  let height: Int
  let columns: Int
  let tiles: [Int: [Float]]
  func value(x: Int, y: Int) -> Float {
    guard x >= 0, y >= 0, x < width, y < height else { return 0 }
    return tiles[(y / 64) * columns + x / 64]?[(y % 64) * 64 + x % 64] ?? 0
  }
  var bounds: IntRect? {
    var x0 = Int.max
    var y0 = Int.max
    var x1 = 0
    var y1 = 0
    for (key, values) in tiles {
      for i in values.indices where values[i] > 0 {
        let x = (key % columns) * 64 + i % 64
        let y = (key / columns) * 64 + i / 64
        x0 = min(x0, x)
        y0 = min(y0, y)
        x1 = max(x1, x + 1)
        y1 = max(y1, y + 1)
      }
    }
    guard x0 < x1 && y0 < y1 else { return nil }
    return IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }
}
