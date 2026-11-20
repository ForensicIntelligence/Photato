import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDShapeInterchangeTests: XCTestCase {
  private var fixtures: URL {
    URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PSDShapesInterop")
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
