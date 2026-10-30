import Foundation

public enum RetouchToneRange: String, CaseIterable, Codable, Sendable {
  case shadows = "Shadows"
  case midtones = "Midtones"
  case highlights = "Highlights"
}
public enum ToningTool: String, CaseIterable, Codable, Sendable {
  case dodge = "Dodge"
  case burn = "Burn"
  case sponge = "Sponge"
}
public enum SpongeMode: String, CaseIterable, Codable, Sendable {
  case desaturate = "Desaturate"
  case saturate = "Saturate"
}
public struct ToningOptions: Codable, Equatable, Sendable {
  public var range = RetouchToneRange.midtones
  public var exposure: Float = 0.5
  public var protectTones = true
  public var spongeMode = SpongeMode.desaturate
  public var vibrance = true
  public init() {}
}

/// PhotoCraft's empirical toning equations, not a Photoshop output oracle.
public enum ToningMath {
  public static func luma(_ c: SIMD3<Float>) -> Float { 0.299 * c.x + 0.587 * c.y + 0.114 * c.z }
  public static func curve(_ value: Float, exposure: Float, range: RetouchToneRange, burn: Bool)
    -> Float
  {
    let v = max(value, 0)
    let e = unit(exposure)
    let m = min(v, 1)
    switch range {
    case .midtones:
      let w = unit(4 * v * (1 - v))
      return v + w * (pow(m, burn ? 1 + e : 1 / (1 + e)) - v)
    case .shadows:
      let q = (1 - m) * (1 - m)
      return burn ? v - e * q * v : v + e * q * (1 - m)
    case .highlights:
      let q = m * m
      return burn ? v - e * q * v : v + e * q * (1 - m)
    }
  }
  static func compress(_ c: SIMD3<Float>, around value: Float) -> SIMD3<Float> {
    let l = unit(value)
    let lo = min(c.x, min(c.y, c.z))
    let hi = max(c.x, max(c.y, c.z))
    var t: Float = 1
    if hi > 1 && hi - l > 1e-9 { t = min(t, (1 - l) / (hi - l)) }
    if lo < 0 && l - lo > 1e-9 { t = min(t, l / (l - lo)) }
    return SIMD3(l + (c.x - l) * t, l + (c.y - l) * t, l + (c.z - l) * t)
  }
  public static func dodgeBurn(
    _ c: SIMD3<Float>, exposure: Float, range: RetouchToneRange,
    burn: Bool, protectTones: Bool
  ) -> SIMD3<Float> {
    if exposure <= 0 { return c }
    if protectTones {
      let l = luma(c)
      let nl = curve(l, exposure: exposure, range: range, burn: burn)
      let out = l > 1e-6 ? SIMD3(c.x * nl / l, c.y * nl / l, c.z * nl / l) : SIMD3(repeating: nl)
      return compress(out, around: nl)
    }
    return SIMD3(
      curve(c.x, exposure: exposure, range: range, burn: burn),
      curve(c.y, exposure: exposure, range: range, burn: burn),
      curve(c.z, exposure: exposure, range: range, burn: burn))
  }
  public static func sponge(_ c: SIMD3<Float>, amount: Float, saturate: Bool, vibrance: Bool)
    -> SIMD3<Float>
  {
    var a = unit(amount)
    if a <= 0 { return c }
    let lo = min(c.x, min(c.y, c.z))
    let hi = max(c.x, max(c.y, c.z))
    let s: Float = hi <= 1e-6 ? 0 : unit((hi - lo) / hi)
    if vibrance { a *= saturate ? 1 - s : 0.25 + 0.75 * s }
    let l = luma(c)
    let k: Float = saturate ? 1 + a : 1 - a
    return compress(SIMD3(l + (c.x - l) * k, l + (c.y - l) * k, l + (c.z - l) * k), around: l)
  }
  public static func perDab(_ strength: Float, spacing: Float) -> Float {
    1 - pow(1 - unit(strength), min(1, max(0.01, spacing)))
  }
}

public struct ToningStroke: Sendable {
  public var tool: ToningTool
  public var options: ToningOptions
  public var brush: CloneBrush
  public var points: [StrokePoint]
  public var mask: Bool
  public init(
    tool: ToningTool, options: ToningOptions = .init(), brush: CloneBrush,
    points: [StrokePoint], mask: Bool = false
  ) {
    self.tool = tool
    self.options = options
    self.brush = brush
    self.points = points
    self.mask = mask
  }
}

public enum ToningPainter {
  @discardableResult public static func paint(
    _ stroke: ToningStroke, on layer: inout Layer,
    canvasWidth: Int, canvasHeight: Int, selection: IntRect? = nil,
    selectionMask: SelectionMask? = nil
  ) throws -> Bool {
    let target = try validate(stroke)
    if stroke.tool != .sponge && stroke.options.exposure == 0 { return false }
    if !stroke.mask {
      _ = try Surface(width: canvasWidth, height: canvasHeight)
      guard case .raster(var pixels) = layer.content else {
        throw CraftError.unsupported("Rasterize this layer before toning.")
      }
      if stroke.brush.opacity == 0 || stroke.brush.flow == 0 { return false }
      let clipping = (selection ?? IntRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
        .clipped(toWidth: canvasWidth, height: canvasHeight)
      // Toning preserves transparency, so a raster target never needs a larger frame.
      guard
        try paintPixels(
          stroke, on: &pixels, transform: layer.coordinateTransform,
          clipping: clipping, selectionMask: selectionMask)
      else { return false }
      try Task.checkCancellation()
      layer.content = .raster(pixels)
      return true
    }
    // A mask's implicit outside value can change and therefore needs expandable storage.
    return try ClonePainter.paintTarget(
      target, on: &layer, canvasWidth: canvasWidth,
      canvasHeight: canvasHeight, selection: selection
    ) { pixels, transform, clipping in
      try paintPixels(
        stroke, on: &pixels, transform: transform, clipping: clipping, selectionMask: selectionMask)
    }
  }
  static func validate(_ stroke: ToningStroke) throws -> CloneStroke {
    // Share stroke validation without capturing a sample image.
    let target = CloneStroke(
      source: .init(surface: try Surface(width: 1, height: 1)),
      mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: stroke.brush,
      points: stroke.points, mask: stroke.mask)
    _ = try ClonePainter.prepare(target)
    guard stroke.options.exposure.isFinite, (0...1).contains(stroke.options.exposure),
      stroke.brush.mode == .normal
    else { throw CraftError.invalid("Invalid toning settings.") }
    return target
  }
  private static func paintPixels(
    _ stroke: ToningStroke, on surface: inout Surface,
    transform: Transform2D, clipping: IntRect, selectionMask: SelectionMask?
  ) throws -> Bool {
    let result = try ToningStrokeSession(surface: surface, stroke: stroke,
      transform: transform, clipping: clipping, selectionMask: selectionMask).surface
    let changed = try result.changedTileBounds(comparedTo: surface) != nil
    if changed { surface = result }
    return changed
  }
}
