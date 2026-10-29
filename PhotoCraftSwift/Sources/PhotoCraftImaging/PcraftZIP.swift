import Foundation
import PhotoCraftCore
import zlib

/// Bounded in-memory original-project container. Entries are returned as bytes;
/// paths are never extracted into the filesystem. ZIP64/encryption are unsupported.
struct PcraftZIP {
  struct Entry {
    let name: String
    let method: Int
    let checksum: UInt32
    let decodedSize: Int
    let range: Range<Int>
  }
  private let data: Data
  let entries: [String: Entry]
  static let maximumArchiveBytes = 512 * 1024 * 1024
  static let maximumEntryBytes = 256 * 1024 * 1024

  init(_ data: Data) throws {
    try Task.checkCancellation()
    guard (22...Self.maximumArchiveBytes).contains(data.count) else {
      throw CraftError.invalid("PhotoCraft ZIP size is unsupported.")
    }
    let data = Data(data) // Normalize sliced Data indices.
    func number(_ at: Int, _ count: Int) throws -> Int {
      guard at >= 0, count <= data.count - at else { throw CraftError.invalid("Truncated PhotoCraft ZIP.") }
      var value = 0
      for i in 0..<count { value |= Int(data[at + i]) << (i * 8) }
      return value
    }
    var end: Int?
    for at in stride(from: data.count - 22, through: max(0, data.count - 22 - 65535), by: -1) {
      if try number(at, 4) == 0x06054b50, try at + 22 + number(at + 20, 2) == data.count {
        end = at; break
      }
    }
    guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0,
      try number(end + 8, 2) == number(end + 10, 2) else {
      throw CraftError.invalid("Invalid or multi-disk PhotoCraft ZIP.")
    }
    let count = try number(end + 10, 2), centralSize = try number(end + 12, 4)
    let centralStart = try number(end + 16, 4)
    guard count < 65535, centralStart <= end, centralSize == end - centralStart else {
      throw CraftError.invalid("Invalid or ZIP64 PhotoCraft directory.")
    }
    var at = centralStart, entries: [String: Entry] = [:], ranges: [Range<Int>] = []
    var totalDecoded = 0
    for _ in 0..<count {
      try Task.checkCancellation()
      guard at <= end - 46, try number(at, 4) == 0x02014b50 else {
        throw CraftError.invalid("Invalid PhotoCraft ZIP directory entry.")
      }
      let flags = try number(at + 8, 2), method = try number(at + 10, 2)
      let crc = UInt32(try number(at + 16, 4))
      let compressed = try number(at + 20, 4), decoded = try number(at + 24, 4)
      let nameCount = try number(at + 28, 2), extra = try number(at + 30, 2), comment = try number(at + 32, 2)
      let local = try number(at + 42, 4), attributes = try number(at + 38, 4)
      guard flags & ~0x080E == 0, method == 0 || method == 8,
        method == 8 || flags & 6 == 0, try number(at + 34, 2) == 0,
        compressed <= Self.maximumEntryBytes, decoded <= Self.maximumEntryBytes,
        nameCount > 0, nameCount + extra + comment <= end - at - 46,
        local <= centralStart - 30, attributes >> 28 != 0xA else {
        throw CraftError.invalid("Unsupported PhotoCraft ZIP entry.")
      }
      totalDecoded += decoded
      guard totalDecoded <= Self.maximumArchiveBytes else {
        throw CraftError.invalid("PhotoCraft ZIP decompressed contents exceed the limit.")
      }
      let nameBytes = data[(at + 46)..<(at + 46 + nameCount)]
      guard let name = String(data: nameBytes, encoding: .utf8),
        !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"), entries[name] == nil else {
        throw CraftError.invalid("Unsafe or duplicate PhotoCraft ZIP path.")
      }
      let components = name.split(separator: "/", omittingEmptySubsequences: false)
      guard components.enumerated().allSatisfy({
        $0.element != "." && $0.element != ".." && (!$0.element.isEmpty || $0.offset == components.count - 1)
      }) else {
        throw CraftError.invalid("Unsafe or duplicate PhotoCraft ZIP path.")
      }
      try Self.validateExtras(data, (at + 46 + nameCount)..<(at + 46 + nameCount + extra))
      guard try number(local, 4) == 0x04034b50,
        try number(local + 6, 2) == flags, try number(local + 8, 2) == method,
        try number(local + 26, 2) == nameCount else {
        throw CraftError.invalid("Mismatched PhotoCraft ZIP local header.")
      }
      let localExtra = try number(local + 28, 2), start = local + 30 + nameCount + localExtra
      guard start <= centralStart, compressed <= centralStart - start,
        data[(local + 30)..<(local + 30 + nameCount)] == nameBytes else {
        throw CraftError.invalid("Invalid PhotoCraft ZIP local extent.")
      }
      try Self.validateExtras(data, (local + 30 + nameCount)..<start)
      var finish = start + compressed
      let localCRC = try number(local + 14, 4), localCompressed = try number(local + 18, 4)
      let localDecoded = try number(local + 22, 4)
      if flags & 8 != 0 {
        guard (localCRC == 0 || localCRC == crc), (localCompressed == 0 || localCompressed == compressed),
          (localDecoded == 0 || localDecoded == decoded) else {
          throw CraftError.invalid("Mismatched PhotoCraft ZIP descriptor header.")
        }
        if finish <= centralStart - 4, try number(finish, 4) == 0x08074b50 { finish += 4 }
        guard finish <= centralStart - 12, try number(finish, 4) == crc,
          try number(finish + 4, 4) == compressed, try number(finish + 8, 4) == decoded else {
          throw CraftError.invalid("Invalid PhotoCraft ZIP data descriptor.")
        }
        finish += 12
      } else {
        guard localCRC == crc, localCompressed == compressed, localDecoded == decoded else {
          throw CraftError.invalid("Mismatched PhotoCraft ZIP sizes or checksum.")
        }
      }
      guard method != 0 || compressed == decoded else {
        throw CraftError.invalid("Invalid stored PhotoCraft ZIP length.")
      }
      entries[name] = Entry(name: name, method: method, checksum: crc, decodedSize: decoded, range: start..<(start + compressed))
      ranges.append(local..<finish)
      at += 46 + nameCount + extra + comment
    }
    guard at == end else { throw CraftError.invalid("Trailing PhotoCraft ZIP directory bytes.") }
    var next = 0
    for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
      guard range.lowerBound == next else { throw CraftError.invalid("Overlapping or unindexed PhotoCraft ZIP bytes.") }
      next = range.upperBound
    }
    guard next == centralStart else { throw CraftError.invalid("Unindexed PhotoCraft ZIP contents.") }
    self.data = data; self.entries = entries
  }

  func read(_ name: String, limit: Int = maximumEntryBytes) throws -> Data {
    try Task.checkCancellation()
    guard let entry = entries[name] else { throw CraftError.invalid("Missing PhotoCraft ZIP entry: \(name)") }
    guard limit >= 0, entry.decodedSize <= limit else { throw CraftError.invalid("PhotoCraft ZIP entry exceeds its limit.") }
    let payload = data[entry.range]
    let decoded = entry.method == 0 ? Data(payload) : try Self.inflate(payload, expected: entry.decodedSize)
    let checksum = decoded.withUnsafeBytes {
      UInt32(crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)))
    }
    guard checksum == entry.checksum else { throw CraftError.invalid("PhotoCraft ZIP checksum mismatch.") }
    return decoded
  }

  private static func validateExtras(_ data: Data, _ range: Range<Int>) throws {
    var at = range.lowerBound
    while at < range.upperBound {
      guard range.upperBound - at >= 4 else { throw CraftError.invalid("Truncated PhotoCraft ZIP extra field.") }
      let tag = Int(data[at]) | (Int(data[at + 1]) << 8)
      let size = Int(data[at + 2]) | (Int(data[at + 3]) << 8)
      guard tag != 1, tag != 0x9901, size <= range.upperBound - at - 4 else {
        throw CraftError.invalid("Unsupported PhotoCraft ZIP extra field.")
      }
      at += 4 + size
    }
  }
  private static func inflate(_ data: Data, expected: Int) throws -> Data {
    var stream = z_stream()
    guard inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
      throw CraftError.invalid("Could not initialize PhotoCraft ZIP decompression.")
    }
    defer { inflateEnd(&stream) }
    return try data.withUnsafeBytes { input in
      stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(input.count)
      var output = Data(), buffer = [UInt8](repeating: 0, count: 64 * 1024)
      output.reserveCapacity(expected)
      while true {
        try Task.checkCancellation()
        let before = stream.avail_in
        let status = buffer.withUnsafeMutableBytes { bytes -> Int32 in
          stream.next_out = bytes.bindMemory(to: Bytef.self).baseAddress
          stream.avail_out = uInt(bytes.count)
          return zlib.inflate(&stream, Z_NO_FLUSH)
        }
        let count = buffer.count - Int(stream.avail_out)
        guard count <= expected - output.count else { throw CraftError.invalid("Oversized PhotoCraft ZIP output.") }
        output.append(contentsOf: buffer.prefix(count))
        if status == Z_STREAM_END {
          guard output.count == expected, stream.avail_in == 0 else {
            throw CraftError.invalid("PhotoCraft ZIP length or trailing-data mismatch.")
          }
          return output
        }
        guard status == Z_OK, count > 0 || stream.avail_in < before else {
          throw CraftError.invalid("Corrupt or truncated PhotoCraft ZIP stream.")
        }
      }
    }
  }
}
