import PhotoCraftCore

/// Destructive raster clipping-mask output keeps the base's straight RGB and
/// coverage separate. Every clip contributes only at its own raster coordinates.
enum ClippingMaskRasterMerge {
  private struct Clip {
    let pixels: Surface
    let bounds: IntRect
    let opacity: Float
    let blendMode: BlendMode
    let copiesOpaqueSource: Bool
  }

  static func render(base: Layer, clips: [Layer], document: CraftDocument) throws -> Surface {
    guard case .raster(let basePixels) = base.content else {
      throw CraftError.invalid("Merge Clipping Mask requires a raster base.")
    }
    let depth = document.depth
    let linear = depth == .f32
    let size = (width: basePixels.width, height: basePixels.height)
    let localBounds = IntRect(x: 0, y: 0, width: size.width, height: size.height)
    var rectangles: [IntRect] = []
    let tile = Surface.tileSide
    func appendTiles(_ pixels: Surface, x: Int, y: Int) throws {
      let columns = (pixels.width + tile - 1) / tile
      for key in pixels.storedTileKeys {
        try Task.checkCancellation()
        let left = key % columns * tile, top = key / columns * tile
        let rect = IntRect(x: x + left, y: y + top, width: min(tile, pixels.width - left),
          height: min(tile, pixels.height - top))
        rectangles.append(rect.clipped(toWidth: size.width, height: size.height))
      }
    }
    func implicit(_ pixels: Surface) throws -> Pixel {
      if !linear { return pixels.defaultPixel }
      if pixels.colorEncoding == .linearRGB {
        return try pixels.interpretingSamples(as: .sRGB).defaultPixel
      }
      return SRGBTransfer.linear(pixels.defaultPixel)
    }
    func combine(_ backdrop: Pixel, _ sample: Pixel, clip: Clip) throws -> Pixel {
      if clip.blendMode == .screen {
        return NormalLayerComposite.screenClipping(backdrop: backdrop, source: sample,
          opacity: clip.opacity, depth: depth)
      }
      let opaque = Pixel(backdrop.r, backdrop.g, backdrop.b, 1)
      let result: Pixel
      if linear {
        let alpha = RGB32NormalRenderer.scaleAlpha(sample.a, by: clip.opacity,
          flushSubnormal: clip.opacity != 1)
        result = try RGB32NormalRenderer.blend(opaque, Pixel(sample.r, sample.g, sample.b, alpha),
          opaque: true, copiesSource: clip.copiesOpaqueSource, forLayerOutput: true)
      } else {
        result = NormalLayerComposite.composite(backdrop: opaque, source: sample, opacity: clip.opacity, depth: depth)
      }
      return Pixel(result.r, result.g, result.b, backdrop.a)
    }
    var backdrop = try implicit(basePixels)
    var sources: [Clip] = []
    try appendTiles(basePixels, x: 0, y: 0)
    for layer in clips where layer.visible && layer.opacity > 0 {
      try Task.checkCancellation()
      guard case .raster(let pixels) = layer.content else {
        throw CraftError.invalid("The clipping mask contains a non-raster source.")
      }
      let bounds = IntRect(x: layer.x - base.x, y: layer.y - base.y, width: pixels.width, height: pixels.height)
      let intersection = bounds.clipped(toWidth: size.width, height: size.height)
      guard intersection.width > 0 && intersection.height > 0 else { continue }
      let copies = linear && RGB32NormalRenderer.canCopyOpaqueRaster(layer, source: pixels, in: document)
        ? try pixels.isOpaque() : false
      let source = Clip(pixels: pixels, bounds: bounds, opacity: layer.opacity,
        blendMode: layer.blendMode, copiesOpaqueSource: copies)
      sources.append(source)
      if intersection == localBounds {
        backdrop = try combine(backdrop, implicit(pixels), clip: source)
        try appendTiles(pixels, x: bounds.x, y: bounds.y)
      } else {
        // The implicit clip can contribute everywhere inside its rectangle.
        rectangles.append(intersection)
      }
    }
    guard !sources.isEmpty else { return basePixels }
    let encoding: SurfaceColorEncoding = linear ? .linearRGB : .sRGB
    let template = try Surface(width: size.width, height: size.height, depth: depth, fill: backdrop)
      .interpretingSamples(as: encoding)
    let builder = try Surface.PagedBuilder(template: template)
    for rect in GeometryPatchRegions(width: size.width, height: size.height, rectangles: rectangles) {
      try Task.checkCancellation()
      var patch = try Surface(width: rect.width, height: rect.height, depth: depth, fill: backdrop)
        .interpretingSamples(as: encoding)
      for y in rect.y..<(rect.y + rect.height) {
        for x in rect.x..<(rect.x + rect.width) {
          var sample = linear ? basePixels.linearPixel(x: x, y: y) : basePixels.pixel(x: x, y: y)
          for clip in sources where clip.bounds.contains(x, y) {
            let cx = x - clip.bounds.x, cy = y - clip.bounds.y
            let foreground = linear ? clip.pixels.linearPixel(x: cx, y: cy) : clip.pixels.pixel(x: cx, y: cy)
            sample = try combine(sample, foreground, clip: clip)
          }
          if linear { patch.setLinearPixel(x: x - rect.x, y: y - rect.y, sample) }
          else { patch.setPixel(x: x - rect.x, y: y - rect.y, sample) }
        }
      }
      try builder.append(patch, atX: rect.x, atY: rect.y)
    }
    return try builder.finish()
  }

