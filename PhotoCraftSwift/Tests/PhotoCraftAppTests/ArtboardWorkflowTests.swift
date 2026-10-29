import AppKit
import XCTest
@testable import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class ArtboardWorkflowTests: XCTestCase {
  // Independent expected sample locations/colors transcribed from the original
  // crates/compose/tests/artboard.rs contents_are_clipped_and_background_painted.
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 40, height: 20, depth: depth)
    d.layers[0].content = .raster(try Surface(width: 40, height: 10, depth: depth, fill: Pixel(1, 0, 0)))
    try Command.artboard(.create(name: "Artboard 1", bounds: .init(x: 10, y: 5, width: 20, height: 10), background: .white, children: [d.layers[0].id])).apply(to: &d)
    return d
  }
  func testOriginalRustClipBackgroundAndHalfOpenEdgeExpectationsAllDepths() throws {
    for depth in PixelDepth.allCases {
      var d = try fixture(depth)
      for passThrough in [false, true] {
        var group = d.layers.last!.group!; group.passThrough = passThrough; d.layers[d.layers.count - 1].content = .group(group)
        let output = try Renderer.composite(d)
        for (x, y, expected) in [(2, 2, Pixel.clear), (35, 8, .clear), (15, 7, Pixel(1, 0, 0)), (15, 12, .white), (29, 14, .white), (30, 14, .clear)] {
          XCTAssertEqual(output.pixel(x: x, y: y), expected, "\(depth) at \(x),\(y)")
        }
      }
    }
  }
  func testNegativeBoardsRebaseWithoutResamplingAndKeepLogicalCoordinates() throws {
    let original = try fixture(); var session = EditorSession(document: original)
    let beforePixels = original.layers[0].content, first = original.artboards[0].id
    try session.execute(.artboard(.create(name: "Left", bounds: .init(x: -12, y: -8, width: 8, height: 6), background: Pixel(0, 0, 1), children: [])))
    let second = session.document.artboards.last!
    XCTAssertEqual(session.document.artboardOrigin, .init(x: -12, y: -8))
    XCTAssertEqual(session.document.logicalArtboardBounds(second), .init(x: -12, y: -8, width: 8, height: 6))
    XCTAssertEqual(session.document.logicalArtboardBounds(session.document.layers.first { $0.id == first }!), .init(x: 10, y: 5, width: 20, height: 10))
    XCTAssertEqual(session.document.layers[0].content, beforePixels)
    XCTAssertEqual(try Renderer.composite(session.document).pixel(x: 2, y: 2), Pixel(0, 0, 1))
    let result = session.document; try session.undo(); XCTAssertEqual(session.document, original); try session.redo(); XCTAssertEqual(session.document, result)
  }
  func testResizeMoveDuplicateAndGuideProperties() throws {
    var session = EditorSession(document: try fixture()); let id = session.document.artboards[0].id
    let child = session.document.layers[0]
    try session.execute(.artboard(.resize(id, bounds: .init(x: 12, y: 7, width: 24, height: 12), moveContents: true)))
    XCTAssertEqual(session.document.layers[0].x, child.x + 2); XCTAssertEqual(session.document.layers[0].y, child.y + 2)
    var board = session.document.artboards[0].artboard!; board.background = .clear; board.guides = [.init(axis: .horizontal, position: 3)]
    try session.execute(.artboard(.settings(id, board))); XCTAssertEqual(session.document.artboards[0].artboard?.guides.count, 1)
    try session.execute(.artboard(.duplicate(id, x: 50, y: 0, name: "Second")))
    XCTAssertEqual(session.document.artboards.count, 2); XCTAssertEqual(session.document.artboards.last?.name, "Second"); XCTAssertGreaterThanOrEqual(session.document.width, 74)
    XCTAssertNotEqual(session.document.artboards.first?.id, session.document.artboards.last?.id)
    try session.execute(.artboard(.clearGuides(id))); XCTAssertTrue(session.document.artboards[0].artboard!.guides.isEmpty)
    try session.undo(); XCTAssertEqual(session.document.artboards[0].artboard?.guides.count, 1)
  }
  func testNative27RoundTripAndInvalidHierarchyRollback() throws {
    let original = try fixture(); XCTAssertEqual(original.minimumArchiveVersion, 27)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(original)), original)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(original)), original)
    var session = EditorSession(document: original)
    try session.execute(.artboard(.create(name: "Other", bounds: .init(x: 0, y: 0, width: 4, height: 4), background: .clear, children: [])))
    let before = session.document, boards = before.artboards
    XCTAssertThrowsError(try session.execute(.relocate(boards[0].id, boards[1].id, 0))); XCTAssertEqual(session.document, before)
    XCTAssertThrowsError(try session.execute(.artboard(.resize(boards[0].id, bounds: .init(x: 0, y: 0, width: 0, height: 2), moveContents: false)))); XCTAssertEqual(session.document, before)
    XCTAssertThrowsError(try session.execute(.artboard(.create(name: "Nested", bounds: .init(x: 0, y: 0, width: 4, height: 4), background: .white, children: [before.layers[0].id])))); XCTAssertEqual(session.document, before)
  }
  func testImageSizeAndQuarterTurnTransformBoardGeometry() throws {
    var session = EditorSession(document: try fixture())
    try session.execute(.imageSize(80, 40, 72, .nearest))
    XCTAssertEqual(session.document.artboards[0].artboardBounds, .init(x: 20, y: 10, width: 40, height: 20))
    try session.execute(.rotateCanvas(.clockwise))
    XCTAssertEqual(session.document.artboards[0].artboardBounds, .init(x: 10, y: 20, width: 20, height: 40))
    XCTAssertEqual(try Renderer.composite(session.document).width, 40)
  }
}
