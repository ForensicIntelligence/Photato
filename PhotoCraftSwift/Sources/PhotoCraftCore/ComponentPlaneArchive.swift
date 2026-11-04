import Darwin
import Foundation

/// Native86 and ephemeral history share portable little-endian raw samples.
/// A small record names a bounded tree; no whole-plane Data or flat key list.
enum ComponentPlaneArchive {
  static let leafCapacity = 1024, branchCapacity = 256, maximumLevel = 2
  static let maximumPageBytes = 12 + leafCapacity * (12 + 1 + 96)
  private static let magic = Data("PHTCMP01".utf8)
  struct Record: Codable, Equatable {
    var version = 1
    var width: Int
    var height: Int
    var depth: PixelDepth
    var defaultWord: UInt32
    var blocks: Int
    var root: String?
    var level: Int
  }
  struct Entry: Equatable {
    var lower: Int
    var upper: Int
    var count: Int
    var reference: String
  }
  struct Page { var level: Int; var entries: [Entry] }
  private static func validReference(_ ref: String) -> Bool {
    !ref.isEmpty && ref.utf8.count <= 96 && ref.utf8.allSatisfy {
      (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
    }
  }
  static func pageBytes(level: Int, entries: [Entry]) throws -> Data {
    guard (0...maximumLevel).contains(level), !entries.isEmpty,
      entries.count <= (level == 0 ? leafCapacity : branchCapacity) else {
      throw CraftError.invalid("Invalid component archive page size or level.")
    }
    var data = magic + Data([UInt8(level), 0]) + NativeChunkedArchive.integer(UInt64(entries.count), width: 2)
    var previous = -1
    for entry in entries {
      guard entry.lower > previous, entry.upper >= entry.lower, entry.upper <= Int(UInt32.max),
        entry.count > 0, entry.count <= entry.upper - entry.lower + 1,
        level != 0 || (entry.lower == entry.upper && entry.count == 1), validReference(entry.reference) else {
        throw CraftError.invalid("Invalid component archive page range or reference.")
      }
      data.append(NativeChunkedArchive.integer(UInt64(entry.lower), width: 4))
      data.append(NativeChunkedArchive.integer(UInt64(entry.upper), width: 4))
      data.append(NativeChunkedArchive.integer(UInt64(entry.count), width: 4))
      data.append(UInt8(entry.reference.utf8.count)); data.append(contentsOf: entry.reference.utf8)
      previous = entry.upper
    }
    return data
  }
  static func page(_ bytes: Data) throws -> Page {
    let bytes = Data(bytes)
    guard bytes.count >= 12, bytes.count <= maximumPageBytes, bytes.starts(with: magic), bytes[9] == 0 else {
      throw CraftError.invalid("Invalid component archive page header.")
    }
    let level = Int(bytes[8]), count = Int(ComponentPlane.load(bytes, offset: 10, stride: 2))
    guard (0...maximumLevel).contains(level), count > 0,
      count <= (level == 0 ? leafCapacity : branchCapacity), bytes.count >= 12 + count * 14 else {
      throw CraftError.invalid("Invalid component archive page count.")
    }
    var offset = 12, entries: [Entry] = []; entries.reserveCapacity(count)
    for _ in 0..<count {
      guard offset <= bytes.count - 13 else { throw CraftError.invalid("Truncated component archive page.") }
      let lower = Int(ComponentPlane.load(bytes, offset: offset, stride: 4))
      let upper = Int(ComponentPlane.load(bytes, offset: offset + 4, stride: 4))
      let n = Int(ComponentPlane.load(bytes, offset: offset + 8, stride: 4)), size = Int(bytes[offset + 12])
      offset += 13
      guard size > 0, size <= 96, size <= bytes.count - offset,
        let ref = String(data: bytes.subdata(in: offset..<offset + size), encoding: .ascii) else {
        throw CraftError.invalid("Invalid component archive reference length.")
      }
      entries.append(Entry(lower: lower, upper: upper, count: n, reference: ref)); offset += size
    }
    guard offset == bytes.count else { throw CraftError.invalid("Trailing component archive page bytes.") }
    // One canonical validator for encoded and independently decoded pages.
    _ = try pageBytes(level: level, entries: entries)
    return Page(level: level, entries: entries)
  }
  static func encode(_ plane: ComponentPlane, context: any RasterBlobEncoding) throws -> Record {
    try Task.checkCancellation()
    var buffers = [[Entry]](repeating: [], count: maximumLevel + 1), blocks = 0
    func node(_ level: Int) throws -> Entry {
      let values = buffers[level], ref = try context.storeBytes(pageBytes(level: level, entries: values))
      buffers[level] = []
      return Entry(lower: values.first!.lower, upper: values.last!.upper,
        count: values.reduce(0) { $0 + $1.count }, reference: ref)
    }
    func append(_ entry: Entry, level: Int) throws {
      guard level <= maximumLevel else { throw CraftError.invalid("Component archive tree exceeds its geometry.") }
      buffers[level].append(entry)
      if buffers[level].count == (level == 0 ? leafCapacity : branchCapacity) {
        try append(node(level), level: level + 1)
      }
    }
    try plane.forEachStoredBlock { key, block in
      let ref = try block.withBytes(stride: plane.sampleBytes) { try context.storeBytes(Data($0)) }
      try append(Entry(lower: key, upper: key, count: 1, reference: ref), level: 0); blocks += 1
    }
    var root: String?, level = 0
    if blocks > 0 {
      for i in 0...maximumLevel {
        guard !buffers[i].isEmpty else { continue }
        let value = try node(i)
        if buffers.dropFirst(i + 1).allSatisfy({ $0.isEmpty }) { root = value.reference; level = i; break }
        try append(value, level: i + 1)
      }
    }
    return Record(width: plane.width, height: plane.height, depth: plane.depth,
      defaultWord: plane.defaultWord, blocks: blocks, root: root, level: level)
  }
  static func decode(_ record: Record, context: any ComponentBlobDecoding,
    budget: RasterDecodeBudget?, alpha: Bool = false, directory: URL? = nil) throws -> ComponentPlane {
    try Task.checkCancellation()
    guard context.supportsComponentPages, record.version == 1, (0...maximumLevel).contains(record.level) else {
      throw CraftError.invalid("Unsupported component archive version or context.")
    }
    let plane = try ComponentPlane(width: record.width, height: record.height, depth: record.depth, defaultWord: record.defaultWord)
    let blockCount = (plane.count + ComponentPlane.blockSamples - 1) / ComponentPlane.blockSamples
    guard record.blocks >= 0, record.blocks <= blockCount,
      (record.blocks == 0 ? record.root == nil && record.level == 0 : record.root.map(validReference) == true) else {
      throw CraftError.invalid("Invalid component archive root or declared count.")
    }
    func validate(_ word: UInt32) throws {
      try ComponentPlane.validate(word: word, depth: plane.depth)
      if alpha && plane.depth == .f32 {
        let value = Float(bitPattern: word)
        guard value >= 0 && value <= 1 else { throw CraftError.invalid("Invalid floating component alpha.") }
      }
    }
    try validate(record.defaultWord)
    guard record.blocks > 0 else { return plane }
    let blockBytes = ComponentPlane.blockSamples * plane.sampleBytes, bitmapBytes = (blockCount + 7) / 8
    let pageSize = Int(getpagesize()), sampleOffset = ((bitmapBytes + pageSize - 1) / pageSize) * pageSize
    let scratchBytes = sampleOffset + record.blocks * blockBytes
    // Legacy owned reads keep their full sample admission. Paged reads charge
    // bounded transfers and the presence bitmap, separately from mapped samples.
    try budget?.reserve(bytes: context.usesMappedComponents ? bitmapBytes + (record.level + 1) * maximumPageBytes + blockBytes * 2 : plane.logicalBytes + (record.level + 1) * maximumPageBytes + blockBytes * 2)
    try context.reserveComponentScratch(bytes: scratchBytes)
    let writer = try ComponentPlaneWriter(plane: plane, maximumBytes: scratchBytes, directory: directory)
    var previous = -1, total = 0
    func visit(_ ref: String, level: Int, expected: Entry? = nil) throws -> Entry {
      try Task.checkCancellation()
      let page = try page(context.bytes(ref, maximumBytes: maximumPageBytes))
      guard page.level == level else { throw CraftError.invalid("Component archive tree level mismatch.") }
      let summary = Entry(lower: page.entries.first!.lower, upper: page.entries.last!.upper,
        count: page.entries.reduce(0) { $0 + $1.count }, reference: ref)
      guard summary.upper < blockCount, summary.count <= record.blocks,
        expected == nil || expected == summary else { throw CraftError.invalid("Component archive subtree range/count mismatch.") }
      for entry in page.entries {
        try Task.checkCancellation()
        if level > 0 { _ = try visit(entry.reference, level: level - 1, expected: entry); continue }
        guard entry.lower > previous, total < record.blocks else { throw CraftError.invalid("Duplicate or excess component archive blocks.") }
        let bytes = try context.bytes(entry.reference, maximumBytes: blockBytes)
        guard bytes.count == blockBytes else { throw CraftError.invalid("Invalid component archive sample block length.") }
        let valid = min(ComponentPlane.blockSamples, plane.count - entry.lower * ComponentPlane.blockSamples)
        for i in 0..<ComponentPlane.blockSamples {
          let word = ComponentPlane.load(bytes, offset: i * plane.sampleBytes, stride: plane.sampleBytes)
          try validate(word)
          guard i < valid || word == plane.defaultWord else { throw CraftError.invalid("Invalid component archive padding.") }
        }
        try writer.write(key: entry.lower, block: ComponentBlock(validatedBytes: bytes))
        previous = entry.lower; total += 1
      }
      return summary
    }
    let summary = try visit(record.root!, level: record.level)
    guard total == record.blocks, summary.count == record.blocks else { throw CraftError.invalid("Component archive block count mismatch.") }
    return plane.retaining(try writer.finish())
  }
}
