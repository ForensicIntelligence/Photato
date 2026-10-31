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
  public static let pagedIndexMinimumTiles = 1024
  public static let runtimeIndexRecordBytes = 16
  public static let smallMappedReferenceAdmissionBytes = 128
  public static let directTileIndexLimit = RasterTileMap.directLimit
  public static let runtimeIndexWriteBufferBytes = 65_536
  /// Photoshop's PSB/native canvas extent. Logical area is independent of resident tiles.
  public static let maxDimension = 300_000
  public static let maxPixels = 90_000_000_000
  /// Existing contiguous algorithms must opt into paging/streaming before exceeding this.
  public static let maximumDensePixels = 36_000_000
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
  // Immutable mapped bases and persistent radix edit paths preserve copy-on-write.
  private var tiles: RasterTileMap = [:]
  // Only this type can write tiles. Quantized setters preserve finite samples;
  // raw crop/expansion copies propagate proof conservatively. Decoding starts
  // untrusted and earns proof only after a full scan, including tile padding.
  // This value travels with COW storage; it is neither serialized nor semantic.
  private var tilesAreKnownFinite = false
  public static func == (lhs: Surface, rhs: Surface) -> Bool {
    lhs.width == rhs.width && lhs.height == rhs.height && lhs.depth == rhs.depth
      && lhs.storedDefaultPixel == rhs.storedDefaultPixel
      && lhs.colorEncoding == rhs.colorEncoding && lhs.tiles == rhs.tiles
  }
  public var tileCount: Int { tiles.count }
  /// Ordered allocated tile keys, including paged bases and COW edits. A caller can
  /// merge several grids without constructing a whole-canvas Set or descriptor array.
  public var storedTileKeys: AnySequence<Int> {
    AnySequence(tiles.entries(in: 0..<(columns * ((height + Self.tileSide - 1) / Self.tileSide))).lazy.map { $0.0 })
  }
  /// Owned heap samples plus a conservative index/reference allowance for mapped tiles.
  /// File-backed pages are reclaimable by macOS and are reported separately.
  public var allocatedBytes: Int { tiles.residentBytes }
  public var mappedBytes: Int { tiles.mappedTileCount * TileArchive.byteCount }
  public var mappedTileCount: Int { tiles.mappedTileCount }
  public var mappedTileIndexBytes: Int { tiles.mappedIndexBytes }
  public var residentTileIndexEstimate: Int { tiles.residentIndexBytes }
  func accountHistoryTiles(_ seen: inout Set<UInt>) -> Int { tiles.accountHistory(&seen) }
  /// Nonzero-alpha extent, independent of hidden RGB and unused tile padding.
  public func contentBounds() throws -> IntRect? {
    var x0 = width
    var y0 = height
    var x1 = 0
    var y1 = 0
    let keys = tiles.keys
    if storedDefaultPixel.a > 0 {
      // Missing tiles are implicit opaque pixels. Count occupied rows/columns,
      // rather than enumerate up to22 million missing tiles on a300k canvas.
      let rows = (height + Self.tileSide - 1) / Self.tileSide
      var rowCounts = [Int](repeating: 0, count: rows)
      var columnCounts = [Int](repeating: 0, count: columns)
      for key in keys { rowCounts[key / columns] += 1; columnCounts[key % columns] += 1 }
      for x in columnCounts.indices where columnCounts[x] < rows {
        x0 = min(x0, x * Self.tileSide)
        x1 = max(x1, min(width, (x + 1) * Self.tileSide))
      }
      for y in rowCounts.indices where rowCounts[y] < columns {
        y0 = min(y0, y * Self.tileSide)
        y1 = max(y1, min(height, (y + 1) * Self.tileSide))
      }
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
    output.tilesAreKnownFinite = tilesAreKnownFinite && storedDefaultPixel.isFinite
    for (key, tile) in tilesIntersecting(bounds) {
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
      throw CraftError.invalid("Image dimensions must be between 1 and 300,000 pixels per side (maximum 90 gigapixels).")
    }
    self.width = width
    self.height = height
    self.depth = depth
    self.colorEncoding = colorEncoding
    storedDefaultPixel = (colorEncoding == .linearRGB ? SRGBTransfer.linear(fill) : fill)
      .quantized(depth)
    tilesAreKnownFinite = true
  }
  private var columns: Int { (width + Self.tileSide - 1) / Self.tileSide }
  private func storedPixel(x: Int, y: Int) -> Pixel {
    guard x >= 0, y >= 0, x < width, y < height else { return .clear }
    let key = (y / Self.tileSide) * columns + x / Self.tileSide
    return tiles.pixel(key:key,offset:(y % Self.tileSide) * Self.tileSide + x % Self.tileSide,
      default:storedDefaultPixel)
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
  // RasterTileMap isolates paged ownership; the ordinary bounded Dictionary
  // path stays visible to optimization in pixel loops.
  private mutating func setStoredPixel(x: Int, y: Int, _ p: Pixel) {
    let key = (y / Self.tileSide) * columns + x / Self.tileSide
    // The default subscript yields the stored Array directly. Optional chaining
    // here creates an allocating read/modify/write coroutine for every pixel.
    // The default allocation is evaluated only when this tile is absent.
    let offset = (y % Self.tileSide) * Self.tileSide + x % Self.tileSide
    tiles.setPixel(key:key,offset:offset,pixel:p,default:storedDefaultPixel)
  }
  public mutating func mapPixels(_ transform: (Int, Int, Pixel) -> Pixel) {
    for y in 0..<height {
      for x in 0..<width { setPixel(x: x, y: y, transform(x, y, pixel(x: x, y: y))) }
    }
  }
  /// A checked component edit must not requantize untargeted channel samples.
  /// Work on a copy so cancellation or invalid output cannot partially commit.
  mutating func mapStoredPixels(_ transform: (Int, Int, Pixel) -> Pixel) throws {
    guard width <= Self.maximumDensePixels / height else { throw CraftError.unsupported("This component operation is not yet tiled for large documents.") }
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
    guard r.width * r.height <= Self.maximumDensePixels else {
      throw CraftError.unsupported("This pixel operation needs a bounded region on a large document.")
    }
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
    for key in tiles.candidateKeys(comparedTo: old.tiles) {
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
        equal = (a ?? b ?? RasterTile([])).allSatisfy { sameBits($0, storedDefaultPixel) }
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
    // A finite fill can overflow a raw linear conversion. It can also become
    // tile data in a later expansion, so neither default is assumed valid here.
    output.tilesAreKnownFinite =
      tilesAreKnownFinite && storedDefaultPixel.isFinite && output.storedDefaultPixel.isFinite
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
            output.tiles[key] = RasterTile(repeating: storedDefaultPixel, count: side * side)
          } else {
            var tile = [Pixel](repeating: output.storedDefaultPixel, count: side * side)
            for y in top..<bottom {
              tile.replaceSubrange(
                y * side + left..<y * side + right,
                with: repeatElement(storedDefaultPixel, count: right - left))
            }
            output.tiles[key] = RasterTile(tile)
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
              key, default: RasterTile(repeating: output.storedDefaultPixel, count: side * side)
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
    guard tiles.isStructurallyValid(maximumKey:maxKey) else { throw CraftError.invalid("Corrupt raster tile metadata.") }
    if !tilesAreKnownFinite {
      for (_,pixels) in tiles {
        try Task.checkCancellation()
        guard pixels.allSatisfy(\.isFinite) else {throw CraftError.invalid("Corrupt raster tile.")}
      }
    }
  }
  /// Straight-alpha interleaved RGBA, little-endian for 16/32-bit samples.
  /// Visits each allocated tile once; avoids per-pixel dictionary lookups and temporary arrays.
  public func rgbaData(
    depth outputDepth: PixelDepth, colorEncoding outputEncoding: SurfaceColorEncoding = .sRGB
  ) throws -> Data {
    try validated()
    guard width <= Self.maximumDensePixels / height else {
      throw CraftError.unsupported("This operation requires a contiguous raster. Use a bounded preview or region for large documents; streamed full-size output is not yet available.")
    }
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
      colorEncoding, tilePages, tileCount
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
      history == nil ? (colorEncoding == .linearRGB ? 2 : 1) : (history is any IndexedRasterBlobEncoding ? 4 : 3), forKey: .packingVersion)
    if colorEncoding == .linearRGB { try c.encode(colorEncoding, forKey: .colorEncoding) }
    if let indexed = history as? any IndexedRasterBlobEncoding {
      var pages: [String] = [], entries: [(Int, UInt64)] = []
      for (key,tile) in tiles {
        try Task.checkCancellation()
        entries.append((key, try indexed.storeOrdinal(TileArchive.encode(Array(tile)))))
        if entries.count == NativeTilePage.capacity {
          pages.append(try indexed.storeBytes(NativeTilePage.encode(entries))); entries.removeAll(keepingCapacity:true)
        }
      }
      if !entries.isEmpty { pages.append(try indexed.storeBytes(NativeTilePage.encode(entries))) }
      try c.encode(tiles.count, forKey: .tileCount); try c.encode(pages, forKey: .tilePages)
      return
    }
    var packed = c.nestedContainer(keyedBy: TileKey.self, forKey: .tileData)
    for (key,tile) in tiles {
      try Task.checkCancellation()
      let bytes = try TileArchive.encode(Array(tile))
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
    guard version == nil || version == 1 || version == 2 || (version == 3 && history != nil) || (version == 4 && history is any IndexedRasterBlobDecoding) else {
      throw CraftError.unsupported("Unsupported native raster packing version.")
    }
    if version == 2 || version == 3 || version == 4 {
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
    if version == 4, let history {
      guard !c.contains(.tiles), !c.contains(.tileData) else { throw CraftError.invalid("Ambiguous paged raster storage.") }
      let count = try c.decode(Int.self, forKey:.tileCount)
      let maximum = ((width + Self.tileSide - 1) / Self.tileSide) * ((height + Self.tileSide - 1) / Self.tileSide)
      guard count >= 0, count <= maximum else { throw CraftError.invalid("Invalid paged raster tile count.") }
      let mapped = history as? any MappedRasterBlobDecoding
      let usesMapped = mapped?.usesMappedTiles == true
      let budget = decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget
      let indexBuilder: RuntimeTileIndex.Builder?
      if usesMapped && count>=Self.pagedIndexMinimumTiles {
        try budget?.reserve(bytes:Self.runtimeIndexWriteBufferBytes+512)
        indexBuilder=try RuntimeTileIndex.Builder(reserveSegment:{try budget?.reserve(bytes:$0)})
      } else {
        indexBuilder=nil
        if usesMapped {try budget?.reserveMappedReferences(tiles:count)}else{try budget?.reserve(tiles:count)}
      }
      let pages = try c.decode([String].self, forKey:.tilePages)
      guard pages.count == (count + NativeTilePage.capacity - 1) / NativeTilePage.capacity else { throw CraftError.invalid("Invalid raster page count.") }
      tiles = [:]; var previous = -1, seen = 0
      for page in pages {
        let entries = try NativeTilePage.decode(history.bytes(page, maximumBytes:NativeTilePage.maximumBytes))
        guard entries.count == min(NativeTilePage.capacity, count-seen) else { throw CraftError.invalid("Invalid raster page coverage.") }
        for (key, ordinal) in entries {
          try Task.checkCancellation()
          guard key > previous, key < maximum else { throw CraftError.invalid("Invalid or duplicate paged tile index.") }
          let identifier = NativeIndexedArchive.identifier(ordinal)
          let tile = try usesMapped ? mapped!.storedTile(identifier) : RasterTile(history.tile(identifier))
          if let indexBuilder {try indexBuilder.append(key:key,tile:tile)}else{tiles[key]=tile}
          previous = key; seen += 1
        }
      }
      guard seen == count else { throw CraftError.invalid("Missing raster tiles.") }
      if let indexBuilder {tiles=RasterTileMap(base:try indexBuilder.finish());tilesAreKnownFinite=true}
      try validated(); tilesAreKnownFinite = true; return
    }
    guard !c.contains(.tilePages), !c.contains(.tileCount) else { throw CraftError.invalid("Ambiguous raster page storage.") }
    let container = try c.nestedContainer(
      keyedBy: TileKey.self,
      forKey: version == nil ? .tiles : .tileData)
    let maxKey =
      ((width + Self.tileSide - 1) / Self.tileSide)
      * ((height + Self.tileSide - 1) / Self.tileSide)
    guard container.allKeys.count <= maxKey else {
      throw CraftError.invalid("Too many raster tiles.")
    }
    let mapped = history as? any MappedRasterBlobDecoding
    let usesMapped = version == 3 && mapped?.usesMappedTiles == true
    let budget=decoder.userInfo[.rasterDecodeBudget] as? RasterDecodeBudget
    let count=container.allKeys.count,indexBuilder:RuntimeTileIndex.Builder?
    if usesMapped && count>=Self.pagedIndexMinimumTiles {
      try budget?.reserve(bytes:Self.runtimeIndexWriteBufferBytes+512)
      indexBuilder=try RuntimeTileIndex.Builder(reserveSegment:{try budget?.reserve(bytes:$0)})
    } else {
      indexBuilder=nil
      if usesMapped {try budget?.reserveMappedReferences(tiles:count)}else{try budget?.reserve(tiles:count)}
    }
    tiles = [:]
    let keys=indexBuilder == nil ? container.allKeys:container.allKeys.sorted {($0.intValue ?? -1)<($1.intValue ?? -1)}
    for key in keys {
      try Task.checkCancellation()
      guard let index = key.intValue, index >= 0, index < maxKey, String(index) == key.stringValue,
        tiles[index] == nil
      else { throw CraftError.invalid("Invalid native tile index.") }
      if usesMapped, let mapped {
        let tile=try mapped.storedTile(container.decode(String.self, forKey:key))
        if let indexBuilder {try indexBuilder.append(key:index,tile:tile)}else{tiles[index]=tile}
      } else if version == 3, let history {
        tiles[index] = RasterTile(try history.tile(container.decode(String.self, forKey: key)))
      } else if version != nil {
        tiles[index] = RasterTile(try TileArchive.decode(container.decode(Data.self, forKey: key)))
      } else {
        var samples = try container.nestedUnkeyedContainer(forKey: key)
        guard samples.count == TileArchive.pixelCount else {
          throw CraftError.invalid("Invalid legacy native tile size.")
        }
        var pixels = [Pixel]()
        pixels.reserveCapacity(TileArchive.pixelCount)
        while !samples.isAtEnd { pixels.append(try samples.decode(Pixel.self)) }
        tiles[index] = RasterTile(pixels)
      }
    }
    if let indexBuilder {tiles=RasterTileMap(base:try indexBuilder.finish());tilesAreKnownFinite=true}
    try validated()
    tilesAreKnownFinite = true
  }
}


extension Surface {
  /// Evaluate a coordinate-independent operation on implicit samples and allocated tiles.
  /// No missing tile is materialized. Used by large-canvas composition, not spatial filters.
  public func mappedStoredSamples(
    encoding: SurfaceColorEncoding? = nil, _ transform: (Pixel) throws -> Pixel
  ) throws -> Surface {
    let value = try transform(storedDefaultPixel)
    guard value.isFinite else { throw CraftError.invalid("Non-finite sparse raster result.") }
    var output = try Surface(width: width, height: height, depth: .f32,
      colorEncoding: encoding ?? colorEncoding)
    output.storedDefaultPixel = value
    let scratch = width * height > Self.maximumDensePixels || mappedTileIndexBytes>0 ? try RasterTileStore() : nil
    let indexBuilder = scratch == nil ? nil:try RuntimeTileIndex.Builder()
    for (key, tile) in tiles {
      try Task.checkCancellation()
      let values = try tile.map(transform)
      guard values.allSatisfy(\.isFinite) else { throw CraftError.invalid("Non-finite sparse raster result.") }
      if !values.allSatisfy({ $0.hasSameBits(as: value) }) {
        let tile = RasterTile(values),stored=try scratch?.append(tile) ?? tile
        if let indexBuilder {try indexBuilder.append(key:key,tile:stored)}else{output.tiles[key]=stored}
      }
    }
    if let indexBuilder {output.tiles=RasterTileMap(base:try indexBuilder.finish())}
    return output
  }
  public func combiningStoredSamples(
    with other: Surface, _ transform: (Pixel, Pixel) throws -> Pixel
  ) throws -> Surface {
    guard width == other.width, height == other.height, colorEncoding == other.colorEncoding else {
      throw CraftError.invalid("Sparse raster grids must agree.")
    }
    let value = try transform(storedDefaultPixel, other.storedDefaultPixel)
    guard value.isFinite else { throw CraftError.invalid("Non-finite sparse raster result.") }
    var output = try Surface(width: width, height: height, depth: .f32, colorEncoding: colorEncoding)
    output.storedDefaultPixel = value
    let scratch = width * height > Self.maximumDensePixels || mappedTileIndexBytes>0 ? try RasterTileStore() : nil
    let indexBuilder = scratch == nil ? nil:try RuntimeTileIndex.Builder()
    for key in tiles.unionKeys(with: other.tiles) {
      try Task.checkCancellation()
      let a = tiles[key], b = other.tiles[key]
      var values = [Pixel](); values.reserveCapacity(Self.tileSide * Self.tileSide)
      for i in 0..<Self.tileSide * Self.tileSide {
        let p = try transform(a?[i] ?? storedDefaultPixel, b?[i] ?? other.storedDefaultPixel)
        guard p.isFinite else { throw CraftError.invalid("Non-finite sparse raster result.") }
        values.append(p)
      }
      if !values.allSatisfy({ $0.hasSameBits(as: value) }) {
        let tile = RasterTile(values),stored=try scratch?.append(tile) ?? tile
        if let indexBuilder {try indexBuilder.append(key:key,tile:stored)}else{output.tiles[key]=stored}
      }
    }
    if let indexBuilder {output.tiles=RasterTileMap(base:try indexBuilder.finish())}
    return output
  }
  public func allStoredSamplesSatisfy(_ predicate: (Pixel) -> Bool) throws -> Bool {
    if tiles.count < columns * ((height + Self.tileSide - 1) / Self.tileSide), !predicate(storedDefaultPixel) { return false }
    for (key, tile) in tiles {
      try Task.checkCancellation()
      let x0 = key % columns * Self.tileSide, y0 = key / columns * Self.tileSide
      for y in 0..<min(Self.tileSide, height - y0) {
        for x in 0..<min(Self.tileSide, width - x0) where !predicate(tile[y * Self.tileSide + x]) { return false }
      }
    }
    return true
  }
  /// Area-filtered, bounded presentation. Implicit samples contribute analytically;
  /// only allocated source pixels are visited, including fractional boundary coverage.
  /// Operates in the stored color encoding and never changes working pixels.
  public func reducedPreview(in region: IntRect, width outWidth: Int, height outHeight: Int) throws -> Surface {
    try reducedPreview(in: region, width: outWidth, height: outHeight,
      encoding: colorEncoding, projection: nil)
  }
  /// Projects numeric channels before area reduction, ignoring source alpha when the
  /// projection supplies opaque coverage. Visits only intersecting allocated samples.
  public func reducedPreview(in region: IntRect, width outWidth: Int, height outHeight: Int,
    encoding: SurfaceColorEncoding, projectingStoredSamples projection: (Pixel) throws -> Pixel
  ) throws -> Surface {
    try withoutActuallyEscaping(projection) { project in
      try reducedPreview(in: region, width: outWidth, height: outHeight,
        encoding: encoding, projection: project)
    }
  }
  private func reducedPreview(in region: IntRect, width outWidth: Int, height outHeight: Int,
    encoding: SurfaceColorEncoding, projection: ((Pixel) throws -> Pixel)?
  ) throws -> Surface {
    try Task.checkCancellation()
    try validated()
    guard region.width > 0, region.height > 0,
      region == region.clipped(toWidth: width, height: height),
      outWidth > 0, outHeight > 0, outWidth <= region.width, outHeight <= region.height,
      outWidth <= 4_194_304 / outHeight else {
      throw CraftError.invalid("The bounded preview must contain at most4,194,304 pixels inside the source.")
    }
    if outWidth == region.width, outHeight == region.height {
      guard let projection else { return try cropped(to: region) }
      var result = try Surface(width: outWidth, height: outHeight, depth: .f32, colorEncoding: encoding)
      for y in 0..<outHeight {
        try Task.checkCancellation()
        for x in 0..<outWidth {
          let value = try projection(storedPixel(x: region.x + x, y: region.y + y))
          guard value.isFinite else { throw CraftError.invalid("Non-finite preview projection.") }
          result.setStoredPixel(x: x, y: y, value)
        }
      }
      return result
    }
    func pm(_ p: Pixel) -> SIMD4<Double> {
      SIMD4(Double(p.r) * Double(p.a), Double(p.g) * Double(p.a), Double(p.b) * Double(p.a), Double(p.a))
    }
    let sx = Double(region.width) / Double(outWidth), sy = Double(region.height) / Double(outHeight)
    let implicit = try projection?(storedDefaultPixel) ?? storedDefaultPixel
    guard implicit.isFinite else { throw CraftError.invalid("Non-finite preview projection.") }
    let area = sx * sy, background = pm(implicit)
    var sums = [SIMD4<Double>](repeating: background * area, count: outWidth * outHeight)
    for (key, tile) in tilesIntersecting(region) {
      try Task.checkCancellation()
      let left = key % columns * Self.tileSide, top = key / columns * Self.tileSide
      let x0 = max(region.x, left), y0 = max(region.y, top)
      let x1 = min(region.x + region.width, min(width, left + Self.tileSide))
      let y1 = min(region.y + region.height, min(height, top + Self.tileSide))
      guard x0 < x1, y0 < y1 else { continue }
      for y in y0..<y1 {
        let t = Double(y - region.y) / sy, b = Double(y + 1 - region.y) / sy
        for x in x0..<x1 {
          let stored = tile[(y - top) * Self.tileSide + x - left]
          let value = try projection?(stored) ?? stored
          guard value.isFinite else { throw CraftError.invalid("Non-finite preview projection.") }
          let delta = pm(value) - background
          if delta == .zero { continue }
          let l = Double(x - region.x) / sx, r = Double(x + 1 - region.x) / sx
          for oy in max(0, Int(floor(t)))..<min(outHeight, Int(ceil(b))) {
            let dy = (min(b, Double(oy + 1)) - max(t, Double(oy))) * sy
            for ox in max(0, Int(floor(l)))..<min(outWidth, Int(ceil(r))) {
              let dx = (min(r, Double(ox + 1)) - max(l, Double(ox))) * sx
              sums[oy * outWidth + ox] += delta * (dx * dy)
            }
          }
        }
      }
    }
    var result = try Surface(width: outWidth, height: outHeight, depth: .f32, colorEncoding: encoding)
    for y in 0..<outHeight {
      try Task.checkCancellation()
      for x in 0..<outWidth {
        let sum = sums[y * outWidth + x]
        let pixel = sum.w > 0 ? Pixel(Float(sum.x / sum.w), Float(sum.y / sum.w), Float(sum.z / sum.w), Float(min(1, max(0, sum.w / area)))) : .clear
        result.setStoredPixel(x: x, y: y, pixel)
      }
    }
    return result
  }
}


extension Surface {
  /// Exact premultiplied rectangle integral for sparse thumbnail footprints.
  public func sparseAreaSample(left: Double, top: Double, right: Double, bottom: Double,
    maximumSamples: Int) throws -> (pixel: Pixel, samples: Int) {
    let area = (right - left) * (bottom - top)
    guard [left, top, right, bottom].allSatisfy(\.isFinite), area > 0, maximumSamples >= 0 else { throw CraftError.invalid("Invalid preview footprint.") }
    let l = max(0, left), t = max(0, top), r = min(Double(width), right), b = min(Double(height), bottom)
    guard r > l, b > t else { return (.clear, 0) }
    func pm(_ p: Pixel) -> SIMD4<Double> { SIMD4(Double(p.r) * Double(p.a), Double(p.g) * Double(p.a), Double(p.b) * Double(p.a), Double(p.a)) }
    let background = pm(defaultPixel)
    var sum = background * ((r - l) * (b - t)), samples = 0
    let region=IntRect(x:Int(floor(l)),y:Int(floor(t)),width:Int(ceil(r))-Int(floor(l)),height:Int(ceil(b))-Int(floor(t)))
    for (key, tile) in tilesIntersecting(region) {
      try Task.checkCancellation()
      let tx = key % columns * Self.tileSide, ty = key / columns * Self.tileSide
      let x0 = max(tx, Int(floor(l))), y0 = max(ty, Int(floor(t)))
      let x1 = min(tx + Self.tileSide, Int(ceil(r))), y1 = min(ty + Self.tileSide, Int(ceil(b)))
      guard x1 > x0, y1 > y0 else { continue }
      let count = (x1 - x0) * (y1 - y0)
      guard count <= maximumSamples - samples else { throw CraftError.invalid("This thumbnail transform exceeds the preview sampling budget.") }
      samples += count
      for y in y0..<y1 {
        let dy = min(b, Double(y + 1)) - max(t, Double(y))
        for x in x0..<x1 {
          let dx = min(r, Double(x + 1)) - max(l, Double(x))
          sum += (pm(encodedSample(tile[(y - ty) * Self.tileSide + x - tx])) - background) * (dx * dy)
        }
      }
    }
    let pixel = sum.w > 0 ? Pixel(Float(sum.x / sum.w), Float(sum.y / sum.w), Float(sum.z / sum.w), Float(min(1, max(0, sum.w / area)))) : .clear
    return (pixel, samples)
  }
}


extension Surface {
  /// Spill owned samples without changing their bits or any retained snapshot.
  /// An I/O failure or cancellation leaves the input surface unchanged.
  public func spillingTiles(to store: RasterTileStore) throws -> Surface {
    try validated()
    var result = self
    for (key, tile) in tiles where !tile.isBacked {
      try Task.checkCancellation()
      result.tiles[key] = try store.append(tile)
    }
    try Task.checkCancellation()
    if result.mappedTileIndexBytes==0 && result.tileCount>=Self.pagedIndexMinimumTiles && result.mappedTileCount==result.tileCount {
      let index=try RuntimeTileIndex.Builder()
      for (key,tile) in result.tiles {try index.append(key:key,tile:tile)}
      result.tiles=RasterTileMap(base:try index.finish())
    }
    return result
  }
  /// Shares the existing numeric samples for a Float32 compositing backdrop.
  /// Every stored integer-depth sample is already exactly represented by Float.
  public func floatingStorageView() throws -> Surface {
    try validated()
    var result = try Surface(width: width, height: height, depth: .f32, colorEncoding: colorEncoding)
    result.storedDefaultPixel = storedDefaultPixel; result.tiles = tiles
    result.tilesAreKnownFinite = tilesAreKnownFinite
    return result
  }
  /// Import tile-aligned decoded patches without retaining a complete heap raster.
  /// Partial right/bottom tiles are accepted only at the document boundary.
  public mutating func importPatch(_ patch: Surface, atX: Int, atY: Int, backing: RasterTileStore) throws {
    guard patch.depth == depth, patch.colorEncoding == colorEncoding,
      atX >= 0, atY >= 0, atX % Self.tileSide == 0, atY % Self.tileSide == 0,
      patch.width <= width - atX, patch.height <= height - atY,
      patch.width % Self.tileSide == 0 || atX + patch.width == width,
      patch.height % Self.tileSide == 0 || atY + patch.height == height else {
      throw CraftError.invalid("Decoded patch must match the destination sample grid.")
    }
    try patch.validated(); var result = self
    let rows = (patch.height + Self.tileSide - 1) / Self.tileSide
    for row in 0..<rows { for column in 0..<patch.columns {
      try Task.checkCancellation()
      let sourceKey = row * patch.columns + column
      let destination = (row + atY / Self.tileSide) * columns + column + atX / Self.tileSide
      if let tile = patch.tiles[sourceKey] { result.tiles[destination] = try backing.append(tile) }
      else if patch.storedDefaultPixel.hasSameBits(as: storedDefaultPixel) { result.tiles[destination] = nil }
      else { result.tiles[destination] = try backing.append(RasterTile(repeating: patch.storedDefaultPixel, count: TileArchive.pixelCount)) }
    } }
    try Task.checkCancellation(); self = result
  }
}


extension Surface {
  private func tilesIntersecting(_ region: IntRect) -> AnySequence<(Int,RasterTile)> {
    let r=region.clipped(toWidth:width,height:height)
    guard r.width>0,r.height>0 else {return AnySequence(EmptyCollection<(Int,RasterTile)>())}
    let firstColumn=r.x/Self.tileSide,lastColumn=(r.x+r.width-1)/Self.tileSide
    let rows=r.y/Self.tileSide...(r.y+r.height-1)/Self.tileSide
    return AnySequence(rows.lazy.flatMap { row in tiles.entries(in:(row*columns+firstColumn)..<(row*columns+lastColumn+1)) })
  }
  /// One-pass, row-major bounded patch import. No complete heap descriptor map is built.
  public final class PagedBuilder {
    private let template:Surface
    private let backing:RasterTileStore
    private let index:RuntimeTileIndex.Builder
    private var lastVisited = -1,finished=false,failed=false
    public convenience init(width:Int,height:Int,depth:PixelDepth = .u8,fill:Pixel = .clear,
                colorEncoding:SurfaceColorEncoding = .sRGB,backing:RasterTileStore? = nil) throws {
      try self.init(template:Surface(width:width,height:height,depth:depth,fill:fill,colorEncoding:colorEncoding),backing:backing)
    }
    public init(template:Surface,backing:RasterTileStore? = nil) throws {
      guard template.tileCount==0 else {throw CraftError.invalid("Paged template must contain only an implicit value.")}
      try template.validated();self.template=template
      self.backing=try backing ?? RasterTileStore();index=try RuntimeTileIndex.Builder()
    }
    public func append(_ patch:Surface,atX:Int,atY:Int) throws {
      do {
        try Task.checkCancellation()
        guard !finished,!failed,patch.depth==template.depth,patch.colorEncoding==template.colorEncoding,
          atX>=0,atY>=0,atX%Surface.tileSide==0,atY%Surface.tileSide==0,
          patch.width<=template.width-atX,patch.height<=template.height-atY,
          patch.width%Surface.tileSide==0 || atX+patch.width==template.width,
          patch.height%Surface.tileSide==0 || atY+patch.height==template.height else {throw CraftError.invalid("Paged patches must match the destination grid and lifecycle.")}
        try patch.validated()
        for row in 0..<(patch.height+Surface.tileSide-1)/Surface.tileSide {
          for column in 0..<patch.columns {
            try Task.checkCancellation()
            let key=(row+atY/Surface.tileSide)*template.columns+column+atX/Surface.tileSide
            guard key>lastVisited else {throw CraftError.invalid("Paged import patches must be ordered and must not overlap.")}
            lastVisited=key
            let tile=patch.tiles[row*patch.columns+column] ?? (patch.storedDefaultPixel.hasSameBits(as:template.storedDefaultPixel) ? nil:RasterTile(repeating:patch.storedDefaultPixel,count:TileArchive.pixelCount))
            if let tile {try index.append(key:key,tile:tile.isBacked ? tile:backing.append(tile))}
          }
        }
      } catch {failed=true;throw error}
    }
    public func finish() throws -> Surface {
      do {
        try Task.checkCancellation();guard !finished,!failed else {throw CraftError.invalid("Paged import builder is no longer usable.")}
        let base=try index.finish();var result=template
        if base.count>=Surface.pagedIndexMinimumTiles {result.tiles=RasterTileMap(base:base)}
        else {for i in 0..<base.count {result.tiles[base.key(at:i)]=base.tile(at:i)}}
        result.tilesAreKnownFinite=true;try result.validated();finished=true;return result
      } catch {failed=true;throw error}
    }
  }
}

extension Surface {
  /// Grid-aligned owned patches share their Array COW values; no pixel re-encoding.
  mutating func importOwnedPatch(_ patch:Surface,atX:Int,atY:Int) throws {
    guard patch.depth==depth,patch.colorEncoding==colorEncoding,
      patch.storedDefaultPixel.hasSameBits(as:storedDefaultPixel),atX%64==0,atY%64==0,
      atX>=0,atY>=0,atX+patch.width<=width,atY+patch.height<=height else {throw CraftError.invalid("Invalid owned geometry patch.")}
    for (key,tile) in patch.tiles {
      tiles[(atY/64+key/patch.columns)*columns+atX/64+key%patch.columns]=tile
    }
  }
  func reframedImplicitValue(width:Int,height:Int) throws -> Surface {
    var output=try Surface(width:width,height:height,depth:depth,colorEncoding:colorEncoding)
    output.storedDefaultPixel=storedDefaultPixel;return output
  }
  /// Apply the ordinary setter once, preserving its depth/encoding/hidden-bit
  /// rules, then use that stored result as the implicit value of a new extent.
  func reframedImplicitValue(width:Int,height:Int,sample:Pixel,linear:Bool)throws->Surface {
    var probe=try reframedImplicitValue(width:1,height:1)
    if linear {probe.setLinearPixel(x:0,y:0,sample)}else{probe.setPixel(x:0,y:0,sample)}
    var output=try reframedImplicitValue(width:width,height:height)
    output.storedDefaultPixel=probe.storedPixel(x:0,y:0);return output
  }
  func projectedGeometrySupport(_ transform:Transform2D,bounds:IntRect,halo:Int) throws -> [IntRect] {
    var rectangles:[IntRect]=[];rectangles.reserveCapacity(tiles.count)
    for (key,_) in tiles {
      try Task.checkCancellation()
      let x=(key%columns)*64,y=(key/columns)*64
      let x0=Double(x-halo),y0=Double(y-halo),x1=Double(min(width,x+64)+halo),y1=Double(min(height,y+64)+halo)
      let points=[transform.point(x0,y0),transform.point(x1,y0),transform.point(x0,y1),transform.point(x1,y1)]
      let left=max(0,min(Double(bounds.width),floor(points.map(\.x).min()!)-Double(bounds.x)-1))
      let top=max(0,min(Double(bounds.height),floor(points.map(\.y).min()!)-Double(bounds.y)-1))
      let right=max(0,min(Double(bounds.width),ceil(points.map(\.x).max()!)-Double(bounds.x)+1))
      let bottom=max(0,min(Double(bounds.height),ceil(points.map(\.y).max()!)-Double(bounds.y)+1))
      if right>left,bottom>top {rectangles.append(IntRect(x:Int(left),y:Int(top),width:Int(right-left),height:Int(bottom-top)))}
    }
    return rectangles
  }
  /// Exact integer permutations retain raw/default bits and process only stored
  /// samples. Sparse candidates are bounded; dense indexes stream in key order.
  func permutingGrid(_ map:RasterGridMap,width:Int,height:Int) throws -> Surface {
    var output=try Surface(width:width,height:height,depth:depth,colorEncoding:colorEncoding)
    output.storedDefaultPixel=storedDefaultPixel
    guard tiles.count>0 else {return output}
    let paged=width*height>Self.maximumDensePixels || mappedBytes>0
    let backing=paged ? try RasterTileStore():nil,index=paged ? try RuntimeTileIndex.Builder():nil
    var candidates:Set<Int> = []
    let sparse=tiles.count<=RasterGeometry.sparseGridSourceTileLimit
    if sparse {
      for (key,_) in tiles {
        try Task.checkCancellation()
        let x=(key%columns)*64,y=(key/columns)*64
        let right=min(self.width-1,x+63),bottom=min(self.height-1,y+63)
        let points=[map.destination(x,y),map.destination(right,y),map.destination(x,bottom),map.destination(right,bottom)]
        let x0=points.map{$0.0}.min()!,x1=points.map{$0.0}.max()!,y0=points.map{$0.1}.min()!,y1=points.map{$0.1}.max()!
        for row in y0/64...y1/64 {for column in x0/64...x1/64 {candidates.insert(row*output.columns+column)}}
      }
    }
    let keys:AnySequence<Int> = sparse ? AnySequence(candidates.sorted()):AnySequence(0..<(output.columns*((height+63)/64)))
    for key in keys {
      try Task.checkCancellation()
      let x=(key%output.columns)*64,y=(key/output.columns)*64,w=min(64,width-x),h=min(64,height-y)
      let points=[map.source(x,y),map.source(x+w-1,y),map.source(x,y+h-1),map.source(x+w-1,y+h-1)]
      let x0=points.map{$0.0}.min()!,x1=points.map{$0.0}.max()!,y0=points.map{$0.1}.min()!,y1=points.map{$0.1}.max()!
      var sourceTiles:[Int:RasterTile]=[:]
      for row in y0/64...y1/64 {for column in x0/64...x1/64 {
        let k=row*columns+column;if let tile=tiles[k] {sourceTiles[k]=tile}
      }}
      guard !sourceTiles.isEmpty else {continue}
      var patch=try Surface(width:w,height:h,depth:depth,colorEncoding:colorEncoding)
      patch.storedDefaultPixel=storedDefaultPixel
      for py in 0..<h {for px in 0..<w {
        let (sx,sy)=map.source(x+px,y+py)
        let value=sourceTiles[(sy/64)*columns+sx/64]?[(sy%64)*64+sx%64] ?? storedDefaultPixel
        if !value.hasSameBits(as:storedDefaultPixel) {patch.setStoredPixel(x:px,y:py,value)}
      }}
      if let tile=patch.tiles[0] {
        if let index,let backing {try index.append(key:key,tile:backing.append(tile))}
        else {output.tiles[key]=tile}
      }
    }
    if let index {
      let base=try index.finish()
      if base.count>=Self.pagedIndexMinimumTiles {output.tiles=RasterTileMap(base:base)}
      else {for i in 0..<base.count {output.tiles[base.key(at:i)]=base.tile(at:i)}}
    }
    output.tilesAreKnownFinite=true;return output
  }
  /// Coloured canvas borders use an implicit majority value and shared constant
  /// tiles. Only rectangle boundaries need distinct samples; index writes stream.
  static func canvasExtension(width:Int,height:Int,depth:PixelDepth,color:Pixel,original:IntRect) throws -> Surface {
    _ = try Surface(width:width,height:height,depth:depth)
    guard color.isFinite else {throw CraftError.invalid("Invalid canvas extension colour.")}
    let hole=original.clipped(toWidth:width,height:height),value=color.quantized(depth)
    let paged=width*height>Self.maximumDensePixels
    let colorDefault=paged && hole.width*hole.height < width*height-hole.width*hole.height
    let implicit:Pixel=colorDefault ? value:.clear
    var output=try Surface(width:width,height:height,depth:depth,fill:implicit)
    let backing=paged ? try RasterTileStore():nil,index=paged ? try RuntimeTileIndex.Builder():nil
    var palette:RasterTile?
    let regions:[IntRect]
    if colorDefault {regions=[hole]}
    else {
      regions=[IntRect(x:0,y:0,width:width,height:hole.y),
        IntRect(x:0,y:hole.y+hole.height,width:width,height:height-hole.y-hole.height),
        IntRect(x:0,y:hole.y,width:hole.x,height:hole.height),
        IntRect(x:hole.x+hole.width,y:hole.y,width:width-hole.x-hole.width,height:hole.height)]
    }
    for row in 0..<(height+63)/64 {
      try Task.checkCancellation()
      var ranges:[Range<Int>]=[]
      for r in regions where r.width>0 && r.height>0 && row*64<r.y+r.height && row*64+64>r.y {
        ranges.append((r.x/64)..<((r.x+r.width+63)/64))
      }
      var next=0
      for range in ranges.sorted(by:{$0.lowerBound<$1.lowerBound}) {
        let low=max(next,range.lowerBound);guard low<range.upperBound else {continue}
        for column in low..<range.upperBound {
          let x=column*64,y=row*64,w=min(64,width-x),h=min(64,height-y),key=row*output.columns+column
          let overlapW=max(0,min(x+w,hole.x+hole.width)-max(x,hole.x))
          let overlapH=max(0,min(y+h,hole.y+hole.height)-max(y,hole.y))
          let area=overlapW*overlapH
          if (area==0 || area==w*h) && w==64 && h==64 {
            let p:Pixel=area==0 ? value:.clear
            if p.hasSameBits(as:implicit) {continue}
            if palette==nil {
              let tile=RasterTile(repeating:p,count:4096);palette=try backing?.append(tile) ?? tile
            }
            if let index {try index.append(key:key,tile:palette!)} else {output.tiles[key]=palette!}
          } else {
            var samples=RasterTile(repeating:implicit,count:4096)
            for py in 0..<h {for px in 0..<w {
              let inside=x+px>=hole.x && x+px<hole.x+hole.width && y+py>=hole.y && y+py<hole.y+hole.height
              samples[py*64+px]=inside ? .clear:value
            }}
            if let index,let backing {try index.append(key:key,tile:backing.append(samples))}
            else {output.tiles[key]=samples}
          }
        }
        next=max(next,range.upperBound)
      }
    }
    if let index {
      let base=try index.finish()
      if base.count>=Self.pagedIndexMinimumTiles {output.tiles=RasterTileMap(base:base)}
      else {for i in 0..<base.count {output.tiles[base.key(at:i)]=base.tile(at:i)}}
    }
    output.tilesAreKnownFinite=true;return output
  }
}

extension Surface {
  /// Quantize existing stored components without changing their sample encoding.
  /// Paged/implicit storage stays bounded; this is not a color-space conversion.
  func quantizedStoredDepth(_ depth: PixelDepth) throws -> Surface {
    let mapped = try mappedStoredSamples { $0.quantized(depth) }
    var output = try Surface(width: width, height: height, depth: depth,
      colorEncoding: colorEncoding)
    output.storedDefaultPixel = mapped.storedDefaultPixel
    output.tiles = mapped.tiles; output.tilesAreKnownFinite = mapped.tilesAreKnownFinite
    return output
  }
  /// Retag already quantized grayscale coverage without another sample round trip.
  func retaggedCoverageStorage(depth:PixelDepth = .u8)throws->Surface {
    var out=try Surface(width:width,height:height,depth:depth,fill:.black)
    out.storedDefaultPixel=storedDefaultPixel;out.tiles=tiles;out.tilesAreKnownFinite=tilesAreKnownFinite
    return out
  }
  func quantizedCoverageStorage()throws->Surface {
    let encoded=colorEncoding == .linearRGB ? try mappedStoredSamples(encoding:.sRGB) {SRGBTransfer.encoded($0)}:self
    let mapped=try encoded.mappedStoredSamples {p in let v=(unit(p.r)*255).rounded()/255;return Pixel(v,v,v)}
    return try mapped.retaggedCoverageStorage()
  }
  /// Exact bounds of nonzero GRAY8 samples. Missing tile ranges contribute
  /// analytically, including inverted/constant maximum-size selections.
  func scalarCoverageBounds()throws->IntRect? {
    try Task.checkCancellation()
    var x0=width,y0=height,x1=0,y1=0,found=false
    func include(_ a:Int,_ b:Int,_ c:Int,_ d:Int) {
      guard c>a,d>b else {return};found=true;x0=min(x0,a);y0=min(y0,b);x1=max(x1,c);y1=max(y1,d)
    }
    func implicit(_ start:Int,_ end:Int) {
      guard storedDefaultPixel.r>0,end>start else {return}
      let first=start/columns,last=(end-1)/columns
      if first==last {include(start%columns*Self.tileSide,first*Self.tileSide,min(width,((end-1)%columns+1)*Self.tileSide),min(height,(first+1)*Self.tileSide))}
      else {include(0,first*Self.tileSide,width,min(height,(last+1)*Self.tileSide))}
    }
    var previous=0
    for (key,tile) in tiles {
      try Task.checkCancellation();implicit(previous,key);previous=key+1
      let tx=key%columns*Self.tileSide,ty=key/columns*Self.tileSide
      for y in 0..<min(Self.tileSide,height-ty) {for x in 0..<min(Self.tileSide,width-tx) where tile[y*Self.tileSide+x].r>0 {include(tx+x,ty+y,tx+x+1,ty+y+1)}}
    }
    implicit(previous,columns*((height+Self.tileSide-1)/Self.tileSide))
    return found ? IntRect(x:x0,y:y0,width:x1-x0,height:y1-y0):nil
  }
  static func rectangularCoverage(width:Int,height:Int,rectangle:IntRect)throws->Surface {
    var out=try Surface(width:width,height:height,depth:.u8,fill:.black);let r=rectangle.clipped(toWidth:width,height:height)
    guard r.width>0,r.height>0 else {return out}
    if r.x==0,r.y==0,r.width==width,r.height==height {return try Surface(width:width,height:height,depth:.u8,fill:.white)}
    let scratch=width*height>maximumDensePixels ? try RasterTileStore():nil
    let index=scratch == nil ? nil:try RuntimeTileIndex.Builder()
    var patterns=[String:RasterTile]()
    for row in r.y/tileSide...(r.y+r.height-1)/tileSide {
      try Task.checkCancellation()
      for col in r.x/tileSide...(r.x+r.width-1)/tileSide {
        let ox=col*tileSide,oy=row*tileSide,l=max(0,r.x-ox),t=max(0,r.y-oy),right=min(tileSide,r.x+r.width-ox),bottom=min(tileSide,r.y+r.height-oy)
        let id="\(l),\(t),\(right),\(bottom)";let stored:RasterTile
        if let prior=patterns[id] {stored=prior}
        else {
          var pixels=[Pixel](repeating:.black,count:tileSide*tileSide)
          for y in t..<bottom {for x in l..<right {pixels[y*tileSide+x] = .white}}
          let tile=RasterTile(pixels);stored=try scratch?.append(tile) ?? tile
          patterns[id]=stored
        }
        let key=row*out.columns+col
        if let index {try index.append(key:key,tile:stored)}else {out.tiles[key]=stored}
      }
    }
    if let index {out.tiles=RasterTileMap(base:try index.finish())}
    return out
  }
}
