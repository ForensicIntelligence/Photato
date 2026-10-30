import PhotoCraftCore

/// The measured RGB32 Normal raster-stack path. Other layer kinds, blend modes,
/// groups and transforms continue through the general renderer.
enum RGB32NormalRenderer {
  static func composite(_ document: CraftDocument, over backdrop: Surface, region: IntRect)
    throws -> Surface?
  {
    guard !document.layers.contains(where: { $0.style != nil }), document.depth == .f32,
      !document.layers.contains(where: { $0.isGroup || $0.parentID != nil || $0.isClipped })
    else { return nil }
    let layers = document.layers.filter { $0.visible && $0.opacity > 0 }
    guard
      layers.allSatisfy({ layer in
        guard case .raster = layer.content else { return false }
        return layer.affine == nil && layer.blendMode == .normal
      })
    else { return nil }
    var output = backdrop
    let opaqueBase = try hasOpaqueBase(layers.first, document: document)
    for (index, layer) in layers.enumerated() {
      try Task.checkCancellation()
      guard case .raster(let source) = layer.content else { continue }
      let mask = try LayerMaskSampler.make(layer: layer, document: document, pixelRegion: region)
      // Photoshop's opaque and alpha-bearing stack paths expand opacity bytes
      // differently. Keep the model value canonical; change only evaluation.
      let opacity = expandedOpacity(layer.opacity, opaque: opaqueBase)
      let x0 = max(region.x, layer.x)
      let y0 = max(region.y, layer.y)
      let x1 = min(region.x + region.width, layer.x + source.width)
      let y1 = min(region.y + region.height, layer.y + source.height)
      guard x0 < x1 && y0 < y1 else { continue }
      for y in y0..<y1 {
        if y % 64 == 0 { try Task.checkCancellation() }
        for x in x0..<x1 {
          var pixel = source.linearPixel(x: x - layer.x, y: y - layer.y)
          // The mask product rounds before the layer-opacity product.
          pixel.a *= mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
          pixel.a = unit(pixel.a * opacity)
          if index == 0 {
            // Photoshop seeds the stack with the first layer's straight RGB,
            // including RGB beneath zero alpha. Later interpolation can reveal
            // its rounding contribution even when backdrop alpha is zero.
            output.setLinearPixel(x: x, y: y, pixel)
            continue
          }
          guard pixel.a > 0 else { continue }
          output.setLinearPixel(
            x: x, y: y,
            try blend(output.linearPixel(x: x, y: y), pixel, opaque: opaqueBase))
        }
      }
    }
    return output
  }

  /// Determine this from the entire canvas, so regional updates use the same
  /// arithmetic as full rendering even if transparency is outside the region.
  static func expandedOpacity(_ value: Float, opaque: Bool) -> Float {
    let byte = (value * 255).rounded()
    return !opaque && value == byte / 255 ? byte * (Float(1) / 255) : value
  }

  static func blend(_ backdrop: Pixel, _ source: Pixel, opaque: Bool) throws -> Pixel {
    guard source.a > 0 else { return backdrop }
    let alpha: Float = opaque ? 1 : (source.a + backdrop.a).addingProduct(-backdrop.a, source.a)
    let ratio = opaque ? source.a : alpha > 0 ? unit(source.a / alpha) : 0
    let result = Pixel(
      backdrop.r.addingProduct(source.r - backdrop.r, ratio),
      backdrop.g.addingProduct(source.g - backdrop.g, ratio),
      backdrop.b.addingProduct(source.b - backdrop.b, ratio), alpha)
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
      return try source.allStoredSamplesSatisfy { $0.a == 1 }
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
