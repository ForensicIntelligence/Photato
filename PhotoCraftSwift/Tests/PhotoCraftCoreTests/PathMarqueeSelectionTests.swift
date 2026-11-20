import XCTest
@testable import PhotoCraftCore

final class PathMarqueeSelectionTests: XCTestCase {
  func testReverseRectangleIncludesEdgesAndSelectsAnchorsRatherThanHandles() {
    let path = VectorPath(components: [
      .init(knots: [.init(.init(10, 10)), .init(.init(19, 19)), .init(.init(30, 25), incoming: .init(12, 12))]),
      .init(knots: [.init(.init(21, 15)), .init(.init(20, 20))])
    ])
    let marquee = PathMarqueeSelection(start: .init(20, 20), end: .init(10, 10))
    let expected = PathTransformSelection.anchors([.init(component: 0, knot: 0),
      .init(component: 0, knot: 1), .init(component: 1, knot: 1)])
    XCTAssertEqual(marquee.selection(in: path), expected)
    XCTAssertEqual(PathMarqueeSelection(start: marquee.end, end: marquee.start).selection(in: path), expected)
  }

  func testAdditiveSelectionKeepsExistingAnchorsAndExpandsSelectedContours() {
    let path = VectorPath(components: [
      .init(knots: [.init(.init(2, 2)), .init(.init(12, 2))]),
      .init(knots: [.init(.init(12, 12)), .init(.init(30, 20))])
    ])
    let marquee = PathMarqueeSelection(start: .init(11, 0), end: .init(15, 17))
    let expected = PathTransformSelection.anchors([.init(component: 0, knot: 0),
      .init(component: 0, knot: 1), .init(component: 1, knot: 0)])
    XCTAssertEqual(marquee.selection(in: path, extending: .components([0])), expected)
    XCTAssertEqual(marquee.selection(in: path, extending: expected), expected)
    let empty = PathMarqueeSelection(start: .init(-10, -20), end: .init(-5, -5))
    XCTAssertEqual(empty.selection(in: path, extending: .components([0])), .components([0]))
    XCTAssertEqual(empty.selection(in: path), .anchors([]))
  }
}
