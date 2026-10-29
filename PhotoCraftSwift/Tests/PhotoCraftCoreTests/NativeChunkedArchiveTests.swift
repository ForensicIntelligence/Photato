import CryptoKit
import Darwin
import Foundation
import XCTest

@testable import PhotoCraftCore

final class NativeChunkedArchiveTests: XCTestCase {
  func temporary() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
      "NativeChunkedTest-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  func testFileAndDataKeepExactSamplesAndLegacyCompatibility() throws {
    let folder = try temporary()
    for depth in [PixelDepth.u8, .u16, .f32] {
      var doc = try CraftDocument(width: 128, height: 65, depth: depth)
      var pixels = try Surface(width: doc.width, height: doc.height, depth: depth)
      pixels.setPixel(x: 0, y: 0, Pixel(0.3, 0.2, 0.8, 0.4))
      pixels.setPixel(x: 65, y: 64, .white)
      doc.layers[0].content = .raster(pixels)
      if depth == .f32 { doc = try HistoryScratchTests().document() }
      let bytes = try NativeArchive.encodeChunked(doc)
      let url = folder.appendingPathComponent("fixture.photato")
      try NativeArchive.write(doc, to: url)
      XCTAssertEqual(try Data(contentsOf: url), bytes)
      let read = try NativeArchive.read(url)
      XCTAssertEqual(read, doc)
      XCTAssertEqual(try NativeArchive.decode(bytes), doc)
      XCTAssertEqual(try NativeArchive.encode(read), try NativeArchive.encode(doc))
      XCTAssertTrue(bytes.starts(with: NativeChunkedArchive.header))
      XCTAssertEqual(try NativeArchive.dimensions(bytes).width, doc.width)
      XCTAssertEqual(try NativeArchive.dimensions(bytes).height, doc.height)
      let legacy = try NativeArchive.encode(doc)
      XCTAssertTrue(legacy.starts(with: Data("bplist00".utf8)))
      try legacy.write(to: url)
      XCTAssertEqual(try NativeArchive.read(url), doc)
      XCTAssertEqual(try NativeArchive.dimensions(legacy).width, doc.width)
    }
  }
  func testOffsetsIntegrityVersionAndTruncationReject() throws {
    let doc = try HistoryScratchTests().document()
    let data = try NativeArchive.encodeChunked(doc)
    var cases = [Data(data.prefix(15)), Data(data.dropLast()), Data(data.prefix(16))]
    for index in [8, 12, 16, data.count - 57, data.count - 1] {
      var invalid = data
      invalid[index] ^= 1
      cases.append(invalid)
    }
    var invalid = data
    invalid.replaceSubrange(
      data.count - 48..<data.count - 40, with: repeatElement(UInt8(255), count: 8))
    cases.append(invalid)
    for bytes in cases { XCTAssertThrowsError(try NativeArchive.decode(bytes)) }
    XCTAssertThrowsError(try NativeArchive.decode(data, rasterByteLimit: 0))
    XCTAssertThrowsError(try NativeArchive.decode(data, rasterByteLimit: -1))
  }
  func changedManifest(_ data: Data, _ change: (inout [String: Any]) throws -> Void) throws -> Data
  {
    let footer = Data(data.suffix(NativeChunkedArchive.footerSize))
    let start = Int(NativeChunkedArchive.number(footer, at: 8))
    let length = Int(NativeChunkedArchive.number(footer, at: 16))
    var object = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: data.subdata(in: start..<start + length), format: nil) as? [String: Any])
    try change(&object)
    let metadata = try PropertyListSerialization.data(
      fromPropertyList: object, format: .binary, options: 0)
    return Data(data.prefix(start)) + metadata + NativeChunkedArchive.footerMagic
      + NativeChunkedArchive.integer(UInt64(start), width: 8)
      + NativeChunkedArchive.integer(UInt64(metadata.count), width: 8)
      + Data(SHA256.hash(data: metadata))
  }
  func testRehashedMaliciousManifestCannotBypassRangeOwnershipOrBlobChecks() throws {
    let data = try NativeArchive.encodeChunked(HistoryScratchTests().document())
    for kind in 0..<6 {
      let changed = try changedManifest(data) { object in
        var records = try XCTUnwrap(object["blobs"] as? [[String: Any]])
        switch kind {
        case 0: records[0]["offset"] = 0
        case 1: records[0]["length"] = UInt64.max
        case 2: records.append(records[0])
        case 3: records[0]["digest"] = String(repeating: "z", count: 64)
        case 4: object["version"] = 12
        default:
          let blank = try CraftDocument(width: 128, height: 65)
          let legacy = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: NativeArchive.encode(blank), format: nil)
              as? [String: Any])
          object["document"] = legacy["document"]  // Keeps valid blob records, removes all uses.
        }
        object["blobs"] = records
      }
      XCTAssertThrowsError(try NativeArchive.decode(changed), "Manifest case \(kind)")
    }
  }
  func testFailedFileOutputRetainsExistingDestinationAndCleansStaging() throws {
    let folder = try temporary()
    let doc = try HistoryScratchTests().document()
    let target = folder.appendingPathComponent("existing.photato")
    let original = Data([1, 2, 3])
    try original.write(to: target)
    XCTAssertThrowsError(try NativeArchive.write(doc, to: target, maximumBytes: 20))
    XCTAssertEqual(try Data(contentsOf: target), original)
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: folder.path), ["existing.photato"])
    XCTAssertThrowsError(try NativeArchive.encodeChunked(doc, maximumBytes: 20))
    XCTAssertThrowsError(try NativeArchive.write(doc, to: target, maximumBytes: Int.max))
    XCTAssertEqual(try Data(contentsOf: target), original)
    let retainedWriter = try AtomicFileWriter(to: target)
    try retainedWriter.append(Data([8, 9]))
    retainedWriter.discard()
    XCTAssertThrowsError(try retainedWriter.commit())
    XCTAssertEqual(
      try FileManager.default.contentsOfDirectory(atPath: folder.path), ["existing.photato"])
    XCTAssertEqual(try Data(contentsOf: target), original)
  }
  func testFileReaderBoundsReadsAndRejectsReplacementOrMutation() throws {
    let folder = try temporary()
    let url = folder.appendingPathComponent("input")
    let bytes = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
    try bytes.write(to: url)
    let source = try NativeArchiveFileSource(url)
    XCTAssertEqual(try source.read(at: 5, count: bytes.count - 5), bytes.dropFirst(5))
    XCTAssertLessThanOrEqual(source.maximumReadBytes, 65_536)
    XCTAssertThrowsError(try source.read(at: Int.max, count: 1))
    let file = try FileHandle(forWritingTo: url)
    try file.seek(toOffset: 1)
    try file.write(contentsOf: Data([99]))
    try file.close()
    XCTAssertThrowsError(try source.read(at: 0, count: 4))
    try bytes.write(to: url)
    let replaced = try NativeArchiveFileSource(url)
    try bytes.write(to: url, options: .atomic)
    XCTAssertThrowsError(try replaced.validateUnchanged())
    try Data().write(to: url)
    XCTAssertThrowsError(try NativeArchive.read(url))
  }
  func testRegularSymlinkWorksAndNonregularFilesRejectWithoutBlocking() throws {
    let folder = try temporary()
    let url = folder.appendingPathComponent("input.photato")
    let doc = try HistoryScratchTests().document()
    try NativeArchive.write(doc, to: url)
    let link = folder.appendingPathComponent("link.photato")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
    XCTAssertEqual(try NativeArchive.read(link), doc)
    XCTAssertThrowsError(try NativeArchive.read(folder))
    let pipe = folder.appendingPathComponent("pipe.photato")
    XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
    XCTAssertThrowsError(try NativeArchive.read(pipe))
  }
  func testReusableTileDecoderKeepsEarlierArraysAndRejectsNonfiniteData() throws {
    let decoder = TileArchive.Decoder()
    let a = [Pixel](repeating: Pixel(-0.0, 0.3, 4, 1), count: TileArchive.pixelCount)
    let first = try decoder.decode(TileArchive.encode(a))
    let b = [Pixel](repeating: .white, count: TileArchive.pixelCount)
    XCTAssertEqual(try decoder.decode(TileArchive.encode(b)), b)
    XCTAssertEqual(first[0].r.bitPattern, 0x8000_0000)
    XCTAssertEqual(first, a)
    var raw = Data([0])
    for _ in 0..<TileArchive.pixelCount { raw.append(TileArchive.encodeSample(.white)) }
    raw.replaceSubrange(1..<5, with: [0, 0, 128, 127])  // positive infinity
    XCTAssertThrowsError(try decoder.decode(raw))
    XCTAssertEqual(try decoder.decode(TileArchive.encode(a)), a)
  }
  func testCancelledNativeArchiveWorkDoesNotPublish() async throws {
    let url = try temporary().appendingPathComponent("cancelled.photato")
    let doc = try HistoryScratchTests().document()
    let original = Data([7, 8])
    try original.write(to: url)
    let bytes = try NativeArchive.encodeChunked(doc)
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      XCTAssertThrowsError(try NativeArchive.encodeChunked(doc))
      XCTAssertThrowsError(try NativeArchive.write(doc, to: url))
      XCTAssertThrowsError(try NativeArchive.decode(bytes))
      XCTAssertThrowsError(try NativeArchive.read(url))
    }
    try await task.value
    XCTAssertEqual(try Data(contentsOf: url), original)
  }
}
