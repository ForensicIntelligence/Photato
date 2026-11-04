import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class LargeSelectionFileTests: XCTestCase {
  struct Point: Decodable { let x: Int, y: Int, word: Int }
  struct Vector: Decodable {
    let file: String, name: String, fileSHA256: String, planeSHA256: String, channelName: String
    let width: Int, height: Int, depth: Int, version: Int, compression: Int, kind: Int, decodedFileBytes: Int
    let points: [Point]
    let ramp: Bool
  }
  struct Manifest: Decodable { let cases: [Vector] }
  func vectors() throws -> [Vector] {
    try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder().appendingPathComponent("manifest.json"))).cases
  }
  func folder() throws -> URL {
    try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures/large-selection-files")
  }
  func input(_ vector: Vector) throws -> Data {
    let packed = try Data(contentsOf: folder().appendingPathComponent(vector.file))
    // This is only the fixture transport. Its independently pinned full-file SHA
    // must match before any PSD decoding assertion can use the bytes.
    let data = Data(try PSDChannelCodec.inflate(packed, expected: vector.decodedFileBytes))
    XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), vector.fileSHA256)
    return data
  }
  func expected(_ vector: Vector) throws -> Surface {
    let depth: PixelDepth = vector.depth == 8 ? .u8 : .u16
    var result = try Surface(width: vector.width, height: vector.height, depth: depth, fill: .black)
    let maximum = Float((1 << vector.depth) - 1)
    if vector.ramp {
      for x in 0..<vector.width { let value = Float(x) / maximum; result.setPixel(x: x, y: 0, Pixel(value, value, value)) }
    } else {
      for point in vector.points { let value = Float(point.word) / maximum; result.setPixel(x: point.x, y: point.y, Pixel(value, value, value)) }
    }
    return result
  }
  func assertSelection(_ document: CraftDocument, _ vector: Vector, file: StaticString = #filePath, line: UInt = #line) throws {
    XCTAssertTrue(document.isChannelOnly, file: file, line: line)
    XCTAssertTrue(document.layers.isEmpty, file: file, line: line)
    XCTAssertNil(document.inkMode, file: file, line: line)
    let channel = try XCTUnwrap(document.alphaChannels?.first, file: file, line: line)
    XCTAssertEqual(document.alphaChannels?.count, 1, file: file, line: line)
    XCTAssertEqual(channel.name, vector.channelName, file: file, line: line)
    XCTAssertEqual(channel.psdIdentifier, 2, file: file, line: line)
    XCTAssertEqual(channel.psdDisplay?.count, 13, file: file, line: line)
    XCTAssertEqual(channel.pixels, try expected(vector), file: file, line: line)
    XCTAssertGreaterThan(channel.pixels.mappedBytes, 0, file: file, line: line)
    XCTAssertLessThan(document.estimatedBytes, 16 * 1024 * 1024, file: file, line: line)
  }
  func capture(_ data: Data, name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else { return }
    let folder = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try data.write(to: folder.appendingPathComponent(name))
  }

  func testIndependentLargeInputsCoverAllDepthsContainersAndFourCodecs() throws {
    let cases = try vectors().filter { $0.width == 4096 && $0.kind == 1 }
    XCTAssertEqual(cases.count, 16)
    for vector in cases {
      XCTAssertGreaterThan(vector.width * vector.height, 8_388_608)
      let document = try PSDCodec.readPaged(input(vector), heapByteLimit: 64 * 1024 * 1024)
      try assertSelection(document, vector)
    }
    let reference = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: folder().appendingPathComponent("photoshop-reference.json"))) as? [String: Any])
    XCTAssertEqual(reference["samples_each"] as? Int, 8_392_704)
    XCTAssertEqual(cases.first { $0.depth == 8 }?.planeSHA256, reference["reference_planeSHA256"] as? String)
  }

  func testMaximumPSBSideAndAboveDensePlaneUsePagedStorage() throws {
    let cases = try vectors().filter { $0.name.hasPrefix("max-side") || $0.name.hasPrefix("above-dense") }
    XCTAssertEqual(cases.count, 3)
    for vector in cases {
      let document = try PSDCodec.readPaged(input(vector), heapByteLimit: 64 * 1024 * 1024)
      try assertSelection(document, vector)
      XCTAssertEqual(document.width == 300000 || document.width * document.height > Surface.maximumDensePixels, true)
      XCTAssertEqual(document.minimumArchiveVersion, 85)
    }
  }

  func testEveryUInt16WordRemainsExactAcrossPagedDecodeAndNativeReopen() throws {
    let vector = try XCTUnwrap(vectors().first { $0.ramp })
    let document = try PSDCodec.readPaged(input(vector)), plane = try XCTUnwrap(document.alphaChannels?.first?.pixels)
    for x in 0..<65536 { XCTAssertEqual(Int((plane.pixel(x: x, y: 0).r * 65535).rounded()), x) }
    let native = try NativeArchive.encodeChunked(document)
    XCTAssertEqual(try NativeArchive.decodePaged(native), document)
  }

  func testFileURLAndNativePSDPSBRewritesKeepNamesIDsMetadataAndEverySample() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for depth in [8, 16] {
      let vector = try XCTUnwrap(vectors().first { $0.depth == depth && $0.version == 2 && $0.compression == 1 && $0.width == 4096 })
      let source = directory.appendingPathComponent("owned-\(depth).psb")
      try input(vector).write(to: source)
      let document = try PSDCodec.read(source)
      try assertSelection(document, vector)
      for format in PSDFileFormat.allCases {
        let bytes = try PSDCodec.writeRasterLayers(document, format: format, compositeCompression: .rle)
        try assertSelection(PSDCodec.readPaged(bytes), vector)
        try capture(bytes, name: "large-selection-\(depth)-\(format.rawValue).psddata")
      }
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(document)), document)
    }
  }

  func testHeapScratchTruncationChecksumAndTrailingBytesReject() throws {
    let vector = try XCTUnwrap(vectors().first { $0.name == "large-8-v2-c2.psb" }), data = try input(vector)
    XCTAssertThrowsError(try PSDCodec.readPaged(data, heapByteLimit: 0))
    XCTAssertThrowsError(try PSDCodec.readPaged(data, scratchByteLimit: 0))
    XCTAssertThrowsError(try PSDCodec.readPaged(data.dropLast()))
    XCTAssertThrowsError(try PSDCodec.readPaged(data + Data([0])))
    var corrupt = data; corrupt[corrupt.count - 1] ^= 1
    XCTAssertThrowsError(try PSDCodec.readPaged(corrupt))
  }

  func testPrintingPlateLimitStaysExplicitAndNamesTrimOnlyFormatTerminator() throws {
    let vector = try XCTUnwrap(vectors().first { $0.kind == 2 })
    XCTAssertThrowsError(try PSDCodec.readPaged(input(vector))) { error in
      XCTAssertTrue(error.localizedDescription.contains("printing plates"))
    }
    var data = PSDWriter(); data.n(1025, 4)
    for _ in 0..<1024 { data.n(65, 2) }; data.n(0, 2)
    let names = try PSDInkChannels.names([.init(id: 1045, data: data.data, raw: Data())], count: 1)
    XCTAssertEqual(names, [String(repeating: "A", count: 1024)])
  }

  func testCancelledDecodeNeverReturnsAPartialSelection() async throws {
    let vector = try XCTUnwrap(vectors().first { $0.name == "large-8-v2-c2.psb" }), data = try input(vector)
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PSDCodec.readPaged(data)
    }
    do { _ = try await task.value; XCTFail("Cancelled decode returned a document") }
    catch is CancellationError { }
  }
}
