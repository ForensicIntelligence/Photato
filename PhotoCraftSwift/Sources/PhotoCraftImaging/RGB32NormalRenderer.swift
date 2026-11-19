import PhotoCraftCore

/// The measured RGB32 Normal raster-stack path. Other layer kinds, blend modes,
/// groups and transforms continue through the general renderer.
enum RGB32NormalRenderer {
  static func supportsLayerOutput(_ document: CraftDocument) -> Bool {
    guard document.depth == .f32 else { return false }
    return document.layers.allSatisfy { layer in
      guard !layer.isGroup, layer.parentID == nil, !layer.isClipped else { return false }
      guard layer.visible && layer.opacity > 0 else { return true }
      guard case .raster = layer.content else { return false }
      return layer.affine == nil && layer.blendMode == .normal && layer.style == nil
        && supportsStoredPixelMask(layer) && layer.vectorMask == nil && layer.smartObject == nil
        && layer.smartFilters == nil && layer.warp == nil && layer.sourceProjection == nil
        && layer.importedSmartAppearance == nil
    }
  }

  private static func supportsStoredPixelMask(_ layer: Layer) -> Bool {
    let properties = layer.effectiveMaskProperties
    guard layer.mask != nil && properties.enabled else { return true }
    let transform = layer.maskCoordinateTransform
    return properties.feather == 0 && properties.density == 1 && !properties.inverted
      && transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1
      && transform.tx.rounded(.towardZero) == transform.tx && transform.ty.rounded(.towardZero) == transform.ty
  }

  static func composite(_ document: CraftDocument, over backdrop: Surface, region: IntRect,
    facts: CompositionFacts? = nil, forLayerOutput: Bool = false)
    throws -> Surface?
  {
    guard !document.layers.contains(where: { $0.style != nil && $0.style?.isChannelBlendingOnly != true }), document.depth == .f32,
      !document.layers.contains(where: { $0.isGroup || $0.parentID != nil || $0.isClipped })
    else { return nil }
    let writesLayer = forLayerOutput && supportsLayerOutput(document)
    let layers = document.layers.filter { $0.visible && $0.opacity > 0 && $0.style?.restrictedChannels?.count != 3 }
    guard
      layers.allSatisfy({ layer in
        guard case .raster = layer.content else { return false }
        return layer.affine == nil && layer.blendMode == .normal
      })
    else { return nil }
    var output = backdrop
    let opaqueBase = try facts.map {try $0.opaqueBase(layers.first)} ?? hasOpaqueBase(layers.first, document: document)
    var backdropAlpha: Float? = 0
    for (index, layer) in layers.enumerated() {
      try Task.checkCancellation()
      guard case .raster(let source) = layer.content else { continue }
      let mask = try facts.map {try $0.mask(layer,region:region)} ?? LayerMaskSampler.make(layer: layer, document: document, pixelRegion: region)
      let appliesStoredMask = writesLayer && layer.mask != nil && layer.effectiveMaskProperties.enabled
      // Photoshop's opaque and alpha-bearing stack paths expand opacity bytes
      // differently. Keep the model value canonical; change only evaluation.
      let opacity = expandedOpacity(layer.opacity, opaque: opaqueBase)
      let x0 = max(region.x, layer.x)
      let y0 = max(region.y, layer.y)
      let x1 = min(region.x + region.width, layer.x + source.width)
      let y1 = min(region.y + region.height, layer.y + source.height)
      let copiesSource: Bool
      if index > 0, backdropAlpha != nil, mask == nil, !appliesStoredMask,
        canCopyOpaqueRaster(layer, source: source, in: document) {
        copiesSource = try facts?.opaqueBase(layer) ?? source.isOpaque()
      } else {
        copiesSource = false
      }
      let sourceAlpha = opaqueBase || copiesSource || mask != nil || appliesStoredMask ? nil : try uniformAlpha(
        layer, source: source, in: document, facts: facts)
      backdropAlpha = compositeUniformAlpha(backdrop: backdropAlpha,
        source: sourceAlpha.map { scaleAlpha($0, by: opacity, flushSubnormal: writesLayer && opacity != 1) }, seeded: index > 0,
        opaque: opaqueBase, copiesSource: copiesSource, forLayerOutput: writesLayer)
      guard x0 < x1 && y0 < y1 else { continue }
      for y in y0..<y1 {
        if y % 64 == 0 { try Task.checkCancellation() }
        for x in x0..<x1 {
          var pixel = source.linearPixel(x: x - layer.x, y: y - layer.y)
          let coverage = mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
          // A zero mask sample excludes the raster at this coordinate, including hidden RGB.
          if appliesStoredMask && coverage == 0 { continue }
          pixel.a = scaleAlpha(pixel.a, by: coverage, flushSubnormal: appliesStoredMask)
          pixel.a = scaleAlpha(pixel.a, by: opacity, flushSubnormal: writesLayer && opacity != 1)
          if index == 0 {
            // Photoshop seeds the stack with the first layer's straight RGB,
            // including RGB beneath zero alpha. Later interpolation can reveal
            // its rounding contribution even when backdrop alpha is zero.
            output.setLinearPixel(x:x,y:y,BlendChannelRestrictions.applying(layer.style?.restrictedChannels,after:pixel,before:output.linearPixel(x:x,y:y)))
            continue
          }
          guard writesLayer || pixel.a > 0 else { continue }
          let previous = output.linearPixel(x: x, y: y)
          let blended = try blend(previous, pixel, opaque: opaqueBase, copiesSource: copiesSource,
            forLayerOutput: writesLayer)
          output.setLinearPixel(x: x, y: y,
            BlendChannelRestrictions.applying(layer.style?.restrictedChannels, after: blended, before: previous))
        }
      }
    }
    return output
  }

