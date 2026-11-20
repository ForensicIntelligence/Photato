import XCTest
@testable import PhotoCraftCore

final class PathTransformTests: XCTestCase {
  func makePath() -> VectorPath {
    .init(components: [
      .init(knots: [
        .init(.init(12, 22), outgoing: .init(38, 96)),
        .init(.init(100, 25), incoming: .init(82, 8)),
        .init(.init(89, 77), incoming: .init(108, 58), outgoing: .init(70, 96), smooth: true),
        .init(.init(17, 70))
      ], closed: true),
      .init(knots: [.init(.init(40, 40)), .init(.init(60, 40)), .init(.init(60, 58))],
            closed: true, operation: .subtract)
    ], fillRule: .evenOdd)
  }

  func testAffineContourTransformsOnlyItsOwnGeometryAndKeepsNamedPath() throws {
    let path = makePath(), saved = NamedPath(name: "Owned contour", path: path, isWorkPath: false)
    var document = try LayerCollectionTransformTests().fixture()
    document.paths = [saved]
    let target = PathTransformTarget.saved(saved.id)
    let matrix = Transform2D.translation(15, -6) * .scale(1.4, 0.7)
    let request = PathTransformRequest(target: target, selection: .components([1]), matrix: .init(matrix))
    var session = EditorSession(document: document)
    try session.execute(.transformPath(request))
    let changed = try XCTUnwrap(session.document.paths?.first)
    XCTAssertEqual(changed.id, saved.id)
    XCTAssertEqual(changed.name, saved.name)
    XCTAssertFalse(changed.isWorkPath)
    XCTAssertEqual(changed.path.components[0], path.components[0])
    XCTAssertEqual(changed.path.components[1].knots, path.components[1].knots.map { $0.transformed(matrix) })
    XCTAssertEqual(changed.path.components[1].operation, .subtract)
    XCTAssertEqual(session.document.layers, document.layers)
    XCTAssertEqual(session.undoStack.last?.label, "Transform Path")
    XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(session.document)), session.document)
    try session.undo()
    XCTAssertEqual(session.document, document)
  }

  func testPartialProjectionPreservesUnselectedKnotsAndRemapsTheSelection() throws {
    let path = makePath()
    let original = path.components[0].knots
    let selection = PathTransformSelection.anchors([.init(component: 0, knot: 0), .init(component: 0, knot: 1)])
    let matrix = try ProjectiveTransform([1, 0, 4, 0.05, 1, 2, -0.004, 0.001, 1])
    let result = try PathTransform.geometry(path, selection: selection, matrix: matrix)
    XCTAssertEqual(result.path.components[1], path.components[1])
    let knots = result.path.components[0].knots
    XCTAssertGreaterThan(knots.count, original.count)
    XCTAssertEqual(Array(knots.suffix(2)), Array(original.suffix(2)))
    XCTAssertEqual(knots[0].anchor, try matrix.point(original[0].anchor.x, original[0].anchor.y))
    let second = knots.count - 3
    XCTAssertEqual(knots[second].anchor, try matrix.point(original[1].anchor.x, original[1].anchor.y))
    XCTAssertEqual(result.selection, .anchors((0...second).map { .init(component: 0, knot: $0) }))
    XCTAssertEqual(result.path.fillRule, path.fillRule)
    XCTAssertTrue(result.path.components[0].closed)
  }

  func testVectorMaskEditsKeepLayerPlacementLinkPropertiesAndPixelSelection() throws {
    var document = try LayerCollectionTransformTests().fixture()
    let id = document.layers[0].id
    var mask = VectorMask(path: makePath())
    mask.density = 0.5; mask.feather = 1.25
    document.layers[0].vectorMask = mask
    document.selection = .init(x: 4, y: 6, width: 3, height: 2)
    let original = document
    let matrix = Transform2D.translation(3, 2)
    try Command.transformPath(.init(target: .vectorMask(id), matrix: .init(matrix))).apply(to: &document)
    XCTAssertEqual(document.selection, original.selection)
    mask.path = mask.path.transformed(matrix)
    XCTAssertEqual(document.layers[0].vectorMask, mask)
    document.layers[0].vectorMask = original.layers[0].vectorMask
    XCTAssertEqual(document, original)

    document.layers[0].locked = true
    let locked = document
    XCTAssertThrowsError(try Command.transformPath(.init(target: .vectorMask(id), matrix: .init(matrix))).apply(to: &document))
    XCTAssertEqual(document, locked)
  }

  func testBadSelectionAndHorizonDoNotChangeTheSavedPath() throws {
    let path = NamedPath(name: "Owned curve", path: makePath())
    var document = try CraftDocument(width: 150, height: 120)
    document.paths = [path]
    let before = document, target = PathTransformTarget.saved(path.id)
    let translate = ProjectiveTransform(.translation(2, 3))
    let horizon = try ProjectiveTransform([1, 0, 0, 0, 1, 0, -0.02, 0, 1])
    for request in [
      PathTransformRequest(target: target, selection: .components([]), matrix: translate),
      .init(target: target, selection: .components([1, 1]), matrix: translate),
      .init(target: target, selection: .anchors([.init(component: 0, knot: 999)]), matrix: translate),
      .init(target: target, matrix: horizon)
    ] {
      XCTAssertThrowsError(try Command.transformPath(request).apply(to: &document))
      XCTAssertEqual(document, before)
    }
    let box = try PathTransform.bounds(path.path, selection: .anchors([.init(component: 0, knot: 0)]))
    XCTAssertEqual(box, .init(x: 12, y: 22, width: 1, height: 1))
  }

  func testShapeContourEditKeepsStyleAndSeparateVectorMask() throws {
    var document = try CraftDocument(width: 180, height: 130)
    var layer = Layer(name: "Shape to edit", content: .shape(.init(kind: .rectangle, width: 45,
                                                                  height: 30, color: .white)))
    layer.x = 20; layer.y = 26
    var mask = VectorMask(path: makePath())
    mask.linked = false
    layer.vectorMask = mask
    document.layers = [layer]
    document.activeLayerID = layer.id
    let old = try XCTUnwrap(layer.shapePath())
    let target = PathTransformTarget.shape(layer.id)
    let choice = PathTransformSelection.anchors([.init(component: 0, knot: 0)])
    let move = Transform2D.translation(4, 7)
    let expected = try PathTransform.geometry(old, selection: choice, matrix: .init(move)).path
    try Command.transformPath(.init(target: target, selection: choice, matrix: .init(move))).apply(to: &document)
    let edited = document.layers[0]
    XCTAssertEqual(try edited.shapePath(), expected)
    XCTAssertEqual(edited.vectorMask, mask)
    XCTAssertEqual(try edited.shapeTransform(), try layer.shapeTransform())
    XCTAssertEqual(edited.shape?.editableDefinition.fill, layer.shape?.editableDefinition.fill)
    XCTAssertEqual(edited.shape?.editableDefinition.stroke, layer.shape?.editableDefinition.stroke)
  }
}
