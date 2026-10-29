import Darwin
import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class PSDFileInputTests: XCTestCase {
  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  private func fixture(_ name: String, folder: String) throws -> URL {
    try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/" + folder))
  }
  private func same(_ a: CraftDocument, _ b: CraftDocument) throws {
    XCTAssertEqual(a.width, b.width)
    XCTAssertEqual(a.height, b.height)
    XCTAssertEqual(a.depth, b.depth)
    XCTAssertEqual(a.sourceICC, b.sourceICC)
    XCTAssertEqual(a.workingICC, b.workingICC)
    XCTAssertEqual(a.sourceMetadata, b.sourceMetadata)
    XCTAssertEqual(a.layers.count, b.layers.count)
    for (x, y) in zip(a.layers, b.layers) {
      XCTAssertEqual(x.name, y.name)
      XCTAssertEqual(x.sourceTags, y.sourceTags)
      XCTAssertEqual(x.group, y.group)
      XCTAssertEqual(x.maskProperties, y.maskProperties)
      XCTAssertEqual(
        a.layers.firstIndex { $0.id == x.parentID }, b.layers.firstIndex { $0.id == y.parentID })
      switch (x.content, y.content) {
      case (.raster(let p), .raster(let q)):
        let encoding: SurfaceColorEncoding = a.depth == .f32 ? .linearRGB : .sRGB
        XCTAssertEqual(
          try p.rgbaData(depth: .f32, colorEncoding: encoding),
          try q.rgbaData(depth: .f32, colorEncoding: encoding))
      case (.group, .group): break
      default: XCTAssertEqual(x.content, y.content)
      }
      XCTAssertEqual(try x.mask?.rgbaData(depth: .f32), try y.mask?.rgbaData(depth: .f32))
    }
  }

  func testFileAndMemoryReadersMatchIndependentPSDAndPSBCorpora() throws {
    var urls: [URL] = []
    for depth in [8, 16, 32] {
      for compression in 0...3 {
        urls.append(try fixture("rgb\(depth)-compression\(compression).psb", folder: "psb"))
      }
    }
    for name in [
      "0layers", "1layer", "2layers", "group", "16bit5x5", "32bit5x5", "hidden-layer", "300dpi",
      "transparentbg",
    ] {
      for ext in ["psd", "psb"] { urls.append(try fixture(name + "." + ext, folder: "psb-corpus")) }
    }
    for url in urls {
      let data = try Data(contentsOf: url)
      let memory = try PSDCodec.read(data)
      let source = try PSDFileSource(url)
      try same(PSDCodec.read(PSDReader(file: source), name: "File"), memory)
      XCTAssertLessThanOrEqual(source.metrics.maximumReadBytes, 65536)
      XCTAssertLessThanOrEqual(source.metrics.peakCachedBytes, 524288)
      XCTAssertGreaterThan(source.metrics.readCalls, 0)
    }
  }

  func testPublicFileImportSniffsActualContainerAndRetainsUnsupportedGuards() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let input = try fixture("rgb32-compression3.psb", folder: "psb")
    let disguised = directory.appendingPathComponent("different.png")
    try FileManager.default.copyItem(at: input, to: disguised)
    try same(RasterIO.read(disguised), PSDCodec.read(input))
    let symlink = directory.appendingPathComponent("linked.psb")
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: input)
    try same(PSDCodec.read(symlink), PSDCodec.read(input))
    for ext in ["psd", "psb"] {
      let unsupported = try fixture("semi-transparent-layers." + ext, folder: "psb-corpus")
      XCTAssertThrowsError(try PSDCodec.read(unsupported)) { error in
        XCTAssertTrue(error.localizedDescription.contains("sn2P"))
      }
    }
  }

  func testFileViewsUse64BitOffsetsWithoutLoadingSparseFile() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("offset.bin")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    let offset = (UInt64(1) << 32) + 17
    try handle.seek(toOffset: offset)
    try handle.write(contentsOf: Data([1, 2, 3, 4, 5]))
    try handle.close()
    // Internal byte-source qualification only; public import limits stay512MiB.
    let source = try PSDFileSource(url, maximumBytes: Int.max)
    var reader = PSDReader(file: source)
    _ = try reader.view(Int(offset))
    XCTAssertEqual(try reader.u32(), 0x0102_0304)
    XCTAssertEqual(try reader.u8(), 5)
    XCTAssertEqual(reader.remaining, 0)
    XCTAssertEqual(try source.bytes(at: Int(offset) - 2, count: 7), Data([0, 0, 1, 2, 3, 4, 5]))
    XCTAssertLessThanOrEqual(source.metrics.maximumReadBytes, 65536)
    XCTAssertLessThanOrEqual(source.metrics.peakCachedBytes, 65536)
    XCTAssertThrowsError(try PSDCodec.read(url))
    XCTAssertThrowsError(try source.bytes(at: Int.max, count: 1))
    XCTAssertThrowsError(try source.bytes(at: -1, count: 1))
    XCTAssertThrowsError(try source.bytes(at: 0, count: Int.max))
    try source.validateUnchanged()
  }

  func testParserRejectsChangesEvenWhenOriginalBytesAreCached() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let original = try Data(contentsOf: fixture("rgb8-compression2.psb", folder: "psb"))
    for replacement in [false, true] {
      let url = directory.appendingPathComponent("change-\(replacement).psb")
      try original.write(to: url)
      let source = try PSDFileSource(url)
      _ = try source.bytes(at: 0, count: source.count)
      if replacement {
        try original.write(to: url, options: .atomic)
      } else {
        let writer = try FileHandle(forWritingTo: url)
        try writer.seekToEnd()
        try writer.write(contentsOf: Data([0]))
        try writer.close()
      }
      XCTAssertThrowsError(try PSDCodec.read(PSDReader(file: source), name: "Changed")) { error in
        XCTAssertTrue(error.localizedDescription.contains("changed"), error.localizedDescription)
      }
    }
  }

  func testTruncationAndNonRegularInputsFailWithoutMappingOrBlocking() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("truncate.bin")
    try Data(repeating: 42, count: 200000).write(to: url)
    let source = try PSDFileSource(url)
    XCTAssertEqual(try source.bytes(at: 0, count: 1), Data([42]))
    let writer = try FileHandle(forWritingTo: url)
    try writer.truncate(atOffset: 0)
    try writer.close()
    XCTAssertThrowsError(try source.bytes(at: 100000, count: 1))
    XCTAssertThrowsError(try source.validateUnchanged())
    XCTAssertThrowsError(try PSDFileSource(directory))
    let fifo = directory.appendingPathComponent("pipe")
    XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
    XCTAssertThrowsError(try PSDFileSource(fifo))
    XCTAssertThrowsError(try PSDFileSource(URL(string: "https://example.invalid/a.psb")!))
    XCTAssertThrowsError(try PSDFileSource(directory.appendingPathComponent("missing.psb")))
  }

  func testInterleavedReadWindowsStayBoundedAndMatchOriginalBytes() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("pages.bin")
    var original = Data()
    for i in 0..<20 { original.append(Data(repeating: UInt8(i), count: 65536)) }
    try original.write(to: url)
    let source = try PSDFileSource(url)
    for i in (0..<20).reversed() {
      let offset = i * 65536 + 65530
      let size = min(32, original.count - offset)
      XCTAssertEqual(
        try source.bytes(at: offset, count: size), original.subdata(in: offset..<offset + size))
      XCTAssertEqual(try source.bytes(at: 3, count: 7), Data(repeating: 0, count: 7))
    }
    XCTAssertEqual(source.metrics.maximumReadBytes, 65536)
    XCTAssertLessThanOrEqual(source.metrics.peakCachedBytes, 524288)
    XCTAssertGreaterThan(source.metrics.readCalls, 8)
    try source.validateUnchanged()
  }

  func testCancelledFileImportDoesNotPublishContent() async throws {
    let url = try fixture("rgb32-compression3.psb", folder: "psb")
    let task = Task.detached {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PSDCodec.read(url)
    }
    do {
      _ = try await task.value
      XCTFail("Cancelled import returned a document")
    } catch is CancellationError {
      // Cancellation remains distinguishable from malformed-file errors.
    }
  }
}
