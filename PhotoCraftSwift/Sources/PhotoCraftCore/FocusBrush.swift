import Foundation

public enum FocusTool: String, CaseIterable, Sendable {
  case blur = "Blur"
  case sharpen = "Sharpen"
  case smudge = "Smudge"
}
public struct FocusOptions: Equatable, Sendable {
  public var strength: Float = 0.5
  public var protectDetail = true
  public var sampleAllLayers = false
  public var fingerPainting = false
  public init() {}
}
public struct FocusStroke: Sendable {
  public var tool: FocusTool
  public var options: FocusOptions
  public var brush: CloneBrush
  public var points: [StrokePoint]
  public var mask: Bool
  public var foreground: Pixel
  /// Immutable visible composite when Sample All Layers is enabled. Nil otherwise.
  public var sample: CloneSample?
  public init(
    tool: FocusTool, options: FocusOptions = .init(), brush: CloneBrush,
    points: [StrokePoint], mask: Bool = false, foreground: Pixel = .black,
    sample: CloneSample? = nil
  ) {
    self.tool = tool
    self.options = options
    self.brush = brush
    self.points = points
    self.mask = mask
    self.foreground = foreground
    self.sample = sample
  }
}

public enum FocusPainter {
  @discardableResult public static func paint(
    _ focus: FocusStroke, on layer: inout Layer,
    canvasWidth: Int, canvasHeight: Int, selection: IntRect? = nil,
    selectionMask: SelectionMask? = nil
  ) throws -> Bool {
    try Task.checkCancellation()
    let original: Surface
    let targetTransform: Transform2D
    let outside: Pixel
    if focus.mask {
      guard let mask = layer.mask else { throw CraftError.invalid("This layer has no pixel mask.") }
      original = mask
      targetTransform = layer.maskCoordinateTransform
      let value = layer.effectiveMaskProperties.outside
      outside = Pixel(value, value, value)
    } else {
      guard case .raster(let pixels) = layer.content else {
        throw CraftError.unsupported("Rasterize this layer before retouching.")
      }
      original = pixels
      targetTransform = layer.coordinateTransform
      outside = .clear
    }
    let useAll = focus.options.sampleAllLayers && !focus.mask
    if useAll && focus.sample == nil {
      throw CraftError.invalid("Sample All Layers needs an immutable image sample.")
    }
    let source =
      useAll
      ? focus.sample! : CloneSample(surface: original, transform: targetTransform, outside: outside)
    let stroke = CloneStroke(
      source: source, mapping: .init(source: .init(0, 0), anchor: .init(0, 0)),
      brush: focus.brush, points: focus.points, mask: focus.mask)
    let mapping = try ClonePainter.prepare(stroke)
    guard focus.options.strength.isFinite, (0...1).contains(focus.options.strength),
      focus.foreground.isFinite, (0...1).contains(focus.foreground.a), focus.brush.mode == .normal
    else { throw CraftError.invalid("Invalid focus tool settings.") }
    _ = try Surface(width: canvasWidth, height: canvasHeight)
    guard focus.brush.opacity > 0, focus.brush.flow > 0, focus.options.strength > 0 else {
      return false
    }
    // Neighborhood effects and pickup operate before selection clipping, as in the source.
    let canvas = IntRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
    guard let bounds = ClonePainter.footprint(stroke, clipping: canvas) else { return false }
    let sigma = min(4, max(1, Float(focus.brush.size) * 0.03))
    let halo =
      focus.tool == .smudge ? Int(ceil(focus.brush.size / 2)) + 2 : Int(ceil(sigma * 3)) + 1
    let region = IntRect(
      x: bounds.x - halo, y: bounds.y - halo, width: bounds.width + 2 * halo,
      height: bounds.height + 2 * halo)
    guard region.width <= 36_864, region.height <= 36_864,
      region.width <= FocusKernels.maxPixels / region.height
    else {
      throw CraftError.invalid("Retouching region exceeds its 40-megapixel working limit.")
    }
    let w = region.width
    let h = region.height
    let ch = focus.mask ? 1 : 4
    let alpha: Int? = focus.mask ? nil : 3
    let nearest =
      mapping.a == 1 && mapping.b == 0 && mapping.c == 0 && mapping.d == 1
      && mapping.tx == mapping.tx.rounded() && mapping.ty == mapping.ty.rounded()
    var work = [Float](repeating: 0, count: w * h * ch)
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        let q = mapping.point(Double(region.x + x) + 0.5, Double(region.y + y) + 0.5)
        let pixel = ClonePainter.sample(
          source.surface, x: q.x, y: q.y, nearest: nearest,
          linear: original.depth == .f32 && !focus.mask, outside: source.outside,
          grayscale: focus.mask)
        guard pixel.isFinite, [pixel.r, pixel.g, pixel.b].allSatisfy({ abs($0) <= 1e12 }) else {
          throw CraftError.invalid("Retouching sample exceeds its numeric range.")
        }
        let i = (y * w + x) * ch
        work[i] = pixel.r
        if ch == 4 {
          work[i + 1] = pixel.g
          work[i + 2] = pixel.b
          work[i + 3] = pixel.a
        }
      }
    }
    let finger: [Float]? =
      focus.options.fingerPainting
      ? (focus.mask
        ? [ToningMath.luma(focus.foreground.rgb)]
        : [focus.foreground.r, focus.foreground.g, focus.foreground.b, focus.foreground.a]) : nil
    var smudge = try SmudgeKernel(
      strength: focus.options.strength, finger: finger, maxBrushSize: Float(focus.brush.size),
      alpha: alpha)
    var visits = 0
    var touched = false
    try RetouchDabs.forEach(brush: focus.brush, points: focus.points) { point in
      guard point.pressure > 0 else { return }
      let radius = max(
        0.25, focus.brush.size * (focus.brush.pressureSize ? Double(point.pressure) : 1) / 2)
      let cx = point.x - Double(region.x)
      let cy = point.y - Double(region.y)
      let x0 = Int(max(0, min(Double(w), floor(cx - radius - 0.5))))
      let x1 = Int(max(0, min(Double(w), ceil(cx + radius + 0.5) + 1)))
      let y0 = Int(max(0, min(Double(h), floor(cy - radius - 0.5))))
      let y1 = Int(max(0, min(Double(h), ceil(cy + radius + 0.5) + 1)))
      guard x1 > x0 && y1 > y0 else { return }
      let win = IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
      visits += win.width * win.height
      guard visits <= 200_000_000 else {
        throw CraftError.invalid("Retouching stroke exceeds its processing limit.")
      }
      var coverage = [Float](repeating: 0, count: win.width * win.height)
      for y in y0..<y1 {
        try Task.checkCancellation()
        for x in x0..<x1 {
          coverage[(y - y0) * win.width + x - x0] =
            ClonePainter.coverage(
              distance: Float(hypot(Double(x) + 0.5 - cx, Double(y) + 0.5 - cy)),
              radius: Float(radius), hardness: focus.brush.hardness) * focus.brush.flow
            * (focus.brush.pressureOpacity ? point.pressure : 1)
        }
      }
      if !coverage.contains(where: { $0 > 0 }) { return }
      touched = true
      if focus.tool == .smudge {
        try smudge.applyUnchecked(to: &work, w, h, ch, .init(cx, cy), win, coverage)
      } else {
        let filtered =
          focus.tool == .blur
          ? try FocusKernels.blurUnchecked(work, w, h, ch, alpha, win, sigma)
          : try FocusKernels.sharpenUnchecked(
            work, w, h, ch, alpha, win, 1, focus.options.protectDetail)
        for y in y0..<y1 {
          try Task.checkCancellation()
          for x in x0..<x1 {
            let o = (y - y0) * win.width + x - x0
            let k = ToningMath.perDab(
              coverage[o] * focus.options.strength, spacing: Float(focus.brush.spacing))
            if k <= 0 { continue }
            let i = (y * w + x) * ch
            if focus.tool == .blur && ch == 4 {
              // Blur changes alpha. Mixing straight RGB here darkens a newly revealed
              // transparent edge, even though the convolution itself is premultiplied.
              let before = Pixel(work[i], work[i + 1], work[i + 2], work[i + 3])
              let at = o * ch
              let after = Pixel(filtered[at], filtered[at + 1], filtered[at + 2], filtered[at + 3])
              let mixed = FocusKernels.mix(before, after, k)
              guard mixed.isFinite else {
                throw CraftError.invalid("Blur produced a non-finite sample.")
              }
              work[i] = mixed.r
              work[i + 1] = mixed.g
              work[i + 2] = mixed.b
              work[i + 3] = mixed.a
              continue
            }
            for c in 0..<ch {
              work[i + c] += (filtered[o * ch + c] - work[i + c]) * k
              guard work[i + c].isFinite else {
                throw CraftError.invalid("Retouching produced a non-finite sample.")
              }
            }
          }
        }
      }
    }
    guard touched else { return false }
    func pixel(_ x: Int, _ y: Int) -> Pixel {
      let i = (min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))) * ch
      return ch == 1
        ? Pixel(work[i], work[i], work[i]) : Pixel(work[i], work[i + 1], work[i + 2], work[i + 3])
    }
    func sample(_ x: Double, _ y: Double) -> Pixel {
      let x = x - Double(region.x) - 0.5
      let y = y - Double(region.y) - 0.5
      let ix = Int(floor(x))
      let iy = Int(floor(y))
      let tx = Float(x - floor(x))
      let ty = Float(y - floor(y))
      if tx == 0 && ty == 0 { return pixel(ix, iy) }
      func pm(_ x: Int, _ y: Int) -> SIMD4<Float> {
        var p = pixel(x, y)
        if original.depth == .f32 && !focus.mask { p = SRGBTransfer.linear(p) }
        return SIMD4(p.r * p.a, p.g * p.a, p.b * p.a, p.a)
      }
      let v =
        (pm(ix, iy) * (1 - tx) + pm(ix + 1, iy) * tx) * (1 - ty)
        + (pm(ix, iy + 1) * (1 - tx) + pm(ix + 1, iy + 1) * tx) * ty
      if v.w <= 1e-8 { return .clear }
      let p = Pixel(v.x / v.w, v.y / v.w, v.z / v.w, v.w)
      return original.depth == .f32 && !focus.mask ? SRGBTransfer.encoded(p) : p
    }
    return try ClonePainter.paintTarget(
      stroke, on: &layer, canvasWidth: canvasWidth, canvasHeight: canvasHeight, selection: selection
    ) { pixels, transform, clipping in
      let coverage = try ClonePainter.strokeCoverage(stroke, surface: pixels, transform: transform)
      var result = pixels
      var changed = false
      for (key, values) in coverage.tiles {
        try Task.checkCancellation()
        for i in values.indices where values[i] > 0 {
          let x = key % coverage.columns * 64 + i % 64
          let y = key / coverage.columns * 64 + i / 64
          guard x < pixels.width, y < pixels.height else { continue }
          let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
          let dx = Int(floor(q.x))
          let dy = Int(floor(q.y))
          guard clipping.contains(dx, dy) else { continue }
          let k = focus.brush.opacity * (selectionMask?.coverage(x: dx, y: dy) ?? 1)
          if k <= 0 { continue }
          let raw = pixels.pixel(x: x, y: y)
          let before = focus.mask ? Pixel(unit(raw.r), unit(raw.r), unit(raw.r)) : raw
          let after = sample(q.x, q.y)
          if !focus.mask && before.a == 0 && after.a == 0 { continue }
          let p = FocusKernels.mix(before, after, k).quantized(pixels.depth)
          guard p.isFinite else {
            throw CraftError.invalid("Retouching produced a non-finite sample.")
          }
          if !p.hasSameBits(as: raw) {
            result.setPixel(x: x, y: y, p)
            changed = true
          }
        }
      }
      try Task.checkCancellation()
      if changed { pixels = result }
      return changed
    }
  }
}
