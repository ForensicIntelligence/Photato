import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSBTaggedBlockTests: XCTestCase {
  // Owned mask-display values and a public empty ActionDescriptor, not vendor code.
  let maskDisplay = Data([0,0,255,255,0,0,0,0,0,0,0,50])
  let channelInfo = Data([0,0,0,16,0,0,0,0,0,0,0,0,110,117,108,108,0,0,0,0])
  func auxiliary(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 3, depth: depth)
    d.channelOnly = true; d.layers = []; d.activeLayerID = nil
    var p = try Surface(width: 4, height: 3, depth: depth, fill: .black)
    p.setPixel(x: 1, y: 0, .white); p.setPixel(x: 3, y: 2, Pixel(0.4,0.4,0.4))
    var alpha = AlphaChannel(name: "Owned selection Ω", pixels: p); alpha.psdIdentifier = 2
    d.alphaChannels = [alpha]
    d.sourceMetadata = ["psdGlobal_FMsk":maskDisplay, "psdGlobal_cinf":channelInfo]
    try d.validate(); return d
  }
  func assertHeader(_ data: Data, key: String, wide: Bool, payload: Data? = nil,
    file: StaticString = #filePath, line: UInt = #line) throws {
    let signature = wide ? "8B64":"8BIM", bytes = wide ? 8:4
    let start = try XCTUnwrap(data.range(of: Data((signature + key).utf8)), file: file, line: line).upperBound
    XCTAssertNil(data.range(of: Data(((wide ? "8BIM":"8B64") + key).utf8)), file: file, line: line)
    guard let payload else { return }
    let length = data[start..<(start + bytes)].reduce(0) { ($0 << 8) | Int($1) }
    XCTAssertEqual(length, payload.count, file: file, line: line)
    XCTAssertEqual(data[(start + bytes)..<(start + bytes + length)], payload, file: file, line: line)
  }
  func capture(_ bytes: Data, _ name: String) throws {
    guard let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else { return }
    let dir = URL(fileURLWithPath: path); try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try bytes.write(to: dir.appendingPathComponent(name))
  }
  func testAuxiliaryBothDepthsContainersAndCodecsUseLiteralHeadersAndKeepExactWords() throws {
    for depth in [PixelDepth.u8,.u16] { for format in PSDFileFormat.allCases { for method in PSDCompression.allCases {
      let original = try auxiliary(depth)
      let bytes = try PSDCodec.writeRasterLayers(original, format: format, compositeCompression: method)
      try assertHeader(bytes, key: "FMsk", wide: format == .psb, payload: maskDisplay)
      try assertHeader(bytes, key: "cinf", wide: format == .psb, payload: channelInfo)
      let restored = try PSDCodec.readPaged(bytes)
      XCTAssertEqual(restored.alphaChannels?.first?.pixels, original.alphaChannels?.first?.pixels)
      XCTAssertEqual(restored.alphaChannels?.first?.name, original.alphaChannels?.first?.name)
      XCTAssertEqual(restored.alphaChannels?.first?.psdIdentifier, 2)
      XCTAssertEqual(restored.sourceMetadata?["psdGlobal_FMsk"], maskDisplay)
      XCTAssertEqual(restored.sourceMetadata?["psdGlobal_cinf"], channelInfo)
      try capture(bytes, "psb64-small-\(depth.rawValue)-\(format.rawValue)-\(method.rawValue).psddata")
    } } }
  }
  func testLargeStandaloneFileAndDataWritersPreserveEverySampleAndWideMetadata() throws {
    let helper = LargeSelectionFileTests(), folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for vector in try helper.vectors().filter({$0.width == 4096 && $0.version == 2 && $0.compression == 1 && $0.kind == 1}) {
      var d = try PSDCodec.readPaged(helper.input(vector)); d.sourceMetadata?["psdGlobal_FMsk"] = maskDisplay; d.sourceMetadata?["psdGlobal_cinf"] = channelInfo
      let original = d
      for format in PSDFileFormat.allCases {
        let bytes = try PSDCodec.writeRasterLayers(d, format: format, compositeCompression: .raw)
        let file = folder.appendingPathComponent("large.\(format == .psb ? "psb":"psd")")
        try PSDCodec.writeRasterLayers(d, to: file, format: format, compositeCompression: .raw)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        try assertHeader(bytes, key: "FMsk", wide: format == .psb, payload: maskDisplay)
        let read = try PSDCodec.read(file)
        XCTAssertEqual(read.alphaChannels?.first?.pixels, d.alphaChannels?.first?.pixels)
        XCTAssertEqual(read.alphaChannels?.first?.psdIdentifier, 2)
        XCTAssertEqual(d, original)
        try capture(bytes, "psb64-large-\(vector.depth)-\(format.rawValue).psddata")
      }
    }
  }
  func testRasterSavedPathsMaskDisplaySmartObjectAndFilterCachesUseWideHeaders() throws {
    for depth in PixelDepth.allCases {
      var d = try SmartObjectTests().converted(depth)
      try Command.applyFilter(d.layers[0].id, RasterFilter(.gaussianBlur)).apply(to: &d)
      d.paths = [NamedPath(name: "Saved Ω", path: VectorPath(components: [PathComponent(knots: [PathKnot(PathPoint(0,0)),PathKnot(PathPoint(2,0)),PathKnot(PathPoint(2,2))], closed: true)]), isWorkPath: false)]
      let overlay = maskDisplay + Data([128]); d.sourceMetadata = ["psdGlobal_LMsk":overlay]
      let before = d
      for format in PSDFileFormat.allCases {
        let bytes = try PSDCodec.writeRasterLayers(d, format: format)
        for key in ["pths","lnk2","FEid"] { try assertHeader(bytes, key: key, wide: format == .psb) }
        try assertHeader(bytes, key: "LMsk", wide: format == .psb, payload: overlay)
        let read = try PSDCodec.readPaged(bytes)
        XCTAssertEqual(read.paths?.map(\.name), ["Saved Ω"])
        XCTAssertEqual(read.sourceMetadata?["psdGlobal_LMsk"], overlay)
        XCTAssertNotNil(read.layers.first?.smartObject); XCTAssertNotNil(read.layers.first?.smartFilters)
        XCTAssertEqual(d, before)
        try capture(bytes, "psb64-rich-\(depth.rawValue)-\(format.rawValue).psddata")
      }
    }
  }
  func testOrdinaryLayerDepthSectionsUse64BitSignaturesOnlyInPSB() throws {
    for depth in [PixelDepth.u16,.f32] { for format in PSDFileFormat.allCases {
      let d = try SmartObjectTests().fixture(depth)
      let bytes = try PSDCodec.writeRasterLayers(d, format: format)
      try assertHeader(bytes, key: depth == .u16 ? "Lr16":"Lr32", wide: format == .psb)
      let read = try PSDCodec.readPaged(bytes)
      XCTAssertEqual(read.depth, depth); XCTAssertEqual(read.layers.count, d.layers.count)
      try capture(bytes, "psb64-depth-\(depth.rawValue)-\(format.rawValue).psddata")
    } }
  }

  func testLegacyIncorrectWideSignaturesRemainReadableWithoutChangingNumericPlanes() throws {
    let source = try auxiliary(.u16)
    var bytes = try PSDCodec.writeRasterLayers(source, format: .psb)
    for key in ["FMsk","cinf"] {
      let range = try XCTUnwrap(bytes.range(of: Data(("8B64" + key).utf8)))
      bytes.replaceSubrange(range.lowerBound..<(range.lowerBound + 4), with: Data("8BIM".utf8))
    }
    let read = try PSDCodec.readPaged(bytes)
    XCTAssertEqual(read.alphaChannels?.first?.pixels, source.alphaChannels?.first?.pixels)
    XCTAssertEqual(read.sourceMetadata?["psdGlobal_FMsk"], maskDisplay)
  }
  func testInvalidMaskMetadataAndCancellationLeaveExistingOutputUntouched() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("existing.psb"), old = Data("Owned existing output".utf8); try old.write(to: url)
    var d = try CraftDocument(width: 4, height: 3); d.sourceMetadata = ["psdGlobal_LMsk":Data([1,2,3])]
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d, to: url, format: .psb))
    XCTAssertEqual(try Data(contentsOf: url), old)
    let original = try auxiliary()
    let task = Task { while !Task.isCancelled { await Task.yield() }; try PSDCodec.writeRasterLayers(original, to: url, format: .psb) }
    task.cancel()
    do { try await task.value; XCTFail("Cancelled writer succeeded") } catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(try Data(contentsOf: url), old)
  }
}
