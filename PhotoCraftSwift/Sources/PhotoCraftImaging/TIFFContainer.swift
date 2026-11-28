import Foundation
import PhotoCraftCore

/// Bounded classic TIFF directory handling. Writers consume our uncompressed
/// ImageIO intermediate; sample import retains only the fields it needs.
struct TIFFContainer {
  static let byteLimit = 512 * 1024 * 1024
  static let classicFileMaximumBytes = Int(UInt32.max)
  enum Order {
    case little, big
    func bytes(_ value: Int, _ count: Int) -> Data {
      Data((0..<count).map {
        UInt8(truncatingIfNeeded: value >> (8 * (self == .little ? $0 : count - 1 - $0)))
      })
    }
    func number(_ data: Data, _ offset: Int, _ count: Int) -> Int {
      (0..<count).reduce(0) { result, i in
        (result << 8) | Int(data[offset + (self == .big ? i : count - 1 - i)])
      }
    }
  }
  struct Field {
    let tag: Int
    var type: Int
    var count: Int
    var data: Data
    var children: [Directory] = []
    var fileRange: Range<Int>?
    var serialized: PSDReader?
  }
  final class Directory {
    var fields: [Int: Field] = [:]
    var next: Directory?
  }
  private let storage: PSDByteStorage
  var byteCount: Int { storage.count }
  let order: Order
  let root: Directory
  static func isClassic(_ data: Data) -> Bool {
    data.starts(with: [73, 73, 42, 0]) || data.starts(with: [77, 77, 0, 42])
  }
  static func size(_ type: Int) -> Int? {
    switch type {
    case 1, 2, 6, 7: 1
    case 3, 8: 2
    case 4, 9, 11, 13: 4
    case 5, 10, 12: 8
    default: nil
    }
  }
  init(_ input: Data, metadata: Bool, additionalTags: Set<Int> = []) throws {
    try self.init(storage: .memory(Data(input)), maximumBytes: Self.byteLimit,
      metadata: metadata, additionalTags: additionalTags)
  }
  init(file: PSDFileSource, metadata: Bool, additionalTags: Set<Int> = []) throws {
    try self.init(storage: .file(file), maximumBytes: Self.classicFileMaximumBytes,
      metadata: metadata, additionalTags: additionalTags)
  }
  func bytes(at offset: Int, count: Int) throws -> Data {
    guard offset >= 0, count >= 0, offset <= storage.count, count <= storage.count - offset else {
      throw CraftError.invalid("Invalid TIFF sample block extent.")
    }
    return try storage.bytes(at: offset, count: count)
  }
  func reader(at offset: Int, count: Int) throws -> PSDReader {
    guard offset >= 0, count >= 0, offset <= storage.count, count <= storage.count - offset else {
      throw CraftError.invalid("Invalid TIFF sample block extent.")
    }
    return PSDReader(storage: storage, range: offset..<offset + count)
  }
  func reader(for field: Field) throws -> PSDReader {
    guard let range = field.fileRange else { return PSDReader(data: field.data) }
    return try reader(at: range.lowerBound, count: range.count)
  }
  private init(storage: PSDByteStorage, maximumBytes: Int,
    metadata: Bool, additionalTags: Set<Int>, omittedTags: Set<Int> = [],
    followNextDirectories: Bool = true) throws {
    let fileSize = storage.count
    guard (8...maximumBytes).contains(fileSize) else {
      throw CraftError.invalid("Invalid classic TIFF size.")
    }
    let header = try storage.bytes(at: 0, count: 8)
    guard Self.isClassic(header) else { throw CraftError.invalid("Invalid classic TIFF header.") }
    self.storage = storage
    order = header[0] == 73 ? .little : .big
    let byteOrder = order
    var visited: Set<Int> = [], retained = 0
    let sampleTags: Set<Int> = [256, 257, 258, 259, 262, 273, 274, 277, 278, 279, 284, 317,
      322, 323, 324, 325, 338, 339]
    func directory(_ offset: Int, _ depth: Int) throws -> Directory {
      try Task.checkCancellation()
      guard depth < 12, visited.count < 64, offset >= 8, offset <= fileSize - 2,
        visited.insert(offset).inserted else {
        throw CraftError.invalid("Invalid or cyclic TIFF directory.")
      }
      let count = byteOrder.number(try storage.bytes(at: offset, count: 2), 0, 2)
      guard count <= 4096, count <= (fileSize - offset - 2) / 12,
        fileSize - offset - 2 - count * 12 >= 4 else {
        throw CraftError.invalid("Truncated TIFF directory.")
      }
      let table = try storage.bytes(at: offset + 2, count: count * 12 + 4)
      let node = Directory()
      for i in 0..<count {
        let at = i * 12
        let tag = byteOrder.number(table, at, 2)
        if omittedTags.contains(tag) || (!metadata && !sampleTags.contains(tag) && !additionalTags.contains(tag)) { continue }
        let type = byteOrder.number(table, at + 2, 2), elements = byteOrder.number(table, at + 4, 4)
        // Keep the Photoshop layer container as a validated source extent.
        let layerPixels = tag == 37724 && additionalTags.contains(tag)
        let deferredLayerPixels = layerPixels && !metadata
        let limit = deferredLayerPixels ? maximumBytes : Self.byteLimit
        guard let unit = Self.size(type), elements <= limit / unit,
          node.fields[tag] == nil else { throw CraftError.invalid("Invalid TIFF field type or size.") }
        let size = unit * elements
        let start = size <= 4 ? offset + 2 + at + 8 : byteOrder.number(table, at + 8, 4)
        guard start <= fileSize, size <= fileSize - start,
          layerPixels || size <= 32 * 1024 * 1024 - retained else {
          throw CraftError.invalid("Invalid or excessive TIFF metadata.")
        }
        if !layerPixels { retained += size }
        var field = Field(tag: tag, type: type, count: elements,
          data: deferredLayerPixels ? Data() : try storage.bytes(at: start, count: size),
          fileRange: deferredLayerPixels ? start..<start + size : nil)
        if metadata && [330, 34665, 34853, 40965].contains(tag) {
          guard [4, 13].contains(type), elements <= 64 else {
            throw CraftError.invalid("Invalid TIFF child directory pointer.")
          }
          for j in 0..<elements {
            let child = byteOrder.number(field.data, j * 4, 4)
            guard child != 0 else { throw CraftError.invalid("Empty TIFF child directory pointer.") }
            field.children.append(try directory(child, depth + 1))
          }
        }
        node.fields[tag] = field
      }
      let next = byteOrder.number(table, count * 12, 4)
      if metadata && followNextDirectories && next != 0 { node.next = try directory(next, depth + 1) }
      return node
    }
    root = try directory(order.number(header, 4, 4), 0)
  }
  /// Give ImageIO the retained metadata without exposing the original image
  /// bytes or editable layer payload to its whole-file metadata decoder.
  static func metadataSnapshot(_ input: PSDByteStorage) throws -> Data {
    let omitted: Set<Int> = [273, 279, 322, 323, 324, 325, 330, 513, 514, 37724]
    let file = try TIFFContainer(storage: input, maximumBytes: Self.classicFileMaximumBytes,
      metadata: true, additionalTags: [], omittedTags: omitted, followNextDirectories: false)
    let bits = try file.numbers(258)
    guard (1...56).contains(bits.count), bits.allSatisfy({ [8, 16, 32].contains($0) }) else {
      throw CraftError.invalid("Invalid TIFF metadata sample shape.")
    }
    let sampleBytes = bits.reduce(0, +) / 8
    let order = file.order
    var bytes = Data(order == .big ? [77, 77, 0, 42, 0, 0, 0, 0] : [73, 73, 42, 0, 0, 0, 0, 0])
    bytes.append(Data(repeating: 0, count: sampleBytes))
    file.set(256, [1], type: 4); file.set(257, [1], type: 4)
    file.set(259, [1]); file.set(273, [8], type: 4); file.set(278, [1], type: 4)
    file.set(279, [sampleBytes], type: 4); file.set(284, [1]); file.set(317, [1])
    try file.appendDirectories(to: &bytes, order: order)
    return bytes
  }
  func numbers(_ tag: Int, default fallback: [Int]? = nil) throws -> [Int] {
    guard let field = root.fields[tag] else {
      if let fallback { return fallback }
      throw CraftError.invalid("Missing TIFF field \(tag).")
    }
    guard [3, 4].contains(field.type), field.count > 0 else {
      throw CraftError.invalid("Invalid numeric TIFF field \(tag).")
    }
    let size = field.type == 3 ? 2 : 4
    return (0..<field.count).map { order.number(field.data, $0 * size, size) }
  }
  func scalar(_ tag: Int, default fallback: Int? = nil) throws -> Int {
    let values = try numbers(tag, default: fallback.map { [$0] })
    guard values.count == 1 else { throw CraftError.invalid("Expected scalar TIFF field \(tag).") }
    return values[0]
  }
  func set(_ tag: Int, _ values: [Int], type: Int = 3) {
    let size = type == 3 ? 2 : 4
    root.fields[tag] = Field(tag: tag, type: type, count: values.count,
      data: values.reduce(into: Data()) { $0.append(order.bytes($1, size)) })
  }
  func appendDirectories(to output: inout Data, order target: Order) throws {
    let directory = try detachedDirectories(start: output.count, order: target, maximumOutput: Self.byteLimit)
    output.append(directory.payload)
    output.replaceSubrange(4..<8, with: directory.offset)
  }

