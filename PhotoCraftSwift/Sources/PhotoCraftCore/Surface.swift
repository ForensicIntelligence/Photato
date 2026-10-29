import Foundation

public struct IntRect: Codable, Equatable, Sendable {
  public var x: Int
  public var y: Int
  public var width: Int
  public var height: Int
  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
  public func contains(_ px: Int, _ py: Int) -> Bool {
    px >= x && py >= y && px - x < width && py - y < height
  }
  /// Clip before doing range arithmetic, including rectangles supplied by callers at Int limits.
  public func clipped(toWidth w: Int, height h: Int) -> IntRect {
    let right = x.addingReportingOverflow(max(0, width))
    let bottom = y.addingReportingOverflow(max(0, height))
    let x0 = min(w, max(0, x))
    let y0 = min(h, max(0, y))
    let x1 = min(w, max(0, right.overflow ? Int.max : right.partialValue))
    let y1 = min(h, max(0, bottom.overflow ? Int.max : bottom.partialValue))
    return IntRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
  }
}
/// Numeric storage encoding. Masks and legacy archives use sRGB-valued samples;
/// linearRGB retains native HDR color bits without a transfer-function round trip.
public enum SurfaceColorEncoding: String, Codable, Sendable {
  case sRGB
  case linearRGB
}
public struct Surface: Codable, Equatable, Sendable {
  public static let tileSide = 64
  public static let maxDimension = 32768
  public static let maxPixels = 36_000_000
  public let width: Int
  public let height: Int
  public let depth: PixelDepth
  private var storedDefaultPixel: Pixel
  public private(set) var colorEncoding: SurfaceColorEncoding = .sRGB
  /// Existing editing/display APIs read sRGB values. Linear access retains HDR bits.
  public var defaultPixel: Pixel { encodedSample(storedDefaultPixel) }
  private func encodedSample(_ p: Pixel) -> Pixel {
    colorEncoding == .linearRGB ? SRGBTransfer.encoded(p) : p
  }
  // Dictionary and Array supply two levels of native Swift copy-on-write.
  private var tiles: [Int: [Pixel]] = [:]
  public var tileCount: Int { tiles.count }
  public var allocatedBytes: Int { tiles.count * Self.tileSide * Self.tileSide * 16 }
  func accountHistoryTiles(_ seen: inout Set<UInt>) -> Int {
    var bytes = 0
    for pixels in tiles.values {
      pixels.withUnsafeBufferPointer { buffer in
        if let address = buffer.baseAddress, seen.insert(UInt(bitPattern: address)).inserted {
          bytes += buffer.count * MemoryLayout<Pixel>.stride
        }
      }
    }
    return bytes
  }
  /// Nonzero-alpha extent, independent of hidden RGB and unused tile padding.
  public func contentBounds() throws -> IntRect? {
    var x0 = width
    var y0 = height
    var x1 = 0
    var y1 = 0
    let keys: [Int]
    if storedDefaultPixel.a > 0 {
      keys = Array(0..<columns * ((height + Self.tileSide - 1) / Self.tileSide))
    } else {
      keys = Array(tiles.keys)
    }
    for key in keys {
      try Task.checkCancellation()
      let left = key % columns * Self.tileSide
      let top = key / columns * Self.tileSide
      let right = min(width, left + Self.tileSide)
      let bottom = min(height, top + Self.tileSide)
      if let tile = tiles[key] {
        for y in top..<bottom {
          for x in left..<right where tile[(y - top) * Self.tileSide + x - left].a > 0 {
            x0 = min(x0, x)
            y0 = min(y0, y)
            x1 = max(x1, x + 1)
            y1 = max(y1, y + 1)
          }
        }
      } else if storedDefaultPixel.a > 0 {
        x0 = min(x0, left)
        y0 = min(y0, top)
        x1 = max(x1, right)
        y1 = max(y1, bottom)
      }
    }
    return x1 > x0 && y1 > y0 ? IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) : nil
  }
  /// Extract stored samples without resampling or requantizing their bits.
  public func cropped(to bounds: IntRect) throws -> Surface {
    guard bounds.width > 0, bounds.height > 0,
      bounds == bounds.clipped(toWidth: width, height: height)
    else {
      throw CraftError.invalid("The crop rectangle must lie inside the stored pixels.")
    }
    if bounds == IntRect(x: 0, y: 0, width: width, height: height) { return self }
    var output = try Surface(
      width: bounds.width, height: bounds.height, depth: depth, fill: defaultPixel,
      colorEncoding: colorEncoding)
    output.storedDefaultPixel = storedDefaultPixel
    for (key, tile) in tiles {
      try Task.checkCancellation()
      let left = key % columns * Self.tileSide
      let top = key / columns * Self.tileSide
      let x0 = max(left, bounds.x)
      let y0 = max(top, bounds.y)
      let x1 = min(left + Self.tileSide, bounds.x + bounds.width)
      let y1 = min(top + Self.tileSide, bounds.y + bounds.height)
      guard x1 > x0, y1 > y0 else { continue }
      for y in y0..<y1 {
        for x in x0..<x1 {
          output.setStoredPixel(
            x: x - bounds.x, y: y - bounds.y,
            tile[(y - top) * Self.tileSide + x - left])
        }
      }
    }
    try Task.checkCancellation()
    return output
  }
  public init(
    width: Int, height: Int, depth: PixelDepth = .u8, fill: Pixel = .clear,
    colorEncoding: SurfaceColorEncoding = .sRGB
  ) throws {
    guard width > 0, height > 0, width <= Self.maxDimension, height <= Self.maxDimension,
      width <= Self.maxPixels / height, fill.isFinite,
      colorEncoding != .linearRGB || depth == .f32
    else {
      throw CraftError.invalid("Image dimensions or pixels are invalid (maximum 36 megapixels).")
    }
    self.width = width
    self.height = height
    self.depth = depth
    self.colorEncoding = colorEncoding
    storedDefaultPixel = (colorEncoding == .linearRGB ? SRGBTransfer.linear(fill) : fill)
      .quantized(depth)
  }
  private var columns: Int { (width + Self.tileSide - 1) / Self.tileSide }
  private func storedPixel(x: Int, y: Int) -> Pixel {
    guard x >= 0, y >= 0, x < width, y < height else { return .clear }
    let key = (y / Self.tileSide) * columns + x / Self.tileSide
    return tiles[key]?[(y % Self.tileSide) * Self.tileSide + x % Self.tileSide]
      ?? storedDefaultPixel
  }
  public func pixel(x: Int, y: Int) -> Pixel { encodedSample(storedPixel(x: x, y: y)) }
  public func linearPixel(x: Int, y: Int) -> Pixel {
    let p = storedPixel(x: x, y: y)
    return colorEncoding == .linearRGB ? p : SRGBTransfer.linear(p)
  }
  /// Assign the meaning of decoded channel samples without changing their bits.
  /// Codec boundaries use this only when the source encoding is already known.
  public func interpretingSamples(as encoding: SurfaceColorEncoding) throws -> Surface {
    guard encoding != .linearRGB || depth == .f32 else {
      throw CraftError.invalid("Linear RGB storage requires 32-bit samples.")
    }
    var result = self
    result.colorEncoding = encoding
    return result
  }
  public mutating func setPixel(x: Int, y: Int, _ p: Pixel) {
    guard x >= 0, y >= 0, x < width, y < height else { return }
    guard colorEncoding == .linearRGB else {
      setStoredPixel(x: x, y: y, p.quantized(depth))
      return
    }
    let old = storedPixel(x: x, y: y)
    let view = encodedSample(old)
    let value = p.quantized(depth)
    // Retain untouched components, including hidden RGB and signed zeros.
    // An encoded view cannot reconstruct every original Float32 linear sample.
    func changed(_ next: Float, _ prior: Float, _ stored: Float) -> Float {
      next.bitPattern == prior.bitPattern
        ? stored : PixelDepth.f32.quantize(SRGBTransfer.linear(next))
    }
    let stored = Pixel(
      changed(value.r, view.r, old.r), changed(value.g, view.g, old.g),
      changed(value.b, view.b, old.b), p.a.bitPattern == view.a.bitPattern ? old.a : value.a)
    if !old.hasSameBits(as: stored) { setStoredPixel(x: x, y: y, stored) }
  }
  public mutating func setLinearPixel(x: Int, y: Int, _ p: Pixel) {
    guard x >= 0, y >= 0, x < width, y < height else { return }
    guard colorEncoding == .linearRGB else {
      setPixel(x: x, y: y, SRGBTransfer.encoded(p))
      return
    }
    let alpha = p.a.isFinite && p.a >= 0 && p.a <= 1 ? p.a : unit(p.a)
    let value = Pixel(depth.quantize(p.r), depth.quantize(p.g), depth.quantize(p.b), alpha)
    setStoredPixel(x: x, y: y, value)
  }
  private mutating func setStoredPixel(x: Int, y: Int, _ p: Pixel) {
    let key = (y / Self.tileSide) * columns + x / Self.tileSide
    // The default subscript yields the stored Array directly. Optional chaining
    // here creates an allocating read/modify/write coroutine for every pixel.
    // The default allocation is evaluated only when this tile is absent.
    let offset = (y % Self.tileSide) * Self.tileSide + x % Self.tileSide
    tiles[key, default: Array(repeating: storedDefaultPixel, count: Self.tileSide * Self.tileSide)][
      offset] = p
  }
  public mutating func mapPixels(_ transform: (Int, Int, Pixel) -> Pixel) {
    for y in 0..<height {
      for x in 0..<width { setPixel(x: x, y: y, transform(x, y, pixel(x: x, y: y))) }
    }
  }
  /// A checked component edit must not requantize untargeted channel samples.
  /// Work on a copy so cancellation or invalid output cannot partially commit.
  mutating func mapStoredPixels(_ transform: (Int, Int, Pixel) -> Pixel) throws {
    var result = self
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let original = pixel(x: x, y: y)
        let edited = transform(x, y, original)
        guard edited.isFinite else { throw CraftError.invalid("Non-finite component edit.") }
        if !original.hasSameBits(as: edited) {
          if colorEncoding == .linearRGB {
            result.setPixel(x: x, y: y, edited)
          } else {
            result.setStoredPixel(x: x, y: y, edited)
          }
        }
      }
    }
    try Task.checkCancellation()
    self = result
  }
  /// Replaces only this rectangle. Cancellation leaves the receiving surface unchanged.
  public mutating func mapPixels(
    in region: IntRect, _ transform: (Int, Int, Pixel) -> Pixel
  ) throws {
    let r = region.clipped(toWidth: width, height: height)
    var result = self
    for y in r.y..<r.y + r.height {
      try Task.checkCancellation()
      for x in r.x..<r.x + r.width {
        result.setPixel(x: x, y: y, transform(x, y, pixel(x: x, y: y)))
      }
    }
    try Task.checkCancellation()
    self = result
  }
  /// Conservative bounds of changed storage tiles. Shared COW buffers need no pixel scan.
  /// Layout changes invalidate the entire receiving surface; callers comparing geometry must
  /// also account for the previous surface's extent. Comparison preserves signed-zero bits.
  public func changedTileBounds(comparedTo old: Surface) throws -> IntRect? {
    func sameBits(_ a: Pixel, _ b: Pixel) -> Bool {
      a.hasSameBits(as: b)
    }
    guard width == old.width, height == old.height, depth == old.depth,
      colorEncoding == old.colorEncoding,
      sameBits(storedDefaultPixel, old.storedDefaultPixel)
    else { return IntRect(x: 0, y: 0, width: width, height: height) }
    var x0 = width
    var y0 = height
    var x1 = 0
    var y1 = 0
    for key in Set(tiles.keys).union(old.tiles.keys) {
      try Task.checkCancellation()
      let a = tiles[key]
      let b = old.tiles[key]
      let equal: Bool
      if let a, let b {
        equal = a.withUnsafeBufferPointer { left in
          b.withUnsafeBufferPointer { right in
            left.baseAddress == right.baseAddress
              || zip(left, right).allSatisfy { sameBits($0, $1) }
          }
        }
      } else {
        equal = (a ?? b ?? []).allSatisfy { sameBits($0, storedDefaultPixel) }
      }
      if equal { continue }
      let x = key % columns * Self.tileSide
      let y = key / columns * Self.tileSide
      x0 = min(x0, x)
      y0 = min(y0, y)
      x1 = max(x1, min(width, x + Self.tileSide))
      y1 = max(y1, min(height, y + Self.tileSide))
    }
    return x1 > x0 && y1 > y0
      ? IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) : nil
  }
  /// Grow storage in the existing sample grid without resampling or losing hidden RGB.
  /// `bounds` contains the entire original surface; its origin becomes the new local origin.
  public func expanded(to bounds: IntRect, fill: Pixel, preservingFillBits: Bool = false) throws
    -> Surface
  {
    try Task.checkCancellation()
    let right = bounds.x.addingReportingOverflow(bounds.width)
    let bottom = bounds.y.addingReportingOverflow(bounds.height)
    guard !right.overflow, !bottom.overflow, bounds.x <= 0, bounds.y <= 0,
      right.partialValue >= width, bottom.partialValue >= height
    else { throw CraftError.invalid("Expanded storage must contain the existing pixels.") }
    var output = try Surface(
      width: bounds.width, height: bounds.height, depth: depth, fill: fill,
      colorEncoding: colorEncoding)
    // Mask outside coverage is continuous even when stored mask samples are integer-depth.
    // Padding must preserve that implicit value exactly until a pixel is actually painted.
    if preservingFillBits {
      output.storedDefaultPixel = colorEncoding == .linearRGB ? SRGBTransfer.linear(fill) : fill
    }
    if bounds.x == 0, bounds.y == 0, bounds.width == width, bounds.height == height { return self }
    let ox = -bounds.x
    let oy = -bounds.y
    // Preserve an opaque or nonzero sparse default only inside its original extent.
    if !storedDefaultPixel.hasSameBits(as: output.storedDefaultPixel) {
      let side = Self.tileSide
      for ty in oy / side...(oy + height - 1) / side {
        try Task.checkCancellation()
        for tx in ox / side...(ox + width - 1) / side {
          let left = max(ox, tx * side) - tx * side
          let top = max(oy, ty * side) - ty * side
          let right = min(ox + width, (tx + 1) * side) - tx * side
          let bottom = min(oy + height, (ty + 1) * side) - ty * side
          let key = ty * output.columns + tx
          if left == 0, top == 0, right == side, bottom == side {
            output.tiles[key] = [Pixel](repeating: storedDefaultPixel, count: side * side)
          } else {
            var tile = [Pixel](repeating: output.storedDefaultPixel, count: side * side)
            for y in top..<bottom {
              tile.replaceSubrange(
                y * side + left..<y * side + right,
                with: repeatElement(storedDefaultPixel, count: right - left))
            }
            output.tiles[key] = tile
          }
        }
      }
    }
    for (key, pixels) in tiles {
      try Task.checkCancellation()
      let x0 = key % columns * Self.tileSide
      let y0 = key / columns * Self.tileSide
      let w = min(Self.tileSide, width - x0)
      let h = min(Self.tileSide, height - y0)
      if ox % Self.tileSide == 0, oy % Self.tileSide == 0,
        w == Self.tileSide, h == Self.tileSide
      {
        // Complete aligned tiles keep their original COW buffer. Partial boundary tiles
        // must not reveal unused padding samples when the layer grows.
        let newKey = ((y0 + oy) / Self.tileSide) * output.columns + (x0 + ox) / Self.tileSide
        output.tiles[newKey] = pixels
      } else {
        for y in 0..<h {
          try Task.checkCancellation()
          let dy = y0 + oy + y
          var x = 0
          while x < w {
            let dx = x0 + ox + x
            let side = Self.tileSide
            let count = min(w - x, side - dx % side)
            let sourceStart = y * side + x
            let destinationStart = dy % side * side + dx % side
            let key = dy / side * output.columns + dx / side
            // Mutate the dictionary's array in place, copying a contiguous row segment.
            // This preserves bits and avoids one dictionary lookup per copied sample.
            output.tiles[
              key, default: [Pixel](repeating: output.storedDefaultPixel, count: side * side)
            ]
            .replaceSubrange(
              destinationStart..<destinationStart + count,
              with: pixels[sourceStart..<sourceStart + count])
            x += count
          }
        }
      }
    }
    return output
  }
  public func validated() throws {
    guard width > 0, height > 0, width <= Self.maxDimension, height <= Self.maxDimension,
      width <= Self.maxPixels / height, storedDefaultPixel.isFinite,
      colorEncoding != .linearRGB || depth == .f32,
      tiles.count <= columns * ((height + Self.tileSide - 1) / Self.tileSide)
    else { throw CraftError.invalid("Invalid raster storage.") }
    let maxKey = columns * ((height + Self.tileSide - 1) / Self.tileSide)
    for (key, pixels) in tiles {
      guard key >= 0, key < maxKey, pixels.count == Self.tileSide * Self.tileSide,
        pixels.allSatisfy(\.isFinite)
      else { throw CraftError.invalid("Corrupt raster tile.") }
    }
  }
  /// Straight-alpha interleaved RGBA, little-endian for 16/32-bit samples.
  /// Visits each allocated tile once; avoids per-pixel dictionary lookups and temporary arrays.
  public func rgbaData(
    depth outputDepth: PixelDepth, colorEncoding outputEncoding: SurfaceColorEncoding = .sRGB
  ) throws -> Data {
    try validated()
    let stride = outputDepth == .u8 ? 4 : outputDepth == .u16 ? 8 : 16
    var output = Data(count: width * height * stride)
    try output.withUnsafeMutableBytes { bytes in
      @inline(__always) func write(_ stored: Pixel, at offset: Int) {
        let value =
          colorEncoding == outputEncoding
          ? stored
          : outputEncoding == .linearRGB
            ? SRGBTransfer.linear(stored) : SRGBTransfer.encoded(stored)
        switch outputDepth {
        case .u8:
          bytes[offset] = UInt8((unit(value.r) * 255).rounded())
          bytes[offset + 1] = UInt8((unit(value.g) * 255).rounded())
          bytes[offset + 2] = UInt8((unit(value.b) * 255).rounded())
          bytes[offset + 3] = UInt8((unit(value.a) * 255).rounded())
        case .u16:
          bytes.storeBytes(
            of: UInt16((unit(value.r) * 65535).rounded()).littleEndian,
            toByteOffset: offset, as: UInt16.self)
          bytes.storeBytes(
            of: UInt16((unit(value.g) * 65535).rounded()).littleEndian,
            toByteOffset: offset + 2, as: UInt16.self)
          bytes.storeBytes(
            of: UInt16((unit(value.b) * 65535).rounded()).littleEndian,
            toByteOffset: offset + 4, as: UInt16.self)
          bytes.storeBytes(
            of: UInt16((unit(value.a) * 65535).rounded()).littleEndian,
            toByteOffset: offset + 6, as: UInt16.self)
        case .f32:
          bytes.storeBytes(
            of: value.r.bitPattern.littleEndian, toByteOffset: offset, as: UInt32.self)
          bytes.storeBytes(
            of: value.g.bitPattern.littleEndian, toByteOffset: offset + 4, as: UInt32.self)
          bytes.storeBytes(
            of: value.b.bitPattern.littleEndian, toByteOffset: offset + 8, as: UInt32.self)
          bytes.storeBytes(
            of: value.a.bitPattern.littleEndian, toByteOffset: offset + 12, as: UInt32.self)
        }
      }
      write(storedDefaultPixel, at: 0)
      // Copy the already encoded default sample with integer stores, then overlay allocated tiles.
      let word0 =
        stride == 4
        ? UInt64(bytes.loadUnaligned(as: UInt32.self)) : bytes.loadUnaligned(as: UInt64.self)
      let word1 = stride == 16 ? bytes.loadUnaligned(fromByteOffset: 8, as: UInt64.self) : 0
      if word0 != 0 || word1 != 0 {
        for y in 0..<height {
          try Task.checkCancellation()
          for x in 0..<width {
            let offset = (y * width + x) * stride
            if stride == 4 {
              bytes.storeBytes(of: UInt32(word0), toByteOffset: offset, as: UInt32.self)
            } else {
              bytes.storeBytes(of: word0, toByteOffset: offset, as: UInt64.self)
              if stride == 16 {
                bytes.storeBytes(of: word1, toByteOffset: offset + 8, as: UInt64.self)
              }
            }
          }
        }
      }
      for (key, pixels) in tiles {
        try Task.checkCancellation()
        let x0 = (key % columns) * Self.tileSide
        let y0 = (key / columns) * Self.tileSide
        for y in 0..<min(Self.tileSide, height - y0) {
          for x in 0..<min(Self.tileSide, width - x0) {
            write(pixels[y * Self.tileSide + x], at: ((y0 + y) * width + x0 + x) * stride)
          }
        }
      }
    }
    return output
  }
  private enum CodingKeys: String, CodingKey {
    case width, height, depth, defaultPixel, defaultSample, tiles, packingVersion, tileData,
      colorEncoding
  }
  private struct TileKey: CodingKey {
    var stringValue: String
    var intValue: Int? { Int(stringValue) }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { stringValue = String(intValue) }
  }
  public func encode(to encoder: any Encoder) throws {
    try validated()
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(width, forKey: .width)
    try c.encode(height, forKey: .height)
    try c.encode(depth, forKey: .depth)
    try c.encode(TileArchive.encodeSample(storedDefaultPixel), forKey: .defaultSample)
    let history = encoder.userInfo[.historyTileEncoder] as? any RasterBlobEncoding
    try c.encode(
      history == nil ? (colorEncoding == .linearRGB ? 2 : 1) : 3, forKey: .packingVersion)
    if colorEncoding == .linearRGB { try c.encode(colorEncoding, forKey: .colorEncoding) }
    var packed = c.nestedContainer(keyedBy: TileKey.self, forKey: .tileData)
    for key in tiles.keys.sorted() {
      try Task.checkCancellation()
      let bytes = try TileArchive.encode(tiles[key]!)
      if let history {
        try packed.encode(history.storeBytes(bytes), forKey: TileKey(intValue: key)!)
      } else {
        try packed.encode(bytes, forKey: TileKey(intValue: key)!)
      }
    }
  }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    width = try c.decode(Int.self, forKey: .width)
    height = try c.decode(Int.self, forKey: .height)
    depth = try c.decode(PixelDepth.self, forKey: .depth)
    let version = try c.decodeIfPresent(Int.self, forKey: .packingVersion)
    let history = decoder.userInfo[.historyTileDecoder] as? any RasterBlobDecoding
    guard version == nil || version == 1 || version == 2 || (version == 3 && history != nil) else {
      throw CraftError.unsupported("Unsupported native raster packing version.")
    }
    if version == 2 || version == 3 {
      colorEncoding =
        try c.decodeIfPresent(SurfaceColorEncoding.self, forKey: .colorEncoding) ?? .sRGB
      guard version != 2 || colorEncoding == .linearRGB,
        colorEncoding != .linearRGB || depth == .f32
      else {
        throw CraftError.invalid("Invalid linear RGB raster storage.")
      }
    } else {
      guard !c.contains(.colorEncoding) else {
        throw CraftError.invalid("Ambiguous raster color encoding.")
      }
      colorEncoding = .sRGB
    }
    guard version == nil ? !c.contains(.defaultSample) : !c.contains(.defaultPixel) else {
      throw CraftError.invalid("Ambiguous default pixel storage.")
    }
    storedDefaultPixel =
      try version == nil
      ? c.decode(Pixel.self, forKey: .defaultPixel)
      : TileArchive.decodeSample(c.decode(Data.self, forKey: .defaultSample))
    guard width > 0, height > 0, width <= Self.maxDimension, height <= Self.maxDimension,
      width <= Self.maxPixels / height, storedDefaultPixel.isFinite
    else { throw CraftError.invalid("Invalid raster dimensions or default pixel.") }
    guard version == nil ? !c.contains(.tileData) : !c.contains(.tiles) else {
      throw CraftError.invalid("Ambiguous native raster storage.")
    }
    let container = try c.nestedContainer(
      keyedBy: TileKey.self,
      forKey: version == nil ? .tiles : .tileData)
    let maxKey =
      ((width + Self.tileSide - 1) / Self.tileSide)
      * ((height + Self.tileSide - 1) / Self.tileSide)
    guard container.allKeys.count <= maxKey else {
      throw CraftError.invalid("Too many raster tiles.")
    }
    try (decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget)?
      .reserve(tiles: container.allKeys.count)
    tiles = [:]
    for key in container.allKeys {
      try Task.checkCancellation()
      guard let index = key.intValue, index >= 0, index < maxKey, String(index) == key.stringValue,
        tiles[index] == nil
      else { throw CraftError.invalid("Invalid native tile index.") }
      if version == 3, let history {
        tiles[index] = try history.tile(container.decode(String.self, forKey: key))
      } else if version != nil {
        tiles[index] = try TileArchive.decode(container.decode(Data.self, forKey: key))
      } else {
        var samples = try container.nestedUnkeyedContainer(forKey: key)
        guard samples.count == TileArchive.pixelCount else {
          throw CraftError.invalid("Invalid legacy native tile size.")
        }
        var pixels = [Pixel]()
        pixels.reserveCapacity(TileArchive.pixelCount)
        while !samples.isAtEnd { pixels.append(try samples.decode(Pixel.self)) }
        tiles[index] = pixels
      }
    }
    try validated()
  }
}
