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
    let mask: ClipMask?
    let arithmetic: HDRClippedArithmetic?
    let scalarDivideStart: Int?
  }

  private struct ClipMask {
    let pixels: Surface
    let bounds: IntRect
    let properties: MaskProperties

    func coverage(_ sample: Float, depth: PixelDepth) -> Float {
      let value = properties.inverted ? 1 - sample : sample
      return NormalLayerComposite.clippedMaskCoverage(value, density: properties.density, depth: depth)
    }

    func coverage(x: Int, y: Int, depth: PixelDepth) -> Float {
      let raw = bounds.contains(x, y) ? pixels.pixel(x: x - bounds.x, y: y - bounds.y).r : properties.outside
      return coverage(raw, depth: depth)
    }
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
    func combine(_ backdrop: Pixel, _ source: Pixel, clip: Clip, x: Int, coverage: Float) throws -> Pixel {
      var sample = source
      if clip.mask != nil {
        if linear {
          if coverage == 0 { return backdrop }
          sample.a = RGB32NormalRenderer.scaleAlpha(sample.a, by: coverage, flushSubnormal: true)
        } else {
          sample.a = NormalLayerComposite.applyClippedPixelMask(coverage, to: sample.a, depth: depth)
        }
      }
      if !linear {
        return try NormalLayerComposite.blendClippedInteger(backdrop: backdrop, source: sample,
          mode: clip.blendMode, opacity: clip.opacity, depth: depth)
      }
      let alpha = RGB32NormalRenderer.scaleAlpha(sample.a, by: clip.opacity,
        flushSubnormal: clip.opacity != 1)
      if let arithmetic = clip.arithmetic {
        let scalarDivide = clip.scalarDivideStart.map { x >= $0 } ?? false
        return try arithmetic.blend(backdrop: backdrop, source: sample, alpha: alpha, scalarDivide: scalarDivide)
      }
      let opaque = Pixel(backdrop.r, backdrop.g, backdrop.b, 1)
      let b = clip.blendMode
      let blended = Pixel(b.channel(backdrop.r, sample.r), b.channel(backdrop.g, sample.g),
        b.channel(backdrop.b, sample.b), alpha)
      let result = try RGB32NormalRenderer.blend(opaque, blended,
        opaque: true, copiesSource: clip.copiesOpaqueSource, forLayerOutput: true)
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
      let mask = try prepareMask(layer, relativeTo: base)
      let copies = linear && mask == nil && layer.blendMode == .normal
        && RGB32NormalRenderer.canCopyOpaqueRaster(layer, source: pixels, in: document)
        ? try pixels.isOpaque() : false
      let arithmetic = linear
        ? try HDRClippedArithmetic(mode: layer.blendMode, pixels: pixels, hasMask: mask != nil) : nil
      let scalarDivideStart = arithmetic?.scalarDivideStart(in: intersection)
      let source = Clip(pixels: pixels, bounds: bounds, opacity: layer.opacity,
        blendMode: layer.blendMode, copiesOpaqueSource: copies, mask: mask,
        arithmetic: arithmetic, scalarDivideStart: scalarDivideStart)
      sources.append(source)
      if intersection == localBounds {
        var coverage: Float = 1
        if let mask {
          let maskIntersection = mask.bounds.clipped(toWidth: size.width, height: size.height)
          coverage = mask.coverage(mask.properties.outside, depth: depth)
          let inBounds = mask.coverage(mask.pixels.defaultPixel.r, depth: depth)
          if maskIntersection == localBounds {
            coverage = inBounds
          } else if coverage != inBounds {
            rectangles.append(maskIntersection)
          }
          try appendTiles(mask.pixels, x: mask.bounds.x, y: mask.bounds.y)
        }
        let background = backdrop
        let foreground = try implicit(pixels)
        backdrop = try combine(background, foreground, clip: source, x: 0, coverage: coverage)
        if let tail = scalarDivideStart, tail > 0 {
          let scalar = try combine(background, foreground, clip: source, x: tail, coverage: coverage)
          if !scalar.hasSameBits(as: backdrop) {
            rectangles.append(IntRect(x: tail, y: 0, width: size.width - tail, height: size.height))
          }
        }
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
            let coverage = clip.mask?.coverage(x: x, y: y, depth: depth) ?? 1
            sample = try combine(sample, foreground, clip: clip, x: x, coverage: coverage)
          }
          if linear { patch.setLinearPixel(x: x - rect.x, y: y - rect.y, sample) }
          else { patch.setPixel(x: x - rect.x, y: y - rect.y, sample) }
        }
      }
      try builder.append(patch, atX: rect.x, atY: rect.y)
    }
    return try builder.finish()
  }

  private static func prepareMask(_ layer: Layer, relativeTo base: Layer) throws -> ClipMask? {
    let properties = layer.effectiveMaskProperties
    guard let pixels = layer.mask, properties.enabled else { return nil }
    let transform = layer.maskCoordinateTransform
    guard let x = Int(exactly: transform.tx - Double(base.x)),
      let y = Int(exactly: transform.ty - Double(base.y)),
      x <= Int.max - pixels.width, y <= Int.max - pixels.height else {
      throw CraftError.unsupported("The clip mask lies outside the supported coordinate range.")
    }
    return ClipMask(pixels: pixels, bounds: IntRect(x: x, y: y, width: pixels.width, height: pixels.height),
      properties: properties)
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

private enum HDRClippedArithmetic {
  case add(opaqueSource: Bool)
  case subtract(opaqueSource: Bool)
  case divide

  init?(mode: BlendMode, pixels: Surface, hasMask: Bool) throws {
    switch mode {
    case .linearDodge, .subtract:
      let opaque = hasMask ? false : try pixels.isOpaque()
      self = mode == .linearDodge ? .add(opaqueSource: opaque) : .subtract(opaqueSource: opaque)
    case .divide:
      self = .divide
    default:
      return nil
    }
  }

  func scalarDivideStart(in intersection: IntRect) -> Int? {
    #if arch(arm64)
    // Full groups of four use a fused addition. The remainder of the clipped
    // row uses two rounded products even when a render tile ends earlier.
    guard case .divide = self, intersection.width % 4 != 0 else { return nil }
    return intersection.x + intersection.width - intersection.width % 4
    #else
    return nil
    #endif
  }

  func blend(backdrop: Pixel, source: Pixel, alpha: Float, scalarDivide: Bool) throws -> Pixel {
    let complement = 1 - alpha
    func channel(_ base: Float, _ clip: Float) -> Float {
      switch self {
      case .add(let opaqueSource):
        // The fully weighted source uses the direct channel addition path.
        if opaqueSource && alpha == 1 { return Self.multiplyAdd(clip, alpha, to: base) }
        let sum = Self.flush(base + clip)
        if opaqueSource { return Self.multiplyAdd(sum, alpha, to: Self.product(base, complement)) }
        return Self.multiplyAdd(Self.flush(sum - base), alpha, to: base)
      case .subtract(let opaqueSource):
        if opaqueSource {
          return Self.multiplyAdd(Self.flush(base - clip), alpha, to: Self.product(base, complement))
        }
        return Self.multiplyAdd(-clip, alpha, to: base)
      case .divide:
        let weighted = Self.flush(Self.product(base, alpha) / max(0x1p-39, clip))
        if scalarDivide { return Self.product(base, complement) + weighted }
        return Self.multiplyAdd(base, complement, to: weighted)
      }
    }
    let result = Pixel(channel(backdrop.r, source.r), channel(backdrop.g, source.g),
      channel(backdrop.b, source.b), backdrop.a)
    guard result.isFinite else {
      throw CraftError.invalid("Layer composition exceeds the floating-point range.")
    }
    return result
  }

  @inline(__always) private static func flush(_ value: Float) -> Float {
    #if arch(x86_64)
    if value.isSubnormal { return Float(signOf: value, magnitudeOf: 0) }
    #endif
    return value
  }

  @inline(__always) private static func product(_ left: Float, _ right: Float) -> Float {
    flush(left * right)
  }

  @inline(__always) private static func multiplyAdd(_ value: Float, _ factor: Float, to base: Float) -> Float {
    #if arch(x86_64)
    return flush(base + product(value, factor))
    #else
    return RGB32NormalRenderer.multiplyAdd(value, factor, to: base)
    #endif
  }
}
