import Foundation

/// Raw numeric samples, independent of RGB transfer functions and alpha semantics.
/// Constant regions cost no sample buffer. Edits copy 4 Ki-sample blocks and four
/// bounded radix nodes; immutable snapshots can live in private mapped scratch.
public struct ComponentPlane: Equatable, Sendable {
  public static let blockSamples = 4096
  public let width: Int
  public let height: Int
  public let depth: PixelDepth
  public let defaultWord: UInt32
  private var edits = ComponentBlockMap()
  private var base: ComponentPlaneMapping?
  public var count: Int { width * height }
  public var sampleBytes: Int { depth == .u8 ? 1 : depth == .u16 ? 2 : 4 }
  public var logicalBytes: Int { count * sampleBytes }
  public var residentEditBytes: Int { edits.residentBytes }
  public var storedBlockCount: Int { blockKeys.reduce(0) { n, _ in n + 1 } }
  /// Referenced file content; neither physical disk allocation nor process RSS.
  public var referencedScratchBytes: Int { base?.storedBytes ?? 0 }
  public var mappedVirtualBytes: Int { base?.length ?? 0 }

  public init(width: Int, height: Int, depth: PixelDepth, defaultWord: UInt32 = 0) throws {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= Surface.maxPixels / height else { throw CraftError.invalid("Invalid component plane dimensions.") }
    try Self.validate(word: defaultWord, depth: depth)
    self.width = width; self.height = height; self.depth = depth; self.defaultWord = defaultWord
  }
  static func validate(word: UInt32, depth: PixelDepth) throws {
    guard depth == .f32 ? Float(bitPattern: word).isFinite : word <= (depth == .u8 ? 255 : 65535) else {
      throw CraftError.invalid("Component samples must fit their depth and floating samples must be finite.")
    }
  }
  public func word(at index: Int) -> UInt32 {
    guard (0..<count).contains(index) else { return 0 }
    return block(index / Self.blockSamples)?.word(index % Self.blockSamples, stride: sampleBytes) ?? defaultWord
  }
  public mutating func setWord(_ word: UInt32, at index: Int) throws {
    guard (0..<count).contains(index) else { throw CraftError.invalid("Component sample index is outside its plane.") }
    try Self.validate(word: word, depth: depth)
    setValidatedWord(word, at: index)
  }
  /// Internal callers have already validated dimensions, range and quantization.
  mutating func setValidatedWord(_ word: UInt32, at index: Int) {
    guard self.word(at: index) != word else { return }
    let key = index / Self.blockSamples
    if edits[key] == nil {
      edits[key] = block(key) ?? ComponentBlock(fill: defaultWord, stride: sampleBytes)
    }
    edits.modify(key, offset: index % Self.blockSamples, word: word, stride: sampleBytes)
  }
  public func row(_ y: Int, x: Int = 0, count requested: Int? = nil) throws -> Data {
    guard y >= 0, y < height, x >= 0, x <= width else { throw CraftError.invalid("Invalid component row range.") }
    let length = requested ?? width - x
    guard length >= 0, length <= width - x else { throw CraftError.invalid("Invalid component row length.") }
    var result = Data(count: length * sampleBytes)
    for i in 0..<length {
      if i % 4096 == 0 { try Task.checkCancellation() }
      Self.store(word(at: y * width + x + i), in: &result, offset: i * sampleBytes, stride: sampleBytes)
    }
    return result
  }
  /// Validation and cancellation cannot partially modify the caller's plane.
  public mutating func writeRow(_ y: Int, x: Int = 0, bytes: Data) throws {
    guard y >= 0, y < height, x >= 0, x <= width,
      bytes.count % sampleBytes == 0, bytes.count / sampleBytes <= width - x else {
      throw CraftError.invalid("Component row write exceeds its plane or contains incomplete samples.")
    }
    let bytes = Data(bytes), length = bytes.count / sampleBytes
    for i in 0..<length {
      if i % 4096 == 0 { try Task.checkCancellation() }
      try Self.validate(word: Self.load(bytes, offset: i * sampleBytes, stride: sampleBytes), depth: depth)
    }
    var candidate = self
    for i in 0..<length {
      if i % 4096 == 0 { try Task.checkCancellation() }
      candidate.setValidatedWord(Self.load(bytes, offset: i * sampleBytes, stride: sampleBytes), at: y * width + x + i)
    }
    self = candidate
  }
  /// Publish a fresh immutable snapshot. The original plane/history is unchanged
  /// on admission, cancellation or I/O failure; callers can discard the builder.
  public func spilling(maximumBytes: Int = RasterTileStore.defaultMaximumBytes, directory: URL? = nil) throws -> Self {
    try Task.checkCancellation()
    let writer = try ComponentPlaneWriter(plane: self, maximumBytes: maximumBytes, directory: directory)
    for key in blockKeys {
      try Task.checkCancellation()
      try writer.write(key: key, block: block(key)!)
    }
    var result = self
    result.base = try writer.finish()
    result.edits = ComponentBlockMap()
    return result
  }
  private func block(_ key: Int) -> ComponentBlock? { edits[key] ?? base?.block(key) }
  private var blockKeys: AnySequence<Int> {
    let edits = edits, base = base
    return AnySequence {
      var a = edits.makeIterator(), b = base?.makeIterator()
      var left = a.next()?.0, right = b?.next()
      return AnyIterator<Int> {
        guard left != nil || right != nil else { return nil }
        let key = min(left ?? Int.max, right ?? Int.max)
        if left == key { left = a.next()?.0 }
        if right == key { right = b?.next() }
        return key
      }
    }
  }
  /// Ordered ranges of retained raw blocks; default-only samples need no visit.
  var storedSampleRanges: AnySequence<Range<Int>> {
    let count = count
    return AnySequence(blockKeys.lazy.map { key in
      let start = key * Self.blockSamples
      return start..<min(count, start + Self.blockSamples)
    })
  }
  /// Bounded legacy callers still admit only their existing dense byte capacity.
  var legacyBytes: Data {
    var bytes = Data(count: logicalBytes)
    for i in 0..<count { Self.store(word(at: i), in: &bytes, offset: i * sampleBytes, stride: sampleBytes) }
    return bytes
  }
  func allWordsEqual(_ word: UInt32) -> Bool {
    var covered = 0
    for range in storedSampleRanges {
      for i in range where self.word(at: i) != word { return false }
      covered += range.count
    }
    return defaultWord == word || covered == count
  }
  public static func == (a: Self, b: Self) -> Bool {
    guard a.width == b.width, a.height == b.height, a.depth == b.depth else { return false }
    if a.defaultWord == b.defaultWord, a.base === b.base, a.edits.sharesRoot(with: b.edits) { return true }
    var ai = a.blockKeys.makeIterator(), bi = b.blockKeys.makeIterator()
    var ak = ai.next(), bk = bi.next(), covered = 0
    while ak != nil || bk != nil {
      let key = min(ak ?? Int.max, bk ?? Int.max), valid = min(blockSamples, a.count - key * blockSamples)
      let at = a.block(key), bt = b.block(key)
      for i in 0..<valid {
        if (at?.word(i, stride: a.sampleBytes) ?? a.defaultWord) != (bt?.word(i, stride: b.sampleBytes) ?? b.defaultWord) { return false }
      }
      covered += valid
      if ak == key { ak = ai.next() }
      if bk == key { bk = bi.next() }
    }
    return covered == a.count || a.defaultWord == b.defaultWord
  }
  static func load(_ data: Data, offset: Int, stride: Int) -> UInt32 {
    var word: UInt32 = 0
    for i in 0..<stride { word |= UInt32(data[offset + i]) << (i * 8) }
    return word
  }
  static func store(_ word: UInt32, in data: inout Data, offset: Int, stride: Int) {
    for i in 0..<stride { data[offset + i] = UInt8(truncatingIfNeeded: word >> (i * 8)) }
  }
}

