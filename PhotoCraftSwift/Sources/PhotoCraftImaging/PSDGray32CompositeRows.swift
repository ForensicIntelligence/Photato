import PhotoCraftCore

/// Compose eligible Gray32 files from their stored gray and alpha planes. A PSD
/// preview has its own color plane and never needs an intermediate RGB transform.
struct PSDGray32CompositeRows {
  private struct Entry {
    let raster: NativeModeRaster
    let mask: LayerMaskSampler?
    let opacity: Float
    let blendMode: BlendMode
  }

  private struct Sample {
    var gray: Float
    var alpha: Float
  }

  private let entries: [Entry]
  private let opaque: Bool
  let hasOpaqueBackground: Bool

  init?(_ document: CraftDocument) throws {
    guard document.colorMode == .grayscale, document.depth == .f32,
      !document.layers.contains(where: { $0.isGroup || $0.parentID != nil || $0.isClipped })
    else { return nil }
    let visible = document.layers.filter { $0.visible && $0.opacity > 0 }
    guard let first = visible.first, first.blendMode == .normal, let base = first.nativeMode else {
      return nil
    }
    var eligible: [(Layer, NativeModeRaster)] = []
    for layer in visible {
      guard case .raster = layer.content, let raster = layer.nativeMode,
        layer.x == 0, layer.y == 0, raster.width == document.width, raster.height == document.height,
        layer.affine == nil, layer.warp == nil, layer.sourceProjection == nil,
        layer.style == nil, layer.vectorMask == nil,
        layer.effectiveMaskProperties.feather == 0
      else { return nil }
      eligible.append((layer, raster))
    }
    let opaque = first.opacity == 1 && first.mask == nil && base.isOpaque
    guard visible.allSatisfy({ $0.blendMode == .normal || (opaque && $0.blendMode == .multiply) }) else {
      return nil
    }
    self.opaque = opaque
    hasOpaqueBackground = first.isBackground && opaque
    entries = try eligible.map { layer, raster in
      Entry(raster: raster, mask: try LayerMaskSampler.make(layer: layer, document: document),
        opacity: RGB32NormalRenderer.expandedOpacity(layer.opacity, opaque: opaque), blendMode: layer.blendMode)
    }
  }

  func row(_ y: Int, channel: Int, transparency: Bool) throws -> [UInt8] {
    let width = entries[0].raster.width
    let start = y * width
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * 4)
    for x in 0..<width {
      if x % 4096 == 0 { try Task.checkCancellation() }
      // Keep the first layer's straight gray even underneath zero alpha.
      let index = start + x
      var merged = sample(entries[0], index: index, x: x, y: y)
      for layer in entries.dropFirst() {
        let source = sample(layer, index: index, x: x, y: y)
        guard source.alpha > 0 else { continue }
        let alpha: Float = opaque ? 1
          : (source.alpha + merged.alpha).addingProduct(-merged.alpha, source.alpha)
        let ratio = opaque ? source.alpha : alpha > 0 ? unit(source.alpha / alpha) : 0
        let color = layer.blendMode == .multiply ? merged.gray * source.gray : source.gray
        let difference = color - merged.gray
        #if arch(x86_64)
        merged.gray += difference * ratio
        #else
        merged.gray = merged.gray.addingProduct(difference, ratio)
        #endif
        merged.alpha = alpha
      }
      let value = channel == 1 ? merged.alpha : transparency
        ? PSDMergedSample.whiteMatte(merged.gray, alpha: merged.alpha) : merged.gray
      try PSDChannelCodec.append(value, depth: 32, to: &bytes)
    }
    return bytes
  }

  private func sample(_ entry: Entry, index: Int, x: Int, y: Int) -> Sample {
    let mask = entry.mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
    let alpha = unit((entry.raster.value(component: 1, index: index) * mask) * entry.opacity)
    return Sample(gray: entry.raster.value(component: 0, index: index), alpha: alpha)
  }
}
