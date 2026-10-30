import Foundation
import PhotoCraftCore
import zlib

/// Recompresses only the IDAT stream of our ImageIO output. Filtered sample bytes,
/// Adam7 ordering and all non-IDAT chunks remain untouched. The intermediate
/// uncompressed image is streamed through two 64 KiB buffers.
enum PNGCompression {
  static func rewrite(_ input: Data, level: Int) throws -> Data {
    guard (0...9).contains(level),
      input.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
      throw CraftError.invalid("Invalid PNG compression request.")
    }
    var chunks: [(type: String, whole: Range<Int>, payload: Range<Int>)] = []
    var offset = 8, seenData = false, endedData = false
    func number(_ at: Int) -> Int {
      input[at..<(at + 4)].reduce(0) { ($0 << 8) | Int($1) }
    }
    while offset < input.count {
      try Task.checkCancellation()
      guard input.count - offset >= 12 else { throw CraftError.invalid("Truncated PNG chunk.") }
      let count = number(offset)
      guard count <= input.count - offset - 12 else { throw CraftError.invalid("Invalid PNG chunk length.") }
      let end = offset + count + 12
      let type = String(decoding: input[(offset + 4)..<(offset + 8)], as: UTF8.self)
      let crc = checksum(input[(offset + 4)..<(end - 4)])
      guard crc == UInt32(number(end - 4)) else { throw CraftError.invalid("PNG checksum mismatch.") }
      if type == "IDAT" {
        guard !endedData else { throw CraftError.invalid("Noncontiguous PNG image data.") }
        seenData = true
      } else if seenData { endedData = true }
      chunks.append((type, offset..<end, (offset + 8)..<(end - 4)))
      offset = end
      if type == "IEND" { break }
    }
    guard offset == input.count, chunks.first?.type == "IHDR",
      chunks.first?.payload.count == 13, chunks.last?.type == "IEND",
      chunks.last?.payload.isEmpty == true, seenData else {
      throw CraftError.invalid("Incomplete PNG image.")
    }
    let h = chunks[0].payload.lowerBound
    let width = number(h), height = number(h + 4), bits = Int(input[h + 8])
    let channels: Int
    switch input[h + 9] {
    case 0: channels = 1
    case 2: channels = 3
    case 3: channels = 1
    case 4: channels = 2
    case 6: channels = 4
    default: throw CraftError.invalid("Unsupported PNG sample layout.")
    }
    guard width > 0, height > 0, width <= Surface.maxDimension,
      height <= Surface.maxDimension, width <= Surface.maximumDensePixels / height,
      [1, 2, 4, 8, 16].contains(bits), input[h + 10] == 0, input[h + 11] == 0,
      input[h + 12] <= 1 else { throw CraftError.invalid("Invalid PNG geometry.") }
    let passes = input[h + 12] == 0 ? [(0, 0, 1, 1)] :
      [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
       (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
    var expected = 0
    for (x, y, dx, dy) in passes where width > x && height > y {
      let w = (width - x + dx - 1) / dx, rows = (height - y + dy - 1) / dy
      expected += ((w * channels * bits + 7) / 8 + 1) * rows
    }
    let transcode = try PNGDeflateTranscoder(level: level, expectedBytes: expected)
    for chunk in chunks where chunk.type == "IDAT" { try transcode.append(input[chunk.payload]) }
    let compressed = try transcode.finish()
    var output = Data(input.prefix(8)), written = false
    for chunk in chunks {
      if chunk.type == "IDAT" {
        if !written {
          for start in stride(from: 0, to: compressed.count, by: 64 * 1024) {
            try Task.checkCancellation()
            let payload = compressed[start..<min(compressed.count, start + 64 * 1024)]
            appendNumber(UInt32(payload.count), to: &output)
            let body = Data("IDAT".utf8) + payload
            output.append(body); appendNumber(checksum(body), to: &output)
          }
          written = true
        }
      } else { output.append(input[chunk.whole]) }
    }
    return output
  }
  private static func appendNumber(_ value: UInt32, to data: inout Data) {
    var number = value.bigEndian
    withUnsafeBytes(of: &number) { data.append(contentsOf: $0) }
  }
  private static func checksum(_ data: Data) -> UInt32 {
    data.withUnsafeBytes { UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count))) }
  }
}

