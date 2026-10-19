import Foundation
import XCTest

@testable import PhotoCraftCore

final class LayerLayoutTests: XCTestCase {
  struct Reference: Decodable {
    var name: String, kind: String, edge: String
    var target: [Int]?
    var bounds: [[Int]], before: [[Int]], expected: [[Int]]
  }
  func rect(_ r: [Int]) -> IntRect { IntRect(x: r[0], y: r[1], width: r[2], height: r[3]) }
  func testTwentySixIndependentPhotoshopPlacements() throws {
    let url = try XCTUnwrap(
      Bundle.module.url(
        forResource: "photoshop-layer-layout", withExtension: "json", subdirectory: "Fixtures"))
    let cases = try JSONDecoder().decode([Reference].self, from: Data(contentsOf: url))
    XCTAssertEqual(cases.count, 26)
    let names = [
      "top": "Top Edges", "bottom": "Bottom Edges", "vcenter": "Vertical Centers",
      "left": "Left Edges", "right": "Right Edges", "hcenter": "Horizontal Centers",
      "hspace": "Horizontally", "vspace": "Vertically",
    ]
    for row in cases {
      let operation: LayerLayoutOperation =
        row.kind == "align"
        ? .align(try XCTUnwrap(LayerAlignment(rawValue: names[row.edge]!)))
        : .distribute(try XCTUnwrap(LayerDistribution(rawValue: names[row.edge]!)))
      let items = row.bounds.map { LayerLayoutItem(id: UUID(), bounds: rect($0)) }
      let moves = try LayerLayout.plan(items, operation: operation, target: row.target.map(rect))
      for i in moves.indices {
        XCTAssertEqual(moves[i].id, items[i].id)
        XCTAssertEqual(row.before[i][0] + moves[i].dx, row.expected[i][0], row.name)
        XCTAssertEqual(row.before[i][1] + moves[i].dy, row.expected[i][1], row.name)
      }
    }
  }
  func testSparseAlphaBoundsIncludePartialPixelsButIgnoreHiddenRGBAndTilePadding() throws {
    var s = try Surface(width: 70, height: 67, depth: .f32)
    s.setPixel(x: 0, y: 0, Pixel(1, 1, 1, 0))
    XCTAssertNil(try s.contentBounds())
    s.setPixel(x: 69, y: 66, Pixel(1, 0, 0, 0.0001))
    s.setPixel(x: 2, y: 3, .white)
    XCTAssertEqual(try s.contentBounds(), IntRect(x: 2, y: 3, width: 68, height: 64))
    var opaque = try Surface(width: 65, height: 66, fill: .white)
    for x in 0..<65 { opaque.setPixel(x: x, y: 0, .clear) }
    XCTAssertEqual(try opaque.contentBounds(), IntRect(x: 0, y: 1, width: 65, height: 65))
    XCTAssertEqual(s.tileCount, 2)
  }
  func testInvalidAndInsufficientPlansRejectWithoutOverflow() throws {
    let a = LayerLayoutItem(id: UUID(), bounds: IntRect(x: 1, y: 2, width: 3, height: 4))
    let b = LayerLayoutItem(id: UUID(), bounds: a.bounds)
    XCTAssertThrowsError(try LayerLayout.plan([], operation: .align(.left)))
    XCTAssertThrowsError(try LayerLayout.plan([a, a], operation: .align(.left)))
    XCTAssertThrowsError(try LayerLayout.plan([a], operation: .align(.left)))
    XCTAssertThrowsError(try LayerLayout.plan([a, b], operation: .distribute(.left)))
    for bad in [
      IntRect(x: Int.max, y: 0, width: Int.max, height: 1),
      IntRect(x: 0, y: Int.min, width: 1, height: 1), IntRect(x: 0, y: 0, width: -1, height: 1),
    ] {
      XCTAssertThrowsError(try LayerLayout.plan([a], operation: .align(.left), target: bad))
      XCTAssertThrowsError(try LayerLayout.union([a.bounds, bad]))
    }
  }
  func grouped() throws -> CraftDocument {
    var d = try CraftDocument(width: 40, height: 30)
    let group = Layer(name: "Group", content: .group(GroupContent()))
    var a = Layer(name: "Linked", content: .raster(try Surface(width: 4, height: 3, fill: .white)))
    a.x = 8
    a.y = 4
    a.parentID = group.id
    a.mask = try Surface(width: 4, height: 3, fill: .white)
    a.vectorMask = VectorMask(
      path: VectorPath(components: [
        PathComponent(
          knots: [PathPoint(8, 4), PathPoint(12, 4), PathPoint(12, 7), PathPoint(8, 7)].map {
            PathKnot($0)
          }, closed: true)
      ]))
    var b = a
    b.id = UUID()
    b.name = "Unlinked"
    b.x = 20
    b.vectorMask?.linked = false
    var properties = MaskProperties()
    properties.linked = false
    b.maskProperties = properties
    d.layers = [a, b, group]
    d.activeLayerID = group.id
    return d
  }
  func testAtomicGroupMovePreservesMasksContentAndUndo() throws {
    let d = try grouped()
    let group = d.layers[2].id
    XCTAssertEqual(try LayerLayout.roots(Set(d.layers.map(\.id)), in: d).map(\.id), [group])
    var session = EditorSession(document: d)
    try session.execute(.layoutLayers([LayerTranslation(id: group, dx: -3, dy: 7)], .align(.left)))
    XCTAssertEqual(session.undoStack.count, 1)
    for i in 0..<2 {
      XCTAssertEqual(session.document.layers[i].content, d.layers[i].content)
      XCTAssertEqual(session.document.layers[i].mask, d.layers[i].mask)
      XCTAssertEqual(session.document.layers[i].x, d.layers[i].x - 3)
    }
    XCTAssertEqual(
      session.document.layers[0].maskCoordinateTransform.tx,
      d.layers[0].maskCoordinateTransform.tx - 3)
    XCTAssertEqual(
      session.document.layers[1].maskCoordinateTransform, d.layers[1].maskCoordinateTransform)
    XCTAssertEqual(
      session.document.layers[0].vectorMask?.path,
      d.layers[0].vectorMask?.path.transformed(.translation(-3, 7)))
    XCTAssertEqual(session.document.layers[1].vectorMask, d.layers[1].vectorMask)
    let changed = session.document
    session.undo()
    XCTAssertEqual(session.document, d)
    session.redo()
    XCTAssertEqual(session.document, changed)
    try session.execute(.layoutLayers([LayerTranslation(id: group, dx: 0, dy: 0)], .align(.left)))
    XCTAssertEqual(session.undoStack.count, 1)
  }
  func testLockedDescendantInvalidIDsAndOutOfRangeMovesAreAtomic() throws {
    var d = try grouped()
    d.layers[1].locked = true
    let before = d
    let id = d.layers[2].id
    XCTAssertThrowsError(
      try Command.layoutLayers([LayerTranslation(id: id, dx: 3, dy: 2)], .align(.top)).apply(to: &d)
    )
    XCTAssertEqual(d, before)
    d.layers[1].locked = false
    let unlocked = d
    for moves in [
      [LayerTranslation(id: id, dx: Int.max, dy: 0)], [LayerTranslation(id: UUID(), dx: 1, dy: 0)],
      [LayerTranslation(id: id, dx: 0, dy: 1), LayerTranslation(id: d.layers[0].id, dx: 1, dy: 0)],
      [LayerTranslation(id: id, dx: 1_000_000, dy: 0)],
    ] {
      XCTAssertThrowsError(try Command.layoutLayers(moves, .align(.left)).apply(to: &d))
      XCTAssertEqual(d, unlocked)
    }
  }
  func testRasterTrimPreservesSamplesAndMaskFramesAtAllDepths() throws {
    for depth in PixelDepth.allCases {
      for linked in [true, false] {
        var pixels = try Surface(width: 8, height: 7, depth: depth)
        for y in 1..<6 {
          for x in 2..<7 {
            pixels.setPixel(x: x, y: y, Pixel(Float(x) / 9, Float(y) / 11, 0.23, 0.6))
          }
        }
        var layer = Layer(name: "Padded", content: .raster(pixels))
        layer.x = 9
        layer.y = 12
        layer.mask = try Surface(width: 6, height: 6, depth: depth, fill: .white)
        var mask = MaskProperties()
        mask.linked = linked
        mask.transform = .translation(-2, 1)
        layer.maskProperties = mask
        var d = try CraftDocument(width: 60, height: 40, depth: depth)
        d.layers = [layer]
        d.activeLayerID = layer.id
        var session = EditorSession(document: d)
        try session.execute(
          .layoutLayers([LayerTranslation(id: layer.id, dx: 5, dy: -3)], .align(.left)))
        let moved = session.document.layers[0]
        guard case .raster(let cropped) = moved.content else { return XCTFail("Lost raster") }
        XCTAssertEqual(cropped.width, 5)
        XCTAssertEqual(cropped.height, 5)
        XCTAssertEqual(moved.x, 16)
        XCTAssertEqual(moved.y, 10)
        for y in 0..<5 {
          for x in 0..<5 {
            XCTAssertTrue(
              cropped.pixel(x: x, y: y).hasSameBits(as: pixels.pixel(x: x + 2, y: y + 1)))
          }
        }
        XCTAssertEqual(moved.mask, layer.mask)
        XCTAssertEqual(
          moved.maskCoordinateTransform,
          linked
            ? Transform2D.translation(5, -3) * layer.maskCoordinateTransform
            : layer.maskCoordinateTransform)
        session.undo()
        XCTAssertEqual(session.document, d)
        XCTAssertThrowsError(try pixels.cropped(to: IntRect(x: Int.max, y: 0, width: 1, height: 1)))
      }
    }
  }
}
