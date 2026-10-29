import Foundation
import PhotoCraftCore
import zlib

/// One decoded scanline at a time. Source sections view memory or a file-backed
/// input; ZIP keeps only a 64 KiB input window, zlib state and the requested row.
/// The document/tile/file budgets still apply independently of this scratch space.
final class PSDChannelReader {
  private var source: PSDReader
  private var lengths: PSDReader?
  private let rowLengthBytes: Int
  private let rowBytes: Int
  private let width: Int
  private let depth: Int
  private let compression: Int
  private var zip: PSDZIPReader?
  private(set) var remainingRows: Int

  init(
    _ source: PSDReader, width: Int, height: Int, depth: Int, channels: Int = 1,
    format: PSDFileFormat = .psd
  ) throws {
    let expected = try PSDChannelCodec.byteCount(
      width: width, height: height, depth: depth, channels: channels)
    self.source = source
    self.width = width
    self.depth = depth
    rowBytes = width * (depth / 8)
    remainingRows = height * channels
    rowLengthBytes = format.rowLengthBytes
    compression = try self.source.u16()
    switch compression {
    case 0: break
    case 1:
      lengths = try self.source.view(remainingRows * rowLengthBytes)
    case 2, 3:
      zip = try PSDZIPReader(self.source, expected: expected)
    default:
      throw CraftError.unsupported("Unknown PSD channel compression \(compression).")
    }
  }

  func nextRow() throws -> [UInt8] {
    guard remainingRows > 0 else {
      throw CraftError.invalid("No remaining PSD channel rows.")
    }
    var row: [UInt8]
    switch compression {
    case 0:
      row = Array(try source.bytes(rowBytes))
    case 1:
      let length = try lengths!.length(rowLengthBytes)
      row = try PSDCodec.decodePackBits(source.view(length), expected: rowBytes)
    default:
      row = try zip!.read(rowBytes)
      if compression == 3 {
        PSDChannelCodec.predict(&row, width: width, depth: depth, decode: true)
      }
    }
    remainingRows -= 1
    if remainingRows == 0 {
      if let zip {
        try zip.finish()
      } else if source.remaining != 0 {
        throw CraftError.invalid("Unexpected PSD channel bytes.")
      }
    }
    return row
  }

  /// Validate even unused caches/channels, without allocating their full output.
  func discardRemaining() throws {
    while remainingRows > 0 { _ = try nextRow() }
  }
}

/// Incremental zlib reader with exact input/output, checksum and end-marker
/// validation. No pointer into Data/Array escapes its withUnsafe* scope.
final class PSDZIPReader {
  static let inputChunkBytes = 64 * 1024
  private var source: PSDReader
  private var input = Data()
  private var inputOffset = 0
  private var stream = z_stream()
  private var initialized = false
  private var ended = false
  private var decoded = 0
  private let expected: Int

  init(_ source: PSDReader, expected: Int) throws {
    guard expected > 0, expected <= PSDChannelCodec.byteLimit,
      source.remaining > 0, source.remaining <= PSDChannelCodec.byteLimit
    else { throw CraftError.invalid("Invalid PSD ZIP size.") }
    self.source = source
    self.expected = expected
    guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      throw CraftError.invalid("Cannot initialize PSD ZIP decoder.")
    }
    initialized = true
  }

  deinit {
    if initialized { inflateEnd(&stream) }
  }

  func read(_ count: Int) throws -> [UInt8] {
    guard count > 0, count <= expected - decoded else {
      throw CraftError.invalid("PSD ZIP output exceeds its declared size.")
    }
    var output = [UInt8](repeating: 0, count: count)
    var offset = 0
    while offset < count && !ended { offset += try pump(into: &output, at: offset) }
    guard offset == count else {
      throw CraftError.invalid("Truncated PSD ZIP output.")
    }
    decoded += count
    return output
  }

  func finish() throws {
    guard decoded == expected else {
      throw CraftError.invalid("Incomplete PSD ZIP output.")
    }
    // zlib may still need to read the checksum after the final output byte.
    // A one-byte sentinel detects an oversized stream without expanding it.
    var sentinel: [UInt8] = [0]
    while !ended {
      guard try pump(into: &sentinel, at: 0) == 0 else {
        throw CraftError.invalid("Oversized PSD ZIP output.")
      }
    }
    guard source.remaining == 0, inputOffset == input.count else {
      throw CraftError.invalid("Unexpected bytes after PSD ZIP stream.")
    }
  }

  private func pump(into output: inout [UInt8], at offset: Int) throws -> Int {
    if inputOffset == input.count && source.remaining > 0 {
      input = try source.bytes(min(Self.inputChunkBytes, source.remaining))
      inputOffset = 0
    }
    let available = input.count - inputOffset
    let capacity = output.count - offset
    var consumed = 0
    var produced = 0
    let status = input.withUnsafeBytes { bytes in
      output.withUnsafeMutableBufferPointer { target in
        stream.next_in = UnsafeMutablePointer(
          mutating: bytes.bindMemory(to: UInt8.self).baseAddress?.advanced(by: inputOffset))
        stream.avail_in = uInt(available)
        stream.next_out = target.baseAddress!.advanced(by: offset)
        stream.avail_out = uInt(capacity)
        let result = zlib.inflate(&stream, Z_NO_FLUSH)
        consumed = available - Int(stream.avail_in)
        produced = capacity - Int(stream.avail_out)
        stream.next_in = nil
        stream.next_out = nil
        return result
      }
    }
    inputOffset += consumed
    guard status == Z_OK || status == Z_STREAM_END,
      consumed > 0 || produced > 0 || status == Z_STREAM_END
    else { throw CraftError.invalid("Corrupt or truncated PSD ZIP stream.") }
    ended = status == Z_STREAM_END
    return produced
  }
}
