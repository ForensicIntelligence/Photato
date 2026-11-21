import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDPathComponentOperationsTests: XCTestCase {
  private func paintedCutout(width: Int, height: Int, depth: PixelDepth = .u8,
                              placement: Transform2D) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: height, depth: depth)
    document.layers = []
    document.activeLayerID = nil
    var shape = ShapeDefinition(geometry: .init(kind: .ellipse, width: 64, height: 40))
    shape.components[0].operation = .subtract
    shape.fill.kind = .gradient
    shape.fill.gradient = .init(dither: false)
    shape.stroke.paint = .init(color: Pixel(1, 0, 0))
    shape.stroke.width = 6
    try Command.shape(.create("Painted cutout", shape, placement)).apply(to: &document)
    return document
  }

  func testStyledCutoutViewportAtMaximumCanvasAndNativeReopen() throws {
    let side = Surface.maxDimension
    let document = try paintedCutout(width: side, height: side, placement: .translation(240_000, 230_000))
    let saved = try NativeArchive.encodeChunked(document)
    let reopened = try NativeArchive.decode(saved)
    XCTAssertEqual(reopened, document)
    let viewport = IntRect(x: 239_985, y: 229_985, width: 100, height: 70)
    let output = try Renderer.composite(reopened, region: viewport)
    XCTAssertEqual(output.pixel(x: 240_032, y: 230_020), .clear)
    XCTAssertEqual(output.pixel(x: 239_998, y: 230_020), Pixel(1, 0, 0))
    XCTAssertEqual(output.pixel(x: 239_989, y: 230_020).a, 1)
    XCTAssertEqual(output.pixel(x: 450, y: 450), .clear)
    XCTAssertLessThan(output.allocatedBytes, 2_000_000)
    let layer = try XCTUnwrap(reopened.layers.last)
    XCTAssertEqual(try Renderer.layoutBounds(layer, in: reopened, stored: false),
                   .init(x: 0, y: 0, width: side, height: side))
    XCTAssertEqual(try ShapeRenderer.viewportPixel(layer, in: reopened, x: 239_998, y: 230_020), Pixel(1, 0, 0))
    let preview = try XCTUnwrap(Renderer.layerThumbnail(layer, in: reopened, framing: .layerBounds, maximumSize: 120))
    XCTAssertEqual([preview.width, preview.height], [120, 120])
    XCTAssertEqual(preview.pixel(x: 0, y: 0).a, 1)
    let far = try Renderer.composite(reopened, region: .init(x: 299_950, y: 20, width: 24, height: 24))
    XCTAssertNotEqual(far.pixel(x: 299_956, y: 28), output.pixel(x: 239_989, y: 230_020))
    XCTAssertEqual(far.pixel(x: 299_956, y: 28).a, 1)
  }

  func testPaintedAffineCutoutPatchesMatchMaterializedSourceAtEveryDepth() throws {
    let transform = Transform2D.translation(95.375, 83.625) * .rotation(19)
    for depth in PixelDepth.allCases {
      var document = try paintedCutout(width: 260, height: 220, depth: depth, placement: transform)
      let layer = try XCTUnwrap(document.layers.last)
      var definition = try XCTUnwrap(layer.shape?.definition)
      definition.fill.gradient?.dither = true
      definition.fill.gradient?.placement.angle = 27
      definition.stroke.paint.kind = .gradient
      definition.stroke.paint.gradient = .init(aligned: false)
      definition.stroke.dash = [6, 4]
      definition.stroke.cap = .round
      try Command.shape(.configure(layer.id, definition)).apply(to: &document)
      let placed = try ShapeRenderer.rasterInput(XCTUnwrap(document.layers.last), in: document)
      let expected = try Renderer.layerSurface(placed, in: document)
      for viewport in [
        IntRect(x: 82, y: 99, width: 32, height: 33),
        IntRect(x: 110, y: 88, width: 41, height: 45),
        IntRect(x: 0, y: 0, width: 17, height: 12),
      ] {
        let patch = try XCTUnwrap(ShapeRenderer.viewportRaster(placed, in: document, region: viewport))
        let source = try expected.cropped(to: .init(x: patch.x, y: patch.y,
          width: patch.surface.width, height: patch.surface.height))
        XCTAssertEqual(try patch.surface.rgbaData(depth: depth), try source.rgbaData(depth: depth))
      }
    }
  }

  func testSolidExteriorWithEditableGradientStrokeStaysSparseOnMaximumCanvas() throws {
    let side = Surface.maxDimension
    var document = try paintedCutout(width: side, height: side, placement: .translation(240_000, 230_000))
    let layer = try XCTUnwrap(document.layers.last)
    var definition = try XCTUnwrap(layer.shape?.definition)
    definition.fill = .init(color: .white)
    definition.stroke.paint.kind = .gradient
    definition.stroke.paint.gradient = .init(dither: false)
    try Command.shape(.configure(layer.id, definition)).apply(to: &document)
    let output = try Renderer.composite(document)
    XCTAssertEqual(output.pixel(x: 299_999, y: 299_999), .white)
    XCTAssertEqual(output.pixel(x: 240_032, y: 230_020), .clear)
    let edge = output.pixel(x: 239_998, y: 230_020)
    XCTAssertEqual(edge.a, 1)
    XCTAssertLessThan(edge.r, 1)
    XCTAssertLessThan(output.allocatedBytes, 2_000_000)
  }

  func testPatternedExteriorMatchesPagedCompositeAndMaskedViewport() throws {
    var document = try paintedCutout(width: 2080, height: 140, placement: .translation(1998, 50))
    let layer = try XCTUnwrap(document.layers.last)
    var pattern = try Surface(width: 2, height: 2, fill: Pixel(0, 1, 0))
    pattern.setPixel(x: 0, y: 0, Pixel(0, 0, 1))
    let patternID = try document.installPattern(.init(name: "Check", surface: pattern))
    var definition = try XCTUnwrap(layer.shape?.definition)
    definition.fill.kind = .pattern
    definition.fill.gradient = nil
    definition.fill.pattern = .init(patternID: patternID)
    try Command.shape(.configure(layer.id, definition)).apply(to: &document)
    var mask = try Surface(width: document.width, height: document.height, fill: .white)
    mask.setPixel(x: 2021, y: 42, .black)
    try Command.mask(layer.id, mask).apply(to: &document)
    let whole = try Renderer.composite(document)
    let paged = try Renderer.compositePaged(document)
    XCTAssertEqual(try whole.rgbaData(depth: .u8), try paged.rgbaData(depth: .u8))
    let viewport = IntRect(x: 1995, y: 37, width: 73, height: 68)
    let viewed = try Renderer.composite(document, region: viewport)
    XCTAssertEqual(try viewed.cropped(to: viewport).rgbaData(depth: .u8),
                   try whole.cropped(to: viewport).rgbaData(depth: .u8))
    XCTAssertEqual(viewed.pixel(x: 2021, y: 42).a, 0)
  }

  private func cutoutDocument() throws -> CraftDocument {
    var document = try CraftDocument(width: 128, height: 96)
    document.layers = []
    document.activeLayerID = nil
    var shape = ShapeDefinition(geometry: .init(width: 32, height: 24))
    shape.components[0].operation = .subtract
    try Command.shape(.create("Cutout", shape, .translation(32, 24))).apply(to: &document)
    return document
  }

  func testMovingTheLayerMovesTheHoleAndRetainsCanvasCoverage() throws {
    var document = try cutoutDocument()
    let initial = try XCTUnwrap(document.layers.last)
    let before = try XCTUnwrap(initial.shapePath())
    try Command.moveLayers(.init(layerIDs: [initial.id], dx: 18, dy: 7)).apply(to: &document)
    let moved = try XCTUnwrap(document.layers.last)
    XCTAssertEqual(moved.x, initial.x + 18)
    XCTAssertEqual(moved.y, initial.y + 7)
    XCTAssertEqual(try moved.shapePath(), before.transformed(.translation(18, 7)))
    let model = document
    let visible = try Renderer.composite(document)
    XCTAssertEqual(visible.pixel(x: 0, y: 0), .black)
    XCTAssertEqual(visible.pixel(x: 127, y: 95), .black)
    XCTAssertEqual(visible.pixel(x: 40, y: 36), .black)
    XCTAssertEqual(visible.pixel(x: 66, y: 42), .clear)
    XCTAssertEqual(document, model)
    let clipping = try Renderer.clippingCoverage(moved, in: document)
    XCTAssertEqual(clipping.pixel(x: 0, y: 0).a, 1)
    XCTAssertEqual(clipping.pixel(x: 66, y: 42).a, 0)
    let thumbnail = try Renderer.layerThumbnail(moved, in: document, framing: .entireDocument, maximumSize: 128)
    XCTAssertEqual(thumbnail?.pixel(x: 0, y: 0), .black)
  }

  func testCanvasSizeAndCropReframeEditablePSDAndPSB() throws {
    var document = try cutoutDocument()
    let id = try XCTUnwrap(document.activeLayerID)
    try Command.moveLayers(.init(layerIDs: [id], dx: 18, dy: 8)).apply(to: &document)
    let moved = try XCTUnwrap(document.layers.last?.shapePath())
    try Command.canvasSize(160, 128, .center, nil).apply(to: &document)
    XCTAssertEqual(try document.layers.last?.shapePath(), moved.transformed(.translation(16, 16)))
    let expanded = try Renderer.composite(document)
    XCTAssertEqual(expanded.pixel(x: 159, y: 127), .black)
    XCTAssertEqual(expanded.pixel(x: 82, y: 58), .clear)
    let crop = IntRect(x: 24, y: 24, width: 128, height: 96)
    try Command.crop(crop).apply(to: &document)
    let expectedPath = moved.transformed(.translation(-8, -8))
    XCTAssertEqual(try document.layers.last?.shapePath(), expectedPath)
    let cropped = try Renderer.composite(document)
    XCTAssertEqual(cropped.pixel(x: 0, y: 0), .black)
    XCTAssertEqual(cropped.pixel(x: 127, y: 95), .black)
    XCTAssertEqual(cropped.pixel(x: 58, y: 34), .clear)
    let expected = try cropped.rgbaData(depth: .u8)
    for format in PSDFileFormat.allCases {
      let data = try PSDCodec.writeRasterLayers(document, format: format)
      let reopened = try PSDCodec.read(data)
      let layer = try XCTUnwrap(reopened.layers.last)
      XCTAssertEqual(try layer.shapePath(), expectedPath)
      XCTAssertEqual(try Renderer.composite(reopened).rgbaData(depth: .u8), expected)
      if let output = ProcessInfo.processInfo.environment["PHOTATO_SHAPE_CANVAS_OUTPUT"] {
        let folder = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(format == .psd ? "reframed.psd" : "reframed.psb"))
        try expected.write(to: folder.appendingPathComponent("reframed.rgba"))
      }
    }
  }

  func testRasterizingReframedExteriorKeepsUnlinkedMaskAndRenderedPixels() throws {
    var document = try cutoutDocument()
    let id = try XCTUnwrap(document.activeLayerID)
    var mask = try Surface(width: 128, height: 96, fill: .white)
    mask.setPixel(x: 11, y: 9, .black)
    document.layers[0].mask = mask
    var properties = MaskProperties()
    properties.linked = false
    document.layers[0].maskProperties = properties
    let beforeMaskPlacement = document.layers[0].maskCoordinateTransform
    try Command.moveLayers(.init(layerIDs: [id], dx: 20, dy: 12)).apply(to: &document)
    let movedLayer = try XCTUnwrap(document.layers.last)
    let moved = try Renderer.composite(document).rgbaData(depth: .u8)
    let operation = try SmartObjectIO.rasterizationCommand(movedLayer, in: document)
    try operation.apply(to: &document)
    let rasterLayer = try XCTUnwrap(document.layers.last)
    XCTAssertNil(rasterLayer.shape)
    XCTAssertEqual(rasterLayer.maskCoordinateTransform, beforeMaskPlacement)
    XCTAssertEqual(rasterLayer.maskProperties?.linked, false)
    XCTAssertEqual(try Renderer.composite(document).rgbaData(depth: .u8), moved)
  }

  func testMovedMaximumCanvasExteriorKeepsSparseCoverage() throws {
    let side = Surface.maxDimension
    var document = try cutoutDocument()
    let id = try XCTUnwrap(document.activeLayerID)
    try Command.canvasSize(side, side, .topLeft, nil).apply(to: &document)
    try Command.moveLayers(.init(layerIDs: [id], dx: side - 120, dy: side - 100)).apply(to: &document)
    let output = try Renderer.composite(document)
    XCTAssertEqual(output.pixel(x: 0, y: 0), .black)
    XCTAssertEqual(output.pixel(x: side - 1, y: side - 1), .black)
    XCTAssertEqual(output.pixel(x: side - 80, y: side - 70), .clear)
    XCTAssertLessThan(output.allocatedBytes, 1_000_000)
  }

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
