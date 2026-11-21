import CoreGraphics
import XCTest
@testable import PhotoCraftCore

final class PathComponentLayoutTests: XCTestCase {
  private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                    operation: PathOperation = .combine) -> PathComponent {
    let points = [PathPoint(x, y), .init(x+w, y), .init(x+w, y+h), .init(x, y+h)]
    return .init(knots: points.map { PathKnot($0) }, closed: true, operation: operation)
  }

  private func fixture() throws -> (CraftDocument, NamedPath) {
    var source = try CraftDocument(width: 150, height: 150)
    let saved = NamedPath(name: "Components", path: .init(components: [
      rect(0.25, 0.5, 10.5, 13.25), rect(21.25, 33.5, 4.25, 8.5, operation: .subtract),
      rect(52.75, 70.75, 7.5, 6.25, operation: .exclude), rect(100, 110, 5.5, 3)
    ], fillRule: .evenOdd))
    source.paths = [saved]
    return (source, saved)
  }

  private func bounds(_ component: PathComponent) throws -> CGRect {
    try PathTransform.selectedBounds(.init(components: [component]), selection: .all)
  }

  func testAllSixAlignmentEdgesUseFractionalUnionWithoutChangingUnselectedGeometry() throws {
    let (source, saved) = try fixture()
    let expected: [(LayerAlignment, Double)] = [
      (.top, 0.5), (.verticalCenter, 38.75), (.bottom, 77.0),
      (.left, 0.25), (.horizontalCenter, 30.25), (.right, 60.25)
    ]
    for (edge, required) in expected {
      let edit = try PathComponentLayout.geometry(
        .init(target: .saved(saved.id), components: [2, 0, 1], operation: .align(edge)), in: source)
      XCTAssertEqual(edit.choice.selection, .components([0, 1, 2]))
      XCTAssertEqual(edit.path.components[3], saved.path.components[3])
      XCTAssertEqual(edit.path.fillRule, .evenOdd)
      XCTAssertEqual(edit.path.components.map(\.operation), saved.path.components.map(\.operation))
      XCTAssertEqual(edit.path.components.map(\.closed), saved.path.components.map(\.closed))
      for index in 0..<3 {
        let actual = try bounds(edit.path.components[index])
        let original = try bounds(saved.path.components[index])
        switch edge {
        case .top: XCTAssertEqual(actual.minY, required)
        case .verticalCenter: XCTAssertEqual(actual.midY, required)
        case .bottom: XCTAssertEqual(actual.maxY, required)
        case .left: XCTAssertEqual(actual.minX, required)
        case .horizontalCenter: XCTAssertEqual(actual.midX, required)
        case .right: XCTAssertEqual(actual.maxX, required)
        }
        XCTAssertEqual(actual.size, original.size)
        XCTAssertEqual(edge.horizontal ? actual.minY : actual.minX, edge.horizontal ? original.minY : original.minX)
      }
    }
  }

  func testDistributionLeavesEndpointsFixedAndSupportsEdgeCenterAndGapModes() throws {
    let (source, saved) = try fixture()
    let choices: [(LayerDistribution, Double, Double)] = [
      (.left, 26.5, 33.5), (.horizontalCenter, 28.875, 33.5), (.right, 31.25, 33.5),
      (.top, 21.25, 35.625), (.verticalCenter, 21.25, 36.25), (.bottom, 21.25, 36.875),
      (.horizontally, 29.625, 33.5), (.vertically, 21.25, 38.0)
    ]
    // These are the leading document coordinates of the middle component.
    for (mode, x, y) in choices {
      let edit = try PathComponentLayout.geometry(
        .init(target: .saved(saved.id), components: [2, 1, 0], operation: .distribute(mode)), in: source)
      XCTAssertEqual(edit.path.components[0], saved.path.components[0], mode.rawValue)
      XCTAssertEqual(edit.path.components[2...3], saved.path.components[2...3], mode.rawValue)
      let moved = try bounds(edit.path.components[1])
      XCTAssertEqual(moved.minX, x, mode.rawValue)
      XCTAssertEqual(moved.minY, y, mode.rawValue)
    }
  }

  func testBezierExtremaExcludeControlPolygonAndMoveEveryHandle() throws {
    var (source, saved) = try fixture()
    let curve = PathComponent(knots: [
      .init(.init(40.75, 21), outgoing: .init(40.75, -11), smooth: true),
      .init(.init(56.75, 21), incoming: .init(56.75, -11), smooth: true)
    ])
    saved.path.components[2] = curve
    source.paths = [saved]
    let edit = try PathComponentLayout.geometry(
      .init(target: .saved(saved.id), components: [0, 2], operation: .align(.top)), in: source)
    XCTAssertEqual(try bounds(curve).minY, -3)
    XCTAssertEqual(try bounds(edit.path.components[0]).minY, -3)
    XCTAssertEqual(edit.path.components[2], curve)
    XCTAssertEqual(edit.path.components[0].knots,
                   saved.path.components[0].knots.map { $0.transformed(.translation(0, -3.5)) })
  }

  func testVectorMaskAndLiveShapeUseSameEditAndInvalidRequestsAreAtomic() throws {
    var (source, saved) = try fixture()
    var mask = Layer(name: "Masked", content: .raster(try Surface(width: 150, height: 150, fill: .white)))
    mask.vectorMask = .init(path: saved.path)
    mask.vectorMask?.linked = false
    var shapeDefinition = ShapeDefinition(geometry: .init(width: 10, height: 12))
    shapeDefinition.components = [
      ShapeComponent(geometry: .init(width: 10, height: 12), transform: .translation(1.25, 3.5)),
      ShapeComponent(geometry: .init(width: 8, height: 16), transform: .translation(21.75, 36.5)),
      ShapeComponent(geometry: .init(width: 12, height: 10), transform: .translation(46.5, 80.25))
    ]
    let shapeLayer = Layer(name: "Live", content: .shape(try .init(definition: shapeDefinition)))
    source.layers = [mask, shapeLayer]
    source.activeLayerID = shapeLayer.id

    var document = source
    let align = PathComponentLayoutRequest(target: .vectorMask(mask.id), components: [2, 1, 0], operation: .align(.left))
    try Command.layoutPathComponents(align).apply(to: &document)
    XCTAssertEqual(document.layers[0].vectorMask?.linked, false)
    XCTAssertEqual(document.layers[0].vectorMask?.path.components[3], saved.path.components[3])
    XCTAssertEqual(document.layers[0].content, source.layers[0].content)
    XCTAssertEqual(document.layers[1], source.layers[1])

    let live = PathComponentLayoutRequest(target: .shape(shapeLayer.id), operation: .align(.top))
    let exact = try PathComponentLayout.geometry(live, in: document).path
    try Command.layoutPathComponents(live).apply(to: &document)
    XCTAssertEqual(try document.layers[1].shapePath(), exact)
    let retained = try XCTUnwrap(document.layers[1].shape?.definition)
    XCTAssertEqual(retained.components.map(\.geometry), shapeDefinition.components.map(\.geometry))
    XCTAssertEqual(retained.components.map { $0.transform.ty }, [3.5, 3.5, 3.5])

    let unchanged = document
    for invalid in [[0, 0], [0, 4], [0]] {
      XCTAssertThrowsError(try Command.layoutPathComponents(
        .init(target: .shape(shapeLayer.id), components: invalid, operation: .align(.left))).apply(to: &document))
      XCTAssertEqual(document, unchanged)
    }
    document.layers[1].locked = true
    let locked = document
    XCTAssertThrowsError(try Command.layoutPathComponents(live).apply(to: &document))
    XCTAssertEqual(document, locked)
  }
}
