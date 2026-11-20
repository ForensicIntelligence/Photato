import XCTest
@testable import PhotoCraftCore

final class PathWarpTests: XCTestCase {
  private func document() throws -> CraftDocument {
    var document = try CraftDocument(width: 200, height: 160)
    let path = VectorPath(components: [.init(knots: [
      .init(.init(20, 40), outgoing: .init(60, 40)),
      .init(.init(140, 40), incoming: .init(100, 40))
    ], closed: false)])
    document.paths = [.init(name: "Measuring curve", path: path)]
    return document
  }

  private func cubic(_ a: PathKnot, _ b: PathKnot, at t: Double) -> PathPoint {
    let u = 1 - t
    let points = [a.anchor, a.outgoing, b.incoming, b.anchor]
    let weights = [u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t]
    return .init(zip(points, weights).reduce(0) { $0 + $1.0.x * $1.1 },
                 zip(points, weights).reduce(0) { $0 + $1.0.y * $1.1 })
  }

  func testSplitMeshUsesOneSidedTangentsAtItsInteriorBoundary() throws {
    let source = try document(), saved = try XCTUnwrap(source.paths?.first)
    let choice = PathTransformChoice(.saved(saved.id))
    var settings = WarpDefinition()
    settings.sourceBounds = .init(x: 20, y: 10, width: 120, height: 100)
    settings.style = .custom
    settings.mesh = try WarpMesh.fit(columns: 2, rows: 1) { u, v in
      let offset = u - 0.5
      let shift = u < 0.5 ? 40 * u * u : 10 - 30 * offset + 40 * offset * offset
      return .init(20 + 120 * u, 10 + 100 * v + shift)
    }
    let result = try PathWarpEdit.prepare(.init(choices: [choice], settings: settings), in: source)
    let knots = try XCTUnwrap(result.result.paths?.first?.path.components[0].knots)
    XCTAssertEqual(knots.count, 3)
    let split = try XCTUnwrap(knots.dropFirst().first)
    XCTAssertEqual(split.anchor.x, 80, accuracy: 1e-8)
    XCTAssertEqual(split.anchor.y, 50, accuracy: 1e-8)
    XCTAssertGreaterThan(split.anchor.y - split.incoming.y, 6)
    XCTAssertLessThan(split.outgoing.y - split.anchor.y, -4)
    for (index, pair) in zip(knots, knots.dropFirst()).enumerated() {
      for n in 0...128 {
        let t = Double(n) / 128, u = (Double(index) + t) / 2
        let offset = u - 0.5
        let y = 40 + (u < 0.5 ? 40 * u * u : 10 - 30 * offset + 40 * offset * offset)
        let output = cubic(pair.0, pair.1, at: t)
        XCTAssertEqual(output.x, 20 + 120 * u, accuracy: 1e-8)
        XCTAssertEqual(output.y, y, accuracy: 1e-8)
      }
    }
  }

  func testWaveFitsAnEditableCurveAgainstDenseDocumentCoordinates() throws {
    let source = try document(), saved = try XCTUnwrap(source.paths?.first)
    let choice = PathTransformChoice(.saved(saved.id))
    var settings = WarpDefinition()
    settings.style = .wave
    settings.bend = 84
    settings.sourceBounds = .init(x: 20, y: 10, width: 120, height: 100)
    let result = try PathWarpEdit.prepare(.init(choices: [choice], settings: settings), in: source)
    let component = try XCTUnwrap(result.result.paths?.first?.path.components.first)
    XCTAssertFalse(component.closed)
    XCTAssertGreaterThan(component.knots.count, 2)
    for (a, b) in zip(component.knots, component.knots.dropFirst()) {
      for n in 0...128 {
        let output = cubic(a, b, at: Double(n) / 128)
        let u = (output.x - 20) / 60 - 1
        let v = -0.4
        let expected = 40 - 21 * sin(.pi * u + v * .pi / 2)
        XCTAssertEqual(output.y, expected, accuracy: 1.0 / 64)
      }
    }
  }

  func testIdentityMeshLeavesPathsExactAndStalePreparedEditCannotCommit() throws {
    var source = try PathGroupTransformTests().document()
    let saved = try XCTUnwrap(source.paths?.first)
    let shape = source.layers[1]
    let choices = [PathTransformChoice(.saved(saved.id)), .init(.vectorMask(shape.id)), .init(.shape(shape.id))]
    var settings = WarpDefinition()
    settings.sourceBounds = try PathWarp.sourceBounds(choices, matrix: .identity, in: source)
    settings = try settings.custom(width: source.width, height: source.height, columns: 4, rows: 3)
    let unchanged = try PathWarpEdit.prepare(.init(choices: choices, settings: settings), in: source)
    XCTAssertEqual(unchanged.result, source)
    var session = EditorSession(document: source)
    try session.execute(.warpPaths(unchanged))
    XCTAssertTrue(session.undoStack.isEmpty)
    var bend = WarpDefinition()
    bend.style = .arc
    bend.bend = 50
    let edit = try PathWarpEdit.prepare(.init(choices: choices, settings: bend), in: source)
    XCTAssertNotEqual(try edit.result.layers[1].shapePath(), try shape.shapePath())
    XCTAssertEqual(edit.result.layers[1].shape?.editableDefinition.fill, shape.shape?.editableDefinition.fill)
    XCTAssertEqual(try edit.result.layers[1].shapeTransform(), try shape.shapeTransform())
    source.layers[1].locked = true
    XCTAssertThrowsError(try PathWarpEdit.prepare(edit.request, in: source))
    XCTAssertThrowsError(try Command.warpPaths(edit).apply(to: &source))
    XCTAssertEqual(source.paths?.first, saved)
  }
}