private final class PNGDeflateTranscoder {
  private var decoder = z_stream(), encoder = z_stream()
  private let expected: Int
  private var decoded = 0, finished = false
  private var result = Data()
  init(level: Int, expectedBytes: Int) throws {
    expected = expectedBytes
    guard inflateInit_(&decoder, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      throw CraftError.invalid("PNG decompressor initialization failed.")
    }
    guard deflateInit_(&encoder, Int32(level), ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      inflateEnd(&decoder)
      throw CraftError.invalid("PNG compressor initialization failed.")
    }
  }
  deinit { inflateEnd(&decoder); deflateEnd(&encoder) }
  func append(_ input: Data) throws {
    guard !finished || input.isEmpty else { throw CraftError.invalid("Trailing PNG compressed data.") }
    if input.isEmpty { return }
    try input.withUnsafeBytes { source in
      decoder.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
      decoder.avail_in = uInt(source.count)
      defer { decoder.next_in = nil; decoder.avail_in = 0 }
      var buffer = [UInt8](repeating: 0, count: 64 * 1024)
      while decoder.avail_in > 0 || decoder.avail_out == 0 {
        try Task.checkCancellation()
        let before = decoder.avail_in
        let (status, bytes) = buffer.withUnsafeMutableBufferPointer { destination in
          decoder.next_out = destination.baseAddress; decoder.avail_out = uInt(destination.count)
          let status = inflate(&decoder, Z_NO_FLUSH)
          return (status, destination.count - Int(decoder.avail_out))
        }
        decoder.next_out = nil
        if status == Z_BUF_ERROR && before == 0 && bytes == 0 { break }
        guard status == Z_OK || status == Z_STREAM_END, bytes <= expected - decoded else {
          throw CraftError.invalid("Invalid or excessive PNG image stream.")
        }
        decoded += bytes
        try compress(Data(buffer.prefix(bytes)), flush: Z_NO_FLUSH)
        if status == Z_STREAM_END {
          guard decoder.avail_in == 0 else { throw CraftError.invalid("Trailing PNG image stream.") }
          finished = true; break
        }
        guard bytes > 0 || decoder.avail_in < before else {
          throw CraftError.invalid("PNG decompression made no progress.")
        }
      }
    }
  }
  func finish() throws -> Data {
    guard finished, decoded == expected else { throw CraftError.invalid("Incomplete PNG sample stream.") }
    try compress(Data(), flush: Z_FINISH)
    return result
  }
  private func compress(_ data: Data, flush: Int32) throws {
    if data.isEmpty && flush == Z_NO_FLUSH { return }
    try data.withUnsafeBytes { source in
      encoder.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
      encoder.avail_in = uInt(source.count)
      defer { encoder.next_in = nil; encoder.avail_in = 0 }
      var buffer = [UInt8](repeating: 0, count: 64 * 1024)
      repeat {
        try Task.checkCancellation()
        let before = encoder.avail_in
        let (status, bytes) = buffer.withUnsafeMutableBufferPointer { destination in
          encoder.next_out = destination.baseAddress; encoder.avail_out = uInt(destination.count)
          let status = deflate(&encoder, flush)
          return (status, destination.count - Int(encoder.avail_out))
        }
        encoder.next_out = nil
        guard status == Z_OK || status == Z_STREAM_END else {
          throw CraftError.invalid("PNG compression failed.")
        }
        result.append(contentsOf: buffer.prefix(bytes))
        if status == Z_STREAM_END || (flush == Z_NO_FLUSH && encoder.avail_in == 0 && encoder.avail_out > 0) { break }
        guard bytes > 0 || encoder.avail_in < before else {
          throw CraftError.invalid("PNG compression made no progress.")
        }
      } while true
    }
  }
}
