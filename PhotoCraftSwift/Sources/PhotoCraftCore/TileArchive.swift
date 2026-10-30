import Foundation
import zlib

/// Portable little-endian Float32 RGBA tiles. Compression never changes sample bits.
enum TileArchive {
  static let pixelCount = Surface.tileSide * Surface.tileSide
  static let byteCount = pixelCount * 16
  static func encodeSample(_ pixel: Pixel) -> Data {
    var bytes = Data()
    for value in [pixel.r, pixel.g, pixel.b, pixel.a] {
      let bits = value.bitPattern
      bytes.append(contentsOf: [
        UInt8(truncatingIfNeeded: bits), UInt8(truncatingIfNeeded: bits >> 8),
        UInt8(truncatingIfNeeded: bits >> 16), UInt8(truncatingIfNeeded: bits >> 24),
      ])
    }
    return bytes
  }
  static func decodeSample(_ data: Data) throws -> Pixel {
    guard data.count == 16 else { throw CraftError.invalid("Invalid default pixel storage.") }
    let pixel = data.withUnsafeBytes { bytes in
      func channel(_ offset: Int) -> Float {
        Float(
          bitPattern: UInt32(
            littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
      }
      return Pixel(channel(0), channel(4), channel(8), channel(12))
    }
    guard pixel.isFinite else { throw CraftError.invalid("Nonfinite default pixel.") }
    return pixel
  }
  static func encode(_ pixels: [Pixel]) throws -> Data {
    guard pixels.count == pixelCount, pixels.allSatisfy(\.isFinite) else {
      throw CraftError.invalid("Invalid raster tile.")
    }
    var raw = Data(count: byteCount)
    raw.withUnsafeMutableBytes { bytes in
      for (i, p) in pixels.enumerated() {
        bytes.storeBytes(of: p.r.bitPattern.littleEndian, toByteOffset: i * 16, as: UInt32.self)
        bytes.storeBytes(of: p.g.bitPattern.littleEndian, toByteOffset: i * 16 + 4, as: UInt32.self)
        bytes.storeBytes(of: p.b.bitPattern.littleEndian, toByteOffset: i * 16 + 8, as: UInt32.self)
        bytes.storeBytes(
          of: p.a.bitPattern.littleEndian, toByteOffset: i * 16 + 12, as: UInt32.self)
      }
    }
    var compressed = Data(count: Int(compressBound(uLong(byteCount))))
    var length = uLongf(compressed.count)
    let result = compressed.withUnsafeMutableBytes { output in
      raw.withUnsafeBytes { input in
        compress2(
          output.bindMemory(to: UInt8.self).baseAddress!, &length,
          input.bindMemory(to: UInt8.self).baseAddress!, uLong(byteCount), Z_BEST_SPEED)
      }
    }
    guard result == Z_OK else { throw CraftError.invalid("Native tile compression failed.") }
    if length < byteCount {
      var data = Data([1])
      data.append(compressed.prefix(Int(length)))
      return data
    }
    var data = Data([0])
    data.append(raw)
    return data
  }
  static func decode(_ data: Data) throws -> [Pixel] {
    try Decoder().decode(data)
  }
  /// One decode owns this workspace; reuse the inflation buffer across tiles.
  /// Returned arrays have independent value storage and never alias the workspace.
  final class Decoder {
    private var inflated = Data(count: byteCount)
    func decode(_ data: Data) throws -> [Pixel] {
      try Task.checkCancellation()
      guard !data.isEmpty, data.count <= byteCount + 1 else {
        throw CraftError.invalid("Invalid native tile size.")
      }
      switch data[data.startIndex] {
      case 0:
        guard data.count == byteCount + 1 else {
          throw CraftError.invalid("Truncated native tile.")
        }
        return try data.withUnsafeBytes {
          try pixels(UnsafeRawBufferPointer(rebasing: $0.dropFirst()))
        }
      case 1:
        var length = uLongf(byteCount)
        var consumed = uLong(data.count - 1)
        let result = inflated.withUnsafeMutableBytes { target in
          data.withUnsafeBytes { source in
            uncompress2(
              target.bindMemory(to: UInt8.self).baseAddress!, &length,
              source.bindMemory(to: UInt8.self).baseAddress!.advanced(by: 1), &consumed)
          }
        }
        guard result == Z_OK, length == byteCount, consumed == data.count - 1 else {
          throw CraftError.invalid("Corrupt, truncated or oversized native tile stream.")
        }
        return try inflated.withUnsafeBytes { try pixels($0) }
      default: throw CraftError.unsupported("Unsupported native tile compression.")
      }
    }
    private func pixels(_ bytes: UnsafeRawBufferPointer) throws -> [Pixel] {
      try Array(unsafeUninitializedCapacity: pixelCount) { buffer, initialized in
        for offset in stride(from: 0, to: byteCount, by: 16) {
          func channel(_ index: Int) -> Float {
            Float(
              bitPattern: UInt32(
                littleEndian: bytes.loadUnaligned(
                  fromByteOffset: offset + index * 4, as: UInt32.self)))
          }
          let pixel = Pixel(channel(0), channel(1), channel(2), channel(3))
          guard pixel.isFinite else { throw CraftError.invalid("Nonfinite native tile samples.") }
          buffer.baseAddress!.advanced(by: initialized).initialize(to: pixel)
          initialized += 1
        }
      }
    }
  }
}

extension CodingUserInfoKey {
  static let rasterDecodeBudget = CodingUserInfoKey(rawValue: "Photato.RasterDecodeBudget")!
}
/// Shared by all surfaces in one decode; reserve before expanding any tiles.
final class RasterDecodeBudget {
  private let limit: Int
  private var remaining: Int
  init(bytes: Int) { limit = bytes; remaining = bytes }
  func reserve(tiles: Int) throws {
    guard tiles >= 0, tiles <= Int.max / TileArchive.byteCount else {
      throw CraftError.invalid("Invalid native raster allocation.")
    }
    try reserve(bytes: tiles * TileArchive.byteCount)
  }
  func reserveMappedReferences(tiles: Int) throws {
    guard tiles >= 0, tiles <= Int.max / 128 else { throw CraftError.invalid("Invalid mapped tile index allocation.") }
    try reserve(bytes: tiles * 128)
  }
  private func reserve(bytes: Int) throws {
    guard bytes <= remaining else {
      let required = (limit - remaining).addingReportingOverflow(bytes)
      throw NativeArchiveMemoryLimit.raster(
        requiredBytes: required.overflow ? Int.max : required.partialValue, limitBytes: limit)
    }
    remaining -= bytes
  }
}
