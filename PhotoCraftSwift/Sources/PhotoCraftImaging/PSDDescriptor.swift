import Foundation
import PhotoCraftCore

// Native port of photocraft's crates/psd/src/descriptor.rs (MIT OR Apache-2.0).
// Preserve ordered keys, raw UTF-16, ID encoding and floating-point payload bits.
// The typed consumers, not this transport codec, decide which semantics are supported.
struct PSDID: Equatable {
  var bytes: Data
  var isCode: Bool
  init(_ text: String) {
    bytes = Data(text.utf8)
    isCode = bytes.count == 4
  }
  init(bytes: Data, isCode: Bool) {
    self.bytes = bytes
    self.isCode = isCode
  }
  var text: String { String(decoding: bytes, as: UTF8.self) }
}

struct PSDClass: Equatable {
  var name: [UInt16] = []
  var id: PSDID
}

enum PSDReference: Equatable {
  case property(PSDClass, PSDID)
  case type(PSDClass)
  case enumerated(PSDClass, PSDID, PSDID)
  case offset(PSDClass, Int32)
  case identifier(UInt32)
  case index(UInt32)
  case name(PSDClass, [UInt16])
}

indirect enum PSDValue: Equatable {
  case reference([PSDReference])
  case object(PSDDescriptor)
  case globalObject(PSDDescriptor)
  case list([PSDValue])
  case doubleBits(UInt64)
  case unit(Data, UInt64)
  case units(Data, [UInt64])
  case text([UInt16])
  case enumerated(PSDID, PSDID)
  case integer(Int32)
  case largeInteger(Int64)
  case boolean(Bool)
  case type(PSDClass)
  case globalClass(PSDClass)
  case alias(Data)
  case path(Data)
  case raw(Data)
  case objectArray(UInt32, PSDDescriptor)

  static func number(_ value: Double) -> Self { .doubleBits(value.bitPattern) }
  var number: Double? {
    switch self {
    case .doubleBits(let bits): Double(bitPattern: bits)
    case .integer(let value): Double(value)
    default: nil
    }
  }
}

struct PSDDescriptor: Equatable {
  struct Item: Equatable {
    var key: PSDID
    var value: PSDValue
    init(_ key: String, _ value: PSDValue) {
      self.key = PSDID(key)
      self.value = value
    }
    init(key: PSDID, value: PSDValue) {
      self.key = key
      self.value = value
    }
  }
  var name: [UInt16] = []
  var classID: PSDID
  var items: [Item] = []
  init(_ classID: String, items: [Item] = []) {
    self.classID = PSDID(classID)
    self.items = items
  }
  subscript(_ key: String) -> PSDValue? { items.first { $0.key.bytes == Data(key.utf8) }?.value }

  static let maxBytes = 16 * 1024 * 1024
  static let maxNodes = 100_000
  static let maxDepth = 64

  static func read(_ data: Data, padding: Bool = false) throws -> Self {
    let (descriptor, consumed) = try readPrefix(data)
    let tail = data.dropFirst(consumed)
    guard tail.isEmpty || (padding && tail.count <= 3 && tail.allSatisfy { $0 == 0 }) else {
      throw CraftError.invalid("Unexpected PSD descriptor tail.")
    }
    return descriptor
  }

  static func readPrefix(_ data: Data, littleEndian: Bool = false) throws -> (descriptor: Self, consumed: Int) {
    guard data.count <= maxBytes else { throw CraftError.invalid("PSD descriptor exceeds 16 MiB.") }
    var parser = Parser(reader: PSDReader(data: data), littleEndian: littleEndian)
    guard try parser.u32() == 16 else {
      throw CraftError.invalid("Unsupported PSD descriptor version.")
    }
    let descriptor = try parser.descriptor(0)
    return (descriptor, data.count - parser.reader.remaining)
  }

  /// A file-open descriptor may be followed by a large embedded source.
  /// Inspect only the bounded prefix and advance past the descriptor itself.
  static func readPrefix(_ reader: inout PSDReader) throws -> Self {
    var lookahead = reader
    var parser = Parser(reader: try lookahead.view(min(reader.remaining, maxBytes)))
    guard try parser.u32() == 16 else {
      throw CraftError.invalid("Unsupported PSD descriptor version.")
    }
    let descriptor = try parser.descriptor(0)
    _ = try reader.view(parser.reader.offset)
    return descriptor
  }

  func encoded(littleEndian: Bool = false) throws -> Data {
    var encoder = Encoder(littleEndian: littleEndian)
    encoder.number(16, 4)
    try encoder.descriptor(self, 0)
    guard encoder.writer.data.count <= Self.maxBytes else {
      throw CraftError.invalid("PSD descriptor exceeds 16 MiB.")
    }
    return encoder.writer.data
  }

