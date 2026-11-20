import Foundation

/// One numeric printing plane. Samples have no RGB transfer function or alpha.
public struct InkPlane: Codable, Equatable, Sendable {
  public static let maximumPixels = 8_388_608
  public static let maximumDocumentPixels = Surface.maxPixels
  public let width: Int
  public let height: Int
  public let depth: PixelDepth
  private var storage: ComponentPlane
  /// Portable legacy bytes. Large plates use raw words and indexed archive pages.
  public var bytes: Data {
    get throws {
      guard !requiresPagedArchive else { throw CraftError.unsupported("Use bounded rows for large printing plates.") }
      return storage.legacyBytes
    }
  }
  public var residentSampleBytes: Int { storage.residentEditBytes }
  public var count: Int { width * height }
  public var estimatedBytes: Int { requiresPagedArchive ? storage.estimatedResidentBytes : count * stride }
  public var requiresPagedArchive: Bool { count > Self.maximumPixels }
  package var retainedSampleBytes: Int { storage.mappedSampleBytes }
  package var defaultWord: UInt32 { storage.defaultWord }
  package var storedSampleRanges: AnySequence<Range<Int>> { storage.storedSampleRanges }
  private var stride: Int { depth == .u8 ? 1 : 2 }

  func forEachNondefaultWord(_ visit: (Int, UInt32) throws -> Void) throws {
    try storage.forEachStoredBlock { key, block in
      let start = key * ComponentPlane.blockSamples
      for offset in 0..<min(ComponentPlane.blockSamples, count - start) {
        let word = block.word(offset, stride: stride)
        if word != storage.defaultWord { try visit(start + offset, word) }
      }
    }
  }

