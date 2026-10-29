import Foundation
import PhotoCraftCore

/// Source metadata stays independent of the native editing model. In particular,
/// IDs and floating-point tokens never round-trip through NSNumber/Double.
indirect enum PcraftJSON: Equatable, Sendable {
  case object([String: PcraftJSON]), array([PcraftJSON]), string(String)
  case number(String), bool(Bool), null

  subscript(_ key: String) -> PcraftJSON? {
    guard case .object(let fields) = self else { return nil }
    return fields[key]
  }
  var string: String? { if case .string(let value) = self { return value }; return nil }
  var array: [PcraftJSON]? { if case .array(let value) = self { return value }; return nil }
  var uint: UInt64? { if case .number(let value) = self { return UInt64(value) }; return nil }
  var int: Int64? { if case .number(let value) = self { return Int64(value) }; return nil }
  var bool: Bool? { if case .bool(let value) = self { return value }; return nil }

  static func parse(_ data: Data, maximumNodes: Int = 250_000) throws -> Self {
    guard maximumNodes > 0 else { throw CraftError.invalid("Invalid PhotoCraft JSON budget.") }
    var parser = Parser(bytes: Array(data), remaining: maximumNodes)
    let result = try parser.value(depth: 0)
    parser.whitespace()
    guard parser.at == parser.bytes.count else { throw Parser.error }
    return result
  }

  private struct Parser {
    let bytes: [UInt8]
    var remaining: Int
    var at = 0
    static var error: CraftError { .invalid("Invalid or excessive PhotoCraft manifest JSON.") }
    mutating func whitespace() {
      while at < bytes.count && [9, 10, 13, 32].contains(bytes[at]) { at += 1 }
    }
    mutating func take(_ byte: UInt8) -> Bool {
      guard at < bytes.count && bytes[at] == byte else { return false }
      at += 1; return true
    }
    mutating func value(depth: Int) throws -> PcraftJSON {
      try Task.checkCancellation()
      guard remaining > 0, depth <= 367 else { throw Self.error }
      remaining -= 1; whitespace()
      guard at < bytes.count else { throw Self.error }
      switch bytes[at] {
      case 123:
        at += 1; whitespace()
        var fields: [String: PcraftJSON] = [:]
        if take(125) { return .object(fields) }
        while true {
          let key = try string()
          guard fields[key] == nil else { throw Self.error }
          whitespace(); guard take(58) else { throw Self.error }
          fields[key] = try value(depth: depth + 1)
          whitespace()
          if take(125) { return .object(fields) }
          guard take(44) else { throw Self.error }; whitespace()
        }
      case 91:
        at += 1; whitespace()
        var items: [PcraftJSON] = []
        if take(93) { return .array(items) }
        while true {
          items.append(try value(depth: depth + 1)); whitespace()
          if take(93) { return .array(items) }
          guard take(44) else { throw Self.error }
        }
      case 34: return .string(try string())
      case 116: try literal("true"); return .bool(true)
      case 102: try literal("false"); return .bool(false)
      case 110: try literal("null"); return .null
      default:
        let start = at
        _ = take(45)
        if !take(48) { try digits() }
        if take(46) { try digits() }
        if take(101) || take(69) {
          if !take(43) { _ = take(45) }
          try digits()
        }
        let token = String(decoding: bytes[start..<at], as: UTF8.self)
        guard let number = Double(token), number.isFinite else { throw Self.error }
        return .number(token)
      }
    }
    mutating func digits() throws {
      let start = at
      while at < bytes.count && (48...57).contains(bytes[at]) { at += 1 }
      guard at > start else { throw Self.error }
    }
    mutating func literal(_ text: String) throws {
      for byte in text.utf8 { guard take(byte) else { throw Self.error } }
    }
    mutating func string() throws -> String {
      let start = at
      guard take(34) else { throw Self.error }
      while at < bytes.count {
        let byte = bytes[at]; at += 1
        if byte == 34 {
          // Foundation handles UTF-8, escape sequences and surrogate pairs.
          return try JSONDecoder().decode(String.self, from: Data(bytes[start..<at]))
        }
        if byte == 92 {
          guard at < bytes.count else { throw Self.error }
          at += 1
        } else if byte < 32 { throw Self.error }
        if at & 4095 == 0 { try Task.checkCancellation() }
      }
      throw Self.error
    }
  }
}
