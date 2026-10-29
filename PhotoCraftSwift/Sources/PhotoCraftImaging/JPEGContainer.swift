import Foundation
import PhotoCraftCore

/// Bounded JPEG marker framing, including stuffed entropy bytes and restart markers.
/// Used only for explicit output transformations; omitted options preserve encoder bytes.
enum JPEGContainer {
  static let maximumBytes = 512 * 1_024 * 1_024
  struct Segment {
    let marker: UInt8
    let range: Range<Int>
    let payload: Range<Int>
    let entropy: Range<Int>?
  }
  static func invalid() -> CraftError { .invalid("Invalid or unsupported JPEG output structure.") }
  static func segments(_ bytes: [UInt8]) throws -> [Segment] {
    try Task.checkCancellation()
    guard bytes.count >= 4, bytes.count <= maximumBytes,
      bytes[0] == 255, bytes[1] == 216 else { throw invalid() }
    var position = 2
    var result: [Segment] = []
    while position < bytes.count {
      try Task.checkCancellation()
      guard result.count < 65_536 else { throw invalid() }
      let start = position
      guard bytes[position] == 255 else { throw invalid() }
      while position < bytes.count && bytes[position] == 255 { position += 1 }
      guard position < bytes.count else { throw invalid() }
      let marker = bytes[position]; position += 1
      if marker == 217 {
        guard position == bytes.count else { throw invalid() }
        result.append(.init(marker: marker, range: start..<position,
          payload: position..<position, entropy: nil))
        return result
      }
      guard marker != 0, marker != 216, !(208...215).contains(marker), marker != 1,
        position + 2 <= bytes.count else { throw invalid() }
      let size = Int(bytes[position]) * 256 + Int(bytes[position + 1])
      guard size >= 2, size <= bytes.count - position else { throw invalid() }
      let payload = (position + 2)..<(position + size)
      position += size
      let headerEnd = position
      var entropy: Range<Int>?
      if marker == 218 {
        let entropyStart = position
        while position < bytes.count {
          if position & 0xffff == 0 { try Task.checkCancellation() }
          if bytes[position] != 255 { position += 1; continue }
          let mark = position
          while position < bytes.count && bytes[position] == 255 { position += 1 }
          guard position < bytes.count else { throw invalid() }
          let next = bytes[position]
          if next == 0 || (208...215).contains(next) { position += 1; continue }
          position = mark; break
        }
        guard position < bytes.count else { throw invalid() }
        entropy = entropyStart..<position
      }
      result.append(.init(marker: marker, range: start..<headerEnd,
        payload: payload, entropy: entropy))
    }
    throw invalid()
  }
  static func withoutICC(_ data: Data) throws -> Data {
    guard data.count <= maximumBytes else { throw invalid() }
    let bytes = [UInt8](data), records = try segments(bytes)
    let prefix = Array("ICC_PROFILE\0".utf8)
    var output = Data([255, 216])
    for record in records {
      if record.marker == 226 && bytes[record.payload].starts(with: prefix) { continue }
      output.append(contentsOf: bytes[record.range])
      if let entropy = record.entropy { output.append(contentsOf: bytes[entropy]) }
    }
    return output
  }
  static func embeddingICC(_ profile: Data, into data: Data) throws -> Data {
    guard !profile.isEmpty, profile.count <= 16 * 1_024 * 1_024 else { throw invalid() }
    let stripped = try withoutICC(data)
    // APP2 length includes its two length bytes, 12-byte signature and sequence/count.
    let capacity = 65_519
    let count = (profile.count + capacity - 1) / capacity
    guard count <= 255, stripped.count + profile.count + count * 18 <= maximumBytes else { throw invalid() }
    let records = try segments([UInt8](stripped))
    let insertion = records.first(where: { [192,194].contains($0.marker) })?.range.lowerBound ?? 2
    var output = Data(stripped.prefix(insertion))
    for index in 0..<count {
      try Task.checkCancellation()
      let start = index * capacity, end = min(start + capacity, profile.count)
      let size = end - start + 16
      output.append(contentsOf: [255,226,UInt8(size >> 8),UInt8(size & 255)])
      output.append(contentsOf: "ICC_PROFILE\0".utf8)
      output.append(contentsOf: [UInt8(index + 1),UInt8(count)])
      output.append(profile[start..<end])
    }
    output.append(stripped.dropFirst(insertion))
    return output
  }
}
