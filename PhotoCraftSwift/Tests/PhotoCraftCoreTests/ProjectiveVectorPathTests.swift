import XCTest
@testable import PhotoCraftCore

final class ProjectiveVectorPathTests: XCTestCase {
  func testCurveFollowsTheIndependentRationalCurveAndRetainsEditableTangents() throws {
    let source = PathComponent(knots: [
      PathKnot(.init(3, 8), outgoing: .init(40, 170)),
      PathKnot(.init(130, 35), incoming: .init(90, -20), smooth: true)
    ], operation: .intersect)
    let path = VectorPath(components: [source], fillRule: .evenOdd, inverted: true)
    let coefficients = [1.0, 0, 3, 0.1, 1, 4, -0.004, 0, 1]
    let matrix = try ProjectiveTransform(coefficients)
    let result = try ProjectiveVectorPath.apply(path, matrix: matrix)
    let curve = result.components[0]
    XCTAssertFalse(curve.closed)
    XCTAssertEqual(curve.operation, .intersect)
    XCTAssertTrue(result.inverted)
    XCTAssertEqual(result.fillRule, .evenOdd)
    XCTAssertGreaterThan(curve.knots.count, 2)
    XCTAssertEqual(curve.knots.first?.smooth, false)
    XCTAssertTrue(curve.knots.dropFirst().allSatisfy(\.smooth))
    func reference(_ t: Double) -> PathPoint {
      let u = 1 - t, a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
      let x = a * 3 + b * 40 + c * 90 + d * 130
      let y = a * 8 + b * 170 - c * 20 + d * 35
      let w = 1 - 0.004 * x
      return .init((x + 3) / w, (0.1 * x + y + 4) / w)
    }
    // The projected x coordinate is monotonic. Recover each subdivision
    // boundary from the separately evaluated curve, without relying on the fitter.
    func parameter(_ x: Double) -> Double {
      var left = 0.0, right = 1.0
      for _ in 0..<50 {
        let midpoint = (left + right) / 2
        if reference(midpoint).x < x { left = midpoint } else { right = midpoint }
      }
      return (left + right) / 2
    }
    for i in 0..<(curve.knots.count - 1) {
      let start = parameter(curve.knots[i].anchor.x), end = parameter(curve.knots[i + 1].anchor.x)
      for j in 0...64 {
        let t = Double(j) / 64
        let actual = try XCTUnwrap(curve.point(segment: i, at: t))
        let expected = reference(start + (end - start) * t)
        XCTAssertLessThanOrEqual(hypot(actual.x - expected.x, actual.y - expected.y), 1.0 / 64)
      }
    }
    let scaled = try ProjectiveVectorPath.apply(path, matrix: ProjectiveTransform(coefficients.map { -8 * $0 }))
    XCTAssertEqual(result, scaled)
  }

  func testStraightClosedMaskAndGroupHierarchyRemainExact() throws {
    var source = try LayerCollectionTransformTests().fixture()
    try Command.groupLayers(source.layers.map(\.id), "Masked group").apply(to: &source)
    let group = try XCTUnwrap(source.activeLayerID)
    let groupIndex = try XCTUnwrap(source.layers.firstIndex { $0.id == group })
    let childIndex = try XCTUnwrap(source.layers.firstIndex { !$0.isGroup })
    let child = source.layers[childIndex].id
    let corners = [PathPoint(2, 3), .init(12, 3), .init(12, 10), .init(2, 10)]
    let component = PathComponent(knots: corners.map { PathKnot($0) }, closed: true, operation: .subtract)
    var moving = VectorMask(path: .init(components: [component, PathComponent(operation: .exclude)],
                                       fillRule: .evenOdd, inverted: true))
    moving.density = 0.41; moving.feather = 2; moving.enabled = false
    source.layers[groupIndex].vectorMask = moving
    var fixed = moving; fixed.linked = false
    source.layers[childIndex].vectorMask = fixed
    let matrix = try ProjectiveTransform([1, 0.1, 2, 0.05, 1, 1, 0.01, 0.005, 1])
    var result = source
    try Command.transformLayers(.init(layerIDs: [group, child], projection: matrix)).apply(to: &result)
    var groupOnly = source
    try Command.transformLayers(.init(layerIDs: [group], projection: matrix)).apply(to: &groupOnly)
    XCTAssertEqual(result, groupOnly)
    XCTAssertEqual(result.layers.map(\.parentID), source.layers.map(\.parentID))
    XCTAssertEqual(result.layers[childIndex].vectorMask, fixed)
    moving.path.components[0].knots = try corners.map { PathKnot(try matrix.point($0.x, $0.y)) }
    XCTAssertEqual(result.layers[groupIndex].vectorMask, moving)
  }

  func testAControlOutsideTheHorizonCanStillDefineAFiniteCurve() throws {
    let path = VectorPath(components: [PathComponent(knots: [
      PathKnot(.init(0, 3), outgoing: .init(110, 3)),
      PathKnot(.init(0, 12), incoming: .init(110, 12))
    ])])
    let matrix = try ProjectiveTransform([1, 0, 0, 0, 1, 0, -0.01, 0, 1])
    let result = try ProjectiveVectorPath.apply(path, matrix: matrix)
    XCTAssertGreaterThan(result.knotCount, 2)
    XCTAssertEqual(result.components[0].knots.first?.anchor, .init(0, 3))
    XCTAssertEqual(result.components[0].knots.last?.anchor, .init(0, 12))
    XCTAssertTrue(result.components[0].knots.contains { abs($0.anchor.x - 82.5 / 0.175) < 1e-9 })
  }

  func testHorizonInLinkedCurveFailsAtomicallyAndCanStayFixedWhenUnlinked() throws {
    var source = try LayerCollectionTransformTests().fixture()
    let mask = VectorMask(path: .init(components: [PathComponent(knots: [
      PathKnot(.init(0, 3), outgoing: .init(150, 3)),
      PathKnot(.init(0, 12), incoming: .init(150, 12))
    ])]))
    source.layers[1].vectorMask = mask
    let matrix = try ProjectiveTransform([1, 0, 0, 0, 1, 0, -0.01, 0, 1])
    let command = Command.transformLayers(.init(layerIDs: source.layers.map(\.id), projection: matrix))
    var result = source
    XCTAssertThrowsError(try command.apply(to: &result)) { error in
      XCTAssertTrue(error.localizedDescription.contains("horizon"))
    }
    XCTAssertEqual(result, source)
    var fixed = mask; fixed.linked = false
    source.layers[1].vectorMask = fixed
    var session = EditorSession(document: source)
    try session.execute(command)
    XCTAssertEqual(session.document.layers[1].vectorMask, fixed)
    XCTAssertEqual(session.undoStack.count, 1)
    try session.undo()
    XCTAssertEqual(session.document, source)
  }

  func testSubdivisionRespectsTheExistingKnotLimit() throws {
    let path = VectorPath(components: [PathComponent(knots: [
      PathKnot(.init(0, 0), outgoing: .init(30, 100)),
      PathKnot(.init(60, 10), incoming: .init(40, -15))
    ] + Array(repeating: PathKnot(.init(60, 10)), count: VectorPath.maxKnots - 2))])
    let matrix = try ProjectiveTransform([1, 0, 0, 0, 1, 0, -0.01, 0, 1])
    XCTAssertThrowsError(try ProjectiveVectorPath.apply(path, matrix: matrix)) { error in
      XCTAssertTrue(error.localizedDescription.contains("knot limit"))
    }
  }
}