  /// A canvas-sized opaque source can copy over uniform backdrop alpha.
  /// Grouped clipping preserves its base alpha and checks the source alone.
  static func canCopyOpaqueRaster(_ layer: Layer, source: Surface, in document: CraftDocument) -> Bool {
    layer.opacity == 1 && coversCanvas(layer, source: source, in: document)
  }

  private static func coversCanvas(_ layer: Layer, source: Surface, in document: CraftDocument) -> Bool {
    layer.affine == nil && layer.x == 0 && layer.y == 0
      && source.width == document.width && source.height == document.height
  }

  static func uniformAlpha(_ layer: Layer, source: Surface, in document: CraftDocument,
    facts: CompositionFacts?) throws -> Float? {
    guard coversCanvas(layer, source: source, in: document) else { return nil }
    if let facts { return try facts.uniformRasterAlpha(source, layerID: layer.id) }
    return try uniformRasterAlpha(source)
  }

  static func uniformRasterAlpha(_ source: Surface) throws -> Float? {
    let alpha = source.linearPixel(x: 0, y: 0).a
    if alpha == 1 { return try source.isOpaque() ? 1 : nil }
    return try source.allStoredSamplesSatisfy { $0.a == alpha } ? alpha : nil
  }

  /// This proof always covers the full canvas, even when drawing one patch.
  static func compositeUniformAlpha(backdrop: Float?, source: Float?, seeded: Bool,
    opaque: Bool, copiesSource: Bool, forLayerOutput: Bool = false) -> Float? {
    if opaque || copiesSource { return 1 }
    if !seeded { return source }
    if !forLayerOutput && source == 0 { return backdrop }
    guard let backdrop, let source else { return nil }
    return unit(combinedAlpha(backdrop, source, forLayerOutput: forLayerOutput))
  }

  /// Determine this from the entire canvas, so regional updates use the same
  /// arithmetic as full rendering even if transparency is outside the region.
  static func expandedOpacity(_ value: Float, opaque: Bool) -> Float {
    let byte = (value * 255).rounded()
    return !opaque && value == byte / 255 ? byte * (Float(1) / 255) : value
  }

