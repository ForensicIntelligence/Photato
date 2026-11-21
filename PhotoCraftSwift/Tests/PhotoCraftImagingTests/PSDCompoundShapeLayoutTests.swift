import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDCompoundShapeLayoutTests: XCTestCase {
  func testCompoundLiveGeometrySurvivesLayoutAndEditablePhotoshopFileRoundTrip() throws {
    var document = try CraftDocument(width: 260, height: 210)
    var shape = ShapeDefinition(geometry: .init(width: 63.5, height: 45.25),
                                fill: .init(color: .init(1, 0, 0)))
    shape.components += [
      .init(geometry: .init(kind: .ellipse, width: 28.75, height: 26), transform: .translation(12, 11),
            operation: .subtract),
      .init(geometry: .init(width: 47.5, height: 35), transform: .translation(92.75, 64.25))
    ]
    try Command.shape(.create("Compound paths", shape, .translation(27.25, 22.5))).apply(to: &document)
    let source = try XCTUnwrap(document.layers.last)
    try Command.layoutPathComponents(.init(target: .shape(source.id), components: [0, 2],
                                           operation: .align(.top))).apply(to: &document)
    let edited = try XCTUnwrap(document.layers.last)
    let expected = try XCTUnwrap(edited.shapePath())
    XCTAssertEqual(edited.shape?.definition?.components.map(\.geometry), shape.components.map(\.geometry))
    for format in PSDFileFormat.allCases {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
      let layer = try XCTUnwrap(reopened.layers.first { $0.name == "Compound paths" })
      let definition = try XCTUnwrap(layer.shape?.definition)
      XCTAssertEqual(definition.components.map(\.geometry), shape.components.map(\.geometry))
      XCTAssertEqual(definition.components.map(\.operation), [.combine, .subtract, .combine])
      let tags = try XCTUnwrap(layer.sourceTags)
      XCTAssertTrue(["vscg", "vsms", "vowv", "vogk", "vstk", "sn2P"].allSatisfy { tags[$0]?.count.isMultiple(of: 2) == true })
      let record = try XCTUnwrap(tags["vsms"])
      XCTAssertEqual(try PSDPaths.maskOriginationIndices(record), [0, 1, 2])
      let actual = try XCTUnwrap(layer.shapePath())
      XCTAssertEqual(actual.components.map(\.closed), expected.components.map(\.closed))
      XCTAssertEqual(actual.components.map { $0.knots.count }, expected.components.map { $0.knots.count })
      for (a, b) in zip(actual.components.flatMap(\.knots), expected.components.flatMap(\.knots)) {
        for (x, y) in zip([a.anchor, a.incoming, a.outgoing], [b.anchor, b.incoming, b.outgoing]) {
          XCTAssertEqual(x.x, y.x, accuracy: 0.0001)
          XCTAssertEqual(x.y, y.y, accuracy: 0.0001)
        }
      }
      let savedAgain = try PSDCodec.read(PSDCodec.writeRasterLayers(reopened, format: format))
      XCTAssertEqual(try savedAgain.layers.first { $0.name == "Compound paths" }?.shapePath(), actual)
    }
  }
}
