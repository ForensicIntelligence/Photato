import Foundation

/// One worker owns the unquantized neighborhood and Smudge pickup state.
/// Complete commands and incremental previews execute these same kernels.
final class FocusWorkBuffer {
  let focus: FocusStroke
  let source: CloneSample
  let mapping: Transform2D
  let depth: PixelDepth
  let nearest: Bool
  let ch: Int
  let alpha: Int?
  private(set) var region: IntRect
  private var work: [Float] = []
  private var smudge: SmudgeKernel
  private var generator = RetouchDabGenerator()
  private var visits = 0
  private(set) var touched = false
  private(set) var dirty: IntRect?
  private var w: Int { region.width }
  private var h: Int { region.height }
  init(
    focus: FocusStroke, source: CloneSample, mapping: Transform2D,
    depth: PixelDepth, region: IntRect
  ) throws {
    var metadata = focus
    metadata.points = []
    self.focus = metadata
    self.source = source
    self.mapping = mapping
    self.depth = depth
    self.region = region
    ch = focus.mask ? 1 : 4
    alpha = focus.mask ? nil : 3
    nearest =
      mapping.a == 1 && mapping.b == 0 && mapping.c == 0 && mapping.d == 1
      && mapping.tx == mapping.tx.rounded() && mapping.ty == mapping.ty.rounded()
    let finger: [Float]? =
      focus.options.fingerPainting
      ? (focus.mask
        ? [ToningMath.luma(focus.foreground.rgb)]
        : [focus.foreground.r, focus.foreground.g, focus.foreground.b, focus.foreground.a]) : nil
    smudge = try SmudgeKernel(
      strength: focus.options.strength, finger: finger, maxBrushSize: Float(focus.brush.size),
      alpha: alpha)
    try grow(to: region)
  }
  static func union(_ a: IntRect, _ b: IntRect) -> IntRect {
    let x = min(a.x, b.x)
    let y = min(a.y, b.y)
    return .init(
      x: x, y: y, width: max(a.x + a.width, b.x + b.width) - x,
      height: max(a.y + a.height, b.y + b.height) - y)
  }
  func grow(to requested: IntRect) throws {
    let next = work.isEmpty ? requested : Self.union(region, requested)
    guard next.width > 0, next.height > 0, next.width <= 36_864, next.height <= 36_864,
      next.width <= FocusKernels.maxPixels / next.height
    else {
      throw CraftError.invalid("Retouching region exceeds its 40-megapixel working limit.")
    }
    if next == region && !work.isEmpty { return }
    var expanded = [Float](repeating: 0, count: next.width * next.height * ch)
    for y in 0..<next.height {
      try Task.checkCancellation()
      for x in 0..<next.width {
        let gx = next.x + x
        let gy = next.y + y
        let i = (y * next.width + x) * ch
        if !work.isEmpty && region.contains(gx, gy) {
          let old = ((gy - region.y) * w + gx - region.x) * ch
          for c in 0..<ch { expanded[i + c] = work[old + c] }
          continue
        }
        let q = mapping.point(Double(gx) + 0.5, Double(gy) + 0.5)
        let pixel = ClonePainter.sample(
          source.surface, x: q.x, y: q.y, nearest: nearest,
          linear: depth == .f32 && !focus.mask, outside: source.outside, grayscale: focus.mask)
        guard pixel.isFinite, [pixel.r, pixel.g, pixel.b].allSatisfy({ abs($0) <= 1e12 }) else {
          throw CraftError.invalid("Retouching sample exceeds its numeric range.")
        }
        expanded[i] = pixel.r
        if ch == 4 {
          expanded[i + 1] = pixel.g
          expanded[i + 2] = pixel.b
          expanded[i + 3] = pixel.a
        }
      }
    }
    region = next
    work = expanded
  }
  func append(_ points: [StrokePoint]) throws {
    dirty = nil
    let sigma = min(4, max(1, Float(focus.brush.size) * 0.03))
    var sequence = generator
    try sequence.append(points, brush: focus.brush) { point in
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
      let changed = IntRect(
        x: region.x + win.x - 1, y: region.y + win.y - 1,
        width: win.width + 2, height: win.height + 2)
      dirty = dirty.map { Self.union($0, changed) } ?? changed
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
    generator = sequence
  }
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
      if depth == .f32 && !focus.mask { p = SRGBTransfer.linear(p) }
      return SIMD4(p.r * p.a, p.g * p.a, p.b * p.a, p.a)
    }
    let v =
      (pm(ix, iy) * (1 - tx) + pm(ix + 1, iy) * tx) * (1 - ty)
      + (pm(ix, iy + 1) * (1 - tx) + pm(ix + 1, iy + 1) * tx) * ty
    if v.w <= 1e-8 { return .clear }
    let p = Pixel(v.x / v.w, v.y / v.w, v.z / v.w, v.w)
    return depth == .f32 && !focus.mask ? SRGBTransfer.encoded(p) : p
  }
}
