import Foundation
import PhotoCraftCore
import UniformTypeIdentifiers

/// Remove color interpretation tags without decoding or re-encoding samples.
/// Used only for the app's validated, freshly encoded output.
enum UntaggedOutput {
  static func hasProfile(_ data: Data) throws -> Bool? {
    if TIFFContainer.isClassic(data) { return try TIFFContainer(data, metadata: false, additionalTags: [34675]).root.fields[34675] != nil }
    if data.starts(with: [255, 216]) {
      let bytes = [UInt8](data)
      return try JPEGContainer.segments(bytes).contains { $0.marker == 226 && bytes[$0.payload].starts(with: Array("ICC_PROFILE\0".utf8)) }
    }
    guard data.starts(with: [137,80,78,71,13,10,26,10]) else { return nil }
    var at = 8
    while at < data.count {
      guard data.count - at >= 12 else { throw CraftError.invalid("Truncated PNG metadata.") }
      let length = data[at..<at+4].reduce(0) { ($0 << 8) | Int($1) }
      guard length <= data.count - at - 12 else { throw CraftError.invalid("Truncated PNG chunk.") }
      let kind = String(decoding: data[at+4..<at+8], as: UTF8.self)
      if ["iCCP", "sRGB"].contains(kind) { return true }
      at += length + 12
    }
    return false
  }
  static func strip(_ data: Data, type: UTType) throws -> Data {
    if type == .jpeg { return try JPEGContainer.withoutICC(data) }
    if type == .tiff {
      let file = try TIFFContainer(data, metadata: true)
      file.root.fields.removeValue(forKey: 34675)
      file.root.fields.removeValue(forKey: 318); file.root.fields.removeValue(forKey: 319)
      if let exif = file.root.fields[34665]?.children.first {
        exif.fields[40961] = .init(tag: 40961, type: 3, count: 1, data: file.order.bytes(65535, 2))
      }
      var output = data; try file.appendDirectories(to: &output, order: file.order); return output
    }
    guard type == .png, data.count >= 8 else { throw CraftError.invalid("Unsupported untagged output format.") }
    var output = Data(data.prefix(8)), at = 8
    while at < data.count {
      guard data.count - at >= 12 else { throw CraftError.invalid("Truncated PNG color metadata.") }
      let length = data[at..<at + 4].reduce(0) { ($0 << 8) | Int($1) }
      guard length <= data.count - at - 12 else { throw CraftError.invalid("Truncated PNG chunk.") }
      let kind = String(decoding: data[at + 4..<at + 8], as: UTF8.self)
      if !["iCCP", "sRGB", "gAMA", "cHRM", "cICP", "mDCv", "cLLi"].contains(kind) { output.append(data[at..<at + length + 12]) }
      at += length + 12
    }
    return output
  }
}
