import XCTest
@testable import PhotoCraftCore

final class PathWarpFollowUpTests: XCTestCase {
  func testRepeatedTransformsAfterWarpReprojectTheSameCurvesAndPreserveScope() throws {
    let source = try PathGroupTransformTests().document()
    let saved = try XCTUnwrap(source.paths?.first)
    let layer = source.layers[1]
    let partial = PathTransformSelection.anchors([.init(component: 0, knot: 0), .init(component: 0, knot: 1)])
    let choices = [PathTransformChoice(.saved(saved.id), selection: partial), .init(.shape(layer.id)),
                   .init(.vectorMask(layer.id))]
    let before = ProjectiveTransform(.translation(7, 9))
    var settings = WarpDefinition()
    settings.style = .arch
    settings.bend = 47
    let originalWarp = try PathWarpEdit.prepare(.init(choices: choices, matrix: before, settings: settings), in: source)
    let first = try ProjectiveTransform([1, 0.04, 2, -0.03, 1, 3, 0.001, -0.0004, 1])
    let second = ProjectiveTransform(.translation(-4, 5))
    let combined = try first.followed(by: second)
    let actual = try originalWarp.followed(by: first).followed(by: second)

    var expected = originalWarp.result
    try Command.transformPaths(.init(choices: originalWarp.geometry.map(\.choice), matrix: combined)).apply(to: &expected)
    XCTAssertEqual(actual.request.matrixAfter, combined)
    XCTAssertEqual(actual.result, expected)
    XCTAssertEqual(actual.geometry, try PathWarp.geometry(actual.request, in: source))
    XCTAssertEqual(try actual.followed(by: .identity).result, actual.result)
    XCTAssertEqual(actual.result.selection, source.selection)
    XCTAssertEqual(actual.result.layers[0], source.layers[0])
    XCTAssertEqual(try actual.result.layers[1].shapeTransform(), try layer.shapeTransform())
    XCTAssertEqual(actual.result.paths?.first?.path.components[0].knots.last, saved.path.components[0].knots.last)

    var history = EditorSession(document: source)
    try history.execute(.warpPaths(actual))
    XCTAssertEqual(history.undoStack.count, 1)
    try history.undo()
    XCTAssertEqual(history.document, source)
    try history.redo()
    XCTAssertEqual(history.document, expected)
  }

  func testPostWarpProjectiveHorizonBetweenTargetsLeavesOriginalUntouched() throws {
    let source = try PathGroupTransformTests().document()
    let saved = try XCTUnwrap(source.paths?.first?.id)
    let selection = PathTransformSelection.anchors([.init(component: 0, knot: 0)])
    let choices = [PathTransformChoice(.saved(saved), selection: selection),
                   .init(.vectorMask(source.layers[1].id), selection: selection)]
    var settings = WarpDefinition()
    settings.style = .wave
    settings.bend = 20
    let staged = try PathWarpEdit.prepare(.init(choices: choices, settings: settings), in: source)
    let horizon = try ProjectiveTransform([1, 0, 0, 0, 1, 0, -0.02, 0, 1])
    for item in staged.geometry {
      XCTAssertNoThrow(try PathTransform.geometry(item.path, selection: item.choice.selection, matrix: horizon))
    }
    XCTAssertThrowsError(try staged.followed(by: horizon)) {
      XCTAssertTrue($0.localizedDescription.contains("horizon"))
    }
    XCTAssertThrowsError(try PathWarpEdit.prepare(
      .init(choices: choices, settings: settings, matrixAfter: horizon), in: source))
    XCTAssertEqual(staged.source, source)
  }
}
