import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDPathComponentOperationsTests: XCTestCase {
  func testMergeWritesEditableContourAndStackingRetainsLivePrimitives() throws {
    var document = try CraftDocument(width: 160, height: 150)
    var shape = ShapeDefinition(geometry: .init(width: 50, height: 38), fill: .init(color: .black))
    shape.components.append(.init(geometry: .init(width: 31, height: 42), transform: .translation(25, 11)))
    try Command.shape(.create("Merged artwork", shape, .translation(20, 28))).apply(to: &document)
    let target = PathTransformTarget.shape(try XCTUnwrap(document.activeLayerID))
    let pixels = try Renderer.composite(document).rgbaData(depth: .u8)
    let stack = try PathComponentEdit.prepare(
      .init(target: target, components: [0], operation: .bringToFront), in: document)
    try Command.editPathComponents(stack).apply(to: &document)
    XCTAssertEqual(document.layers.last?.shape?.definition?.components.map(\.geometry),
                   shape.components.reversed().map(\.geometry))
    for format in PSDFileFormat.allCases {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
      XCTAssertEqual(reopened.layers.last?.shape?.definition?.components.map(\.geometry),
                     shape.components.reversed().map(\.geometry))
    }
    let merge = try PathComponentEdit.prepare(.init(target: target, operation: .merge), in: document)
    try Command.editPathComponents(merge).apply(to: &document)
    let path = try PathTransform.path(target, in: document)
    XCTAssertEqual(path.components.count, 1)
    XCTAssertGreaterThan(path.knotCount, 4)
    XCTAssertEqual(try Renderer.composite(document).rgbaData(depth: .u8), pixels)
    for format in PSDFileFormat.allCases {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
      let layer = try XCTUnwrap(reopened.layers.last)
      XCTAssertEqual(layer.shape?.definition?.components.map(\.geometry.kind), [.custom])
      XCTAssertNil(layer.sourceTags?["vogk"])
      XCTAssertNotNil(layer.sourceTags?["vsms"])
      XCTAssertEqual(try layer.shapePath()?.knotCount, path.knotCount)
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8), pixels)
    }
  }
}
