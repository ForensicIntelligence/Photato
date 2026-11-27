import PhotoCraftCore

/// Compose stored gray words directly for a PNG copy of an aligned Normal raster stack.
/// The RGB display cache has already lost precision and hidden gray samples.
struct GrayscalePNGComposite {
  let raster: NativeModeRaster
  let visibleBounds: IntRect

  init?(_ document: CraftDocument, descriptor: DocumentModeDescriptor) throws {
    guard let composite = try GrayscaleNormalComposite(document, descriptor: descriptor) else { return nil }
    let width = composite.width, height = composite.height
    let builder = try NativeModeRaster.RowBuilder(width: width, height: height,
      mode: .grayscale, depth: document.depth, profile: descriptor.profile, intent: descriptor.intent)
    var gray = [UInt32](repeating: 0, count: width), alpha = gray
    var left = width, top = height, right = 0, bottomEdge = 0
    for y in 0..<height {
      try Task.checkCancellation()
      let start = y * width
      for x in 0..<width {
        if x % 4096 == 0 { try Task.checkCancellation() }
        let pixel = composite.straightSample(at: start + x)
        gray[x] = pixel.gray
        alpha[x] = pixel.alpha
      }
      if let first = alpha.firstIndex(where: { $0 > 0 }), let last = alpha.lastIndex(where: { $0 > 0 }) {
        left = min(left, first)
        right = max(right, last + 1)
        top = min(top, y)
        bottomEdge = y + 1
      }
      try builder.appendRow(gray, component: 0)
      try builder.appendRow(alpha, component: 1)
    }
    raster = try builder.finish()
    visibleBounds = IntRect(x: left, y: top, width: max(0, right - left), height: max(0, bottomEdge - top))
  }
}
