import Foundation
import XCTest
@testable import PhotoCraftCore

final class ComponentArchiveTestContext: ComponentBlobEncoding, ComponentBlobDecoding {
  var supportsComponentPages = true
  var usesMappedComponents = true
  var blobs: [String: Data] = [:]
  var maximumRead = 0
  var maximumWrite = 0
  var reads = 0
  var failAfterReads: Int?
  var scratch = 0
  var scratchLimit = RasterTileStore.defaultMaximumBytes
  func storeBytes(_ data: Data) throws -> String {
    maximumWrite = max(maximumWrite, data.count)
    let id = "b\(blobs.count)"; blobs[id] = data; return id
  }
  func bytes(_ ref: String, maximumBytes: Int) throws -> Data {
    reads += 1
    if let limit = failAfterReads, reads > limit { throw CraftError.invalid("Injected owned read failure.") }
    guard let bytes = blobs[ref], bytes.count <= maximumBytes else { throw CraftError.invalid("Missing or oversized owned blob.") }
    maximumRead = max(maximumRead, bytes.count); return bytes
  }
  func tile(_ ref: String) throws -> [Pixel] { throw CraftError.invalid("Raw components must never be decoded as RGBA.") }
  func reserveComponentScratch(bytes: Int) throws {
    guard bytes <= scratchLimit - scratch else { throw RasterScratchFailure.capacity(requiredBytes: scratch + bytes, limitBytes: scratchLimit) }
    scratch += bytes
  }
}
final class ComponentPlaneArchiveTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .f32) throws -> ComponentPlane {
    var p = try ComponentPlane(width: 8193, height: 1, depth: depth, defaultWord: depth == .f32 ? 0x80000000 : 17)
    let words: [UInt32] = depth == .f32 ? [1, 0x80000001, 0x3f800001, 0xc0500000] : depth == .u8 ? [1, 255, 127, 0] : [1, 65535, 32769, 0]
    for (i, word) in words.enumerated() { try p.setWord(word, at: 4094 + i) }
    try p.setWord(words[1], at: 8192); return p
  }
  func testAllDepthsKeepExactRawWordsAndPortablePageBytes() throws {
    for depth in PixelDepth.allCases {
      let p = try fixture(depth), context = ComponentArchiveTestContext()
      let record = try ComponentPlaneArchive.encode(p, context: context)
      let restored = try ComponentPlaneArchive.decode(record, context: context, budget: RasterDecodeBudget(bytes: 1_000_000))
      XCTAssertEqual(restored, p); XCTAssertEqual(restored.residentEditBytes, 0)
      XCTAssertEqual(record.blocks, 3); XCTAssertLessThanOrEqual(context.maximumWrite, 16384)
      for index in 0..<p.count { XCTAssertEqual(restored.word(at: index), p.word(at: index)) }
      if let folder = ProcessInfo.processInfo.environment["PHOTATO_COMPONENT_OUTPUT_DIR"] {
        let url = URL(fileURLWithPath: folder).appendingPathComponent("archive-\(depth.rawValue)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: url.appendingPathComponent("record.json"))
        for (ref, bytes) in context.blobs { try bytes.write(to: url.appendingPathComponent(ref + ".bin")) }
        try restored.row(0).write(to: url.appendingPathComponent("row.bin"))
      }
    }
  }
  func testMaximumSparseGeometryIsBoundedAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var p = try ComponentPlane(width: 300000, height: 300000, depth: depth, defaultWord: 1)
      try p.setWord(0, at: p.count - 1)
      let c = ComponentArchiveTestContext(), record = try ComponentPlaneArchive.encode(p, context: c)
      let restored = try ComponentPlaneArchive.decode(record, context: c, budget: RasterDecodeBudget(bytes: 4_000_000))
      XCTAssertEqual(restored, p); XCTAssertEqual(record.blocks, 1); XCTAssertEqual(c.blobs.count, 2)
      XCTAssertLessThan(c.maximumRead, 20000); XCTAssertLessThan(c.scratch, 3_000_000)
      XCTAssertEqual(restored.word(at: p.count - 2), 1); XCTAssertEqual(restored.word(at: p.count - 1), 0)
    }
  }
  func testUniformMaximumGeometryNeedsNoBlobsOrScratch() throws {
    let p = try ComponentPlane(width: 300000, height: 300000, depth: .f32, defaultWord: 0x80000000), c = ComponentArchiveTestContext()
    let record = try ComponentPlaneArchive.encode(p, context: c)
    XCTAssertEqual(try ComponentPlaneArchive.decode(record, context: c, budget: RasterDecodeBudget(bytes: 0)), p)
    XCTAssertTrue(c.blobs.isEmpty); XCTAssertEqual(c.scratch, 0); XCTAssertEqual(c.reads, 0)
  }
  func testLeafOverflowAndPartialBranchKeepOrderedCounts() throws {
    var p = try ComponentPlane(width: 4096, height: 1025, depth: .u8, defaultWord: 9)
    for key in 0..<1025 { try p.setWord(UInt32(key % 8), at: key * 4096) }
    let c = ComponentArchiveTestContext(), record = try ComponentPlaneArchive.encode(p, context: c)
    XCTAssertEqual(record.level, 1); XCTAssertEqual(record.blocks, 1025)
    XCTAssertEqual(try ComponentPlaneArchive.decode(record, context: c, budget: RasterDecodeBudget(bytes: 1_000_000)), p)
    XCTAssertLessThanOrEqual(c.maximumRead, ComponentPlaneArchive.maximumPageBytes)
    XCTAssertEqual(c.blobs.count, 1028)
  }
  func testTwoBranchLevelsValidateEachSubtree() throws {
    let p = try fixture(.u16), c = ComponentArchiveTestContext()
    var record = try ComponentPlaneArchive.encode(p, context: c)
    for level in 1...2 {
      let e = ComponentPlaneArchive.Entry(lower: 0, upper: 2, count: 3, reference: record.root!)
      record.root = try c.storeBytes(ComponentPlaneArchive.pageBytes(level: level, entries: [e])); record.level = level
    }
    XCTAssertEqual(try ComponentPlaneArchive.decode(record, context: c, budget: nil), p)
    var page = try ComponentPlaneArchive.page(c.blobs[record.root!]!)
    page.entries[0].count = 2
    c.blobs[record.root!] = try ComponentPlaneArchive.pageBytes(level: 2, entries: page.entries)
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
  }
  func testMalformedRootsGeometryCountsAndUnsupportedContextsReject() throws {
    let p = try fixture(), c = ComponentArchiveTestContext(), record = try ComponentPlaneArchive.encode(p, context: c)
    var bad = record
    for update in [ { (r: inout ComponentPlaneArchive.Record) in r.version = 2 }, { $0.width = 300001 }, { $0.blocks = -1 }, { $0.blocks = 4 }, { $0.root = nil }, { $0.root = "../outside" }, { $0.level = 3 }, { $0.defaultWord = 0x7f800000 }] {
      bad = record; update(&bad); XCTAssertThrowsError(try ComponentPlaneArchive.decode(bad, context: c, budget: nil))
    }
    c.supportsComponentPages = false
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
  }
  func testTruncationTrailingBytesAndInvalidPageReferencesReject() throws {
    let p = try fixture(), c = ComponentArchiveTestContext(), record = try ComponentPlaneArchive.encode(p, context: c)
    let ref = record.root!, original = c.blobs[ref]!
    for data in [Data(), Data(original.prefix(11)), Data(original.dropLast()), original + Data([0])] {
      c.blobs[ref] = data; XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
    }
    var bad = original; bad[9] = 1; c.blobs[ref] = bad
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
    for ref in ["", "../b0", String(repeating: "b", count: 97)] {
      XCTAssertThrowsError(try ComponentPlaneArchive.pageBytes(level: 0, entries: [.init(lower: 0, upper: 0, count: 1, reference: ref)]))
    }
  }
  func testDuplicateReorderedRangesCyclesAndMissingBlocksReject() throws {
    let c = ComponentArchiveTestContext(), record = try ComponentPlaneArchive.encode(fixture(), context: c)
    var page = try ComponentPlaneArchive.page(c.blobs[record.root!]!)
    page.entries[1].lower = 0; page.entries[1].upper = 0
    XCTAssertThrowsError(try ComponentPlaneArchive.pageBytes(level: 0, entries: page.entries))
    let root = record.root!
    c.blobs[root] = try ComponentPlaneArchive.pageBytes(level: 1, entries: [.init(lower: 0, upper: 2, count: 3, reference: root)])
    var cyclic = record; cyclic.level = 1
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(cyclic, context: c, budget: nil))
    c.blobs.removeValue(forKey: root)
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
  }
  func testInvalidSampleSizesNonfiniteWordsPaddingAndAlphaReject() throws {
    let c = ComponentArchiveTestContext(), record = try ComponentPlaneArchive.encode(fixture(), context: c)
    let page = try ComponentPlaneArchive.page(c.blobs[record.root!]!), first = page.entries[0].reference, last = page.entries.last!.reference
    let original = c.blobs[first]!
    for bytes in [Data(original.dropLast()), original + Data([0])] {
      c.blobs[first] = bytes; XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
    }
    var bad = original; ComponentPlane.store(0x7fc00000, in: &bad, offset: 0, stride: 4); c.blobs[first] = bad
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
    c.blobs[first] = original
    var padded = c.blobs[last]!; ComponentPlane.store(0, in: &padded, offset: 4, stride: 4); c.blobs[last] = padded
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
    let alpha = try ComponentPlane(width: 1, height: 1, depth: .f32, defaultWord: Float(2).bitPattern)
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(ComponentPlaneArchive.encode(alpha, context: c), context: c, budget: nil, alpha: true))
    XCTAssertEqual(try ComponentPlaneArchive.decode(ComponentPlaneArchive.encode(alpha, context: c), context: c, budget: nil), alpha)
  }
  func testAdmissionIOFailureAndMappedCopyOnWritePreserveOriginal() throws {
    let p = try fixture(), c = ComponentArchiveTestContext(), record = try ComponentPlaneArchive.encode(p, context: c)
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: RasterDecodeBudget(bytes: 1)))
    c.scratchLimit = 1; XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
    c.scratchLimit = RasterTileStore.defaultMaximumBytes; c.failAfterReads = c.reads + 1
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
    c.failAfterReads = nil
    let restored = try ComponentPlaneArchive.decode(record, context: c, budget: nil)
    c.blobs = [:]
    var edited = restored; try edited.setWord(0, at: 4095)
    XCTAssertEqual(restored, p); XCTAssertNotEqual(edited, restored); XCTAssertLessThan(edited.residentEditBytes, 20000)
    let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let newContext = ComponentArchiveTestContext(), newRecord = try ComponentPlaneArchive.encode(p, context: newContext)
    XCTAssertThrowsError(try ComponentPlaneArchive.decode(newRecord, context: newContext, budget: nil, directory: missing))
  }
  func testCancellationDiscardsUnpublishedDecode() async throws {
    let p = try fixture()
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      let c = ComponentArchiveTestContext()
      XCTAssertThrowsError(try ComponentPlaneArchive.encode(p, context: c))
      let record = ComponentPlaneArchive.Record(width: p.width, height: p.height, depth: p.depth, defaultWord: p.defaultWord, blocks: 0, root: nil, level: 0)
      XCTAssertThrowsError(try ComponentPlaneArchive.decode(record, context: c, budget: nil))
      XCTAssertTrue(c.blobs.isEmpty)
    }
    try await task.value
    XCTAssertEqual(p.word(at: 4094), 1)
  }
  func testScratchAllowanceIsSharedWithRGBATiles() throws {
    let store = try RasterTileStore(maximumBytes: TileArchive.byteCount + 4096)
    try store.reserveComponentScratch(bytes: 4096)
    _ = try store.append(RasterTile([Pixel](repeating: .clear, count: TileArchive.pixelCount)))
    XCTAssertThrowsError(try store.reserveComponentScratch(bytes: 1))
    XCTAssertThrowsError(try store.reserveComponentScratch(bytes: Int.max))
    XCTAssertThrowsError(try store.reserveComponentScratch(bytes: -1))
    XCTAssertThrowsError(try store.append(RasterTile([Pixel](repeating: .clear, count: TileArchive.pixelCount))))
  }
}
