import Foundation

public enum RetouchToneRange: String, CaseIterable, Sendable {
  case shadows = "Shadows"
  case midtones = "Midtones"
  case highlights = "Highlights"
}
public enum ToningTool: String, CaseIterable, Sendable {
  case dodge = "Dodge"
  case burn = "Burn"
  case sponge = "Sponge"
}
public enum SpongeMode: String, CaseIterable, Sendable {
  case desaturate = "Desaturate"
  case saturate = "Saturate"
}
public struct ToningOptions: Equatable, Sendable {
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
    // Share stroke validation without capturing a sample image.
    let target = CloneStroke(
      source: .init(surface: try Surface(width: 1, height: 1)),
      mapping: .init(source: .init(0, 0), anchor: .init(0, 0)), brush: stroke.brush,
      points: stroke.points, mask: stroke.mask)
    _ = try ClonePainter.prepare(target)
    guard stroke.options.exposure.isFinite, (0...1).contains(stroke.options.exposure),
      stroke.brush.mode == .normal
    else { throw CraftError.invalid("Invalid toning settings.") }
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
  private static func paintPixels(
    _ stroke: ToningStroke, on surface: inout Surface,
    transform: Transform2D, clipping: IntRect, selectionMask: SelectionMask?
  ) throws -> Bool {
    let inverse = try transform.inverted()
    let brush = stroke.brush
    let columns = (surface.width + 63) / 64
    // Negative alpha marks untouched cells. Every working sample stays Float32 across
    // sequential dabs; integer storage is quantized only at the final commit.
    var tiles: [Int: [SIMD4<Float>]] = [:]
    let empty = SIMD4<Float>(0, 0, 0, -1)
    var visits = 0
    try RetouchDabs.forEach(brush: brush, points: stroke.points) { point in
      guard point.pressure > 0 else { return }
      let radius = max(0.25, brush.size * (brush.pressureSize ? Double(point.pressure) : 1) / 2)
      let center = inverse.point(point.x, point.y)
      let rx = (radius + 0.5) * hypot(inverse.a, inverse.c)
      let ry = (radius + 0.5) * hypot(inverse.b, inverse.d)
      let x0 = Int(max(0, min(Double(surface.width), floor(center.x - rx))))
      let x1 = Int(max(-1, min(Double(surface.width - 1), ceil(center.x + rx))))
      let y0 = Int(max(0, min(Double(surface.height), floor(center.y - ry))))
      let y1 = Int(max(-1, min(Double(surface.height - 1), ceil(center.y + ry))))
      guard x0 <= x1, y0 <= y1 else { return }
      visits += (x1 - x0 + 1) * (y1 - y0 + 1)
      guard visits <= 200_000_000 else {
        throw CraftError.invalid("Toning stroke exceeds its processing limit.")
      }
      for y in y0...y1 {
        try Task.checkCancellation()
        for x in x0...x1 {
          let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
          let dx = Int(floor(q.x))
          let dy = Int(floor(q.y))
          guard clipping.contains(dx, dy), (selectionMask?.coverage(x: dx, y: dy) ?? 1) > 0 else {
            continue
          }
          let coverage =
            ClonePainter.coverage(
              distance: Float(hypot(q.x - point.x, q.y - point.y)),
              radius: Float(radius), hardness: brush.hardness) * brush.flow
            * (brush.pressureOpacity ? point.pressure : 1)
          let k = ToningMath.perDab(
            coverage * (stroke.tool == .sponge ? 0.5 : stroke.options.exposure),
            spacing: Float(brush.spacing))
          if k <= 0 { continue }
          let key = y / 64 * columns + x / 64
          let i = y % 64 * 64 + x % 64
          let original = surface.pixel(x: x, y: y)
          // Preserve invisible raster samples and avoid expanding empty layers for a no-op.
          if !stroke.mask && original.a <= 0 { continue }
          let prior = tiles[key]?[i] ?? empty
          let base =
            stroke.mask ? Pixel(unit(original.r), unit(original.r), unit(original.r)) : original
          let c = prior.w >= 0 ? SIMD3(prior.x, prior.y, prior.z) : SIMD3(base.r, base.g, base.b)
          let out =
            stroke.tool == .sponge
            ? ToningMath.sponge(
              c, amount: k, saturate: stroke.options.spongeMode == .saturate,
              vibrance: stroke.options.vibrance)
            : ToningMath.dodgeBurn(
              c, exposure: k, range: stroke.options.range, burn: stroke.tool == .burn,
              protectTones: stroke.options.protectTones)
          guard out.x.isFinite && out.y.isFinite && out.z.isFinite else {
            throw CraftError.invalid("Toning produced a non-finite sample.")
          }
          if out == c { continue }
          if tiles[key] == nil {
            guard tiles.count < 10_240 else {
              throw CraftError.invalid("Toning stroke exceeds its memory limit.")
            }
            tiles[key] = [SIMD4<Float>](repeating: empty, count: 4096)
          }
          tiles[key]?[i] = SIMD4(out.x, out.y, out.z, base.a)
        }
      }
    }
    var result = surface
    var changed = false
    for (key, values) in tiles {
      try Task.checkCancellation()
      for i in values.indices where values[i].w >= 0 {
        let x = key % columns * 64 + i % 64
        let y = key / columns * 64 + i / 64
        let original = surface.pixel(x: x, y: y)
        let base =
          stroke.mask ? Pixel(unit(original.r), unit(original.r), unit(original.r)) : original
        let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
        let k =
          brush.opacity * (selectionMask?.coverage(x: Int(floor(q.x)), y: Int(floor(q.y))) ?? 1)
        let out = values[i]
        func mix(_ before: Float, _ after: Float) -> Float {
          if !stroke.mask && base.a > 1e-6 {
            return (before * base.a + (after * base.a - before * base.a) * k) / base.a
          }
          return before + (after - before) * k
        }
        let pixel = Pixel(mix(base.r, out.x), mix(base.g, out.y), mix(base.b, out.z), base.a)
          .quantized(surface.depth)
        guard pixel.isFinite else {
          throw CraftError.invalid("Toning produced a non-finite sample.")
        }
        if !pixel.hasSameBits(as: original) {
          result.setPixel(x: x, y: y, pixel)
          changed = true
        }
      }
    }
    try Task.checkCancellation()
    if changed { surface = result }
    return changed
  }
}