/// One owned block or a slice of a retained immutable mapping. Data COW never
/// exposes mutable mapped bytes, including when Undo outlives the original file.
struct ComponentBlock: @unchecked Sendable {
  private var owned: Data?
  private let mapping: ComponentPlaneMapping?
  private let key: Int
  var residentBytes: Int { owned?.count ?? 0 }
  init(fill: UInt32, stride: Int) {
    var bytes = Data(count: ComponentPlane.blockSamples * stride)
    for i in 0..<ComponentPlane.blockSamples { ComponentPlane.store(fill, in: &bytes, offset: i * stride, stride: stride) }
    owned = bytes; mapping = nil; key = 0
  }
  init(mapping: ComponentPlaneMapping, key: Int) { owned = nil; self.mapping = mapping; self.key = key }
  func word(_ offset: Int, stride: Int) -> UInt32 {
    if let owned { return ComponentPlane.load(owned, offset: offset * stride, stride: stride) }
    let bytes = mapping!.sampleAddress(key).assumingMemoryBound(to: UInt8.self)
    var word: UInt32 = 0
    for i in 0..<stride { word |= UInt32(bytes[offset * stride + i]) << (i * 8) }
    return word
  }
  mutating func set(_ word: UInt32, offset: Int, stride: Int) {
    if owned == nil { owned = Data(bytes: mapping!.sampleAddress(key), count: ComponentPlane.blockSamples * stride) }
    ComponentPlane.store(word, in: &owned!, offset: offset * stride, stride: stride)
  }
  func withBytes<T>(stride: Int, _ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
    if let owned { return try owned.withUnsafeBytes(body) }
    return try withExtendedLifetime(mapping) {
      try body(UnsafeRawBufferPointer(start: mapping!.sampleAddress(key), count: ComponentPlane.blockSamples * stride))
    }
  }
}
