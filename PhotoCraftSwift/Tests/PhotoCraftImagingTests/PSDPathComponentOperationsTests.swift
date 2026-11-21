import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDPathComponentOperationsTests: XCTestCase {
  func testFirstSubtractKeepsLiveShapeAndTransparentHoleThroughPSDAndPSB() throws {
    var document = try CraftDocument(width: 128, height: 96)
    document.layers = []
    document.activeLayerID = nil
    let geometry = ShapeGeometry(width: 32, height: 24)
    let shape = ShapeDefinition(geometry: geometry, fill: .init(color: Pixel(1, 0, 0)))
    try Command.shape(.create("Cutout", shape, .translation(32, 24))).apply(to: &document)
    let target = PathTransformTarget.shape(try XCTUnwrap(document.activeLayerID))
    let originalPath = try PathTransform.path(target, in: document)
    let firstSubtract = try PathComponentEdit.prepare(.init(target: target, operation: .subtract), in: document)
    try Command.editPathComponents(firstSubtract).apply(to: &document)
    let native = try XCTUnwrap(document.layers.last?.shape?.definition)
    XCTAssertEqual(native.components.map(\.geometry), [geometry])
    XCTAssertEqual(document.minimumArchiveVersion, ShapeDefinition.exteriorArchiveVersion)
    XCTAssertEqual(try PathTransform.path(target, in: document).components.map(\.knots),
                   originalPath.components.map(\.knots))
    let expected = try Renderer.composite(document)
    XCTAssertEqual(expected.pixel(x: 0, y: 0), Pixel(1, 0, 0))
    XCTAssertEqual(expected.pixel(x: 47, y: 35), .clear)
    XCTAssertEqual(expected.pixel(x: 127, y: 95), Pixel(1, 0, 0))
    for format in PSDFileFormat.allCases {
      let data = try PSDCodec.writeRasterLayers(document, format: format)
      if let output = ProcessInfo.processInfo.environment["PHOTATO_SHAPE_SUBTRACTION_OUTPUT"] {
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(format == .psd ? "cutout.psd" : "cutout.psb"))
        try expected.rgbaData(depth: .u8).write(to: folder.appendingPathComponent("cutout.rgba"))
      }
      let reopened = try PSDCodec.read(data)
      let layer = try XCTUnwrap(reopened.layers.last)
      XCTAssertEqual(layer.shape?.definition?.components.map(\.geometry), [geometry])
      XCTAssertEqual(try layer.shapePath()?.components.first?.operation, .subtract)
      XCTAssertNotNil(layer.sourceTags?["vsms"])
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8), try expected.rgbaData(depth: .u8))
      let combine = try PathComponentEdit.prepare(
        .init(target: .shape(layer.id), operation: .combine), in: reopened)
      var edited = reopened
      try Command.editPathComponents(combine).apply(to: &edited)
      XCTAssertNil(edited.layers.last?.shape?.definition?.exteriorFrame)
      let combined = try Renderer.composite(edited)
      XCTAssertEqual(combined.pixel(x: 0, y: 0), .clear)
      XCTAssertEqual(combined.pixel(x: 47, y: 35), Pixel(1, 0, 0))
    }
  }

  func testSubtractThenIntersectKeepsOnlyTheFiniteRemainder() throws {
    var document = try CraftDocument(width: 100, height: 80)
    document.layers = []
    document.activeLayerID = nil
    var shape = ShapeDefinition(geometry: .init(width: 20, height: 16))
    shape.components[0].operation = .subtract
    shape.components.append(.init(geometry: .init(width: 36, height: 24), transform: .translation(12, 3), operation: .intersect))
    try Command.shape(.create("Finite remainder", shape, .translation(14, 21))).apply(to: &document)
    let result = try Renderer.composite(document)
    XCTAssertEqual(result.pixel(x: 2, y: 2), .clear)
    XCTAssertEqual(result.pixel(x: 28, y: 28), .clear)
    XCTAssertEqual(result.pixel(x: 38, y: 28), .black)
  }

  func testShapeSubtractIntersectMatchesOwnedPhotoshopReferenceChannels() throws {
    let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/psd-path-semantics")
    let source = try PSDCodec.read(Data(contentsOf: folder.appendingPathComponent("photoshop-path-semantics.psd")))
    let expected = try Data(contentsOf: folder.appendingPathComponent("photoshop-path-semantics.rgb"))
    let index = try XCTUnwrap(source.layers.firstIndex { $0.name == "Subtract then Intersect" })
    let old = source.layers[index]
    guard case .raster(let raster) = old.content else { return XCTFail("The Adobe fixture needs its original raster.") }
    let mask = try XCTUnwrap(old.vectorMask)
    var definition = ShapeDefinition(geometry: .init(), fill: .init(color: raster.pixel(x: 0, y: 0)))
    definition.components = try ShapeDefinition.editablePathComponents(mask.path)
    definition.fillRule = mask.path.fillRule
    var scratch = try CraftDocument(width: source.width, height: source.height)
    try Command.shape(.create(old.name, definition, .identity)).apply(to: &scratch)
    let shape = try XCTUnwrap(scratch.layers.last)
    var comparison = source
    comparison.layers[index].content = shape.content
    comparison.layers[index].x = shape.x
    comparison.layers[index].y = shape.y
    comparison.layers[index].affine = shape.affine
    comparison.layers[index].vectorMask = nil
    let actual = try Renderer.composite(comparison).rgbaData(depth: .u8)
    for i in 0..<(source.width * source.height) {
      XCTAssertEqual(actual[4 * i], expected[3 * i], "red word \(i)")
      XCTAssertEqual(actual[4 * i + 1], expected[3 * i + 1], "green word \(i)")
    }
  }

  func testLeadingSubtractShowsOnlyTheContourStroke() throws {
    var document = try CraftDocument(width: 128, height: 96)
    document.layers = []
    document.activeLayerID = nil
    var stroke = ShapeStroke()
    stroke.paint = .init(color: .white)
    stroke.width = 4
    var shape = ShapeDefinition(geometry: .init(width: 32, height: 24), stroke: stroke)
    shape.components[0].operation = .subtract
    try Command.shape(.create("Stroked cutout", shape, .translation(32, 24))).apply(to: &document)
    let result = try Renderer.composite(document)
    XCTAssertEqual(result.pixel(x: 0, y: 0), .black)
    XCTAssertEqual(result.pixel(x: 31, y: 35), .white)
    XCTAssertEqual(result.pixel(x: 40, y: 35), .clear)
  }

  func testSparseExteriorRendersOnMaximumCanvasAndReopensNatively() throws {
    let side = Surface.maxDimension
    var document = try CraftDocument(width: side, height: side)
    document.layers = []
    document.activeLayerID = nil
    var shape = ShapeDefinition(geometry: .init(width: 20, height: 16))
    shape.components[0].operation = .subtract
    try Command.shape(.create("Large cutout", shape, .translation(240_000, 225_000))).apply(to: &document)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".photato")
    defer { try? FileManager.default.removeItem(at: file) }
    try NativeArchive.write(document, to: file)
    let reopened = try NativeArchive.read(file)
    let viewport = IntRect(x: 239_990, y: 224_990, width: 50, height: 50)
    let composite = try Renderer.composite(reopened, region: viewport)
    XCTAssertEqual(composite.pixel(x: 239_999, y: 225_001), .black)
    XCTAssertEqual(composite.pixel(x: 240_001, y: 225_001), .clear)
    let whole = try Renderer.composite(reopened)
    XCTAssertEqual(whole.pixel(x: side - 1, y: side - 1), .black)
    XCTAssertEqual(whole.pixel(x: 240_001, y: 225_001), .clear)
    XCTAssertLessThan(whole.allocatedBytes, 1_000_000)
  }

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
