import Foundation

/// One numeric printing plane. Samples have no RGB transfer function or alpha.
public struct InkPlane: Codable, Equatable, Sendable {
  public static let maximumPixels = 8_388_608
  public let width: Int
  public let height: Int
  public let depth: PixelDepth
  private var storage: ComponentPlane
  /// Portable legacy bytes; current ink/file workflows retain their explicit8MP cap.
  public var bytes: Data {
    var result = Data(count: count * stride)
    for i in 0..<count { ComponentPlane.store(storage.word(at: i), in: &result, offset: i * stride, stride: stride) }
    return result
  }
  public var residentSampleBytes: Int { storage.residentEditBytes }
  public var count: Int { width * height }
  public var estimatedBytes: Int { count * stride }
  private var stride: Int { depth == .u8 ? 1 : 2 }

  public init(width: Int, height: Int, depth: PixelDepth = .u8, bytes: Data) throws {
    try Self.dimensions(width, height, depth)
    guard bytes.count == width * height * (depth == .u8 ? 1 : 2) else { throw CraftError.invalid("Ink plane sample count differs from its dimensions.") }
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
  static func dimensions(_ width: Int, _ height: Int, _ depth: PixelDepth) throws {
    guard width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= maximumPixels / height, [.u8, .u16].contains(depth) else {
      throw CraftError.invalid("Ink planes require 8-bit or 16-bit samples and at most 8,388,608 pixels.")
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
    var result = self
    for i in 0..<count {
      if i % 4096 == 0 { try Task.checkCancellation() }
      let old = value(at: i), next = try transform(i % width, i / width, old)
      guard next.isFinite, (0...1).contains(next) else { throw CraftError.invalid("Invalid numeric ink sample.") }
      if next != old { result.store(next, at: i) }
    }
    return result
  }
  public func converted(to depth: PixelDepth, inverted: Bool = false) throws -> Self {
    if depth == self.depth, !inverted { return self }
    var result = try Self(width: width, height: height, depth: depth)
    for i in 0..<count {
      if i % 4096 == 0 { try Task.checkCancellation() }
      let value = value(at: i); result.store(inverted ? 1 - value : value, at: i)
    }
    return result
  }
  /// Grayscale editing/display cache; ink density is inverted for a paper preview.
  public func surface(inverted: Bool = false) throws -> Surface {
    try validate()
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
    var result = self
    for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
      let p = edited.pixel(x: x, y: y)
      guard p != previous.pixel(x: x, y: y) else { continue }
      guard p.isFinite else { throw CraftError.invalid("Ink edits require finite pixels.") }
      let gray = unit((p.r * 0.2126 + p.g * 0.7152 + p.b * 0.0722) * unit(p.a) + 1 - unit(p.a))
      result.store(inverted ? 1 - gray : gray, at: y * width + x)
    } }
    return result
  }
  private enum CodingKeys: String, CodingKey { case width, height, depth, bytes, blob }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let width = try c.decode(Int.self, forKey: .width), height = try c.decode(Int.self, forKey: .height)
    let depth = try c.decode(PixelDepth.self, forKey: .depth)
    try Self.dimensions(width, height, depth)
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
    if let context = encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding {
      try c.encode(context.storeBytes(bytes), forKey: .blob)
    } else { try c.encode(bytes, forKey: .bytes) }
  }
}
