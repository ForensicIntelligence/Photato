import Foundation

/// Worker-confined toning on a fixed raster grid. Retain unquantized working
/// samples across preview batches; quantized display surfaces are immutable.
public final class ToningStrokeSession {
  public private(set) var surface: Surface
  private let originalSurface: Surface
  private let stroke: ToningStroke
  private let brush: CloneBrush
  private let transform: Transform2D
  private let inverse: Transform2D
  private let clipping: IntRect
  private let selectionMask: SelectionMask?
  private let columns: Int
  private let empty = SIMD4<Float>(0, 0, 0, -1)
  private var tiles: [Int: [SIMD4<Float>]] = [:]
  private var dirty: Set<Int> = []
  private var generator = RetouchDabGenerator()
  private var visits = 0
  private var count = 0
  private var failed = false
  public init(surface: Surface, stroke: ToningStroke, transform: Transform2D,
    clipping: IntRect, selectionMask: SelectionMask? = nil) throws {
    _ = try ToningPainter.validate(stroke); try surface.validated(); try transform.validated()
    guard (-1_000_000...1_000_000).contains(clipping.x), (-1_000_000...1_000_000).contains(clipping.y),
      (0...2_000_000).contains(clipping.width), (0...2_000_000).contains(clipping.height)
    else { throw CraftError.invalid("Invalid toning clipping bounds.") }
    self.surface = surface; originalSurface = surface; self.transform = transform
    inverse = try transform.inverted(); self.clipping = clipping; self.selectionMask = selectionMask
    columns = (surface.width + 63) / 64; brush = stroke.brush
    var metadata = stroke; metadata.points = []; self.stroke = metadata
    _ = try append(stroke.points)
  }
  public func append(_ points: [StrokePoint]) throws -> Surface {
    guard !failed else { throw CraftError.invalid("The failed or cancelled toning stroke must be restarted.") }
    do {
      try Task.checkCancellation()
      guard count + points.count <= 100_000 else { throw CraftError.invalid("Toning stroke is too long.") }
      for point in points {
        guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000,
          point.pressure.isFinite, (0...1).contains(point.pressure)
        else { throw CraftError.invalid("Invalid toning sample.") }
      }
      count += points.count
      guard brush.opacity > 0, brush.flow > 0, stroke.tool == .sponge || stroke.options.exposure > 0 else { return surface }
      dirty.removeAll(keepingCapacity: true)
      var sequence = generator
      try sequence.append(points, brush: brush) { try self.dab($0) }
      generator = sequence
      return try snapshot()
    } catch { failed = true; throw error }
  }
  private func dab(_ point: StrokePoint) throws {
      guard point.pressure > 0 else { return }
      let radius = max(0.25, brush.size * (brush.pressureSize ? Double(point.pressure) : 1) / 2)
      let center = inverse.point(point.x, point.y)
      let rx = (radius + 0.5) * hypot(inverse.a, inverse.c)
      let ry = (radius + 0.5) * hypot(inverse.b, inverse.d)
      let x0 = Int(max(0, min(Double(originalSurface.width), floor(center.x - rx))))
      let x1 = Int(max(-1, min(Double(originalSurface.width - 1), ceil(center.x + rx))))
      let y0 = Int(max(0, min(Double(originalSurface.height), floor(center.y - ry))))
      let y1 = Int(max(-1, min(Double(originalSurface.height - 1), ceil(center.y + ry))))
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
          let original = originalSurface.pixel(x: x, y: y)
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
          dirty.insert(key)
        }
      }
  }
  private func snapshot() throws -> Surface {
    var result = surface
    var changed = false
    for key in dirty {
      let values = tiles[key]!
      try Task.checkCancellation()
      for i in values.indices where values[i].w >= 0 {
        let x = key % columns * 64 + i % 64
        let y = key / columns * 64 + i / 64
        let original = originalSurface.pixel(x: x, y: y)
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
        if !pixel.hasSameBits(as: surface.pixel(x: x, y: y)) {
          result.setPixel(x: x, y: y, pixel)
          changed = true
        }
      }
    }
    try Task.checkCancellation()
    if changed { surface = result }
    return surface
  }
}
