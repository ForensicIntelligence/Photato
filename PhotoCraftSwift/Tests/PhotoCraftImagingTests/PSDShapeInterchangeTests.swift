import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDShapeInterchangeTests: XCTestCase {
  private var fixtures: URL {
    URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PSDShapesInterop")
  }

  func testRGB8NormalShapeOpacityMatchesAuthoredCompositeSamples() throws {
    let samples: [([(Pixel, UInt8)], [UInt8])] = [
      // psd-tools fixture stroke.psd, Rectangle 1 at (45,44).
      ([(Pixel.white, 255), (Pixel(29 / 255, 32 / 255, 136 / 255, 120 / 255), 194)],
       [174, 175, 213, 255]),
      // blend-modes/normal.psd at the interior (26,17) and edge (19,19).
      ([(Pixel(0, 0, 1), 128), (Pixel(0, 1, 0), 128), (Pixel(1, 0, 0), 128)],
       [159, 95, 63, 224]),
      ([(Pixel(0, 0, 1), 128), (Pixel(0, 1, 0), 128), (Pixel(1, 0, 0, 117 / 255), 128)],
       [107, 146, 98, 207]),
    ]
    for (layers, expected) in samples {
      var document = try CraftDocument(width: 1, height: 1)
      document.layers = try layers.enumerated().map { index, item in
        let (pixel, opacity) = item
        let cache = try Surface(width: 1, height: 1, fill: pixel)
        let definition = ShapeDefinition(geometry: .init(width: 1, height: 1))
        var shape = try ShapeContent(definition: definition)
        shape.width = 1
        shape.height = 1
        shape.importedAppearance = .init(definition: definition, pixels: cache)
        var layer = Layer(name: "Sample \(index)", content: .shape(shape))
        layer.opacity = Float(opacity) / 255
        return layer
      }
      document.activeLayerID = document.layers.last?.id
      let composed = try Renderer.composite(document)
      let sample = PSDMergedSample.encode(composed.pixel(x: 0, y: 0), depth: 8)
      let bytes = [sample.r, sample.g, sample.b, sample.a].map { UInt8(($0 * 255).rounded()) }
      XCTAssertEqual(bytes, expected)
      XCTAssertEqual(composed.pixel(x: 0, y: 0).a, Float(expected[3]) / 255)
      let region = try Renderer.composite(document, region: .init(x: 0, y: 0, width: 1, height: 1))
      XCTAssertEqual(region, composed)
    }
  }

  func testLegacyLinkedPatternUsesReferencePointAndRoundsUnscaledPaint() throws {
    var tile = try Surface(width: 5, height: 3)
    for y in 0..<tile.height {
      for x in 0..<tile.width { tile.setPixel(x: x, y: y, Pixel(Float(x) / 4, Float(y) / 2, 0)) }
    }
    let resource = try RasterPattern(name: "Owned phase tile", surface: tile, id: "legacy-phase-owned")
    var document = try CraftDocument(width: 40, height: 38)
    document.patterns = [resource]
    document.layers[0].content = .raster(try Surface(width: 40, height: 38))
    var placement = PatternPlacement()
    placement.phaseX = 1.5
    placement.phaseY = 2.25
    let paint = PatternFill(patternID: resource.id, placement: placement)
    let generator = try PSDPatternFill.write(paint, pattern: resource)
    let geometry = ShapeGeometry(width: 16, height: 16)
    let path = try geometry.path().transformed(.translation(10, 8))
    let vector = try PSDPaths.writeMask(VectorMask(path: path), width: 40, height: 38)
    let reference = [7.0, 11.0].reduce(into: Data()) { bytes, value in
      var bits = value.bitPattern.bigEndian
      withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) }
    }
    let tags = ["PtFl": generator, "vmsk": vector, "sn2P": Data([0, 0, 0, 1]), "fxrp": reference]
    let blank = try Surface(width: 18, height: 18)
    let recovered = try PSDLiveShape.read(tags, x: 9, y: 7, cache: blank, document: document)
    var layer = Layer(name: "Legacy pattern", content: .shape(recovered))
    layer.x = 9
    layer.y = 7
    layer.sourceTags = tags
    document.layers.append(layer)
    document.activeLayerID = layer.id
    XCTAssertEqual(recovered.editableDefinition.fill.pattern?.placement.phaseX, -0.5)
    XCTAssertEqual(recovered.editableDefinition.fill.pattern?.placement.phaseY, 6.25)
    var definition = recovered.editableDefinition
    definition.fill.pattern?.placement.phaseX += 5
    try Command.shape(.configure(layer.id, definition)).apply(to: &document)
    let composite = try Renderer.composite(document)
    // Phase (13.5, 13.25) snaps to (14, 13) at 100%, while the stored
    // linked phase keeps the original fractional value for later edits.
    XCTAssertEqual(composite.pixel(x: 16, y: 16), tile.pixel(x: 2, y: 0))
    for format in [PSDFileFormat.psd, .psb] {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
      let actual = try XCTUnwrap(reopened.layers.first { $0.name == layer.name })
      XCTAssertNotNil(actual.shape)
      XCTAssertNil(actual.vectorMask)
      XCTAssertEqual(actual.sourceTags?["fxrp"], reference)
      XCTAssertNil(actual.sourceTags?["vscg"])
      let saved = try PSDPatternFill.read(XCTUnwrap(actual.sourceTags?["PtFl"])).fill
      XCTAssertEqual(saved.placement.phaseX, 6.5)
      XCTAssertEqual(saved.placement.phaseY, 2.25)
      XCTAssertEqual(try Renderer.composite(reopened), composite)
    }
  }

  func testPatternedShapePhaseAndCacheFollowTheirLinkSetting() throws {
    var tile = try Surface(width: 5, height: 2)
    for y in 0..<tile.height {
      for x in 0..<tile.width { tile.setPixel(x: x, y: y, Pixel(Float(x) / 4, Float(y), 0)) }
    }
    let pattern = try RasterPattern(name: "Owned grid", surface: tile, id: "owned-shape-grid")
    var source = try CraftDocument(width: 92, height: 56)
    source.layers[0].content = .raster(try Surface(width: 92, height: 56))
    for (name, linked, x) in [("Linked", true, 8), ("Anchored", false, 45)] {
      var fill = ShapePaint()
      fill.kind = .pattern
      fill.pattern = .init(patternID: pattern.id, linked: linked)
      var stroke = ShapeStroke()
      stroke.width = 2
      stroke.alignment = .inside
      stroke.paint = fill
      let definition = ShapeDefinition(geometry: .init(width: 22, height: 18), fill: fill, stroke: stroke)
      try Command.shape(.create(name, definition, .translation(Double(x), 12), patterns: [pattern])).apply(to: &source)
    }
    XCTAssertEqual(source.patterns?.count, 1)
    for format in [PSDFileFormat.psd, .psb] {
      let imported = try PSDCodec.read(PSDCodec.writeRasterLayers(source, format: format))
      XCTAssertEqual(imported.pattern(pattern.id)?.surface, tile)
      var session = EditorSession(document: try NativeArchive.decode(NativeArchive.encode(imported)))
      let initial = session.document
      let original = try Renderer.composite(initial)
      XCTAssertEqual(original, try Renderer.composite(source))
      let linked = try XCTUnwrap(initial.layers.first { $0.name == "Linked" })
      let anchored = try XCTUnwrap(initial.layers.first { $0.name == "Anchored" })
      for layer in [linked, anchored] {
        let raw = try XCTUnwrap(layer.sourceTags?["vscg"])
        XCTAssertEqual(String(decoding: raw.prefix(4), as: UTF8.self), "PtFl")
        let fill = try PSDPatternFill.read(Data(raw.dropFirst(4))).fill
        XCTAssertEqual(fill.patternID, pattern.id)
        XCTAssertEqual(fill.placement.phaseX, layer.id == linked.id ? 8 : 0)
        XCTAssertEqual(fill.placement.phaseY, layer.id == linked.id ? 12 : 0)
        let stroke = try PSDDescriptor.read(XCTUnwrap(layer.sourceTags?["vstk"]), padding: true)
        guard case .object(let paint)? = stroke["strokeStyleContent"] else {
          return XCTFail("Missing editable pattern stroke")
        }
        XCTAssertEqual(paint.classID.text, "patternLayer")
        XCTAssertEqual(try PSDPatternFill.read(paint.encoded()).fill, fill)
      }
      XCTAssertNil(linked.shape?.importedAppearance?.documentPatternPlacement)
      XCTAssertEqual(anchored.shape?.importedAppearance?.documentPatternPlacement, anchored.coordinateTransform)
      try session.execute(.moveLayers(.init(layerIDs: [linked.id, anchored.id], dx: 7, dy: 0)))
      let moved = try Renderer.composite(session.document)
      XCTAssertEqual(moved.pixel(x: 20, y: 19), original.pixel(x: 13, y: 19))
      XCTAssertEqual(moved.pixel(x: 59, y: 19), original.pixel(x: 59, y: 19))
      XCTAssertNotEqual(moved.pixel(x: 59, y: 19), original.pixel(x: 52, y: 19))
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
      XCTAssertEqual(try Renderer.composite(reopened), moved)
      let movedLinked = try XCTUnwrap(reopened.layers.first { $0.name == "Linked" })
      let movedTag = try XCTUnwrap(movedLinked.sourceTags?["vscg"])
      XCTAssertEqual(try PSDPatternFill.read(Data(movedTag.dropFirst(4))).fill.placement.phaseX, 15)
      try session.undo()
      XCTAssertEqual(session.document, initial)
    }
  }

  func testArrowlessLiveLineRetainsEndpointsAndPatternPaintAfterEditing() throws {
    let tile = try Surface(width: 2, height: 2, fill: Pixel(0, 0.5, 1))
    let pattern = try RasterPattern(name: "Blue", surface: tile, id: "owned-line-tile")
    var source = try CraftDocument(width: 118, height: 82)
    var geometry = ShapeGeometry(kind: .line, width: 30, height: 0)
    geometry.lineWeight = 5
    var paint = ShapePaint()
    paint.kind = .pattern
    paint.pattern = .init(patternID: pattern.id)
    var definition = ShapeDefinition(geometry: geometry, fill: paint)
    definition.components[0].transform = .rotation(-30)
    try Command.shape(.create("Owned line", definition, .translation(25.25, 40.5), patterns: [pattern])).apply(to: &source)
    for format in [PSDFileFormat.psd, .psb] {
      let imported = try PSDCodec.read(PSDCodec.writeRasterLayers(source, format: format))
      let layer = try XCTUnwrap(imported.layers.first { $0.name == "Owned line" })
      let primitive = try XCTUnwrap(layer.shape?.editableDefinition.components.first)
      XCTAssertEqual(primitive.geometry.kind, .line)
      XCTAssertEqual(primitive.geometry.width, 30, accuracy: 1e-10)
      XCTAssertEqual(primitive.geometry.height, 0)
      XCTAssertEqual(primitive.geometry.lineWeight, 5)
      let origin = try XCTUnwrap(layer.sourceTags?["vogk"])
      let descriptor = try PSDDescriptor.read(Data(origin.dropFirst(4)), padding: true)
      guard case .list(let list)? = descriptor["keyDescriptorList"],
        case .object(let line)? = list.first,
        case .object(let start)? = line["keyOriginLineStart"],
        case .object(let end)? = line["keyOriginLineEnd"] else { return XCTFail("Missing live line endpoints") }
      XCTAssertEqual(start["Hrzn"]?.number, 25.25)
      XCTAssertEqual(start["Vrtc"]?.number, 40.5)
      XCTAssertEqual(end["Vrtc"]?.number ?? .nan, 25.5, accuracy: 1e-10)
      var session = EditorSession(document: imported)
      var altered = try XCTUnwrap(layer.shape?.editableDefinition)
      altered.components[0].geometry.lineWeight = 8
      altered.fill.pattern?.placement.scale = 85
      try session.execute(.shape(.configure(layer.id, altered)))
      let copy = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
      let edited = try XCTUnwrap(copy.layers.first { $0.name == layer.name }?.shape?.editableDefinition)
      XCTAssertEqual(edited.components.first?.geometry.kind, .line)
      XCTAssertEqual(edited.components.first?.geometry.lineWeight, 8)
      XCTAssertEqual(edited.fill.pattern?.placement.scale, 85)
      XCTAssertEqual(edited.fill.pattern?.patternID, pattern.id)
      XCTAssertNotEqual(try Renderer.composite(imported), try Renderer.composite(copy))
      try session.undo()
      XCTAssertEqual(session.document, imported)
    }
  }

  func testShapeGradientFillAndStrokeStayEditableInPSDAndPSB() throws {
    var fillPlacement = GradientPlacement()
    fillPlacement.style = .reflected
    fillPlacement.angle = 30
    fillPlacement.scale = 1.5
    fillPlacement.reverse = true
    fillPlacement.offsetX = 0.125
    fillPlacement.offsetY = -0.25
    var fill = ShapePaint()
    fill.kind = .gradient
    fill.gradient = .init(
      gradient: .init(name: "Fill", colors: [.init(0, .rgb(.black)), .init(1, .rgb(.white))],
                      opacity: [.init(0, 1), .init(1, 0.25)], method: .classic),
      placement: fillPlacement, dither: false)
    var strokePlacement = GradientPlacement()
    strokePlacement.angle = 75
    strokePlacement.scale = 0.75
    var stroke = ShapeStroke()
    stroke.paint.kind = .gradient
    stroke.paint.gradient = .init(
      gradient: .init(name: "Stroke", colors: [.init(0, .rgb(Pixel(1, 0, 0))), .init(1, .rgb(Pixel(0, 0, 1)))],
                      opacity: [.init(0, 0.25), .init(1, 1)], method: .linear),
      placement: strokePlacement, aligned: false, dither: false)
    stroke.width = 5
    stroke.alignment = .inside
    stroke.opacity = 0.75
    stroke.cap = .round
    var definition = ShapeDefinition(geometry: .init(width: 40, height: 28), fill: fill, stroke: stroke)
    definition.paintFrame = try definition.controlPaintFrame()

    for depth in [PixelDepth.u8, .u16] {
      var source = try CraftDocument(width: 76, height: 62, depth: depth)
      source.layers[0].content = .raster(try Surface(width: 76, height: 62, depth: depth))
      try Command.shape(.create("Painted shape", definition, .translation(12, 14))).apply(to: &source)
      let originalPixels = try Renderer.composite(source)
      for format in [PSDFileFormat.psd, .psb] {
        let imported = try PSDCodec.read(PSDCodec.writeRasterLayers(source, compression: .raw, format: format))
        let layer = try XCTUnwrap(imported.layers.first { $0.name == "Painted shape" })
        let shape = try XCTUnwrap(layer.shape)
        let fillTag = try XCTUnwrap(layer.sourceTags?["vscg"])
        let strokeTag = try XCTUnwrap(layer.sourceTags?["vstk"])
        XCTAssertEqual(String(decoding: fillTag.prefix(4), as: UTF8.self), "GdFl")
        guard case .object(let paint)? = try PSDDescriptor.read(strokeTag, padding: true)["strokeStyleContent"] else {
          return XCTFail("Missing editable stroke paint descriptor")
        }
        XCTAssertEqual(paint.classID.text, "gradientLayer")
        XCTAssertEqual(shape.editableDefinition.fill, fill)
        XCTAssertEqual(shape.editableDefinition.stroke, stroke)
        XCTAssertEqual(shape.editableDefinition.components.first?.geometry.width, 40)
        XCTAssertNotNil(shape.importedAppearance?.pixels)
        XCTAssertNil(layer.vectorMask)
        let importedPixels = try Renderer.composite(imported)
        for (x, y) in [(13, 20), (20, 24), (40, 29), (48, 37)] {
          let actual = importedPixels.pixel(x: x, y: y)
          let expected = originalPixels.pixel(x: x, y: y)
          let precision: Float = depth == .u8 ? 0 : 2.0 / 65_535
          XCTAssertEqual(actual.r, expected.r, accuracy: precision)
          XCTAssertEqual(actual.g, expected.g, accuracy: precision)
          XCTAssertEqual(actual.b, expected.b, accuracy: precision)
          XCTAssertEqual(actual.a, expected.a, accuracy: precision)
        }

        let native = try NativeArchive.decode(NativeArchive.encode(imported))
        let unchanged = try PSDCodec.read(PSDCodec.writeRasterLayers(native, format: format))
        let unchangedLayer = try XCTUnwrap(unchanged.layers.first { $0.name == layer.name })
        for key in ["vscg", "vstk", "vsms", "vogk"] {
          XCTAssertEqual(unchangedLayer.sourceTags?[key], layer.sourceTags?[key], key)
        }
        XCTAssertEqual(try Renderer.composite(unchanged), importedPixels)
        XCTAssertEqual(try Renderer.composite(native), importedPixels)

        var edited = shape.editableDefinition
        edited.fill.gradient?.placement.angle = 75
        edited.stroke.paint.gradient?.placement.reverse = true
        var session = EditorSession(document: imported)
        try session.execute(.shape(.configure(layer.id, edited)))
        XCTAssertNil(session.document.layers.first { $0.id == layer.id }?.shape?.importedAppearance)
        XCTAssertNotEqual(try Renderer.composite(session.document), importedPixels)
        let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
        let revised = try XCTUnwrap(reopened.layers.first { $0.name == layer.name }?.shape?.editableDefinition)
        XCTAssertEqual(revised.fill, edited.fill)
        XCTAssertEqual(revised.stroke, edited.stroke)
        try session.undo()
        XCTAssertEqual(session.document, imported)
      }
    }
  }

  func testInvalidatedGradientShapeOriginUsesEditableOutline() throws {
    var source = try CraftDocument(width: 128, height: 96)
    source.layers[0].content = .raster(try Surface(width: 128, height: 96))
    var fill = ShapePaint()
    fill.kind = .gradient
    fill.gradient = .init(dither: false)
    let definition = ShapeDefinition(geometry: .init(width: 50, height: 28), fill: fill)
    try Command.shape(.create("Path", definition, .translation(12, 14))).apply(to: &source)
    let imported = try PSDCodec.read(PSDCodec.writeRasterLayers(source))
    let original = try XCTUnwrap(imported.layers.first { $0.name == "Path" })
    let cache = try XCTUnwrap(original.shape?.importedAppearance?.pixels)
    var tags = try XCTUnwrap(original.sourceTags)
    let invalidated = PSDDescriptor("null", items: [
      .init("keyShapeInvalidated", .boolean(true)), .init("keyOriginIndex", .integer(0)),
    ])
    let list = PSDDescriptor("null", items: [.init("keyDescriptorList", .list([.object(invalidated)]))])
    tags["vogk"] = try Data([0, 0, 0, 1]) + list.encoded()
    let shape = try PSDLiveShape.read(tags, x: original.x, y: original.y, cache: cache, document: imported)
    var layer = original
    layer.content = .shape(shape)
    layer.sourceTags = tags
    XCTAssertEqual(shape.editableDefinition.components.first?.geometry.kind, .custom)
    XCTAssertEqual(try layer.shapePath(), try original.shapePath())
    XCTAssertEqual(shape.importedAppearance?.pixels, cache)
    XCTAssertEqual(Dictionary(uniqueKeysWithValues: try PSDLiveShape.write(layer, document: imported))["vogk"],
      tags["vogk"])
  }

  func testOwnedPhotoshopLiveRectangleAndStrokeRemainEditableWithOriginalMetadata() throws {
    for width in [0,1] {
      let data=try Data(contentsOf:fixtures.appendingPathComponent("photoshop-rectangle-stroke\(width).psd"))
      let document=try PSDCodec.read(data)
      let layer=try XCTUnwrap(document.layers.first(where:{$0.name=="Rectangle 1"}))
      let shape=try XCTUnwrap(layer.shape)
      let definition=shape.editableDefinition
      XCTAssertEqual(definition.components.count,1)
      XCTAssertEqual(definition.components[0].geometry.kind,.rectangle)
      XCTAssertEqual(definition.components[0].geometry.width,64)
      XCTAssertEqual(definition.components[0].geometry.height,40)
      XCTAssertEqual(definition.components[0].geometry.radii,[0,0,0,0])
      XCTAssertEqual(definition.fill.kind,.solid)
      XCTAssertEqual(definition.fill.color,Pixel(0.501953125,0.501953125,0.501953125))
      XCTAssertEqual(definition.stroke.width,Double(width))
      XCTAssertEqual(definition.stroke.paint.kind,.solid)
      XCTAssertEqual(definition.stroke.paint.color,.black)
      XCTAssertEqual(definition.stroke.alignment,.center)
      XCTAssertEqual(definition.stroke.cap,.butt)
      XCTAssertEqual(definition.stroke.join,.miter)
      XCTAssertEqual(definition.stroke.miterLimit,100)
      for tag in ["vscg","vstk","vogk","vsms","sn2P","vowv"] {
        XCTAssertNotNil(layer.sourceTags?[tag],tag)
      }
      let path=try XCTUnwrap(layer.shapePath())
      XCTAssertEqual(path.components.first?.knots.map(\.anchor),[
        PathPoint(16,16.000001907348633),PathPoint(80,16.000001907348633),
        PathPoint(80,55.99999809265137),PathPoint(16,55.99999809265137)])
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)),document)
      for format in [PSDFileFormat.psd, .psb] {
        let copy = try PSDCodec.read(PSDCodec.writeRasterLayers(document, format: format))
        let reopened = try XCTUnwrap(copy.layers.first { $0.name == layer.name })
        XCTAssertEqual(try reopened.shapePath(), path)
        XCTAssertEqual(try Renderer.layerSurface(reopened, in: copy), try Renderer.layerSurface(layer, in: document))
        for key in ["vscg", "vstk", "vogk", "vsms", "sn2P", "vowv"] {
          XCTAssertEqual(reopened.sourceTags?[key], layer.sourceTags?[key], key)
        }
      }
      var session=EditorSession(document:document)
      var changed=definition;changed.stroke.width=Double(width)+2
      try session.execute(.shape(.configure(layer.id,changed)))
      XCTAssertNotEqual(session.document,document)
      try session.undo();XCTAssertEqual(session.document,document)
      try session.redo();XCTAssertEqual(session.document.layers.first(where:{$0.id==layer.id})?.shape?.editableDefinition,changed)
    }
  }
  func testNativeLiveRectangleExportsAsEditableShapeInPSDAndPSB() throws {
    var source=try CraftDocument(width:128,height:96)
    source.layers[0].content = .raster(try Surface(width:128,height:96))
    var definition=ShapeDefinition(geometry:.init(width:64,height:40),
      fill:.init(color:Pixel(0.501953125,0.501953125,0.501953125)))
    definition.stroke.paint = .init(color:.black)
    definition.stroke.width=1;definition.stroke.miterLimit=100
    try Command.shape(.create("Rectangle 1",definition,.translation(16,16),patterns:[])).apply(to:&source)
    let original=source
    for format in [PSDFileFormat.psd,.psb] {
      let data=try PSDCodec.writeRasterLayers(source,format:format)
      let decoded=try PSDCodec.read(data)
      let layer=try XCTUnwrap(decoded.layers.first(where:{$0.name=="Rectangle 1"}))
      let output=try XCTUnwrap(layer.shape?.editableDefinition)
      XCTAssertEqual(output.components[0].geometry.kind,.rectangle)
      XCTAssertEqual(output.components[0].geometry.width,64)
      XCTAssertEqual(output.components[0].geometry.height,40)
      XCTAssertEqual(output.fill,definition.fill)
      XCTAssertEqual(output.stroke.width,1)
      XCTAssertEqual(output.stroke.paint,definition.stroke.paint)
      XCTAssertEqual(output.stroke.miterLimit,100)
      XCTAssertNotNil(layer.sourceTags?["vscg"])
      XCTAssertNotNil(layer.sourceTags?["vstk"])
      XCTAssertNotNil(layer.sourceTags?["vogk"])
      XCTAssertEqual(source,original)
    }
  }

  func testRoundedRectanglesAndDottedEllipsesRetainEditableGeometry() throws {
    var rounded = ShapeGeometry(width: 40, height: 26)
    rounded.radii = [2, 7, 4, 0]
    var maximumRadius = ShapeGeometry(width: 12, height: 12)
    maximumRadius.radii = [6, 6, 6, 6]
    var dotted = ShapeStroke()
    dotted.paint = .init(color: Pixel(0, 0.5, 0.25))
    dotted.width = 2.5
    dotted.alignment = .inside
    dotted.cap = .round
    dotted.dash = [0, 2]
    dotted.widthRelativeDashes = true
    let definitions: [(String, ShapeDefinition, Transform2D)] = [
      ("Independent corners", .init(geometry: rounded), .translation(4.25, 8.5)),
      ("Maximum corners", .init(geometry: maximumRadius), .translation(60, 4)),
      ("Dotted ellipse", .init(geometry: .init(kind: .ellipse, width: 65, height: 37), fill: .none,
        stroke: dotted), .translation(24, 45))
    ]
    for depth in [PixelDepth.u8, .u16] {
      var source = try CraftDocument(width: 128, height: 96, depth: depth)
      source.layers[0].content = .raster(try Surface(width: 128, height: 96, depth: depth))
      for (name, definition, transform) in definitions {
        try Command.shape(.create(name, definition, transform, patterns: [])).apply(to: &source)
      }
      for format in [PSDFileFormat.psd, .psb] {
        let decoded = try PSDCodec.read(PSDCodec.writeRasterLayers(source, format: format))
        XCTAssertEqual(decoded.depth, depth)
        for (name, definition, _) in definitions {
          let layer = try XCTUnwrap(decoded.layers.first { $0.name == name })
          let editable = try XCTUnwrap(layer.shape?.editableDefinition)
          XCTAssertEqual(editable.components.first?.geometry, definition.components.first?.geometry, name)
          XCTAssertEqual(editable.fill, definition.fill, name)
          XCTAssertEqual(editable.stroke, definition.stroke, name)
          let originalLayer = try XCTUnwrap(source.layers.first { $0.name == name })
          let path = try XCTUnwrap(layer.shapePath())
          let originalPath = try XCTUnwrap(originalLayer.shapePath())
          let knots = try XCTUnwrap(path.components.first?.knots)
          let originalKnots = try XCTUnwrap(originalPath.components.first?.knots)
          XCTAssertEqual(knots.count, originalKnots.count, name)
          for (actual, expected) in zip(knots, originalKnots) {
            for (a, b) in zip([actual.anchor, actual.incoming, actual.outgoing],
                              [expected.anchor, expected.incoming, expected.outgoing]) {
              XCTAssertEqual(a.x, b.x, accuracy: 0.000008, name)
              XCTAssertEqual(a.y, b.y, accuracy: 0.000008, name)
            }
          }
          if originalLayer.affine != nil {
            let surface = try Renderer.layerSurface(originalLayer, in: source)
            let bounds = try originalLayer.coordinateTransform.bounds(width: surface.width, height: surface.height)
            let projected = try RasterGeometry.render(surface, transform: originalLayer.coordinateTransform,
              bounds: bounds, method: .bilinear)
            XCTAssertEqual(layer.x, bounds.x)
            XCTAssertEqual(layer.y, bounds.y)
            XCTAssertEqual(try Renderer.layerSurface(layer, in: decoded), projected)
          }
          XCTAssertNotNil(layer.sourceTags?["vogk"], name)
          XCTAssertNotNil(layer.sourceTags?["vsms"], name)
        }
        let ellipse = try XCTUnwrap(decoded.layers.first { $0.name == "Dotted ellipse" })
        var edited = try XCTUnwrap(ellipse.shape?.editableDefinition)
        edited.components[0].geometry.width = 58.5
        var session = EditorSession(document: decoded)
        try session.execute(.shape(.configure(ellipse.id, edited)))
        let saved = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
        let reopened = try XCTUnwrap(saved.layers.first { $0.name == ellipse.name })
        XCTAssertEqual(reopened.shape?.editableDefinition.components.first?.geometry, edited.components.first?.geometry)
        XCTAssertEqual(reopened.shape?.editableDefinition.stroke, dotted)
        try session.undo()
        XCTAssertEqual(session.document, decoded)
      }
    }
  }

  func testLegacySolidShapeRetainsOriginalPathAndSeparatePixelMask() throws {
    let url = fixtures.deletingLastPathComponent().appendingPathComponent("psdtools-mask-density-layermask.psd")
    let source = try PSDCodec.read(url)
    let shapes = source.layers.filter { $0.shape != nil }
    let expectedDensities: [String: UInt8] = [
      "Rectangle 2 copy": 64, "Rectangle 2": 128, "Rectangle 2 copy 3": 191, "Rectangle 2 copy 2": 255,
    ]
    let legacyTags = ["SoCo", "vmsk", "vogk", "vowv", "sn2P"]
    XCTAssertEqual(Set(shapes.map(\.name)), Set(expectedDensities.keys))
    for layer in shapes {
      XCTAssertNotNil(layer.mask)
      XCTAssertNil(layer.vectorMask)
      XCTAssertEqual(layer.effectiveMaskProperties.density, Float(try XCTUnwrap(expectedDensities[layer.name])) / 255)
      XCTAssertEqual(layer.shape?.editableDefinition.components.first?.geometry.kind, .rectangle)
      XCTAssertEqual(layer.shape?.editableDefinition.stroke.paint.kind, ShapePaint.Kind.none)
    }
    let native = try NativeArchive.decode(NativeArchive.encode(source))
    XCTAssertEqual(native, source)
    for format in [PSDFileFormat.psd, .psb] {
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(native, compression: .raw, format: format))
      for original in shapes {
        let layer = try XCTUnwrap(reopened.layers.first { $0.name == original.name })
        XCTAssertEqual(layer.shape, original.shape)
        XCTAssertEqual(try layer.shapePath(), try original.shapePath())
        XCTAssertEqual(layer.mask, original.mask)
        XCTAssertEqual(layer.maskProperties, original.maskProperties)
        XCTAssertEqual(layer.maskCoordinateTransform, original.maskCoordinateTransform)
        XCTAssertNil(layer.vectorMask)
        for key in legacyTags {
          XCTAssertNotNil(original.sourceTags?[key])
          XCTAssertEqual(layer.sourceTags?[key], original.sourceTags?[key], key)
        }
        XCTAssertNil(layer.sourceTags?["vscg"])
        XCTAssertNil(layer.sourceTags?["vsms"])
      }
      let original = try XCTUnwrap(shapes.first { $0.name == "Rectangle 2" })
      var definition = try XCTUnwrap(original.shape?.editableDefinition)
      definition.components[0].geometry.width = 18.75
      var session = EditorSession(document: source)
      try session.execute(.shape(.configure(original.id, definition)))
      let edited = try PSDCodec.read(PSDCodec.writeRasterLayers(session.document, format: format))
      let layer = try XCTUnwrap(edited.layers.first { $0.name == original.name })
      XCTAssertEqual(layer.shape?.editableDefinition.components[0].geometry.width, 18.75)
      XCTAssertEqual(layer.mask, original.mask)
      XCTAssertEqual(layer.maskCoordinateTransform, original.maskCoordinateTransform)
      XCTAssertNotNil(layer.sourceTags?["vscg"])
      XCTAssertNotNil(layer.sourceTags?["vsms"])
      XCTAssertNil(layer.sourceTags?["SoCo"])
      XCTAssertNil(layer.sourceTags?["vmsk"])
      try session.undo()
      XCTAssertEqual(session.document, source)
    }
  }
}
