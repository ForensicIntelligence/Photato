import XCTest
@testable import PhotoCraftCore

final class RecordedGradientTests:XCTestCase {
  func gradient()->GradientDefinition {
    .init(colors:[.init(0,.rgb(Pixel(0.2,0.4,0.8))),.init(1,.rgb(Pixel(0.9,0.3,0.1)))],opacity:[.init(0,1),.init(1,0.2)],method:.classic)
  }
  func testFreshFillRecipeReplaysParentControlsAndSelectionWithoutDocumentUUIDs()throws {
    var d=try CraftDocument(width:20,height:16);let group=Layer(name:"Folder",content:.group(.init()))
    d.layers.append(group);d.activeLayerID=group.id;d.selection = .init(x:2,y:3,width:13,height:10)
    var layer=Layer(name:"Owned",content:.gradientFill(.init(gradient:gradient(),aligned:false,dither:false)))
    layer.parentID=group.id;layer.opacity=0.65;layer.blendMode = .screen
    let op=ActionOperation(recording:.addGradientFill(layer,true),in:d);XCTAssertNil(op.unsupportedReason)
    let bytes=try JSONEncoder().encode(op),decoded=try JSONDecoder().decode(ActionOperation.self,from:bytes)
    XCTAssertFalse(String(decoding:bytes,as:UTF8.self).contains(layer.id.uuidString))
    XCTAssertFalse(String(decoding:bytes,as:UTF8.self).contains(group.id.uuidString))
    var actual=d;try XCTUnwrap(decoded.command(in:actual)).apply(to:&actual)
    var expected=d;try Command.addGradientFill(layer,true).apply(to:&expected)
    let a=try XCTUnwrap(actual.layers.first{$0.id != d.layers[0].id && $0.id != group.id})
    let b=try XCTUnwrap(expected.layers.first{$0.id==layer.id})
    XCTAssertEqual(a.name,b.name);XCTAssertEqual(a.content,b.content);XCTAssertEqual(a.opacity,b.opacity)
    XCTAssertEqual(a.blendMode,b.blendMode);XCTAssertEqual(a.parentID,b.parentID);XCTAssertEqual(a.mask,b.mask);XCTAssertEqual(a.maskProperties,b.maskProperties)
    var locked=d;locked.layers[1].locked=true;XCTAssertThrowsError(try decoded.command(in:locked))
  }
  func testPaintRecipeRetainsEveryFieldAndExactPixelsAcrossDepthShapeAndMask()throws {
    for depth in PixelDepth.allCases {for style in GradientStyle.allCases {for mask in [false,true] {
      var d=try CraftDocument(width:20,height:16,depth:depth);d.selection = .init(x:2,y:2,width:16,height:12)
      if mask{d.layers[0].mask=try Surface(width:d.width,height:d.height,depth:depth,fill:.white)}
      var stroke=GradientStroke(gradient:gradient(),start:.init(2,3),end:.init(18,13))
      stroke.style=style;stroke.reverse=true;stroke.dither=false;stroke.transparency=false;stroke.opacity=0.7;stroke.mode = .multiply;stroke.mask=mask
      let op=ActionOperation(recording:.paintGradient(d.layers[0].id,stroke),in:d);XCTAssertNil(op.unsupportedReason)
      let decoded=try JSONDecoder().decode(ActionOperation.self,from:JSONEncoder().encode(op))
      var actual=d,expected=d;try XCTUnwrap(decoded.command(in:actual)).apply(to:&actual)
      try Command.paintGradient(d.layers[0].id,stroke).apply(to:&expected)
      XCTAssertEqual(actual,expected,"\(depth)/\(style)/\(mask)")
    }}}
  }
  func testMalformedRecipesRejectAndCustomCreationMetadataIsNotSilentlyDiscarded()throws {
    let d=try CraftDocument(width:20,height:16)
    var layer=Layer(name:"Owned",content:.gradientFill(.init(gradient:gradient())))
    layer.x=3;let unsupported=ActionOperation(recording:.addGradientFill(layer,false),in:d)
    XCTAssertNotNil(unsupported.unsupportedReason)
    layer.x=0;var fill=try XCTUnwrap(RecordedGradientFill(layer:layer,maskFromSelection:false,in:d))
    fill.opacity = .nan;XCTAssertThrowsError(try fill.validate());fill.opacity=1
    fill.parent = .named("",occurrence:-1);XCTAssertThrowsError(try fill.validate());fill.parent=nil
    fill.fill.gradient.colors=[];XCTAssertThrowsError(try fill.validate())
    let stroke=GradientStroke(gradient:gradient(),start:.init(0,0),end:.init(10,10))
    var recorded=RecordedGradientStroke(layerID:d.layers[0].id,stroke:stroke,in:d)
    recorded.end.x = .infinity;XCTAssertThrowsError(try recorded.validate());recorded.end.x=10
    recorded.opacity = -1;XCTAssertThrowsError(try recorded.validate())
  }
}
