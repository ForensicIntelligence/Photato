import Foundation

/// Structural validation for a retained RGB working profile. Source provenance is separate.
public enum ICCProfile {
  public static let maximumBytes = 4 * 1024 * 1024
  public static let maximumTags = 4096
  // Retain ranges rather than copying payloads. ICC tags may share the same data;
  // repeating a large payload must not multiply the decoder's memory allocation.
  private static func tags(_ data: Data) throws -> [String: Range<Int>] {
    guard data.count >= 132, data.count <= maximumBytes else {
      throw CraftError.invalid("Invalid working ICC profile size.")
    }
    func n(_ i: Int) -> Int { data[i..<i + 4].reduce(0) { ($0 << 8) | Int($1) } }
    func text(_ i: Int) -> String { String(decoding: data[i..<i + 4], as: UTF8.self) }
    guard n(0) == data.count, text(16) == "RGB ", text(36) == "acsp",
      ["XYZ ", "Lab "].contains(text(20)), [2, 4].contains(data[8]),
      n(128) <= maximumTags, n(128) <= (data.count - 132) / 12
    else {
      throw CraftError.invalid("Invalid RGB working ICC profile header or tag count.")
    }
    let end = 132 + n(128) * 12
    var tags: [String: Range<Int>] = [:]
    for i in stride(from: 132, to: end, by: 12) {
      let offset = n(i + 4)
      let size = n(i + 8)
      let key = text(i)
      guard offset >= end, offset % 4 == 0, size >= 8,
        offset <= data.count, size <= data.count - offset, tags[key] == nil
      else {
        throw CraftError.invalid("Invalid working ICC profile tag table.")
      }
      tags[key] = offset..<offset + size
    }
    return tags
  }
  public static func validate(_ data: Data, linear: Bool) throws {
    let values = try tags(data)
    if linear && !isLinear(data, tags: values) {
      throw CraftError.unsupported("RGB32 working profiles require linear matrix RGB curves.")
    }
  }
  public static func isLinear(_ data: Data) throws -> Bool {
    isLinear(data, tags: try tags(data))
  }
  private static func isLinear(_ data: Data, tags: [String: Range<Int>]) -> Bool {
    func signature(_ range: Range<Int>) -> String {
      String(decoding: data[range.lowerBound..<range.lowerBound + 4], as: UTF8.self)
    }
    func n(_ i: Int) -> UInt32 { data[i..<i + 4].reduce(0) { ($0 << 8) | UInt32($1) } }
    for key in ["rXYZ", "gXYZ", "bXYZ"] {
      guard let value = tags[key], value.count >= 20, signature(value) == "XYZ " else {
        return false
      }
    }
    return ["rTRC", "gTRC", "bTRC"].allSatisfy { key in
      guard let value = tags[key], value.count >= 12 else { return false }
      let start = value.lowerBound
      if signature(value) == "curv" {
        return n(start + 8) == 0
          || (n(start + 8) == 1 && value.count >= 14 && data[start + 12] == 1
            && data[start + 13] == 0)
      }
      return signature(value) == "para" && value.count >= 16
        && data[start + 8] == 0 && data[start + 9] == 0 && n(start + 12) == 65536
    }
  }
}
