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
}