  public init(width: Int, height: Int, depth: PixelDepth = .u8, bytes: Data) throws {
    try Self.dimensions(width, height, depth)
    guard width <= Self.maximumPixels / height,
      bytes.count == width * height * (depth == .u8 ? 1 : 2) else {
      throw CraftError.invalid("Legacy ink plane data exceeds its dimensions or dense capacity.")
    }
    self.width = width; self.height = height; self.depth = depth
    storage = try ComponentPlane(width: width, height: height, depth: depth)
    let bytes = Data(bytes)
    for i in 0..<(width * height) {
      if i % 4096 == 0 { try Task.checkCancellation() }
      storage.setValidatedWord(ComponentPlane.load(bytes, offset: i * stride, stride: stride), at: i)
    }
  }
  public init(width: Int, height: Int, depth: PixelDepth = .u8, value: Float = 0) throws {
    try Self.dimensions(width, height, depth)
    guard value.isFinite, (0...1).contains(value) else { throw CraftError.invalid("Ink samples must be between zero and one.") }
    self.width = width; self.height = height; self.depth = depth
    storage = try ComponentPlane(width: width, height: height, depth: depth, defaultWord: UInt32((value * (depth == .u8 ? 255 : 65535)).rounded()))
  }
  package init(storage: ComponentPlane) throws {
    try Self.dimensions(storage.width, storage.height, storage.depth)
    width = storage.width; height = storage.height; depth = storage.depth; self.storage = storage
  }
  static func dimensions(_ width: Int, _ height: Int, _ depth: PixelDepth) throws {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= maximumDocumentPixels / height, [.u8, .u16].contains(depth) else {
      throw CraftError.invalid("Ink planes require 8-bit or 16-bit samples within the document dimensions.")
    }
  }
  public func validate() throws {
    try Self.dimensions(width, height, depth)
    guard storage.width == width, storage.height == height, storage.depth == depth else { throw CraftError.invalid("Ink plane sample storage differs from its dimensions.") }
  }
  public func value(at index: Int) -> Float {
    guard (0..<count).contains(index) else { return 0 }
    return Float(storage.word(at: index)) / (depth == .u8 ? 255 : 65535)
  }
  public func rawWord(at index: Int) -> UInt32 { storage.word(at: index) }
  private mutating func store(_ value: Float, at index: Int) {
    storage.setValidatedWord(UInt32((value * (depth == .u8 ? 255 : 65535)).rounded()), at: index)
  }
  public func replacing(offset: Int, values: [Float]) throws -> Self {
    guard offset >= 0, offset <= count, values.count <= count - offset,
      values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
      throw CraftError.invalid("Ink sample write exceeds its plane or contains an invalid value.")
    }
    var result = self
    for (i, value) in values.enumerated() {
      if i % 4096 == 0 { try Task.checkCancellation() }
      result.store(value, at: offset + i)
    }
    return result
  }
  /// Share unchanged sample blocks, then edit scalar samples in place. Returning the original value
  /// preserves the original bytes without passing through a display surface.
  public func mapped(_ transform: (Int, Int, Float) throws -> Float) throws -> Self {
    try mapped(in: IntRect(x: 0, y: 0, width: width, height: height), transform)
  }
  func mapped(in area: IntRect, _ transform: (Int, Int, Float) throws -> Float) throws -> Self {
    var result = self
    for y in area.y..<(area.y + area.height) {
      try Task.checkCancellation()
      for x in area.x..<(area.x + area.width) {
        let i = y * width + x
        if x % 4096 == 0 { try Task.checkCancellation() }
        let old = value(at: i), next = try transform(x, y, old)
        guard next.isFinite, (0...1).contains(next) else { throw CraftError.invalid("Invalid numeric ink sample.") }
        if next != old { result.store(next, at: i) }
      }
    }
    return result
  }
  func mappingUniformly(_ transform: (Float) -> Float) throws -> Self {
    let scale: Float = depth == .u8 ? 255 : 65535
    let implicit = transform(Float(storage.defaultWord) / scale)
    let plane = try ComponentPlane(width: width, height: height, depth: depth,
      defaultWord: UInt32((unit(implicit) * scale).rounded()))
    let builder = try ComponentPlaneBuilder(plane: plane, cacheBlocks: 2)
    for range in storedSampleRanges {
      try Task.checkCancellation()
      for index in range {
        let word = UInt32((unit(transform(value(at: index))) * scale).rounded())
        if word != plane.defaultWord { try builder.setWord(word, at: index) }
      }
    }
    return try Self(storage: builder.finish())
  }
  public func converted(to depth: PixelDepth, inverted: Bool = false) throws -> Self {
    if depth == self.depth, !inverted { return self }
    if requiresPagedArchive {
      return try convertingPaged(to: depth, inverted: inverted, budget: ComponentScratchBudget())
    }
    var result = try Self(width: width, height: height, depth: depth)
    for i in 0..<count {
      if i % 4096 == 0 { try Task.checkCancellation() }
      let value = value(at: i); result.store(inverted ? 1 - value : value, at: i)
    }
    return result
  }
  func convertingPaged(to depth: PixelDepth, inverted: Bool, budget: ComponentScratchBudget) throws -> Self {
    try Self.dimensions(width, height, depth)
    if depth == self.depth, !inverted { return self }
    let inputMaximum: UInt32 = self.depth == .u8 ? 255 : 65535
    let outputMaximum: UInt32 = depth == .u8 ? 255 : 65535
    func converted(_ word: UInt32) -> UInt32 {
      if depth == self.depth { return inputMaximum - word }
      let sample = Float(word) / Float(inputMaximum)
      return UInt32(((inverted ? 1 - sample : sample) * Float(outputMaximum)).rounded())
    }
    let plane = try ComponentPlane(width: width, height: height, depth: depth, defaultWord: converted(defaultWord))
    let writer = try ComponentPlaneBuilder(plane: plane, reserve: budget.reserve)
    try forEachNondefaultWord { index, word in try writer.setWord(converted(word), at: index) }
    return try Self(storage: writer.finish())
  }
  var componentPlane: ComponentPlane { storage }
  /// Grayscale editing/display cache; ink density is inverted for a paper preview.
  public func surface(inverted: Bool = false) throws -> Surface {
    try validate()
    if requiresPagedArchive {
      func gray(_ word: UInt32) -> Pixel {
        let value = Float(word) / (depth == .u8 ? 255 : 65535)
        let shade = inverted ? 1 - value : value
        return Pixel(shade, shade, shade)
      }
      return try InkProjection.surface(width: width, height: height, depth: depth, region: nil,
        implicit: gray(storage.defaultWord), storedRanges: [storage.storedSampleRanges]) { gray(storage.word(at: $0)) }
    }
    var result = try Surface(width: width, height: height, depth: depth)
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      let value = value(at: y * width + x), gray = inverted ? 1 - value : value
      result.setPixel(x: x, y: y, Pixel(gray, gray, gray))
    } }
    return result
  }
  /// Update only edited cache pixels, retaining exact numeric samples elsewhere.
  /// Transparency is flattened over paper; ink documents have no composite alpha.
  func reconciled(with edited: Surface, previous: Surface, inverted: Bool = false) throws -> Self {
    guard edited.width == width, edited.height == height,
      previous.width == width, previous.height == height else {
      throw CraftError.invalid("Ink editing requires matching plane and cache dimensions.")
    }
    let area: IntRect
    if requiresPagedArchive {
      guard let bounds = try edited.changedTileBounds(comparedTo: previous) else { return self }
      area = bounds
    } else { area = IntRect(x: 0, y: 0, width: width, height: height) }
    var result = self
    for y in area.y..<(area.y + area.height) { try Task.checkCancellation(); for x in area.x..<(area.x + area.width) {
      let p = edited.pixel(x: x, y: y)
      guard p != previous.pixel(x: x, y: y) else { continue }
      guard p.isFinite else { throw CraftError.invalid("Ink edits require finite pixels.") }
      let gray = unit((p.r * 0.2126 + p.g * 0.7152 + p.b * 0.0722) * unit(p.a) + 1 - unit(p.a))
      result.store(inverted ? 1 - gray : gray, at: y * width + x)
    } }
    return result
  }
  private enum CodingKeys: String, CodingKey { case width, height, depth, bytes, blob, componentPage }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let width = try c.decode(Int.self, forKey: .width), height = try c.decode(Int.self, forKey: .height)
    let depth = try c.decode(PixelDepth.self, forKey: .depth)
    try Self.dimensions(width, height, depth)
    if c.contains(.componentPage) {
      guard !c.contains(.bytes), !c.contains(.blob), width > Self.maximumPixels / height,
        let context = decoder.userInfo[.historyTileDecoder] as? any ComponentBlobDecoding else {
        throw CraftError.invalid("Large ink pages require their native archive context.")
      }
      let record = try c.decode(ComponentPlaneArchive.Record.self, forKey: .componentPage)
      guard record.width == width, record.height == height, record.depth == depth else {
        throw CraftError.invalid("Ink page geometry differs from its header.")
      }
      try self.init(storage: ComponentPlaneArchive.decode(record, context: context,
        budget: decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget, chargeMappedSamplesSeparately: true))
      return
    }
    guard width <= Self.maximumPixels / height else { throw CraftError.invalid("Large ink planes require indexed pages.") }
    let size = width * height * (depth == .u8 ? 1 : 2)
    try (decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget)?.reserve(tiles: (size + TileArchive.byteCount - 1) / TileArchive.byteCount)
    let bytes: Data
    if c.contains(.blob) {
      guard !c.contains(.bytes), let context = decoder.userInfo[.historyTileDecoder] as? any RasterBlobDecoding else {
        throw CraftError.invalid("Ink plane blobs require their native archive context.")
      }
      bytes = try context.bytes(c.decode(String.self, forKey: .blob), maximumBytes: size)
    } else { bytes = try c.decode(Data.self, forKey: .bytes) }
    try self.init(width: width, height: height, depth: depth, bytes: bytes)
  }
  public func encode(to encoder: Encoder) throws {
    try validate(); var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(width, forKey: .width); try c.encode(height, forKey: .height); try c.encode(depth, forKey: .depth)
    if requiresPagedArchive {
      guard let context = encoder.userInfo[.historyTileEncoder] as? any ComponentBlobEncoding,
        context.supportsComponentPages else { throw CraftError.invalid("Large ink planes require indexed pages.") }
      try c.encode(ComponentPlaneArchive.encode(storage, context: context), forKey: .componentPage)
    } else if let context = encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding {
      try c.encode(context.storeBytes(bytes), forKey: .blob)
    } else { try c.encode(bytes, forKey: .bytes) }
  }
}
