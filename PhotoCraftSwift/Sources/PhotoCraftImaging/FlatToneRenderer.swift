import PhotoCraftCore

/// Folds consecutive, channel-independent Normal adjustments into the first
/// raster read. Other stacks use the general sequential layer compositor.
enum FlatToneRenderer {
  private struct Stage: Sendable {
    let adjustment: Adjustment
    let amount: Float

    init?(_ layer: Layer) {
      guard layer.blendMode == .normal, layer.mask == nil, layer.vectorMask == nil,
        layer.style == nil, case .adjustment(let adjustment) = layer.content else { return nil }
      switch adjustment {
      case .brightnessContrast, .exposure, .invert: break
      default: return nil
      }
      self.adjustment = adjustment
      amount = unit(layer.opacity)
    }

    func apply(_ before: Pixel) -> Pixel {
      let after = adjustment.apply(before)
      let rgb = before.rgb + (after.rgb - before.rgb) * amount
      // The general path stores a Float32 sample after each layer.
      return Pixel(rgb.x, rgb.y, rgb.z, before.a).quantized(.f32)
    }
  }

  private struct ToneTable: Sendable {
    struct Entry: Sendable {
      let original: UInt32
      let value: Float
    }
    let maximum: Float
    let entries: [Entry]

    init(maximum: Int, stages: [Stage]) throws {
      self.maximum = Float(maximum)
      var entries: [Entry] = []
      entries.reserveCapacity(maximum + 1)
      for code in 0...maximum {
        if code % 1024 == 0 { try Task.checkCancellation() }
        let value = Float(code) / Float(maximum)
        let result = stages.reduce(Pixel(value, value, value)) { $1.apply($0) }
        entries.append(Entry(original: value.bitPattern, value: result.r))
      }
      self.entries = entries
    }

    @inline(__always)
    func sample(_ value: Float) -> Float? {
      guard value >= 0, value <= 1 else { return nil }
      let entry = entries[Int(value * maximum + 0.5)]
      // Older archives can store continuous channels in an integer surface.
      // A grid index alone is insufficient, particularly for signed zero.
      return value.bitPattern == entry.original ? entry.value : nil
    }
  }

  static func composite(_ document: CraftDocument, region: IntRect) throws -> Surface? {
    guard document.colorMode == .rgb, document.depth != .f32,
      region.width * region.height >= 65_536 else { return nil }
    let visible = document.layers.filter { layer in
      guard layer.visible else { return false }
      if case .adjustment(.source) = layer.content { return true }
      return layer.opacity > 0
    }
    guard visible.count >= 2, let base = visible.first,
      base.blendMode == .normal, base.opacity == 1,
      base.mask == nil, base.vectorMask == nil, base.style == nil, base.affine == nil,
      base.x == 0, base.y == 0, case .raster(let source) = base.content,
      source.depth != .f32, source.width == document.width, source.height == document.height
    else { return nil }
    let stages = visible.dropFirst().compactMap(Stage.init)
    guard stages.count == visible.count - 1 else { return nil }

    let maximum = source.depth == .u8 ? 255 : 65_535
    let table = try ToneTable(maximum: maximum, stages: stages)
    let clear = stages.reduce(Pixel.clear) { $1.apply($0) }
    return try source.compositingIndependentStoredRegion(region) { source in
      if source.a <= 0 { return clear }
      if source.a == 1, let r = table.sample(source.r), let g = table.sample(source.g),
        let b = table.sample(source.b) { return Pixel(r, g, b) }
      let base = BlendMode.normal.composite(backdrop: .clear, source: source).quantized(.f32)
      return stages.reduce(base) { $1.apply($0) }
    }
  }
}
