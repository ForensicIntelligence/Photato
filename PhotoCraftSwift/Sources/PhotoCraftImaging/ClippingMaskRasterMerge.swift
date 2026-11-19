import PhotoCraftCore

/// Destructive raster clipping-mask output keeps the base's straight RGB and
/// coverage separate. Every clip contributes only at its own raster coordinates.
enum ClippingMaskRasterMerge {
  private struct Clip {
    let pixels: Surface
    let bounds: IntRect
    let opacity: Float
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
      let source = Clip(pixels: pixels, bounds: bounds, opacity: layer.opacity, copiesOpaqueSource: copies)
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
}
