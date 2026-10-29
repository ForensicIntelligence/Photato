import Foundation
import PhotoCraftCore
import zlib

/// Encodes one sample row at a time, retaining no full uncompressed/compressed plane.
/// Z_NO_FLUSH preserves a single zlib stream, including its final checksum.
enum PSDChannelWriter {
  static func write(
    width: Int, height: Int, depth: Int, compression: PSDCompression,
    channels: Int = 1, format: PSDFileFormat = .psd,
    to output: PSDOutput, row: (Int) throws -> [UInt8]
  ) throws {
    _ = try PSDChannelCodec.byteCount(width: width, height: height, depth: depth, channels: channels)
    try output.n(compression.rawValue, 2)
    let table = output.count
    if compression == .rle {
      try output.append(Data(count: height * channels * format.rowLengthBytes))
    }
    let zip = compression == .zip || compression == .zipPrediction ? try PSDZIPWriter(output) : nil
    for y in 0..<(height * channels) {
      try Task.checkCancellation()
      var bytes = try row(y)
      guard bytes.count == width * (depth / 8) else {
        throw CraftError.invalid("PSD output row size does not match its geometry.")
      }
      if compression == .zipPrediction {
        PSDChannelCodec.predict(&bytes, width: width, depth: depth, decode: false)
      }
      if compression == .rle {
        let packed = try PSDPackBits.encode(bytes)
        guard format == .psb || packed.count <= Int(UInt16.max) else {
          throw CraftError.unsupported("An RLE row exceeds the PSD limit. Use PSB or another compression method.")
        }
        try output.patchLength(packed.count, at: table + y * format.rowLengthBytes, width: format.rowLengthBytes)
        try output.append(packed)
      } else if let zip { try zip.append(bytes) } else { try output.append(Data(bytes)) }
    }
    try zip?.finish()
  }
}

private final class PSDZIPWriter {
  private var stream = z_stream()
  private let output: PSDOutput
  private var buffer = [UInt8](repeating: 0, count: 64 * 1024)
  init(_ output: PSDOutput) throws {
    self.output = output
    let status = deflateInit_(
      &stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    guard status == Z_OK else { throw CraftError.invalid("PSD ZIP initialization failed.") }
  }
  deinit { deflateEnd(&stream) }
  func append(_ bytes: [UInt8]) throws {
    try bytes.withUnsafeBufferPointer { source in
      stream.next_in = UnsafeMutablePointer(mutating: source.baseAddress)
      stream.avail_in = uInt(source.count)
      defer {
        stream.next_in = nil
        stream.avail_in = 0
      }
      repeat {
        let before = stream.avail_in
        let (status, produced) = try pump(Z_NO_FLUSH)
        guard status == Z_OK || (status == Z_BUF_ERROR && stream.avail_in == 0) else {
          throw CraftError.invalid("PSD ZIP compression failed.")
        }
        if stream.avail_in == 0 && stream.avail_out > 0 { break }
        guard produced > 0 || stream.avail_in < before else {
          throw CraftError.invalid("PSD ZIP compression made no progress.")
        }
      } while true
    }
  }
  func finish() throws {
    while true {
      let (status, produced) = try pump(Z_FINISH)
      if status == Z_STREAM_END { return }
      guard status == Z_OK, produced > 0 else {
        throw CraftError.invalid("PSD ZIP finalization failed.")
      }
    }
  }
  private func pump(_ flush: Int32) throws -> (Int32, Int) {
    try Task.checkCancellation()
    let status = buffer.withUnsafeMutableBufferPointer { target in
      stream.next_out = target.baseAddress
      stream.avail_out = uInt(target.count)
      defer { stream.next_out = nil }
      return deflate(&stream, flush)
    }
    let produced = buffer.count - Int(stream.avail_out)
    if produced > 0 { try output.append(Data(buffer.prefix(produced))) }
    return (status, produced)
  }
}
