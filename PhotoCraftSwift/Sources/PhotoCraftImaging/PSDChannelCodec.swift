import Foundation
import PhotoCraftCore
import zlib

/// Native Swift PSD sample layout and prediction, using macOS's zlib for DEFLATE.
/// Prediction follows PhotoCraft crates/psd/src/compression.rs (MIT OR Apache-2.0).
enum PSDChannelCodec {
  static let byteLimit = 512 * 1024 * 1024
  static func byteCount(width: Int, height: Int, depth: Int, channels: Int) throws -> Int {
    guard [8, 16, 32].contains(depth), (1...4).contains(channels),
      width > 0, height > 0, width <= Surface.maxDimension, height <= Surface.maxDimension,
      width <= Surface.maxPixels / height
    else {
      throw CraftError.invalid("Invalid PSD channel geometry.")
    }
    let count = width * height * (depth / 8) * channels
    guard count <= byteLimit else {
      throw CraftError.invalid("PSD channel data exceeds the memory budget.")
    }
    return count
  }
  static func decode(_ data: Data, width: Int, height: Int, depth: Int, channels: Int = 1) throws
    -> [UInt8]
  {
    let expected = try byteCount(width: width, height: height, depth: depth, channels: channels)
    let rowBytes = width * (depth / 8)
    var r = PSDReader(data: data)
    let compression = try r.u16()
    var output: [UInt8]
    switch compression {
    case 0:
      output = Array(try r.bytes(expected))
    case 1:
      var lengths: [Int] = []
      for _ in 0..<height * channels { lengths.append(try r.u16()) }
      output = []
      output.reserveCapacity(expected)
      for length in lengths {
        output.append(contentsOf: try PSDCodec.decodePackBits(r.bytes(length), expected: rowBytes))
      }
    case 2, 3:
      output = try inflate(r.bytes(r.remaining), expected: expected)
      if compression == 3 { predict(&output, width: width, depth: depth, decode: true) }
    default: throw CraftError.unsupported("Unknown PSD channel compression \(compression).")
    }
    guard r.remaining == 0 else { throw CraftError.invalid("Unexpected PSD channel bytes.") }
    return output
  }
  static func encode(
    _ bytes: [UInt8], width: Int, height: Int, depth: Int, compression: PSDCompression
  ) throws -> Data {
    guard bytes.count == (try byteCount(width: width, height: height, depth: depth, channels: 1))
    else {
      throw CraftError.invalid("PSD channel size does not match its geometry.")
    }
    var output = PSDWriter()
    output.n(compression.rawValue, 2)
    if compression == .raw {
      output.data.append(contentsOf: bytes)
    } else {
      var encoded = bytes
      if compression == .zipPrediction {
        predict(&encoded, width: width, depth: depth, decode: false)
      }
      var count = compressBound(uLong(encoded.count))
      var packed = [UInt8](repeating: 0, count: Int(count))
      let status = packed.withUnsafeMutableBufferPointer { target in
        encoded.withUnsafeBufferPointer { source in
          compress2(
            target.baseAddress!, &count, source.baseAddress!, uLong(encoded.count),
            Z_DEFAULT_COMPRESSION)
        }
      }
      guard status == Z_OK else { throw CraftError.invalid("PSD ZIP compression failed.") }
      output.data.append(contentsOf: packed.prefix(Int(count)))
    }
    return output.data
  }
  /// Require exactly the declared output and all compressed input, including checksum.
  static func inflate(_ data: Data, expected: Int) throws -> [UInt8] {
    guard expected > 0, expected <= byteLimit, !data.isEmpty, data.count <= byteLimit else {
      throw CraftError.invalid("Invalid PSD ZIP size.")
    }
    var output = [UInt8](repeating: 0, count: expected)
    var size = uLongf(expected)
    var consumed = uLong(data.count)
    let result = output.withUnsafeMutableBufferPointer { target in
      data.withUnsafeBytes { source in
        uncompress2(
          target.baseAddress!, &size, source.bindMemory(to: UInt8.self).baseAddress!, &consumed)
      }
    }
    guard result == Z_OK, size == expected, consumed == data.count else {
      throw CraftError.invalid("Corrupt, truncated or oversized PSD ZIP stream.")
    }
    return output
  }
  private static func predict(_ bytes: inout [UInt8], width: Int, depth: Int, decode: Bool) {
    let rowBytes = width * (depth / 8)
    var scratch = [UInt8](repeating: 0, count: depth == 32 ? rowBytes : 0)
    for start in stride(from: 0, to: bytes.count, by: rowBytes) {
      if depth == 16 {
        for x in stride(from: decode ? 1 : width - 1, to: decode ? width : 0, by: decode ? 1 : -1) {
          let at = start + 2 * x
          let a = UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
          let b = UInt16(bytes[at - 2]) << 8 | UInt16(bytes[at - 1])
          let value = decode ? a &+ b : a &- b
          bytes[at] = UInt8(value >> 8)
          bytes[at + 1] = UInt8(truncatingIfNeeded: value)
        }
      } else {
        if depth == 32 && !decode {
          for x in 0..<width {
            for k in 0..<4 { scratch[k * width + x] = bytes[start + x * 4 + k] }
          }
          bytes.replaceSubrange(start..<start + rowBytes, with: scratch)
        }
        for x in stride(
          from: decode ? 1 : rowBytes - 1, to: decode ? rowBytes : 0, by: decode ? 1 : -1)
        {
          bytes[start + x] =
            decode
            ? bytes[start + x] &+ bytes[start + x - 1] : bytes[start + x] &- bytes[start + x - 1]
        }
        if depth == 32 && decode {
          for x in 0..<width {
            for k in 0..<4 { scratch[x * 4 + k] = bytes[start + k * width + x] }
          }
          bytes.replaceSubrange(start..<start + rowBytes, with: scratch)
        }
      }
    }
  }
  static func sample(_ bytes: [UInt8], _ index: Int, depth: Int) throws -> Float {
    switch depth {
    case 8: return Float(bytes[index]) / 255
    case 16: return Float(UInt16(bytes[2 * index]) << 8 | UInt16(bytes[2 * index + 1])) / 65535
    default:
      let at = index * 4
      let bits =
        UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8
        | UInt32(bytes[at + 3])
      let sample = Float(bitPattern: bits)
      guard sample.isFinite else {
        throw CraftError.invalid("Non-finite PSD floating-point sample.")
      }
      return sample
    }
  }
  static func append(_ sample: Float, depth: Int, to bytes: inout [UInt8]) throws {
    guard sample.isFinite else {
      throw CraftError.invalid("PSD sample exceeds its finite numeric range.")
    }
    switch depth {
    case 8: bytes.append(UInt8((unit(sample) * 255).rounded()))
    case 16:
      let n = UInt16((unit(sample) * 65535).rounded())
      bytes.append(contentsOf: [UInt8(n >> 8), UInt8(truncatingIfNeeded: n)])
    default:
      let n = sample.bitPattern
      bytes.append(contentsOf: [
        UInt8(n >> 24), UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 8),
        UInt8(truncatingIfNeeded: n),
      ])
    }
  }
}

public enum PSDCompression: Int, CaseIterable, Sendable {
  case raw = 0
  case zip = 2
  case zipPrediction = 3
}
