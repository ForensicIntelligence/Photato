import PhotoCraftCore
import XCTest

final class VectorPathTests: XCTestCase {
  func rectangle() -> VectorPath {
    VectorPath(components: [
      PathComponent(
        knots: [
          PathPoint(2, 2), PathPoint(12, 2),
          PathPoint(12, 10), PathPoint(2, 10),
        ].map { PathKnot($0) }, closed: true)
    ])
  }
  func testCubicSubdivisionPreservesEveryPointIncludingClosingSegment() throws {
    let a = PathKnot(
      PathPoint(2, 2), incoming: PathPoint(-2, 8), outgoing: PathPoint(4, -5), smooth: true)
    let b = PathKnot(PathPoint(20, 12), incoming: PathPoint(14, 30), outgoing: PathPoint(35, 5))
    let original = PathComponent(knots: [a, b], closed: true)
    for segment in 0...1 {
      var split = original
      try split.split(segment: segment, at: 0.37)
      for i in 0...100 {
        let t = Double(i) / 100
        let p = original.point(segment: segment, at: t)!
        let q = split.point(
          segment: t <= 0.37 ? segment : segment + 1,
          at: t <= 0.37 ? t / 0.37 : (t - 0.37) / 0.63)!
        XCTAssertEqual(p.x, q.x, accuracy: 1e-10)
        XCTAssertEqual(p.y, q.y, accuracy: 1e-10)
      }
    }
  }
  func testHandleEditingPreservesOppositeLengthAndAnchorTranslation() {
    var k = PathKnot(
      PathPoint(0, 0), incoming: PathPoint(-10, 0), outgoing: PathPoint(20, 0), smooth: true)
    k.moveHandle(incoming: false, to: PathPoint(0, 5), independent: false)
    XCTAssertEqual(k.incoming, PathPoint(0, -10))
    k.moveAnchor(to: PathPoint(4, 8))
    XCTAssertEqual(k.outgoing, PathPoint(4, 13))
    XCTAssertEqual(k.incoming, PathPoint(4, -2))
    k.moveHandle(incoming: true, to: PathPoint(2, 2), independent: true)
    XCTAssertFalse(k.smooth)
    XCTAssertEqual(k.outgoing, PathPoint(4, 13))
  }
  func testVectorMaskLinkAndCanvasGeometry() throws {
    var d = try CraftDocument(width: 20, height: 16)
    d.layers[0].vectorMask = VectorMask(path: rectangle())
    d.paths = [NamedPath(path: rectangle())]
    let id = d.layers[0].id
    try Command.move(id, 3, 4).apply(to: &d)
    XCTAssertEqual(d.layers[0].vectorMask!.path, rectangle().transformed(.translation(3, 4)))
    d.layers[0].vectorMask!.linked = false
    let fixed = d.layers[0].vectorMask!.path
    try Command.move(id, 6, 8).apply(to: &d)
    XCTAssertEqual(d.layers[0].vectorMask!.path, fixed)
    try Command.transform(id, .scale(2, 2), .nearest).apply(to: &d)
    XCTAssertEqual(d.layers[0].vectorMask!.path, fixed)
    try Command.imageSize(40, 32, 72, .nearest).apply(to: &d)
    XCTAssertEqual(d.layers[0].vectorMask!.path, fixed.transformed(.scale(2, 2)))
    XCTAssertEqual(d.paths![0].path, rectangle().transformed(.scale(2, 2)))
    try Command.crop(IntRect(x: 2, y: 3, width: 20, height: 16)).apply(to: &d)
    let cropped = rectangle().transformed(.translation(-2, -3) * .scale(2, 2))
    XCTAssertEqual(d.paths![0].path, cropped)
    try Command.canvasSize(24, 20, .center, nil).apply(to: &d)
    XCTAssertEqual(d.paths![0].path, cropped.transformed(.translation(2, 2)))
    try Command.rotateCanvas(.clockwise).apply(to: &d)
    XCTAssertEqual(d.paths![0].path, cropped.transformed(.clockwiseForTest))
  }
  func testNativeArchiveAndAtomicValidationUndo() throws {
    var d = try CraftDocument(width: 20, height: 16)
    let original = d
    let path = NamedPath(path: rectangle())
    var session = EditorSession(document: d)
    try session.execute(.savePath(path))
    try session.execute(.vectorMask(d.layers[0].id, VectorMask(path: path.path)))
    d = session.document
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
    var invalid = path
    invalid.path.components[0].knots[0].anchor.x = .nan
    XCTAssertThrowsError(try session.execute(.savePath(invalid)))
    XCTAssertEqual(session.document, d)
    session.undo()
    session.undo()
    XCTAssertEqual(session.document, original)
    session.redo()
    session.redo()
    XCTAssertEqual(session.document, d)
    var locked = d
    locked.layers[0].locked = true
    var lockedSession = EditorSession(document: locked)
    XCTAssertThrowsError(try lockedSession.execute(.vectorMask(locked.layers[0].id, nil)))
    XCTAssertEqual(lockedSession.document, locked)
  }
  func testMalformedGeometryAndDuplicateWorkPathsReject() throws {
    var d = try CraftDocument(width: 20, height: 16)
    d.paths = [NamedPath(), NamedPath()]
    XCTAssertThrowsError(try d.validate())
    var path = rectangle()
    path.components[0].knots = [PathKnot](repeating: PathKnot(PathPoint(0, 0)), count: 4097)
    XCTAssertThrowsError(try path.validate())
    var c = rectangle().components[0]
    XCTAssertThrowsError(try c.split(segment: -1, at: 0.5))
    XCTAssertThrowsError(try c.split(segment: 0, at: 1))
  }
}
extension Transform2D {
  fileprivate static var clockwiseForTest: Self {
    CanvasTurn.clockwise.transform(width: 24, height: 20) * .translation(2, 2)
  }
}
