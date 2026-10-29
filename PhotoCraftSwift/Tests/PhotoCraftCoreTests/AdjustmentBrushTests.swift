import XCTest
@testable import PhotoCraftCore

final class AdjustmentBrushTests:XCTestCase {
  func request()->AdjustmentBrushRequest {
    var brush=Brush();brush.size=8;brush.hardness=1;brush.color=Pixel(1,0,0);brush.settings = .init();brush.settings!.pressureSize=false
    return .init(adjustment:.exposure(1),points:[.init(x:12,y:12)],brush:brush)
  }
  func testEditableNewLayerAndOneUndoAcrossDepths()throws {
    for depth in [PixelDepth.u8,.u16,.f32] {
      let d=try CraftDocument(width:32,height:24,depth:depth),r=request();var session=EditorSession(document:d)
      try session.execute(.adjustmentBrush(r));let result=session.document
      XCTAssertEqual(result.layers.count,2);XCTAssertEqual(result.layers[0],d.layers[0]);XCTAssertEqual(result.activeLayerID,r.newLayerID)
      XCTAssertEqual(result.layers[1].mask!.pixel(x:12,y:12).r,1);XCTAssertEqual(result.layers[1].mask!.pixel(x:0,y:0).r,0)
      XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertTrue(session.document==d);try session.redo();XCTAssertTrue(session.document==result)
    }
  }
  func testAddSubtractSelectionAndAdjustmentReplacement()throws {
    var d=try CraftDocument(width:32,height:24);d.selection = .init(x:10,y:0,width:10,height:24)
    var r=request();try r.apply(to:&d);r.layerID=r.newLayerID;r.adjustment = .invert;r.subtract=true;try r.apply(to:&d)
    XCTAssertEqual(d.layers.last!.mask!.pixel(x:12,y:12).r,0);XCTAssertEqual(d.layers.last!.content,.adjustment(.invert))
    r.subtract=false;r.points=[.init(x:8,y:12)];try r.apply(to:&d)
    XCTAssertEqual(d.layers.last!.mask!.pixel(x:8,y:12).r,0);XCTAssertGreaterThan(d.layers.last!.mask!.pixel(x:10,y:12).r,0)
  }
  func testObjectMaskPreservesSelectionTransformsAndInversion()throws {
    var d=try CraftDocument(width:32,height:24),r=request();r.points=[]
    r.objectMask=try SelectionMask(width:32,height:24,bytes:(0..<768).map{$0%32<16 ? 255:0});try r.apply(to:&d)
    XCTAssertEqual(d.layers.last!.mask!.pixel(x:8,y:12).r,1);XCTAssertEqual(d.layers.last!.mask!.pixel(x:20,y:12).r,0)
    r.layerID=r.newLayerID;r.objectMask=nil;r.points=[.init(x:12,y:12)]
    d.layers[1].x=4;d.layers[1].maskProperties = .init();d.layers[1].maskProperties!.inverted=true
    try r.apply(to:&d);XCTAssertEqual(d.layers[1].mask!.pixel(x:8,y:12).r,0)
    let result=d;d.layers[1].locked=true;let locked=d;XCTAssertThrowsError(try r.apply(to:&d));XCTAssertTrue(d==locked)
    d=result;d.layers[1].maskProperties!.enabled=false;let disabled=d;XCTAssertThrowsError(try r.apply(to:&d));XCTAssertTrue(d==disabled)
  }
  func testInvalidAndEmptyInputNeverMutatesDocument()throws {
    var d=try CraftDocument(width:32,height:24);let original=d;var r=request();r.points=[];try r.apply(to:&d);XCTAssertTrue(d==original)
    r=request();r.subtract=true;XCTAssertThrowsError(try r.apply(to:&d));XCTAssertTrue(d==original)
    r=request();r.adjustment = .exposure(.nan);XCTAssertThrowsError(try r.apply(to:&d));XCTAssertTrue(d==original)
    r=request();r.layerID=UUID();XCTAssertThrowsError(try r.apply(to:&d));XCTAssertTrue(d==original)
    for kind in AdjustmentBrushKind.allCases {try kind.initial.validate();XCTAssertEqual(AdjustmentBrushKind(adjustment:kind.initial),kind)}
  }
}
