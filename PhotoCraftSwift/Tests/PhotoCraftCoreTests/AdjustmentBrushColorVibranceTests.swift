import XCTest
@testable import PhotoCraftCore

final class AdjustmentBrushColorVibranceTests:XCTestCase {
  func brush()->Brush {
    var b=Brush();b.size=8;b.hardness=1;b.settings = .init();b.settings!.pressureSize=false;return b
  }
  func testObservedPickerOrderInitialValuesAndLegacyDecoding()throws {
    XCTAssertEqual(AdjustmentBrushKind.nativeKinds.map(\.title),["Color and vibrance","Brightness/Contrast","Levels","Curves","Exposure","Hue/Saturation","Color Balance","Black & White","Photo Filter","Channel Mixer","Color Lookup","Selective Color","Invert","Posterize","Threshold","Gradient Map"])
    XCTAssertEqual(AdjustmentBrushKind.allCases.count,17)
    guard case .modern(let value)=AdjustmentBrushKind.colorVibrance.initial else{return XCTFail()}
    XCTAssertEqual(value.values,["temperature":0,"tint":0,"vibrance":100,"saturation":0])
    XCTAssertTrue(ModernAdjustment(.colorVibrance).isIdentity)
    XCTAssertEqual(AdjustmentBrushKind(adjustment:.modern(value)),.colorVibrance)
    XCTAssertEqual(try JSONDecoder().decode(AdjustmentBrushKind.self,from:Data("\"vibrance\"".utf8)),.vibrance)
    XCTAssertEqual(AdjustmentBrushKind(adjustment:AdjustmentBrushKind.vibrance.initial),.vibrance)
    for kind in [ModernAdjustment.Kind.light,.clarityDehaze,.grain] {
      XCTAssertNil(AdjustmentBrushKind(adjustment:.modern(.init(kind))))
    }
  }
  func testPaintSubtractRetainsFullSettingsSelectionMaskAndOneUndoAcrossDepths()throws {
    for depth in PixelDepth.allCases {
      var source=try CraftDocument(width:32,height:24,depth:depth)
      source.layers[0].content = .raster(try Surface(width:32,height:24,depth:depth,fill:Pixel(0.4,0.3,0.2)))
      source.selection = .init(x:10,y:0,width:8,height:24)
      var value=ModernAdjustment(.colorVibrance);value.values=["temperature":17,"tint":-23,"vibrance":31,"saturation":-19];value.seed=91
      var request=AdjustmentBrushRequest(adjustment:.modern(value),points:[.init(x:8,y:12),.init(x:14,y:12)],brush:brush())
      var session=EditorSession(document:source);try session.execute(.adjustmentBrush(request));let painted=session.document
      XCTAssertEqual(painted.layers[0],source.layers[0]);XCTAssertEqual(painted.layers[1].name,"Color and vibrance")
      XCTAssertEqual(painted.layers[1].content,.adjustment(.modern(value)))
      XCTAssertEqual(painted.layers[1].mask?.pixel(x:8,y:12).r,0);XCTAssertEqual(painted.layers[1].mask?.pixel(x:14,y:12).r,1)
      XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertEqual(session.document,source);try session.redo();XCTAssertEqual(session.document,painted)
      request.layerID=request.newLayerID;request.subtract=true;try session.execute(.adjustmentBrush(request))
      XCTAssertEqual(session.document.layers[1].mask?.pixel(x:14,y:12).r,0)
      XCTAssertEqual(session.document.layers[1].content,.adjustment(.modern(value)))
      XCTAssertEqual(painted.minimumArchiveVersion,65)
      XCTAssertEqual(try NativeArchive.decodePaged(NativeArchive.encodeChunked(painted)),painted)
    }
  }
  func testObjectMasksLocksMalformedControlsAndUnlistedTypesAreAtomic()throws {
    let source=try CraftDocument(width:32,height:24)
    var d=source,request=AdjustmentBrushRequest(adjustment:AdjustmentBrushKind.colorVibrance.initial,points:[],brush:brush())
    request.objectMask=try .make(.rectangle(.init(x:4,y:0,width:8,height:24)),width:32,height:24,antiAlias:false)
    try request.apply(to:&d);XCTAssertEqual(d.layers.last?.mask?.pixel(x:6,y:12).r,1);XCTAssertEqual(d.layers.last?.mask?.pixel(x:20,y:12).r,0)
    request.layerID=request.newLayerID;d.layers[1].locked=true;let locked=d
    XCTAssertThrowsError(try request.apply(to:&d));XCTAssertEqual(d,locked)
    for kind in [ModernAdjustment.Kind.light,.clarityDehaze,.grain] {
      d=source;request.layerID=nil;request.adjustment = .modern(.init(kind))
      XCTAssertThrowsError(try request.apply(to:&d));XCTAssertEqual(d,source)
    }
    d=source;var invalid=ModernAdjustment(.colorVibrance);invalid.values["tint"] = .nan;request.adjustment = .modern(invalid)
    XCTAssertThrowsError(try request.apply(to:&d));XCTAssertEqual(d,source)
  }
}
