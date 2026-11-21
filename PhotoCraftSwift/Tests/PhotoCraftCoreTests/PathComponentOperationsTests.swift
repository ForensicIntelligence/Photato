import CoreGraphics
import XCTest
@testable import PhotoCraftCore

final class PathComponentOperationsTests: XCTestCase {
  private func rect(_ x: Double, _ y: Double = 10, size: Double = 18,
                    operation: PathOperation = .combine) -> PathComponent {
    let corners = [PathPoint(x, y), .init(x + size, y), .init(x + size, y + size), .init(x, y + size)]
    return .init(knots: corners.map { PathKnot($0) }, closed: true, operation: operation)
  }

  private func fixture(_ components: [PathComponent]) throws -> (CraftDocument, NamedPath) {
    var document = try CraftDocument(width: 230, height: 180)
    let path = NamedPath(name: "Compound outline", path: .init(components: components, fillRule: .evenOdd))
    document.paths = [path]
    return (document, path)
  }

  func testStackingMovesJoinedGroupsAndReportsNewComponentIndices() throws {
    let parts = [rect(10, operation: .join), rect(12, operation: .join), rect(50), rect(88), rect(125)]
    let (document, path) = try fixture(parts)
    let cases: [(PathComponentOperation, [Int], [Int])] = [
      (.bringToFront, [2, 4, 0, 1, 3], [2, 3, 4]),
      (.bringForward, [2, 0, 1, 4, 3], [1, 2, 4]),
      (.sendBackward, [0, 1, 3, 2, 4], [0, 1, 2]),
      (.sendToBack, [0, 1, 3, 2, 4], [0, 1, 2]),
    ]
    for (operation, order, selection) in cases {
      let edit = try PathComponentEdit.prepare(
        .init(target: .saved(path.id), components: [1, 3], operation: operation), in: document)
      XCTAssertEqual(edit.sourceOrder, order)
      XCTAssertEqual(edit.selection, .components(selection))
      XCTAssertEqual(edit.result.components.map(\.knots), order.map { parts[$0].knots })
      XCTAssertEqual(edit.result.components[selection[1]].operation, .join)
      if order.first != 0 { XCTAssertEqual(edit.result.components[selection[0]].operation, .combine) }
      var changed = document
      try Command.editPathComponents(edit).apply(to: &changed)
      XCTAssertEqual(changed.paths?.first?.path, edit.result)
    }
  }

  func testOverlapAppliesToTheSelectedWholeGroupsAndRejectsStaleInput() throws {
    let (source, saved) = try fixture([rect(10), rect(18, operation: .join), rect(20), rect(100)])
    for (operation, expected) in [(PathComponentOperation.combine, PathOperation.combine),
                                  (.subtract, .subtract), (.intersect, .intersect), (.exclude, .exclude)] {
      let edit = try PathComponentEdit.prepare(.init(target: .saved(saved.id), components: [1, 2],
                                                       operation: operation), in: source)
      XCTAssertEqual(edit.result.components.map(\.operation), [expected, .join, expected, .combine])
      XCTAssertEqual(edit.result.components.map(\.knots), saved.path.components.map(\.knots))
      XCTAssertEqual(edit.selection, .components([0, 1, 2]))
      var stale = source
      stale.paths?[0].path.components[0].knots[0].anchor.x += 1
      let untouched = stale
      XCTAssertThrowsError(try Command.editPathComponents(edit).apply(to: &stale))
      XCTAssertEqual(stale, untouched)
    }
  }

  func testMergeKeepsTheFilledOutlineAndRefusesUnselectedBooleanInterference() throws {
    let untouched = rect(120)
    let (source, saved) = try fixture([rect(10, size: 40), untouched, rect(30, 20, size: 30)])
    let edit = try PathComponentEdit.prepare(.init(target: .saved(saved.id), components: [2, 0], operation: .merge),
                                              in: source)
    XCTAssertEqual(edit.result.components.count, 2)
    XCTAssertEqual(edit.result.components.last, untouched)
    XCTAssertEqual(edit.selection, .components([0]))
    let before = try VectorPathGeometry.componentMergeRegion(saved.path)
    let after = try VectorPathGeometry.componentMergeRegion(edit.result)
    XCTAssertTrue(try VectorPathGeometry.componentMergePathsMatch(before.path, after.path))
    XCTAssertEqual(before.path.boundingBoxOfPath, after.path.boundingBoxOfPath)
    let (interleaved, conflict) = try fixture([
      rect(10, size: 20), rect(18, size: 42, operation: .subtract), rect(34, size: 14)
    ])
    XCTAssertThrowsError(try PathComponentEdit.prepare(
      .init(target: .saved(conflict.id), components: [0, 2], operation: .merge), in: interleaved))
  }

  func testEmptyMergedMaskRetainsZeroCoverage() throws {
    var document = try CraftDocument(width: 80, height: 60)
    var layer = Layer(name: "Masked", content: .raster(try Surface(width: 80, height: 60, fill: .white)))
    layer.vectorMask = VectorMask(path: .init(components: [rect(10), rect(10, operation: .subtract)]))
    layer.vectorMask?.density = 0.8
    document.layers = [layer]
    document.activeLayerID = layer.id
    let edit = try PathComponentEdit.prepare(.init(target: .vectorMask(layer.id), operation: .merge),
                                              in: document)
    try Command.editPathComponents(edit).apply(to: &document)
    let mask = try XCTUnwrap(document.layers.first?.vectorMask)
    XCTAssertTrue(mask.path.isEmpty)
    XCTAssertTrue(mask.path.inverted)
    XCTAssertEqual(mask.density, 0.8)
    XCTAssertEqual(edit.selection, .components([]))
  }
}
