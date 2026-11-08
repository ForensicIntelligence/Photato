import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class IllustratorPathExportTests: XCTestCase {
  private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/IllustratorPaths") }
  private func read(_ name: String) throws -> Data { try Data(contentsOf: fixtures.appendingPathComponent(name)) }
  private func body(_ bytes: Data) throws -> Data {
    let begin = try XCTUnwrap(bytes.range(of: Data("%%Note:\r".utf8)))
    let end = try XCTUnwrap(bytes.range(of: Data("%%Trailer\r".utf8)))
    return Data(bytes[begin.upperBound..<end.lowerBound])
  }
  private func canonical(_ bytes: Data) -> String {
    String(decoding: bytes, as: UTF8.self).components(separatedBy: "\r").map { line in
      if line.hasPrefix("%%Creator:") { return "%%Creator: <producer>" }
      if line.hasPrefix("%%Title:") { return "%%Title: <filename>" }
      return line
    }.joined(separator: "\r")
  }
  private func capture(_ data: Data, name: String) throws {
    if let directory = ProcessInfo.processInfo.environment["PHOTATO_PATH_EXPORT_EVIDENCE_DIR"] {
      try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
    }
  }
  func testOwnedPhotoshopCubicAndRectangleBodyBytesMatchAtPhysicalResolution() throws {
    let source = try PSDCodec.read(read("Owned Paths 144dpi.psd")), before = source
    let bytes = try IllustratorPathExport.encoded(source)
    XCTAssertEqual(try body(bytes), try body(read("photoshop-all-paths144.ai")))
    XCTAssertEqual(canonical(bytes), canonical(try read("photoshop-all-paths144.ai")))
    let text = String(decoding: bytes, as: UTF8.self)
    XCTAssertTrue(text.contains("%%HiResBoundingBox: 0 0 120 60\r"))
    XCTAssertTrue(text.contains("70.0000 55.0000 90.0000 5.0000 110.0000 45.0000 C\rN\r"))
    XCTAssertEqual(source, before)
    try capture(bytes, name: "native-all-paths144.ai")
  }
  func testAllBooleanJoinInversionAndSmoothWorkPathBodyBytesMatchOwnedPhotoshop() throws {
    let source = try PSDCodec.read(read("Owned Operations.psd"))
    XCTAssertEqual(source.paths?.count, 7)
    let bytes = try IllustratorPathExport.encoded(source)
    XCTAssertEqual(try body(bytes), try body(read("photoshop-all-operations.ai")))
    XCTAssertEqual(canonical(bytes), canonical(try read("photoshop-all-operations.ai")))
    try capture(bytes, name: "native-all-operations.ai")
  }
  func testBoundsOnlyMatchesReferenceWithoutAddingAPaintedOrInvisibleRectangle() throws {
    let source = try PSDCodec.read(read("Owned Paths 144dpi.psd"))
    let bytes = try IllustratorPathExport.encoded(source, selection: .init(.documentBounds))
    XCTAssertEqual(try body(bytes), try body(read("photoshop-document-bounds144.ai")))
    XCTAssertEqual(canonical(bytes), canonical(try read("photoshop-document-bounds144.ai")))
    XCTAssertTrue(try body(bytes).isEmpty)
    XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("%AI3_Cropmarks: 0 0 120 60\r"))
    try capture(bytes, name: "native-document-bounds144.ai")
  }
  func testNamedSelectionAndDefaultsDoNotExportUnselectedPaths() throws {
    var source = try PSDCodec.read(read("Owned Paths 144dpi.psd"))
    let rectangle = try XCTUnwrap(source.paths?.first(where: { $0.name == "Rectangle" }))
    let bytes = try IllustratorPathExport.encoded(source, selection: .init(.saved, id: rectangle.id))
    let text = String(decoding: try body(bytes), as: UTF8.self)
    XCTAssertEqual(text.components(separatedBy: "%Adobe_Photoshop_Path_Begin:").count - 1, 1)
    XCTAssertFalse(text.contains(" C\r")); XCTAssertTrue(text.contains("10.0000 50.0000 m\r"))
    XCTAssertEqual(try IllustratorPathExport.defaultSelection(source), .init(.all))
    source.paths = [rectangle]
    XCTAssertEqual(try IllustratorPathExport.defaultSelection(source), .init(.saved, id: rectangle.id))
    XCTAssertEqual(try IllustratorPathExport.choices(source).map(\.name), ["Document Bounds", "Rectangle"])
    source.paths = nil
    XCTAssertEqual(try IllustratorPathExport.defaultSelection(source), .init(.documentBounds))
  }
  func testOnlyActiveLayerShapeAndVectorMaskAreOfferedAndTransformIsAppliedOnce() throws {
    var source = try CraftDocument(width: 240, height: 120)
    let inactive = Layer(name: "Inactive", content: .raster(try Surface(width: 1, height: 1)))
    source.layers.append(inactive)
    try Command.shape(.create("Shape", .init(geometry: .init(width: 20, height: 10)), .translation(30, 40), patterns: [])).apply(to: &source)
    let active = try XCTUnwrap(source.activeLayerID)
    let sources = try IllustratorPathExport.sources(source)
    XCTAssertEqual(sources.count, 1); XCTAssertEqual(sources[0].selection, .init(.shape, id: active))
    XCTAssertEqual(sources[0].path.components[0].knots[0].anchor, PathPoint(30, 40))
    let bytes = try IllustratorPathExport.encoded(source)
    XCTAssertTrue(String(decoding: try body(bytes), as: UTF8.self).contains("30.0000 80.0000 m\r"))
    source.activeLayerID = inactive.id
    XCTAssertTrue(try IllustratorPathExport.sources(source).isEmpty)
    source.layers[source.layers.count - 1].vectorMask = VectorMask(path: sources[0].path)
    XCTAssertEqual(try IllustratorPathExport.sources(source).map(\.selection.target), [.vectorMask])
  }
  func testMaximumSparseCanvasRequiresNoRasterAllocationAndUsesPoints() throws {
    var source = try CraftDocument(width: Surface.maxDimension, height: Surface.maxDimension)
    source.resolution = 300
    let before = source.estimatedBytes
    let bytes = try IllustratorPathExport.encoded(source)
    XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("%%HiResBoundingBox: 0 0 72000 72000\r"))
    XCTAssertLessThan(bytes.count, 1024); XCTAssertEqual(source.estimatedBytes, before)
  }
  func testInvalidIdentifiersGeometryAndControlCharactersRejectAndFilenameIsEscaped() throws {
    let source = try PSDCodec.read(read("Owned Paths 144dpi.psd"))
    for selection in [IllustratorPathExport.Selection(.saved), .init(.all, id: UUID()), .init(.shape, id: UUID()), .init(.saved, id: UUID())] {
      XCTAssertThrowsError(try IllustratorPathExport.encoded(source, selection: selection))
    }
    for name in ["", "bad\n%%Trailer", String(repeating: "x", count: 1025)] { XCTAssertThrowsError(try IllustratorPathExport.encoded(source, title: name)) }
    let escaped = try IllustratorPathExport.encoded(source, title: "Owned (é)\\.ai")
    XCTAssertTrue(String(decoding: escaped, as: UTF8.self).contains("%%Title: (Owned \\(\\303\\251\\)\\\\.ai)\r"))
    var invalid = source; invalid.paths![0].path.components[0].knots[0].anchor.x = .nan
    XCTAssertThrowsError(try IllustratorPathExport.encoded(invalid))
  }
}
