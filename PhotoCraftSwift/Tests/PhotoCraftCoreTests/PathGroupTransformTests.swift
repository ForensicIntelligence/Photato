import XCTest
@testable import PhotoCraftCore

final class PathGroupTransformTests: XCTestCase {
  func document() throws -> CraftDocument {
    var doc = try CraftDocument(width: 220, height: 150)
    let saved = NamedPath(name: "Reflection", path: outline(x: 15, y: 23))
    doc.paths = [saved]
    var shape = Layer(name: "Badge", content: .shape(.init(kind: .rectangle, width: 40, height: 33, color: .black)))
    shape.x = 86; shape.y = 20
    var mask = VectorMask(path: outline(x: 120, y: 30))
    mask.linked = false; mask.feather = 2; mask.density = 0.5
    shape.vectorMask = mask
    let pixels = Layer(name: "Pastel", content: .raster(try Surface(width: 200, height: 140, fill: .white)))
    doc.layers = [pixels, shape]
    doc.activeLayerID = pixels.id
    doc.selection = .init(x: 3, y: 5, width: 14, height: 20)
    return doc
  }

  func outline(x: Double, y: Double) -> VectorPath {
    VectorPath(components: [
      PathComponent(knots: [
        PathKnot(.init(x, y), outgoing: .init(x + 6, y - 5)),
        PathKnot(.init(x + 32, y + 5), incoming: .init(x + 20, y + 7)),
        PathKnot(.init(x + 28, y + 29)), PathKnot(.init(x + 2, y + 22))
      ], closed: true)
    ])
  }

  func testProjectiveBatchPreservesIndependentScopesAndRecordsOneUndo() throws {
    let before = try document(), shape = before.layers[1]
    let saved = try XCTUnwrap(before.paths?.first)
    let choices = [PathTransformChoice(.saved(saved.id)), .init(.shape(shape.id)),
      .init(.vectorMask(shape.id), selection: .anchors([.init(component: 0, knot: 2)]))]
    let perspective = try ProjectiveTransform([1, 0.1, 3, 0.05, 1, 0, -0.001, 0.001, 1])
    var reference = before
    for choice in choices {
      try Command.transformPath(.init(target: choice.target, selection: choice.selection, matrix: perspective))
        .apply(to: &reference)
    }
    var session = EditorSession(document: before)
    try session.execute(.transformPaths(.init(choices: choices, matrix: perspective)))
    XCTAssertEqual(session.document, reference)
    XCTAssertEqual(session.document.selection, before.selection)
    XCTAssertEqual(session.document.layers[0], before.layers[0])
    XCTAssertEqual(session.document.layers[1].shape?.editableDefinition.fill, shape.shape?.editableDefinition.fill)
    XCTAssertEqual(try session.document.layers[1].shapeTransform(), try shape.shapeTransform())
    let beforeMask = try XCTUnwrap(shape.vectorMask)
    var editedMask = try XCTUnwrap(session.document.layers[1].vectorMask)
    XCTAssertEqual(editedMask.path.components[0].knots[0], beforeMask.path.components[0].knots[0])
    XCTAssertNotEqual(editedMask.path.components[0].knots[2], beforeMask.path.components[0].knots[2])
    editedMask.path = beforeMask.path
    XCTAssertEqual(editedMask, beforeMask)
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo()
    XCTAssertEqual(session.document, before)
    try session.redo()
    XCTAssertEqual(session.document, reference)
  }

  func testLockedAndDuplicateTargetsCannotCommitPartOfTheBatch() throws {
    var original = try document()
    let saved = try XCTUnwrap(original.paths?.first)
    original.layers[1].locked = true
    let shape = original.layers[1].id
    let first = PathTransformChoice(.saved(saved.id)), last = PathTransformChoice(.vectorMask(shape))
    let move = ProjectiveTransform(.translation(9, 7))
    var session = EditorSession(document: original)
    for choices in [[first,last], [first,first]] {
      XCTAssertThrowsError(try session.execute(.transformPaths(.init(choices: choices, matrix: move))))
      XCTAssertEqual(session.document, original)
      XCTAssertTrue(session.undoStack.isEmpty)
    }
  }

  func testDisjointPathsUseOneBoundsAndRejectAHorizonBetweenThem() throws {
    let before = try document()
    let saved = try XCTUnwrap(before.paths?.first)
    let id = before.layers[1].id
    let a = PathTransformChoice(.saved(saved.id), selection: .anchors([.init(component: 0, knot: 0)]))
    let b = PathTransformChoice(.vectorMask(id), selection: .anchors([.init(component: 0, knot: 0)]))
    XCTAssertEqual(try PathTransform.bounds([a,b], in: before), .init(x: 15, y: 23, width: 105, height: 7))
    let matrix = try ProjectiveTransform([1, 0, 0, 0, 1, 0, -0.02, 0, 1])
    XCTAssertNoThrow(try PathTransform.geometry(.init(choices: [a], matrix: matrix), in: before))
    XCTAssertNoThrow(try PathTransform.geometry(.init(choices: [b], matrix: matrix), in: before))
    XCTAssertThrowsError(try PathTransform.geometry(.init(choices: [a,b], matrix: matrix), in: before)) {
      XCTAssertTrue($0.localizedDescription.contains("horizon"))
    }
  }
}
