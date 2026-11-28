import PhotoCraftCore

/// The measured encoded-sample composition for aligned Gray8 and Gray16
/// Normal layers. File writers supply their own transparent-pixel policy.
struct GrayscaleNormalComposite {
  private struct Entry {
    let raster: NativeModeRaster
    let opacity: Int
  }

  private let entries: [Entry]
  private let depth: Int
  private let maximum: Int
  private let midpoint: Int
  private let support: PSDNativeRowSupport?
  let width: Int
  let height: Int
  var usesSparseRows: Bool { support != nil }

  init?(_ document: CraftDocument, descriptor: DocumentModeDescriptor) throws {
    guard descriptor.mode == .grayscale, document.depth != .f32,
      document.artboardOrigin == nil else { return nil }
    let visible = document.layers.filter { $0.visible && $0.opacity > 0 }
    guard visible.count > 1 else { return nil }

    var layers: [Entry] = []
    for layer in visible {
      guard case .raster = layer.content, let native = layer.nativeMode,
        layer.parentID == nil, !layer.isClipped, layer.blendMode == .normal,
        layer.mask == nil, layer.vectorMask == nil, layer.style == nil,
        layer.affine == nil, layer.warp == nil, layer.sourceProjection == nil,
        layer.smartObject == nil, layer.smartFilters == nil,
        layer.x == 0, layer.y == 0, native.width == document.width, native.height == document.height,
        native.depth == document.depth, native.profile == descriptor.profile,
        native.mode == .grayscale else { return nil }
      // Gray16 promotes layer opacity to 0...32,768 before multiplying by coverage.
      let opacity = NormalLayerComposite.clippingOpacity(layer.opacity, depth: document.depth)
      layers.append(Entry(raster: native, opacity: opacity))
    }

    width = document.width
    height = document.height
    depth = document.depth == .u8 ? 8 : 16
    maximum = depth == 8 ? 255 : 32_768
    midpoint = maximum / 2
    entries = layers
    if layers.contains(where: { $0.raster.requiresPagedArchive }) {
      support = try PSDNativeRowSupport(width: width, height: height, streams: layers.flatMap {
        [$0.raster.storedComponentRanges(0), $0.raster.storedComponentRanges(1)]
      })
    } else { support = nil }
  }

  private func working(_ sample: UInt32) -> Int {
    depth == 8 ? Int(sample) : (Int(sample) * maximum + 32_767) / 65_535
  }

  private func stored(_ sample: Int) -> UInt32 {
    UInt32(depth == 8 ? sample : (sample * 65_535 + midpoint) / maximum)
  }

  private func sample(_ index: Int) -> (gray: Int, alpha: Int) {
    var color = working(entries[0].raster.rawWord(component: 0, index: index))
    var coverage = 0
    for layer in entries {
      let sourceAlpha = working(layer.raster.rawWord(component: 1, index: index))
      let incoming = (sourceAlpha * layer.opacity + midpoint) / maximum
      guard incoming > 0 else { continue }
      coverage += incoming - (incoming * coverage + midpoint) / maximum
      let weight = min(maximum, (incoming * maximum + coverage / 2) / coverage)
      let sourceGray = working(layer.raster.rawWord(component: 0, index: index))
      color = (sourceGray * weight + color * (maximum - weight) + midpoint) / maximum
    }
    return (color, coverage)
  }

  func straightSample(at index: Int) -> (gray: UInt32, alpha: UInt32) {
    let pixel = sample(index)
    return (stored(pixel.gray), stored(pixel.alpha))
  }

  private func whiteMattedGray(_ pixel: (gray: Int, alpha: Int)) -> Int {
    maximum - ((maximum - pixel.gray) * pixel.alpha + midpoint) / maximum
  }

  func whiteMattedSample(at index: Int) -> UInt32 {
    stored(whiteMattedGray(sample(index)))
  }

  func hasTransparency() throws -> Bool {
    if entries.contains(where: { $0.opacity == maximum && $0.raster.isOpaque }) { return false }
    if let support { return try support.containsSample { sample($0).alpha != maximum } }
    for index in 0..<(width * height) {
      if index % 4096 == 0 { try Task.checkCancellation() }
      if sample(index).alpha != maximum { return true }
    }
    return false
  }

  func repeatedRows(from y: Int) -> Int {
    support?.repeatedRows(from: y) ?? 1
  }

  func photoshopRow(_ y: Int, channel: Int, transparency: Bool) throws -> [UInt8] {
    let denominator: Float = depth == 8 ? 255 : 65_535
    func word(_ index: Int) -> Float {
      let pixel = sample(index)
      if channel == 1 { return Float(stored(pixel.alpha)) / denominator }
      let gray = transparency ? whiteMattedGray(pixel) : pixel.gray
      return Float(stored(gray)) / denominator
    }
    if let support { return try support.row(y, depth: depth, sample: word) }
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * (depth / 8))
    for x in 0..<width {
      if x % 4096 == 0 { try Task.checkCancellation() }
      try PSDChannelCodec.append(word(y * width + x), depth: depth, to: &bytes)
    }
    return bytes
  }
}
