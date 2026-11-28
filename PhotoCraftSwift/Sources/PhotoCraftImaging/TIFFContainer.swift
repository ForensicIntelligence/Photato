import Foundation
import PhotoCraftCore

/// Bounded classic TIFF and BigTIFF directory reading and writing.
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
    func fileInteger(_ data: Data, _ offset: Int, _ count: Int) throws -> Int {
      let value = number(data, offset, count)
      guard value >= 0 else { throw CraftError.invalid("TIFF integer exceeds the addressable file range.") }
      return value
    }
  }
  struct Layout {
    let bigTIFF: Bool
    var pointerBytes: Int { bigTIFF ? 8 : 4 }
    var countBytes: Int { bigTIFF ? 8 : 2 }
    var entryBytes: Int { 4 + pointerBytes * 2 }
    var headerBytes: Int { bigTIFF ? 16 : 8 }
    var headerPointerOffset: Int { headerBytes - pointerBytes }
    var offsetFieldType: Int { bigTIFF ? 16 : 4 }
    var maximumFileBytes: Int { bigTIFF ? PSDCodec.maximumFileBytes : TIFFContainer.classicFileMaximumBytes }

    func header(order: Order) -> Data {
      var data = Data(repeating: order == .big ? 77 : 73, count: 2)
      data.append(order.bytes(bigTIFF ? 43 : 42, 2))
      if bigTIFF {
        data.append(order.bytes(8, 2))
        data.append(order.bytes(0, 2))
      }
      data.append(Data(repeating: 0, count: pointerBytes))
      return data
    }

    func padding(at offset: Int) -> Int {
      let alignment = bigTIFF ? 8 : 2
      return (alignment - offset % alignment) % alignment
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
  let isBigTIFF: Bool
  var headerBytes: Int { isBigTIFF ? 16 : 8 }
  let root: Directory
  static func isBigTIFF(_ data: Data) -> Bool {
    data.starts(with: [73, 73, 43, 0]) || data.starts(with: [77, 77, 0, 43])
  }
  static func recognizes(_ data: Data) -> Bool { isClassic(data) || isBigTIFF(data) }
  static func isClassic(_ data: Data) -> Bool {
    data.starts(with: [73, 73, 42, 0]) || data.starts(with: [77, 77, 0, 42])
  }
  static func size(_ type: Int) -> Int? {
    switch type {
    case 1, 2, 6, 7: 1
    case 3, 8: 2
    case 4, 9, 11, 13: 4
    case 5, 10, 12, 16, 17, 18: 8
    default: nil
    }
  }
  init(_ input: Data, metadata: Bool, additionalTags: Set<Int> = [], inspectSubIFDs: Bool = false) throws {
    try self.init(storage: .memory(Data(input)), maximumBytes: Self.byteLimit,
      metadata: metadata, additionalTags: additionalTags, inspectSubIFDs: inspectSubIFDs)
  }
  init(file: PSDFileSource, metadata: Bool, additionalTags: Set<Int> = [], inspectSubIFDs: Bool = false) throws {
    try self.init(storage: .file(file), maximumBytes: PSDCodec.maximumFileBytes,
      metadata: metadata, additionalTags: additionalTags, inspectSubIFDs: inspectSubIFDs)
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
    followNextDirectories: Bool = true, inspectSubIFDs: Bool = false) throws {
    let fileSize = storage.count
    guard (8...maximumBytes).contains(fileSize) else {
      throw CraftError.invalid("Invalid TIFF file size.")
    }
    let header = try storage.bytes(at: 0, count: min(fileSize, 16))
    guard Self.recognizes(header) else { throw CraftError.invalid("Invalid TIFF header.") }
    let big = Self.isBigTIFF(header)
    let byteOrder: Order = header[0] == 73 ? .little : .big
    let layout = Layout(bigTIFF: big)
    let headerLength = layout.headerBytes
    if big {
      guard header.count >= headerLength, byteOrder.number(header, 4, 2) == 8,
        byteOrder.number(header, 6, 2) == 0 else { throw CraftError.invalid("Invalid BigTIFF offset header.") }
    } else if fileSize > Self.classicFileMaximumBytes {
      throw CraftError.invalid("Classic TIFF exceeds its 32-bit file size limit.")
    }
    let pointerBytes = layout.pointerBytes
    let countBytes = layout.countBytes
    let entryBytes = layout.entryBytes
    let valuePosition = 4 + pointerBytes
    self.storage = storage
    order = byteOrder
    isBigTIFF = big
    var visited: Set<Int> = [], retained = 0
    let sampleTags: Set<Int> = [256, 257, 258, 259, 262, 273, 274, 277, 278, 279, 284, 317,
      322, 323, 324, 325, 338, 339]
    func directory(_ offset: Int, _ depth: Int) throws -> Directory {
      try Task.checkCancellation()
      guard depth < 12, visited.count < 64, offset >= headerLength,
        offset <= fileSize - countBytes - pointerBytes, visited.insert(offset).inserted else {
        throw CraftError.invalid("Invalid or cyclic TIFF directory.")
      }
      let count = try byteOrder.fileInteger(storage.bytes(at: offset, count: countBytes), 0, countBytes)
      guard count <= 4096, count <= (fileSize - offset - countBytes - pointerBytes) / entryBytes else {
        throw CraftError.invalid("Truncated TIFF directory.")
      }
      let endOfEntries = count * entryBytes
      let table = try storage.bytes(at: offset + countBytes, count: endOfEntries + pointerBytes)
      let node = Directory()
      for i in 0..<count {
        let at = i * entryBytes
        let tag = byteOrder.number(table, at, 2)
        let isInspectedSubIFD = inspectSubIFDs && tag == 330
        if omittedTags.contains(tag)
          || (!metadata && !sampleTags.contains(tag) && !additionalTags.contains(tag) && !isInspectedSubIFD) { continue }
        let type = byteOrder.number(table, at + 2, 2)
        let elements = try byteOrder.fileInteger(table, at + 4, pointerBytes)
        // Keep the Photoshop layer container as a validated source extent.
        let layerPixels = tag == 37724 && additionalTags.contains(tag)
        let deferredLayerPixels = layerPixels && !metadata
        let limit = deferredLayerPixels ? maximumBytes : Self.byteLimit
        guard let unit = Self.size(type), (big || type < 16), elements <= limit / unit,
          node.fields[tag] == nil else { throw CraftError.invalid("Invalid TIFF field type or size.") }
        let size = unit * elements
        let start = try size <= pointerBytes ? offset + countBytes + at + valuePosition
          : byteOrder.fileInteger(table, at + valuePosition, pointerBytes)
        guard start >= headerLength, start <= fileSize, size <= fileSize - start,
          layerPixels || size <= 32 * 1024 * 1024 - retained else {
          throw CraftError.invalid("Invalid or excessive TIFF metadata.")
        }
        if !layerPixels { retained += size }
        var field = Field(tag: tag, type: type, count: elements,
          data: deferredLayerPixels ? Data() : try storage.bytes(at: start, count: size),
          fileRange: deferredLayerPixels ? start..<start + size : nil)
        if isInspectedSubIFD || (metadata && [330, 34665, 34853, 40965].contains(tag)) {
          guard [4, 13, 16, 18].contains(type), elements <= 64 else {
            throw CraftError.invalid("Invalid TIFF child directory pointer.")
          }
          for j in 0..<elements {
            let child = try byteOrder.fileInteger(field.data, j * unit, unit)
            guard child != 0 else { throw CraftError.invalid("Empty TIFF child directory pointer.") }
            field.children.append(try directory(child, depth + 1))
          }
        }
        node.fields[tag] = field
      }
      if metadata, followNextDirectories {
        let next = try byteOrder.fileInteger(table, endOfEntries, pointerBytes)
        if next != 0 { node.next = try directory(next, depth + 1) }
      }
      return node
    }
    root = try directory(byteOrder.fileInteger(header, layout.headerPointerOffset, pointerBytes), 0)
  }
  /// Give ImageIO the retained metadata without exposing the original image
  /// bytes or editable layer payload to its whole-file metadata decoder.
  func metadataSnapshot() throws -> Data {
    let omitted: Set<Int> = [273, 279, 322, 323, 324, 325, 330, 347, 513, 514, 529, 530, 531, 532, 37724]
    let file = try TIFFContainer(storage: storage, maximumBytes: PSDCodec.maximumFileBytes,
      metadata: true, additionalTags: [], omittedTags: omitted, followNextDirectories: false)
    let bits = try file.numbers(258, default: [1])
    guard (1...56).contains(bits.count), bits.allSatisfy({ [1, 2, 4, 8, 16, 32].contains($0) }) else {
      throw CraftError.invalid("Invalid TIFF metadata sample shape.")
    }
    let sampleBytes = (bits.reduce(0, +) + 7) / 8
    let order = file.order
    if file.isBigTIFF { file.narrowMetadata(file.root) }
    if try file.scalar(262) == 6 { file.set(262, [2]) }
    var bytes = Data(order == .big ? [77, 77, 0, 42, 0, 0, 0, 0] : [73, 73, 42, 0, 0, 0, 0, 0])
    bytes.append(Data(repeating: 0, count: sampleBytes))
    file.set(256, [1], type: 4); file.set(257, [1], type: 4)
    file.set(259, [1]); file.set(273, [8], type: 4); file.set(278, [1], type: 4)
    file.set(279, [sampleBytes], type: 4); file.set(284, [1]); file.set(317, [1])
    try file.appendDirectories(to: &bytes, order: order)
    return bytes
  }
  /// The metadata bridge is a small classic TIFF. Strip/tile addresses and
  /// layer data never enter it. Current directory pointers are written afresh.
  private func narrowMetadata(_ node: Directory) {
    for (tag, field) in node.fields where field.type >= 16 {
      var retyped = field
      if !field.children.isEmpty {
        retyped.type = 4
      } else if field.type == 16 {
        let values = (0..<field.count).map { order.number(field.data, $0 * 8, 8) }
        guard values.allSatisfy({ (0...Int(UInt32.max)).contains($0) }) else {
          node.fields.removeValue(forKey: tag)
          continue
        }
        retyped.type = 4
        retyped.data = values.reduce(into: Data()) { $0.append(order.bytes($1, 4)) }
      } else {
        node.fields.removeValue(forKey: tag)
        continue
      }
      node.fields[tag] = retyped
    }
    for field in node.fields.values { for child in field.children { narrowMetadata(child) } }
  }
  /// Keep JPEG table and color context intact for the native TIFF decoder.
  static let jpegFields: Set<Int> = [347, 529, 530, 531, 532]

  private init(order: Order) {
    self.order = order
    isBigTIFF = false
    storage = .memory(Data())
    root = Directory()
  }

  func jpegStrip(offset: Int, count: Int, width: Int, rows: Int, components: Int) throws -> Data {
    guard (1...65_535).contains(width), (1...65_535).contains(rows),
      width * rows <= Self.byteLimit / (components == 1 ? 1 : 4),
      (1...Self.byteLimit - 1_048_576).contains(count) else {
      throw CraftError.invalid("Invalid or oversized TIFF JPEG block.")
    }
    let encoded = try bytes(at: offset, count: count)
    guard Self.completeJPEGStream(encoded) else { throw CraftError.invalid("Truncated TIFF JPEG block.") }
    let photo = try scalar(262)
    let block = TIFFContainer(order: order)
    var data = Data(order == .big ? [77, 77, 0, 42, 0, 0, 0, 0] : [73, 73, 42, 0, 0, 0, 0, 0])
    data.append(encoded)
    block.set(256, [width], type: 4)
    block.set(257, [rows], type: 4)
    block.set(258, [Int](repeating: 8, count: components))
    block.set(259, [7])
    block.set(262, [components == 1 ? (photo == 0 ? 0 : 1) : photo])
    block.set(273, [8], type: 4)
    block.set(277, [components])
    block.set(278, [rows], type: 4)
    block.set(279, [count], type: 4)
    block.set(284, [1])
    if let tables = root.fields[347] {
      guard tables.type == 7, tables.data.count <= 65_535,
        Self.completeJPEGStream(tables.data) else {
        throw CraftError.invalid("Invalid TIFF JPEG tables.")
      }
      block.root.fields[347] = tables
    }
    if photo == 6 {
      for tag in Self.jpegFields where tag != 347 {
        block.root.fields[tag] = root.fields[tag]
      }
    }
    try block.appendDirectories(to: &data, order: order)
    return data
  }

  private static func completeJPEGStream(_ data: Data) -> Bool {
    data.count >= 4 && data.starts(with: [0xff, 0xd8]) && data.suffix(2).elementsEqual([0xff, 0xd9])
  }

  func numbers(_ tag: Int, default fallback: [Int]? = nil) throws -> [Int] {
    guard let field = root.fields[tag] else {
      if let fallback { return fallback }
      throw CraftError.invalid("Missing TIFF field \(tag).")
    }
    guard ([3, 4].contains(field.type) || (isBigTIFF && field.type == 16)), field.count > 0 else {
      throw CraftError.invalid("Invalid numeric TIFF field \(tag).")
    }
    let size = field.type == 3 ? 2 : field.type == 4 ? 4 : 8
    return try (0..<field.count).map { try order.fileInteger(field.data, $0 * size, size) }
  }
  func scalar(_ tag: Int, default fallback: Int? = nil) throws -> Int {
    let values = try numbers(tag, default: fallback.map { [$0] })
    guard values.count == 1 else { throw CraftError.invalid("Expected scalar TIFF field \(tag).") }
    return values[0]
  }
  func set(_ tag: Int, _ values: [Int], type: Int = 3) {
    let size = type == 3 ? 2 : type == 16 ? 8 : 4
    root.fields[tag] = Field(tag: tag, type: type, count: values.count,
      data: values.reduce(into: Data()) { $0.append(order.bytes($1, size)) })
  }
  func appendDirectories(to output: inout Data, order target: Order,
    layout: Layout = .init(bigTIFF: false)) throws {
    let directory = try detachedDirectories(start: output.count, order: target,
      maximumOutput: Self.byteLimit, layout: layout)
    output.append(directory.payload)
    output.replaceSubrange(layout.headerPointerOffset..<layout.headerBytes, with: directory.offset)
  }

  /// Serialize absolute IFD offsets while accumulating only the directory payload.
  func detachedDirectories(start: Int, order target: Order,
    maximumOutput: Int, layout: Layout = .init(bigTIFF: false)) throws -> (offset: Data, payload: Data) {
    var payload = Data()
    let pointer = try writeDirectories(order: target, maximumOutput: maximumOutput, layout: layout,
      extent: { start + payload.count }, emit: { payload.append($0) },
      patch: { bytes, offset in
        let position = offset - start
        payload.replaceSubrange(position..<position + bytes.count, with: bytes)
      })
    return (pointer, payload)
  }

  /// Writes IFDs in the same order for memory and file sinks. A staged layer
  /// payload stays streamed at its ordinary field position in the TIFF.
  func writeDirectories(order target: Order, maximumOutput: Int,
    layout: Layout = .init(bigTIFF: false), extent: () -> Int,
    emit: (Data) throws -> Void, patch: (Data, Int) throws -> Void) throws -> Data {
    guard (layout.headerBytes...layout.maximumFileBytes).contains(maximumOutput),
      (layout.headerBytes...maximumOutput).contains(extent()) else {
      throw CraftError.invalid("Invalid TIFF directory offset.")
    }
    let pointerBytes = layout.pointerBytes, countBytes = layout.countBytes, entryBytes = layout.entryBytes
    func require(_ count: Int) throws {
      guard count <= maximumOutput - extent() else {
        throw CraftError.invalid("TIFF exceeds its output size limit.")
      }
    }
    func align() throws {
      let padding = layout.padding(at: extent())
      if padding > 0 { try require(padding); try emit(Data(repeating: 0, count: padding)) }
    }
    func append(_ node: Directory) throws -> Int {
      try Task.checkCancellation()
      try align()
      let origin = extent(), fields = node.fields.values.sorted { $0.tag < $1.tag }
      let tableBytes = fields.count * entryBytes
      try require(countBytes + tableBytes + pointerBytes)
      try emit(target.bytes(fields.count, countBytes))
      try emit(Data(repeating: 0, count: tableBytes + pointerBytes))
      for (i, field) in fields.enumerated() {
        var payload = field.data
        var type = field.type
        if !field.children.isEmpty {
          if layout.bigTIFF { type = 18 }
          payload = Data()
          for child in field.children { payload.append(target.bytes(try append(child), pointerBytes)) }
        } else if order != target {
          let unit: Int
          switch field.type {
          case 3, 8: unit = 2
          case 4, 5, 9, 10, 11, 13: unit = 4
          case 12, 16, 17, 18: unit = 8
          default: unit = 1
          }
          if unit > 1 {
            payload = Data(stride(from: 0, to: payload.count, by: unit).flatMap {
              Array(payload[$0..<$0 + unit].reversed())
            })
          }
        }
        let at = origin + countBytes + i * entryBytes
        var entry = target.bytes(field.tag, 2) + target.bytes(type, 2) + target.bytes(field.count, pointerBytes)
        if var serialized = field.serialized {
          guard field.type == 7, field.count == serialized.remaining, serialized.remaining > pointerBytes else {
            throw CraftError.invalid("Invalid TIFF serialized field extent.")
          }
          try align()
          try require(serialized.remaining)
          entry.append(target.bytes(extent(), pointerBytes))
          while serialized.remaining > 0 {
            try emit(serialized.bytes(min(serialized.remaining, AtomicFileWriter.chunkBytes)))
          }
        } else if payload.count <= pointerBytes {
          entry.append(payload)
          entry.append(Data(repeating: 0, count: pointerBytes - payload.count))
        } else {
          try align()
          try require(payload.count)
          entry.append(target.bytes(extent(), pointerBytes))
          try emit(payload)
        }
        try patch(entry, at)
      }
      if let next = node.next {
        let pointer = try append(next)
        let position = origin + countBytes + tableBytes
        try patch(target.bytes(pointer, pointerBytes), position)
      }
      return origin
    }
    return target.bytes(try append(root), pointerBytes)
  }
}