  static func renderAdjacent(lower: Layer, upper: Layer, depth: PixelDepth) throws
    -> (pixels: Surface, x: Int, y: Int)
  {
    guard case .raster(let lowerPixels) = lower.content, case .raster(let upperPixels) = upper.content else {
      throw CraftError.invalid("Both clipped layers must contain raster pixels.")
    }
    let lowerOpacity = NormalLayerComposite.clippingOpacity(lower.opacity, depth: depth)
    let upperOpacity = NormalLayerComposite.clippingOpacity(upper.opacity, depth: depth)
    func combine(_ below: Pixel?, _ above: Pixel?) -> Pixel {
      NormalLayerComposite.adjacentClips(lower: below, upper: above, lowerOpacity: lowerOpacity,
        upperOpacity: upperOpacity, depth: depth)
    }
    func content(_ layer: Layer, _ pixels: Surface, _ opacity: Int) throws -> IntRect? {
      guard opacity > 0, let coverage = try pixels.contentBounds() else { return nil }
      return IntRect(x: layer.x + coverage.x, y: layer.y + coverage.y, width: coverage.width, height: coverage.height)
    }
    let possibleCoverage = try [content(lower, lowerPixels, lowerOpacity), content(upper, upperPixels, upperOpacity)]
    guard let bounds = try LayerLayout.union(possibleCoverage.compactMap { $0 }) else {
      return (try Surface(width: 1, height: 1, depth: depth), 0, 0)
    }
    let output = IntRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    func region(_ layer: Layer, _ pixels: Surface) -> IntRect {
      IntRect(x: layer.x - bounds.x, y: layer.y - bounds.y, width: pixels.width, height: pixels.height)
    }
    let lowerRegion = region(lower, lowerPixels), upperRegion = region(upper, upperPixels)
    let lowerIntersection = lowerRegion.clipped(toWidth: bounds.width, height: bounds.height)
    let upperIntersection = upperRegion.clipped(toWidth: bounds.width, height: bounds.height)
    let lowerDefault = lowerIntersection == output ? lowerPixels.defaultPixel : nil
    let upperDefault = upperIntersection == output ? upperPixels.defaultPixel : nil
    let fill = combine(lowerDefault, upperDefault)
    let builder = try Surface.PagedBuilder(template: Surface(width: bounds.width, height: bounds.height,
      depth: depth, fill: fill))
    var rectangles: [IntRect] = []
    if lowerDefault == nil && !combine(lowerPixels.defaultPixel, upperDefault).hasSameBits(as: fill) {
      rectangles.append(lowerIntersection)
    }
    if upperDefault == nil && !combine(lowerDefault, upperPixels.defaultPixel).hasSameBits(as: fill) {
      rectangles.append(upperIntersection)
    }
    func appendTiles(_ pixels: Surface, _ region: IntRect) throws {
      let side = Surface.tileSide
      let columns = (pixels.width + side - 1) / side
      for key in pixels.storedTileKeys {
        try Task.checkCancellation()
        let x = key % columns * side, y = key / columns * side
        let tile = IntRect(x: region.x + x, y: region.y + y,
          width: min(side, pixels.width - x), height: min(side, pixels.height - y))
        rectangles.append(tile.clipped(toWidth: bounds.width, height: bounds.height))
      }
    }
    try appendTiles(lowerPixels, lowerRegion)
    try appendTiles(upperPixels, upperRegion)
    for rect in GeometryPatchRegions(width: bounds.width, height: bounds.height, rectangles: rectangles) {
      try Task.checkCancellation()
      var patch = try Surface(width: rect.width, height: rect.height, depth: depth, fill: fill)
      for y in rect.y..<(rect.y + rect.height) {
        for x in rect.x..<(rect.x + rect.width) {
          let below = lowerRegion.contains(x, y)
            ? lowerPixels.pixel(x: x - lowerRegion.x, y: y - lowerRegion.y) : nil
          let above = upperRegion.contains(x, y)
            ? upperPixels.pixel(x: x - upperRegion.x, y: y - upperRegion.y) : nil
          patch.setPixel(x: x - rect.x, y: y - rect.y, combine(below, above))
        }
      }
      try builder.append(patch, atX: rect.x, atY: rect.y)
    }
    let raster = try builder.finish()
    guard let content = try raster.contentBounds() else {
      return (try Surface(width: 1, height: 1, depth: depth), 0, 0)
    }
    return (try raster.cropped(to: content), bounds.x + content.x, bounds.y + content.y)
  }
}
