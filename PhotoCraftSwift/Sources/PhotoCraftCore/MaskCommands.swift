import Foundation

public enum LayerMaskCreation: Sendable, Codable {
  case revealAll, hideAll, revealSelection, hideSelection, fromTransparency
}

extension Layer {
  public var canApplyPixelMask: Bool {
    guard mask != nil else { return false }
    if case .raster = content { return true }
    return false
  }

  /// A pixel layer's affine preview is sampled in document space before changing its alpha.
  /// This also retains pixels outside the canvas, as ordinary layer transforms do.
  private func pixelMaskSource() throws -> (Surface, Layer) {
    guard case .raster(let source) = content else {
      throw CraftError.unsupported(
        "This mask operation requires a pixel layer. Rasterize it first.")
    }
    guard affine != nil else { return (source, self) }
    let matrix = coordinateTransform
    let inverse = try matrix.inverted()
    let bounds = try matrix.bounds(width: source.width, height: source.height)
    var pixels = try Surface(width: bounds.width, height: bounds.height, depth: source.depth)
    for y in 0..<bounds.height {
      try Task.checkCancellation()
      for x in 0..<bounds.width {
        let point = inverse.point(Double(x + bounds.x) + 0.5, Double(y + bounds.y) + 0.5)
        let value = RasterGeometry.sample(source, x: point.x, y: point.y, method: .bilinear)
        if value != .clear { pixels.setPixel(x: x, y: y, value) }
      }
    }
    var result = self
    result.x = bounds.x
    result.y = bounds.y
    result.affine = nil
    return (pixels, result)
  }

  func creatingPixelMask(_ kind: LayerMaskCreation, in document: CraftDocument) throws -> Layer {
    try document.validate()
    guard mask == nil else {
      throw CraftError.invalid("Delete or apply the existing layer mask first.")
    }
    var result = self
    var properties = MaskProperties()
    if kind == .fromTransparency {
      let (source, normalized) = try pixelMaskSource()
      result = normalized
      var background = source.defaultPixel
      let alpha = background.a
      background.a = 1
      var pixels = try Surface(
        width: source.width, height: source.height, depth: source.depth, fill: background)
      var coverage = try Surface(
        width: source.width, height: source.height, depth: source.depth,
        fill: Pixel(alpha, alpha, alpha))
      for y in 0..<source.height {
        try Task.checkCancellation()
        for x in 0..<source.width {
          var pixel = source.pixel(x: x, y: y)
          if pixel.a != alpha {
            coverage.setPixel(x: x, y: y, Pixel(pixel.a, pixel.a, pixel.a))
          }
          pixel.a = 1
          if pixel != background { pixels.setPixel(x: x, y: y, pixel) }
        }
      }
      result.content = .raster(pixels)
      result.mask = coverage
    } else {
      let selection = kind == .revealSelection || kind == .hideSelection
      guard !selection || document.selection != nil else {
        throw CraftError.invalid("Make a selection first.")
      }
      let outside: Float = kind == .revealAll || kind == .hideSelection ? 1 : 0
      var coverage = try Surface(
        width: document.width, height: document.height, depth: document.depth,
        fill: Pixel(outside, outside, outside))
      if selection, let bounds = document.selection {
        for y in bounds.y..<bounds.y + bounds.height {
          try Task.checkCancellation()
          for x in bounds.x..<bounds.x + bounds.width {
            let selected = document.selectionCoverage(x: x, y: y)
            let value = kind == .hideSelection ? 1 - selected : selected
            if value != outside { coverage.setPixel(x: x, y: y, Pixel(value, value, value)) }
          }
        }
      }
      properties.outside = outside
      properties.transform = try coordinateTransform.inverted()
      result.mask = coverage
    }
    result.maskProperties = properties
    return result
  }

  func applyingPixelMask(in document: CraftDocument) throws -> Layer {
    try document.validate()
    guard mask != nil else { throw CraftError.invalid("This layer has no mask.") }
    var masked = self
    var properties = effectiveMaskProperties
    // Apply is an explicit request to bake the stored mask, including when it was disabled.
    properties.enabled = true
    masked.maskProperties = properties
    let sampler = try MaskSampler(
      layer: masked, canvasSize: (document.width, document.height))
    var (pixels, result) = try pixelMaskSource()
    for y in 0..<pixels.height {
      try Task.checkCancellation()
      for x in 0..<pixels.width {
        var pixel = pixels.pixel(x: x, y: y)
        let coverage = sampler.coverage(
          x: Double(x + result.x) + 0.5, y: Double(y + result.y) + 0.5)
        if pixel.a != 0 && coverage != 1 {
          pixel.a *= coverage
          pixels.setPixel(x: x, y: y, pixel)
        }
      }
    }
    result.content = .raster(pixels)
    result.mask = nil
    result.maskProperties = nil
    return result
  }
}
