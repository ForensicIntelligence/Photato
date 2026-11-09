import Foundation

/// Full-resolution sky coverage. Morphology patches include complete dependency
/// halos; Gaussian filtering retains full axis lengths in a separate paged pass.
/// Presentation reduction is never used. Uniform areas remain implicit.
enum PagedSkyMask {
  private static func byte(_ value: Float) -> UInt8 {
    UInt8(min(255, max(0, (value * 255).rounded())))
  }

  private static func regions(_ source: Surface, halo: Int) throws -> GeometryPatchRegions {
    let canvas = IntRect(x: 0, y: 0, width: source.width, height: source.height)
    let support = source.tileCount <= RasterGeometry.sparseGridSourceTileLimit
      ? try source.projectedGeometrySupport(.identity, bounds: canvas, halo: halo) : [canvas]
    return GeometryPatchRegions(width: source.width, height: source.height, rectangles: support)
  }

  static func refined(_ mask: SelectionMask, settings: SkyReplacementSettings,
                      strokes: [SkyMaskStroke]) throws -> SelectionMask {
    try Task.checkCancellation()
    try settings.validate()
    guard strokes.count <= 128 else { throw CraftError.invalid("Sky Replacement supports at most128 refinement strokes.") }
    // Admit every stroke before doing any raster work. Stroke-local brush work
    // and coverage budgets still apply in the shared Painter implementation.
    for stroke in strokes { try stroke.validate() }
    let source = try mask.coverageSurface(), shift = Int((settings.shiftEdge / 100 * 20).rounded())
    let sigma = Float(settings.fadeEdge / 100 * 5)
    let halo = abs(shift)
    func filter(_ values: [Float], _ width: Int, _ height: Int) throws -> [Float] {
      var output = values
      if shift != 0 { output = try MattingFilters.morph(output, width, height, abs(shift), grow: shift > 0) }
      return output
    }
    let background = Float(byte(try filter([source.defaultPixel.r], 1, 1)[0])) / 255
    let builder = try Surface.PagedBuilder(width: source.width, height: source.height, depth: .u8,
      fill: Pixel(background, background, background))
    for region in try regions(source, halo: halo) {
      try Task.checkCancellation()
      let area = SelectionSegmentation.inflate(region, halo, source.width, source.height)
      var values = [Float](repeating: 0, count: area.width * area.height)
      for y in 0..<area.height {
        try Task.checkCancellation()
        for x in 0..<area.width { values[y * area.width + x] = source.pixel(x: area.x + x, y: area.y + y).r }
      }
      values = try filter(values, area.width, area.height)
      var patch = try Surface(width: region.width, height: region.height, depth: .u8,
        fill: Pixel(background, background, background))
      for y in 0..<region.height {
        try Task.checkCancellation()
        for x in 0..<region.width {
          let value = Float(byte(values[(region.y + y - area.y) * area.width + region.x + x - area.x])) / 255
          if value != background { patch.setPixel(x: x, y: y, Pixel(value, value, value)) }
        }
      }
      try builder.append(patch, atX: region.x, atY: region.y)
    }
    var output = try SkyMaskGaussian.apply(builder.finish(), sigma: sigma)
    for stroke in strokes {
      try Task.checkCancellation()
      var brush = Brush()
      brush.size = stroke.size; brush.hardness = stroke.hardness; brush.opacity = stroke.opacity
      let gray: Float = stroke.add ? 1 : 0
      brush.color = Pixel(gray, gray, gray); brush.backgroundColor = brush.color
      brush.erase = false; brush.settings = brush.settings ?? .init()
      brush.settings!.colorDynamics.enabled = false; brush.settings!.mode = .normal
      try Painter.stroke(surface: &output, points: stroke.points, brush: brush, grayscaleMask: true)
      // Each stroke starts from the same quantized coverage as the dense path.
      output = try output.quantizedCoverageStorage()
    }
    return try SelectionMask(coverage: output)
  }

  static func edge(_ mask: SelectionMask) throws -> SelectionMask {
    try Task.checkCancellation()
    let source = try mask.coverageSurface()
    let builder = try Surface.PagedBuilder(width: source.width, height: source.height, depth: .u8, fill: .black)
    for region in try regions(source, halo: 5) {
      try Task.checkCancellation()
      let area = SelectionSegmentation.inflate(region, 5, source.width, source.height)
      var values = [Float](repeating: 0, count: area.width * area.height)
      for y in 0..<area.height {
        try Task.checkCancellation()
        for x in 0..<area.width { values[y * area.width + x] = source.pixel(x: area.x + x, y: area.y + y).r }
      }
      let high = try MattingFilters.extreme(values, area.width, area.height, 5, maximum: true)
      let low = try MattingFilters.extreme(values, area.width, area.height, 5, maximum: false)
      var patch = try Surface(width: region.width, height: region.height, depth: .u8, fill: .black)
      for y in 0..<region.height {
        try Task.checkCancellation()
        for x in 0..<region.width {
          let i = (region.y + y - area.y) * area.width + region.x + x - area.x
          let value = Float(byte((high[i] - low[i]) * (1 - values[i]))) / 255
          if value > 0 { patch.setPixel(x: x, y: y, Pixel(value, value, value)) }
        }
      }
      try builder.append(patch, atX: region.x, atY: region.y)
    }
    return try SelectionMask(coverage: builder.finish())
  }
}
