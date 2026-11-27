import PhotoCraftCore

/// Compose stored gray words directly for a PNG copy of an aligned Normal raster stack.
/// The RGB display cache has already lost precision and hidden gray samples.
struct GrayscalePNGComposite {
  let raster: NativeModeRaster
  let visibleBounds: IntRect

  init?(_ document: CraftDocument, descriptor: DocumentModeDescriptor) throws {
    guard descriptor.mode == .grayscale, document.depth != .f32,
      document.artboardOrigin == nil else { return nil }
    let visible = document.layers.filter { $0.visible && $0.opacity > 0 }
    guard visible.count > 1 else { return nil }

    let width = document.width, height = document.height
    let eightBit = document.depth == .u8
    let maximum = eightBit ? 255 : 32_768
    let midpoint = maximum / 2
    var layers: [(raster: NativeModeRaster, opacity: Int)] = []
    for layer in visible {
      guard case .raster = layer.content, let native = layer.nativeMode,
        layer.parentID == nil, !layer.isClipped, layer.blendMode == .normal,
        layer.mask == nil, layer.vectorMask == nil, layer.style == nil,
        layer.affine == nil, layer.warp == nil, layer.sourceProjection == nil,
        layer.smartObject == nil, layer.smartFilters == nil,
        layer.x == 0, layer.y == 0, native.width == width, native.height == height,
        native.depth == document.depth, native.profile == descriptor.profile,
        native.mode == .grayscale else { return nil }
      // Gray16 promotes layer opacity to 0...32,768 before multiplying by coverage.
      let opacity = NormalLayerComposite.clippingOpacity(layer.opacity, depth: document.depth)
      layers.append((native, opacity))
    }

    let builder = try NativeModeRaster.RowBuilder(width: width, height: height,
      mode: .grayscale, depth: document.depth, profile: descriptor.profile, intent: descriptor.intent)
    func working(_ sample: UInt32) -> Int {
      eightBit ? Int(sample) : (Int(sample) * maximum + 32_767) / 65_535
    }
    func stored(_ sample: Int) -> UInt32 {
      UInt32(eightBit ? sample : (sample * 65_535 + midpoint) / maximum)
    }

    let bottom = layers[0].raster
    var gray = [UInt32](repeating: 0, count: width), alpha = gray
    var left = width, top = height, right = 0, bottomEdge = 0
    for y in 0..<height {
      try Task.checkCancellation()
      let start = y * width
      for x in 0..<width {
        if x % 4096 == 0 { try Task.checkCancellation() }
        let i = start + x
        var color = working(bottom.rawWord(component: 0, index: i))
        var coverage = 0
        for layer in layers {
          let sourceAlpha = working(layer.raster.rawWord(component: 1, index: i))
          let incoming = (sourceAlpha * layer.opacity + midpoint) / maximum
          guard incoming > 0 else { continue }
          coverage += incoming - (incoming * coverage + midpoint) / maximum
          let weight = min(maximum, (incoming * maximum + coverage / 2) / coverage)
          let sourceGray = working(layer.raster.rawWord(component: 0, index: i))
          color = (sourceGray * weight + color * (maximum - weight) + midpoint) / maximum
        }
        gray[x] = stored(color)
        alpha[x] = stored(coverage)
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