  private struct Parser {
    var reader: PSDReader
    var littleEndian = false
    var nodes = 0
    mutating func number(_ width: Int) throws -> UInt64 {
      let bits = try reader.number(width)
      return littleEndian ? bits.byteSwapped >> ((8 - width) * 8) : bits
    }
    mutating func u32() throws -> Int { Int(try number(4)) }
    mutating func i32() throws -> Int32 { Int32(bitPattern: UInt32(try number(4))) }
    mutating func codeBytes() throws -> Data {
      let bytes = try reader.bytes(4)
      return littleEndian ? Data(bytes.reversed()) : bytes
    }
    mutating func code() throws -> String { String(decoding: try codeBytes(), as: UTF8.self) }
    mutating func visit(_ depth: Int) throws {
      nodes += 1
      guard depth <= maxDepth, nodes <= maxNodes else {
        throw CraftError.invalid("PSD descriptor exceeds nesting or item limits.")
      }
    }
    mutating func count(_ minimumBytes: Int) throws -> Int {
      let n = try u32()
      guard n <= maxNodes - nodes, n <= reader.remaining / minimumBytes else {
        throw CraftError.invalid("Invalid PSD descriptor item count.")
      }
      return n
    }
    mutating func unicode() throws -> [UInt16] {
      let n = try u32()
      guard n <= 1_048_576, n <= reader.remaining / 2 else {
        throw CraftError.invalid("Invalid PSD descriptor string length.")
      }
      return try (0..<n).map { _ in UInt16(try number(2)) }
    }
    mutating func id() throws -> PSDID {
      let n = try u32()
      guard n <= 65_536 else { throw CraftError.invalid("PSD descriptor ID is too long.") }
      let bytes = n == 0 ? try codeBytes() : try reader.bytes(n)
      return PSDID(bytes: bytes, isCode: n == 0)
    }
    mutating func blob() throws -> Data {
      let size = try u32()
      return try reader.bytes(size)
    }
    mutating func type() throws -> PSDClass { try PSDClass(name: unicode(), id: id()) }
    mutating func descriptor(_ depth: Int) throws -> PSDDescriptor {
      try visit(depth)
      let name = try unicode()
      let id = try id()
      let n = try count(10)
      var d = PSDDescriptor("")
      d.name = name
      d.classID = id
      for _ in 0..<n { d.items.append(try Item(key: self.id(), value: value(depth + 1))) }
      return d
    }
    mutating func value(_ depth: Int) throws -> PSDValue {
      try visit(depth)
      switch try code() {
      case "obj ":
        let n = try count(8)
        return .reference(try (0..<n).map { _ in try reference(depth + 1) })
      case "Objc": return .object(try descriptor(depth + 1))
      case "GlbO": return .globalObject(try descriptor(depth + 1))
      case "VlLs":
        let n = try count(4)
        return .list(try (0..<n).map { _ in try value(depth + 1) })
      case "doub": return .doubleBits(try number(8))
      case "UntF": return try .unit(codeBytes(), number(8))
      case "UnFl":
        let unit = try codeBytes()
        let n = try count(8)
        nodes += n
        return .units(unit, try (0..<n).map { _ in try number(8) })
      case "TEXT": return .text(try unicode())
      case "enum": return try .enumerated(id(), id())
      case "long": return .integer(try i32())
      case "comp": return .largeInteger(Int64(bitPattern: try number(8)))
      case "bool":
        let b = try reader.u8()
        guard b <= 1 else { throw CraftError.invalid("Invalid PSD descriptor boolean.") }
        return .boolean(b == 1)
      case "type": return .type(try type())
      case "GlbC": return .globalClass(try type())
      case "alis": return .alias(try blob())
      case "Pth ": return .path(try blob())
      case "tdta": return .raw(try blob())
      case "ObAr": return try .objectArray(UInt32(u32()), descriptor(depth + 1))
      default: throw CraftError.unsupported("Unknown PSD descriptor value type.")
      }
    }
    mutating func reference(_ depth: Int) throws -> PSDReference {
      try visit(depth)
      switch try code() {
      case "prop": return try .property(type(), id())
      case "Clss": return .type(try type())
      case "Enmr": return try .enumerated(type(), id(), id())
      case "rele": return try .offset(type(), i32())
      case "Idnt": return .identifier(UInt32(try u32()))
      case "indx": return .index(UInt32(try u32()))
      case "name": return try .name(type(), unicode())
      default: throw CraftError.unsupported("Unknown PSD descriptor reference type.")
      }
    }
  }

