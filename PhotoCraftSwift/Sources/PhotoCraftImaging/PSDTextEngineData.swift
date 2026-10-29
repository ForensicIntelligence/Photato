import Foundation
import PhotoCraftCore

// Native bounded port of photocraft crates/text/src/engine_data.rs.
// Upstream is MIT OR Apache-2.0. PostScript-like syntax, never executable code.
indirect enum PSDTextValue {
  case dictionary([String: Self]), array([Self]), string(String), number(Double), bool(Bool), name(String)
  subscript(_ key: String) -> Self? { if case .dictionary(let d) = self { return d[key] }; return nil }
  var array: [Self]? { if case .array(let a) = self { return a }; return nil }
  var string: String? { if case .string(let s) = self { return s }; return nil }
  var number: Double? { if case .number(let n) = self { return n }; return nil }
  var flag: Bool? { if case .bool(let b) = self { return b }; return nil }
  var fields: [String: Self] { if case .dictionary(let d) = self { return d }; return [:] }
  static func parse(_ data: Data) throws -> Self {
    guard data.count <= 8 * 1024 * 1024 else { throw CraftError.invalid("Type engine data exceeds 8 MiB.") }
    var parser = Parser(bytes: Array(data)); let value = try parser.value(0); parser.skip()
    guard parser.offset == parser.bytes.count else { throw CraftError.invalid("Unexpected type engine data tail.") }
    return value
  }
  func encoded() -> Data {
    switch self {
    case .dictionary(let d):
      var result = Data("<<\n".utf8)
      for key in d.keys.sorted() { result.append(Data("/\(key) ".utf8)); result.append(d[key]!.encoded()); result.append(10) }
      result.append(Data(">>".utf8)); return result
    case .array(let a):
      var result = Data("[ ".utf8)
      for item in a { result.append(item.encoded()); result.append(32) }; result.append(93); return result
    case .string(let s):
      var result = Data([40, 254, 255])
      for unit in s.utf16 { for byte in [UInt8(unit >> 8), UInt8(unit & 255)] {
        if [40, 41, 92].contains(byte) { result.append(92) }; result.append(byte)
      }}
      result.append(41); return result
    case .number(let n): return Data(String(n).utf8)
    case .bool(let b): return Data((b ? "true" : "false").utf8)
    case .name(let name): return Data(("/" + name).utf8)
    }
  }
  private struct Parser {
    var bytes: [UInt8]
    var offset = 0
    var nodes = 0
    mutating func skip() {
      while offset < bytes.count {
        if bytes[offset] <= 32 { offset += 1 }
        else if bytes[offset] == 37 { while offset < bytes.count && bytes[offset] != 10 && bytes[offset] != 13 { offset += 1 } }
        else { break }
      }
    }
    func invalid() -> CraftError { .invalid("Malformed type engine data at byte \(offset).") }
    mutating func token() throws -> String {
      let start = offset
      while offset < bytes.count && bytes[offset] > 32 && ![40, 41, 60, 62, 91, 93, 47].contains(bytes[offset]) { offset += 1 }
      guard offset > start, offset - start <= 1024 else { throw invalid() }
      return String(decoding: bytes[start..<offset], as: UTF8.self)
    }
    mutating func value(_ depth: Int) throws -> PSDTextValue {
      skip(); nodes += 1
      guard depth <= 64, nodes <= 100_000, offset < bytes.count else { throw invalid() }
      if bytes[offset] == 60 {
        guard offset + 1 < bytes.count, bytes[offset + 1] == 60 else { throw invalid() }; offset += 2
        var dictionary: [String: PSDTextValue] = [:]
        while true {
          skip(); guard offset < bytes.count else { throw invalid() }
          if bytes[offset] == 62 {
            guard offset + 1 < bytes.count, bytes[offset + 1] == 62 else { throw invalid() }; offset += 2; return .dictionary(dictionary)
          }
          guard bytes[offset] == 47 else { throw invalid() }; offset += 1
          let key = try token(); guard dictionary[key] == nil else { throw invalid() }
          dictionary[key] = try value(depth + 1)
        }
      }
      if bytes[offset] == 91 {
        offset += 1; var array: [PSDTextValue] = []
        while true {
          skip(); guard offset < bytes.count else { throw invalid() }
          if bytes[offset] == 93 { offset += 1; return .array(array) }
          array.append(try value(depth + 1))
        }
      }
      if bytes[offset] == 40 {
        offset += 1; var data = Data(), nesting = 1
        while offset < bytes.count {
          var b = bytes[offset]; offset += 1
          if b == 92 {
            guard offset < bytes.count else { throw invalid() }; b = bytes[offset]; offset += 1
            if (48...55).contains(b) {
              var octal = Int(b - 48)
              for _ in 0..<2 where offset < bytes.count && (48...55).contains(bytes[offset]) { octal = octal * 8 + Int(bytes[offset] - 48); offset += 1 }
              data.append(UInt8(truncatingIfNeeded: octal)); continue
            }
            if let special = [UInt8(110): UInt8(10), 114: 13, 116: 9, 98: 8, 102: 12][b] { b = special }
            else if b == 10 { continue }
            else if b == 13 { if offset < bytes.count && bytes[offset] == 10 { offset += 1 }; continue }
            data.append(b); continue
          }
          if b == 40 { nesting += 1 }
          if b == 41 { nesting -= 1; if nesting == 0 {
            if data.starts(with: [254, 255]) {
              guard data.count % 2 == 0, let s = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else { throw invalid() }; return .string(s)
            }
            guard let s = String(data: data, encoding: .isoLatin1) else { throw invalid() }; return .string(s)
          }}
          data.append(b)
        }
        throw invalid()
      }
      if bytes[offset] == 47 { offset += 1; return .name(try token()) }
      let word = try token()
      if word == "true" { return .bool(true) }; if word == "false" { return .bool(false) }
      guard let number = Double(word), number.isFinite else { throw invalid() }; return .number(number)
    }
  }
}
