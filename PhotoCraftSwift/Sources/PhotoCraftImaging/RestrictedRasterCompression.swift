import Foundation
import PhotoCraftCore
import zlib

enum RestrictedRasterCompression {
  static func deflate(_ input: Data, level: Int = 6) throws -> Data {
    try Task.checkCancellation()
    guard !input.isEmpty, input.count <= PSDCodec.maximumInputBytes, (0...9).contains(level) else {
      throw CraftError.invalid("Invalid restricted raster compression input.")
    }
    var length = compressBound(uLong(input.count)), result = Data(count: Int(compressBound(uLong(input.count))))
    let status = result.withUnsafeMutableBytes { out in input.withUnsafeBytes { source in
      compress2(out.bindMemory(to: Bytef.self).baseAddress!, &length,
        source.bindMemory(to: Bytef.self).baseAddress!, uLong(input.count), Int32(level))
    } }
    guard status == Z_OK else { throw CraftError.invalid("Raster compression failed.") }
    result.count = Int(length); try Task.checkCancellation(); return result
  }
  static func inflate(_ input: Data, limit: Int, expected: Int? = nil) throws -> Data {
    guard !input.isEmpty, input.count <= PSDCodec.maximumInputBytes, limit > 0, limit <= PSDCodec.maximumInputBytes else {
      throw CraftError.invalid("Invalid restricted raster decompression size.")
    }
    var stream = z_stream()
    guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      throw CraftError.invalid("Raster decompressor initialization failed.")
    }
    defer { inflateEnd(&stream) }
    return try input.withUnsafeBytes { source in
      stream.next_in = UnsafeMutablePointer(mutating: source.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(input.count)
      var result = Data(), buffer = [UInt8](repeating: 0, count: 65536)
      while true {
        try Task.checkCancellation(); let before = stream.avail_in
        let status = buffer.withUnsafeMutableBufferPointer { target in
          stream.next_out = target.baseAddress; stream.avail_out = uInt(target.count)
          return zlib.inflate(&stream, Z_NO_FLUSH)
        }
        stream.next_out = nil
        let count = buffer.count - Int(stream.avail_out)
        guard count <= limit - result.count, status == Z_OK || status == Z_STREAM_END else {
          throw CraftError.invalid("Invalid or excessive compressed raster data.")
        }
        result.append(contentsOf: buffer.prefix(count))
        if status == Z_STREAM_END {
          guard stream.avail_in == 0, expected == nil || result.count == expected else {
            throw CraftError.invalid("Compressed raster size or trailing bytes differ.")
          }; return result
        }
        guard count > 0 || stream.avail_in < before else { throw CraftError.invalid("Truncated compressed raster data.") }
      }
    }
  }
}
