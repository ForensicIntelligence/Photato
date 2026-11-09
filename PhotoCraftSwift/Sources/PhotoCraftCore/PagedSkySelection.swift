import Foundation

/// The classical sky classifier on a bounded analysis grid, followed by guided
/// filtering at the original resolution. Float fields and box-filter passes
/// spill separately, so the refinement radius never requires a 2r-by-2r heap.
enum PagedSkySelection {
  private static func analysisPixel(_ stored: Pixel, encoding: SurfaceColorEncoding) throws -> Pixel {
    let p = encoding == .linearRGB ? SRGBTransfer.encoded(stored) : stored
    guard p.isFinite else { throw CraftError.invalid("Selection source contains a nonfinite sample.") }
    let alpha = unit(p.a)
    return Pixel(unit(p.r) * alpha + 0.5 * (1 - alpha),
      unit(p.g) * alpha + 0.5 * (1 - alpha), unit(p.b) * alpha + 0.5 * (1 - alpha))
  }

  /// Separable, truncated-window box average. Prefix scratch contains one line;
  /// output patches contain at most2048x64pixels regardless of filter radius.
  static func box(_ source: Surface, radius: Int) throws -> Surface {
    guard radius >= 0, radius <= Surface.maxDimension else { throw CraftError.invalid("Invalid sky refinement radius.") }
    try Task.checkCancellation()
    if radius == 0 { return source }
    func pass(_ input: Surface, horizontal: Bool) throws -> Surface {
      let canvas = IntRect(x: 0, y: 0, width: input.width, height: input.height)
      let support: [IntRect]
      if input.tileCount <= RasterGeometry.sparseGridSourceTileLimit {
        support = try input.projectedGeometrySupport(.identity, bounds: canvas, halo: 0).map { r in
          IntRect(x: r.x - (horizontal ? radius : 0), y: r.y - (horizontal ? 0 : radius),
            width: r.width + (horizontal ? 2 * radius : 0), height: r.height + (horizontal ? 0 : 2 * radius))
            .clipped(toWidth: input.width, height: input.height)
        }
      } else { support = [canvas] }
      let background = input.defaultPixel.r
      let builder = try Surface.PagedBuilder(width: input.width, height: input.height, depth: .f32,
        fill: Pixel(background, background, background))
      for region in GeometryPatchRegions(width: input.width, height: input.height, rectangles: support) {
        try Task.checkCancellation()
        var patch = try Surface(width: region.width, height: region.height, depth: .f32,
          fill: Pixel(background, background, background))
        let start = horizontal ? region.x : region.y
        let length = horizontal ? region.width : region.height
        let extent = horizontal ? input.width : input.height
        let lower = max(0, start - radius), upper = min(extent, start + length + radius)
        var prefix = [Double](repeating: 0, count: upper - lower + 1)
        for line in 0..<(horizontal ? region.height : region.width) {
          try Task.checkCancellation(); prefix[0] = 0
          for p in lower..<upper {
            let value = horizontal ? input.pixel(x: p, y: region.y + line).r : input.pixel(x: region.x + line, y: p).r
            prefix[p - lower + 1] = prefix[p - lower] + Double(value)
          }
          for p in start..<start + length {
            let low = max(0, p - radius), high = min(extent, p + radius + 1)
            let value = Float((prefix[high - lower] - prefix[low - lower]) / Double(high - low))
            if value != background {
              patch.setPixel(x: horizontal ? p - start : line, y: horizontal ? line : p - start, Pixel(value, value, value))
            }
          }
        }
        try builder.append(patch, atX: region.x, atY: region.y)
      }
      return try builder.finish()
    }
    return try pass(pass(source, horizontal: true), horizontal: false)
  }

  static func guided(guide: Surface, input: Surface, radius: Int, epsilon: Float) throws -> Surface {
    guard guide.width == input.width, guide.height == input.height,
      epsilon.isFinite, epsilon > 0 else { throw CraftError.invalid("Invalid sky guide or regularization.") }
    let mean = try box(guide, radius: radius), p = try box(input, radius: radius)
    let squared = try guide.mappedStoredSamples { value in let v = value.r * value.r; return Pixel(v, v, v) }
    let product = try guide.combiningStoredSamples(with: input) { i, p in let v = i.r * p.r; return Pixel(v, v, v) }
    let ii = try box(squared, radius: radius), ip = try box(product, radius: radius)
    let means = try mean.combiningStoredSamples(with: p) { Pixel($0.r, $1.r, 0) }
    let products = try ii.combiningStoredSamples(with: ip) { Pixel($0.r, $1.r, 0) }
    let coefficients = try means.combiningStoredSamples(with: products) { m, v in
      let a = (v.g - m.r * m.g) / (max(0, v.r - m.r * m.r) + epsilon)
      return Pixel(a, m.g - a * m.r, 0)
    }
    let a = try box(coefficients.mappedStoredSamples { Pixel($0.r, $0.r, $0.r) }, radius: radius)
    let b = try box(coefficients.mappedStoredSamples { Pixel($0.g, $0.g, $0.g) }, radius: radius)
    let scaled = try a.combiningStoredSamples(with: guide) { a, i in let v = a.r * i.r; return Pixel(v, v, v) }
    return try scaled.combiningStoredSamples(with: b) { a, b in let v = a.r + b.r; return Pixel(v, v, v) }
  }