  /// Serialize absolute classic-TIFF IFD offsets while accumulating only the directory payload.
  func detachedDirectories(start: Int, order target: Order,
    maximumOutput: Int) throws -> (offset: Data, payload: Data) {
    var payload = Data()
    let pointer = try writeDirectories(order: target, maximumOutput: maximumOutput,
      extent: { start + payload.count }, emit: { payload.append($0) },
      patch: { bytes, offset in
        let position = offset - start
        payload.replaceSubrange(position..<position + bytes.count, with: bytes)
      })
    return (pointer, payload)
  }

  /// Writes IFDs in the same order for memory and file sinks. A staged layer
  /// payload stays streamed at its ordinary field position in the TIFF.
  func writeDirectories(order target: Order, maximumOutput: Int, extent: () -> Int,
    emit: (Data) throws -> Void, patch: (Data, Int) throws -> Void) throws -> Data {
    guard (8...Self.classicFileMaximumBytes).contains(maximumOutput), (8...maximumOutput).contains(extent()) else {
      throw CraftError.invalid("Invalid classic TIFF directory offset.")
    }
    func require(_ count: Int) throws {
      guard count <= maximumOutput - extent() else {
        throw CraftError.invalid("TIFF exceeds its output size limit.")
      }
    }
    func align() throws {
      if extent() % 2 != 0 { try require(1); try emit(Data([0])) }
    }
    func append(_ node: Directory) throws -> Int {
      try Task.checkCancellation()
      try align()
      let origin = extent(), fields = node.fields.values.sorted { $0.tag < $1.tag }
      try require(fields.count * 12 + 6)
      try emit(target.bytes(fields.count, 2))
      try emit(Data(repeating: 0, count: fields.count * 12 + 4))
      for (i, field) in fields.enumerated() {
        var payload = field.data
        if !field.children.isEmpty {
          payload = Data()
          for child in field.children { payload.append(target.bytes(try append(child), 4)) }
        } else if order != target {
          let unit: Int
          switch field.type {
          case 3, 8: unit = 2
          case 4, 5, 9, 10, 11, 13: unit = 4
          case 12: unit = 8
          default: unit = 1
          }
          if unit > 1 {
            payload = Data(stride(from: 0, to: payload.count, by: unit).flatMap {
              Array(payload[$0..<$0 + unit].reversed())
            })
          }
        }
        let at = origin + 2 + i * 12
        var entry = target.bytes(field.tag, 2) + target.bytes(field.type, 2) + target.bytes(field.count, 4)
        if var serialized = field.serialized {
          guard field.type == 7, field.count == serialized.remaining, serialized.remaining > 4 else {
            throw CraftError.invalid("Invalid TIFF serialized field extent.")
          }
          try align()
          try require(serialized.remaining)
          entry.append(target.bytes(extent(), 4))
          while serialized.remaining > 0 {
            try emit(serialized.bytes(min(serialized.remaining, AtomicFileWriter.chunkBytes)))
          }
        } else if payload.count <= 4 {
          entry.append(payload)
          entry.append(Data(repeating: 0, count: 4 - payload.count))
        } else {
          try align()
          try require(payload.count)
          entry.append(target.bytes(extent(), 4))
          try emit(payload)
        }
        try patch(entry, at)
      }
      if let next = node.next {
        let pointer = try append(next)
        let position = origin + 2 + fields.count * 12
        try patch(target.bytes(pointer, 4), position)
      }
      return origin
    }
    return target.bytes(try append(root), 4)
  }
}
