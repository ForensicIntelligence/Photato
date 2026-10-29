import Foundation
import XCTest

@testable import PhotoCraftCore

final class SelectionTests: XCTestCase {
  func testPolygonAreaCoverageAndHardEdgesMatchSourceCases() throws {
    let square = try SelectionMask.make(
      .polygon([.init(2, 2), .init(12, 2), .init(12, 12), .init(2, 12)]), width: 20, height: 20)
    XCTAssertEqual(square.bytes.reduce(0) { $0 + Int($1) }, 100 * 255)
    let shape = SelectionShape.polygon([.init(0, 0), .init(10, 0), .init(0, 10)])
    let triangle = try SelectionMask.make(shape, width: 20, height: 20)
    XCTAssertEqual(triangle.bytes.reduce(0) { $0 + Double($1) / 255 }, 50, accuracy: 0.05)
    XCTAssertTrue(triangle.bytes.contains { $0 > 0 && $0 < 255 })
    let hard = try SelectionMask.make(shape, width: 20, height: 20, antiAlias: false)
    XCTAssertTrue(hard.bytes.allSatisfy { $0 == 0 || $0 == 255 })
    let empty = try SelectionMask.make(.polygon([.init(0, 0), .init(1, 1)]), width: 2, height: 2)
    XCTAssertNil(empty.bounds)
  }
  func testEllipseSymmetryAreaAndCanvasClipping() throws {
    let ellipse = try SelectionMask.make(
      .ellipse(.init(x: 2, y: 3, width: 20, height: 10)), width: 24, height: 16)
    XCTAssertEqual(ellipse.coverage(x: 12, y: 8), 1)
    XCTAssertEqual(ellipse.coverage(x: 2, y: 3), 0)
    XCTAssertEqual(ellipse.bytes.reduce(0) { $0 + Double($1) / 255 }, .pi * 10 * 5, accuracy: 1)
    for y in 0..<16 {
      for x in 0..<24 {
        XCTAssertEqual(ellipse.coverage(x: x, y: y), ellipse.coverage(x: 23 - x, y: 15 - y))
      }
    }
    let clipped = try SelectionMask.make(
      .ellipse(.init(x: -10, y: -5, width: 20, height: 10)), width: 12, height: 8)
    XCTAssertEqual(
      clipped.bytes.reduce(0) { $0 + Double($1) / 255 }, .pi * 10 * 5 / 4, accuracy: 0.5)
  }
  func testFractionalCombinationsQuantizeExactlyLikeSource() throws {
    let a = try SelectionMask(width: 4, height: 1, bytes: [0, 64, 128, 255])
    let b = try SelectionMask(width: 4, height: 1, bytes: [255, 128, 64, 0])
    XCTAssertEqual(try b.combined(with: a, mode: .add).bytes, [255, 128, 128, 255])
    XCTAssertEqual(try b.combined(with: a, mode: .subtract).bytes, [0, 0, 64, 255])
    XCTAssertEqual(try b.combined(with: a, mode: .intersect).bytes, [0, 64, 64, 0])
    XCTAssertEqual(try a.combined(with: a, mode: .add), a)
    XCTAssertEqual(try a.combined(with: a, mode: .intersect), a)
    XCTAssertNil(try a.combined(with: a, mode: .subtract).bounds)
    XCTAssertEqual(try a.inverted().inverted(), a)
  }
  func testGaussianFeatherConservesAreaAndSoftensLikeSource() throws {
    let square = try SelectionMask.make(
      .rectangle(.init(x: 5, y: 5, width: 10, height: 10)), width: 20, height: 20)
    let feather = try square.feathered(radius: 4)
    XCTAssertGreaterThan(feather.coverage(x: 5, y: 10), 0.3)
    XCTAssertLessThan(feather.coverage(x: 5, y: 10), 0.8)
    XCTAssertGreaterThan(feather.coverage(x: 4, y: 10), 0)
    XCTAssertEqual(feather.bytes.reduce(0) { $0 + Double($1) / 255 }, 100, accuracy: 1)
    for y in 0..<20 {
      for x in 0..<20 {
        XCTAssertEqual(feather.coverage(x: x, y: y), feather.coverage(x: 19 - x, y: 19 - y))
      }
    }
    XCTAssertEqual(try square.feathered(radius: 0), square)
  }
  func testCoverageClipsFillClearAdjustmentAndBrushAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 4, height: 1, depth: depth)
      let id = doc.layers[0].id
      let mask = try SelectionMask(width: 4, height: 1, bytes: [0, 64, 128, 255])
      doc.setCoverageSelection(mask)
      var session = EditorSession(document: doc)
      try session.execute(.fill(id, .black))
      guard case .raster(let filled) = session.document.layers[0].content else { return XCTFail() }
      for x in 0..<4 {
        XCTAssertEqual(filled.pixel(x: x, y: 0).r, 1 - mask.coverage(x: x, y: 0), accuracy: 0.004)
      }
      try session.undo()
      try session.execute(.clear(id))
      guard case .raster(let cleared) = session.document.layers[0].content else { return XCTFail() }
      XCTAssertEqual(cleared.pixel(x: 2, y: 0).a, 127.0 / 255, accuracy: 0.004)
      XCTAssertEqual(cleared.pixel(x: 2, y: 0).r, 1)
      try session.undo()
      try session.execute(.applyAdjustment(id, .invert))
      guard case .raster(let adjusted) = session.document.layers[0].content else {
        return XCTFail()
      }
      XCTAssertEqual(adjusted, filled)
      try session.undo()
      var brush = Brush()
      brush.size = 30
      brush.hardness = 1
      brush.color = .black
      try session.execute(.stroke(id, [.init(x: 2, y: 0.5), .init(x: 2, y: 0.5)], brush))
      guard case .raster(let painted) = session.document.layers[0].content else { return XCTFail() }
      XCTAssertEqual(
        painted, filled, "Repeated dabs must not increase fractional selection coverage")
    }
  }
  func testOffsetLayerUsesDocumentSpaceCoverage() throws {
    var doc = try CraftDocument(width: 5, height: 2)
    doc.layers[0].x = 2
    doc.setCoverageSelection(
      try .make(.rectangle(.init(x: 3, y: 0, width: 1, height: 2)), width: 5, height: 2))
    var session = EditorSession(document: doc)
    try session.execute(.fill(doc.layers[0].id, .black))
    guard case .raster(let result) = session.document.layers[0].content else { return XCTFail() }
    XCTAssertEqual(result.pixel(x: 0, y: 0), .white)
    XCTAssertEqual(result.pixel(x: 1, y: 0), .black)
    XCTAssertEqual(result.pixel(x: 2, y: 0), .white)
  }
  func testSelectionsFollowCanvasTurnsAndUndo() throws {
    var doc = try CraftDocument(width: 4, height: 3)
    let mask = try SelectionMask(
      width: 4, height: 3, bytes: [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110])
    doc.setCoverageSelection(mask)
    var session = EditorSession(document: doc)
    try session.execute(.rotateCanvas(.clockwise))
    let result = try XCTUnwrap(session.document.selectionMask)
    for y in 0..<3 {
      for x in 0..<4 {
        XCTAssertEqual(result.coverage(x: 2 - y, y: x), mask.coverage(x: x, y: y))
      }
    }
    try session.undo()
    XCTAssertEqual(session.document, doc)
    try session.execute(.canvasSize(6, 5, .bottomRight, nil))
    XCTAssertEqual(session.document.selectionMask?.coverage(x: 3, y: 2), 10.0 / 255)
    XCTAssertEqual(session.document.selectionMask?.coverage(x: 0, y: 0), 0)
    try session.undo()
    try session.execute(.imageSize(8, 6, 72, .bilinear))
    XCTAssertEqual(session.document.selectionMask?.width, 8)
    XCTAssertEqual(session.document.selectionMask?.height, 6)
    try session.document.validate()
    try session.undo()
    XCTAssertEqual(session.document, doc)
  }
  func testSelectionArchiveUndoAndDeselect() throws {
    let doc = try CraftDocument(width: 20, height: 20)
    var session = EditorSession(document: doc)
    try session.execute(
      .selectShape(.ellipse(.init(x: 2, y: 2, width: 16, height: 14)), .replace, true, 2))
    let selected = session.document
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(selected)), selected)
    try session.execute(.invertSelection)
    XCTAssertNotEqual(session.document.selectionMask, selected.selectionMask)
    try session.undo()
    XCTAssertEqual(session.document, selected)
    try session.execute(.selection(nil))
    XCTAssertNil(session.document.selectionMask)
    try session.undo()
    XCTAssertEqual(session.document, selected)
    try session.execute(.crop(.init(x: 1, y: 1, width: 10, height: 10)))
    XCTAssertNil(session.document.selectionMask)
    try session.undo()
    XCTAssertEqual(session.document, selected)
  }
  func testSelectionValidationAndFailedEditsAreAtomic() throws {
    var session = EditorSession(document: try CraftDocument(width: 3, height: 3))
    let before = session.document
    XCTAssertThrowsError(
      try session.execute(.selectShape(.polygon([.init(.nan, 0)]), .replace, true, 0)))
    XCTAssertThrowsError(
      try session.execute(
        .selectShape(.rectangle(.init(x: 0, y: 0, width: 1, height: 1)), .replace, true, .infinity))
    )
    XCTAssertThrowsError(
      try session.execute(
        .selectionCoverage(SelectionMask(width: 1, height: 1, bytes: [255]), .replace)))
    XCTAssertEqual(session.document, before)
    XCTAssertTrue(session.undoStack.isEmpty)
    XCTAssertThrowsError(try SelectionMask(width: 2, height: 2, bytes: [0]))
    XCTAssertThrowsError(try session.execute(.invertSelection))
  }
}