  static func mask(_ source: Surface, settings: SkySelectionSettings, workingPixels: Int) throws -> SelectionMask? {
    try settings.validate(); try Task.checkCancellation()
    guard (16...160_000).contains(workingPixels) else { throw CraftError.invalid("Invalid sky working resolution.") }
    let width = source.width, height = source.height
    guard width >= 4, height >= 4 else { return nil }
    let proposedWidth = max(2, min(width, Int(sqrt(Double(workingPixels) * Double(width) / Double(height)))))
    let lowHeight = max(2, min(height, workingPixels / proposedWidth))
    let lowWidth = min(proposedWidth, workingPixels / lowHeight)
    let overview = try source.reducedPreview(in: .init(x: 0, y: 0, width: width, height: height),
      width: lowWidth, height: lowHeight, encoding: .sRGB) { try analysisPixel($0, encoding: source.colorEncoding) }
    var samples = [SelectionRGB](); samples.reserveCapacity(lowWidth * lowHeight)
    for y in 0..<lowHeight {
      try Task.checkCancellation()
      for x in 0..<lowWidth { let p = overview.pixel(x: x, y: y); samples.append(.init(p.r, p.g, p.b)) }
    }
    guard let low = try SkySelection.low(.init(width: lowWidth, height: lowHeight, pixels: samples),
      threshold: Float(settings.threshold)) else { return nil }
    let count = low.filter { $0 }.count
    if count == low.count {
      return try SelectionMask(coverage: Surface(width: width, height: height, depth: .u8, fill: .white))
    }
    let background: Float = count * 2 >= low.count ? 1 : 0
    let sx = Float(width) / Float(lowWidth), sy = Float(height) / Float(lowHeight)
    var left = lowWidth, top = lowHeight, right = 0, bottom = 0
    for i in low.indices where (low[i] ? Float(1) : 0) != background {
      left = min(left, i % lowWidth); right = max(right, i % lowWidth + 1)
      top = min(top, i / lowWidth); bottom = max(bottom, i / lowWidth + 1)
    }
    let x0 = max(0, Int(floor((Float(left) - 1) * sx))), y0 = max(0, Int(floor((Float(top) - 1) * sy)))
    let x1 = min(width, Int(ceil((Float(right) + 1) * sx))), y1 = min(height, Int(ceil((Float(bottom) + 1) * sy)))
    func coarse(_ x: Int, _ y: Int) -> Float {
      let fx = (Float(x) + 0.5) / sx - 0.5, fy = (Float(y) + 0.5) / sy - 0.5
      let x0 = Int(floor(fx)), y0 = Int(floor(fy)), ax = fx - floor(fx), ay = fy - floor(fy)
      func at(_ x: Int, _ y: Int) -> Float { low[min(lowHeight - 1, max(0, y)) * lowWidth + min(lowWidth - 1, max(0, x))] ? 1 : 0 }
      return (at(x0, y0) * (1 - ax) + at(x0 + 1, y0) * ax) * (1 - ay)
        + (at(x0, y0 + 1) * (1 - ax) + at(x0 + 1, y0 + 1) * ax) * ay
    }
    let builder = try Surface.PagedBuilder(width: width, height: height, depth: .f32,
      fill: Pixel(background, background, background))
    for region in GeometryPatchRegions(width: width, height: height,
      rectangles: [.init(x: x0, y: y0, width: x1 - x0, height: y1 - y0)]) {
      var patch = try Surface(width: region.width, height: region.height, depth: .f32,
        fill: Pixel(background, background, background))
      for y in 0..<region.height {
        try Task.checkCancellation()
        for x in 0..<region.width {
          let value = coarse(region.x + x, region.y + y)
          if value != background { patch.setPixel(x: x, y: y, Pixel(value, value, value)) }
        }
      }
      try builder.append(patch, atX: region.x, atY: region.y)
    }
    let coarseMask = try builder.finish(), soft = Float(settings.softness / 100)
    let radius = max(3, Int(ceil(max(sx, sy) * (1 + 2 * soft))))
    let guide = try source.mappedStoredSamples(encoding: .sRGB) { stored in
      let p = try analysisPixel(stored, encoding: source.colorEncoding)
      let v = SkySelection.luma(.init(p.r, p.g, p.b)); return Pixel(v, v, v)
    }
    let refined = try guided(guide: guide, input: coarseMask, radius: radius, epsilon: 1e-4 + 4e-3 * soft)
    let k: Float = 0.08 + 0.42 * soft
    let coverage = try refined.mappedStoredSamples { p in
      let v = (SkySelection.smooth(0.5 - k, 0.5 + k, p.r) * 255).rounded() / 255
      return Pixel(v, v, v)
    }
    let result = try SelectionMask(coverage: coverage)
    return result.bounds == nil ? nil : result
  }
}