  private struct Encoder {
    var writer = PSDWriter()
    var littleEndian = false
    var nodes = 0
    mutating func number(_ value: Int, _ width: Int) {
      if littleEndian {
        let bits = UInt64(truncatingIfNeeded: value)
        for i in 0..<width { writer.data.append(UInt8(truncatingIfNeeded: bits >> (i * 8))) }
      } else {
        writer.n(value, width)
      }
    }
    mutating func codeBytes(_ value: Data) {
      writer.data.append(littleEndian ? Data(value.reversed()) : value)
    }
    mutating func code(_ value: String) { codeBytes(Data(value.utf8)) }
    mutating func visit(_ depth: Int) throws {
      nodes += 1
      guard depth <= maxDepth, nodes <= maxNodes, writer.data.count <= maxBytes else {
        throw CraftError.invalid("PSD descriptor exceeds encoding limits.")
      }
    }
    mutating func unicode(_ value: [UInt16]) throws {
      guard value.count <= 1_048_576 else { throw CraftError.invalid("PSD string is too long.") }
      number(value.count, 4)
      for unit in value { number(Int(unit), 2) }
    }
    mutating func id(_ value: PSDID) throws {
      guard
        (value.isCode && value.bytes.count == 4)
          || (!value.isCode && (1...65_536).contains(value.bytes.count))
      else {
        throw CraftError.invalid("Invalid PSD descriptor ID.")
      }
      number(value.isCode ? 0 : value.bytes.count, 4)
      if value.isCode { codeBytes(value.bytes) } else { writer.data.append(value.bytes) }
    }
    mutating func type(_ value: PSDClass) throws {
      try unicode(value.name)
      try id(value.id)
    }
    mutating func bits(_ value: UInt64) { number(Int(truncatingIfNeeded: value), 8) }
    mutating func blob(_ value: Data) throws {
      guard value.count <= maxBytes else { throw CraftError.invalid("PSD value is too large.") }
      number(value.count, 4)
      writer.data.append(value)
    }
    mutating func unit(_ value: Data) throws {
      guard value.count == 4 else { throw CraftError.invalid("Invalid PSD unit code.") }
      codeBytes(value)
    }
    mutating func descriptor(_ d: PSDDescriptor, _ depth: Int) throws {
      try visit(depth)
      try unicode(d.name)
      try id(d.classID)
      guard d.items.count <= maxNodes else { throw CraftError.invalid("Too many PSD items.") }
      number(d.items.count, 4)
      for item in d.items {
        try id(item.key)
        try value(item.value, depth + 1)
      }
    }
    mutating func value(_ v: PSDValue, _ depth: Int) throws {
      try visit(depth)
      switch v {
      case .reference(let refs):
        code("obj ")
        number(refs.count, 4)
        for ref in refs { try reference(ref, depth + 1) }
      case .object(let d):
        code("Objc")
        try descriptor(d, depth + 1)
      case .globalObject(let d):
        code("GlbO")
        try descriptor(d, depth + 1)
      case .list(let values):
        code("VlLs")
        number(values.count, 4)
        for v in values { try value(v, depth + 1) }
      case .doubleBits(let b):
        code("doub")
        bits(b)
      case .unit(let u, let b):
        code("UntF")
        try unit(u)
        bits(b)
      case .units(let u, let values):
        guard values.count <= maxNodes - nodes else {
          throw CraftError.invalid("Too many PSD units.")
        }
        nodes += values.count
        code("UnFl")
        try unit(u)
        number(values.count, 4)
        for b in values { bits(b) }
      case .text(let text):
        code("TEXT")
        try unicode(text)
      case .enumerated(let t, let v):
        code("enum")
        try id(t)
        try id(v)
      case .integer(let v):
        code("long")
        number(Int(v), 4)
      case .largeInteger(let v):
        code("comp")
        number(Int(v), 8)
      case .boolean(let v):
        code("bool")
        number(v ? 1 : 0, 1)
      case .type(let t):
        code("type")
        try type(t)
      case .globalClass(let t):
        code("GlbC")
        try type(t)
      case .alias(let b):
        code("alis")
        try blob(b)
      case .path(let b):
        code("Pth ")
        try blob(b)
      case .raw(let b):
        code("tdta")
        try blob(b)
      case .objectArray(let prefix, let d):
        code("ObAr")
        number(Int(prefix), 4)
        try descriptor(d, depth + 1)
      }
    }
    mutating func reference(_ r: PSDReference, _ depth: Int) throws {
      try visit(depth)
      switch r {
      case .property(let t, let k):
        code("prop")
        try type(t)
        try id(k)
      case .type(let t):
        code("Clss")
        try type(t)
      case .enumerated(let t, let k, let v):
        code("Enmr")
        try type(t)
        try id(k)
        try id(v)
      case .offset(let t, let v):
        code("rele")
        try type(t)
        number(Int(v), 4)
      case .identifier(let v):
        code("Idnt")
        number(Int(v), 4)
      case .index(let v):
        code("indx")
        number(Int(v), 4)
      case .name(let t, let n):
        code("name")
        try type(t)
        try unicode(n)
      }
    }
  }
}