  /// Photoshop rounds these products before addition on Intel. Apple Silicon
  /// rounds the fused multiply-add once, including the alpha calculation.
  @inline(__always) static func multiplyAdd(_ value: Float, _ factor: Float, to base: Float) -> Float {
    #if arch(x86_64)
    return base + value * factor
    #else
    return base.addingProduct(value, factor)
    #endif
  }

  @inline(__always) private static func interpolate(_ backdrop: Float, _ source: Float, ratio: Float) -> Float {
    let delta = source - backdrop
    #if arch(x86_64)
    var contribution = delta * ratio
    let minimum = Float.leastNormalMagnitude
    // Photoshop flushes the product even when its unrounded magnitude is
    // below the normal boundary and Float rounds it up to that boundary.
    if contribution.magnitude < minimum || (contribution.magnitude == minimum
      && (Double(delta) * Double(ratio)).magnitude < Double(minimum)) {
      contribution = Float(signOf: contribution, magnitudeOf: 0)
    }
    let result = backdrop + contribution
    return result.isSubnormal ? Float(signOf: result, magnitudeOf: 0) : result
    #else
    return backdrop.addingProduct(delta, ratio)
    #endif
  }

  @inline(__always) static func scaleAlpha(_ source: Float, by multiplier: Float,
    flushSubnormal: Bool) -> Float {
    let coverage = source * multiplier
    #if arch(x86_64)
    // The Intel path flushes the product for a stored mask or partial opacity.
    if flushSubnormal && coverage.isSubnormal { return 0 }
    #endif
    return unit(coverage)
  }

  @inline(__always) private static func combinedAlpha(_ backdrop: Float, _ source: Float,
    forLayerOutput: Bool) -> Float {
    let alpha = multiplyAdd(-backdrop, source, to: source + backdrop)
    #if arch(x86_64)
    if forLayerOutput && alpha.isSubnormal { return Float(signOf: alpha, magnitudeOf: 0) }
    #endif
    return alpha
  }

  static func blend(_ backdrop: Pixel, _ source: Pixel, opaque: Bool, copiesSource: Bool = false,
    forLayerOutput: Bool = false) throws -> Pixel {
    guard forLayerOutput || source.a > 0 else { return backdrop }
    if copiesSource && source.a == 1 && source.isFinite { return source }
    let alpha: Float = opaque ? 1 : combinedAlpha(backdrop.a, source.a, forLayerOutput: forLayerOutput)
    let ratio: Float
    if opaque {
      ratio = source.a
    } else if forLayerOutput && alpha < 1e-16 {
      // The saved layer uses the later raster's straight RGB at negligible coverage.
      ratio = 1
    } else {
      ratio = alpha > 0 ? unit(source.a / alpha) : 0
    }
    let result = Pixel(
      interpolate(backdrop.r, source.r, ratio: ratio),
      interpolate(backdrop.g, source.g, ratio: ratio),
      interpolate(backdrop.b, source.b, ratio: ratio), alpha)
    guard result.isFinite else {
      throw CraftError.invalid("Layer composition exceeds the floating-point range.")
    }
    return result
  }

  static func hasOpaqueBase(_ layer: Layer?, document: CraftDocument) throws -> Bool {
    guard let layer, layer.opacity == 1, case .raster(let source) = layer.content,
      layer.x <= 0, layer.y <= 0,
      layer.x + source.width >= document.width, layer.y + source.height >= document.height
    else { return false }
    if layer.mask == nil, layer.vectorMask == nil, layer.x == 0, layer.y == 0,
      source.width == document.width, source.height == document.height {
      return try source.isOpaque()
    }
    let mask = try LayerMaskSampler.make(
      layer: layer, document: document,
      pixelRegion: IntRect(x: 0, y: 0, width: document.width, height: document.height))
    for y in 0..<document.height {
      if y % 64 == 0 { try Task.checkCancellation() }
      for x in 0..<document.width {
        if source.linearPixel(x: x - layer.x, y: y - layer.y).a != 1 { return false }
        if let mask, mask.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) != 1 { return false }
      }
    }
    return true
  }
}
