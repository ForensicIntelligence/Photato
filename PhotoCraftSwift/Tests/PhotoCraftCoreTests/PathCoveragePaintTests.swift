import XCTest
@testable import PhotoCraftCore

final class PathCoveragePaintTests:XCTestCase {
  func document(_ depth:PixelDepth = .u8)throws->CraftDocument {var d=try CraftDocument(width:4,height:4,depth:depth);d.layers[0].locked=false;d.layers[0].content = .raster(try Surface(width:4,height:4,depth:depth));return d}
  func request(_ d:CraftDocument,mask:SelectionMask,color:Pixel = Pixel(1,0,0),opacity:Float=1,clear:Bool=false)->PixelPaintRequest {
    var settings=PixelPaintSettings(color:color);settings.opacity=opacity
    var r=PixelPaintRequest(.fill,target:.layer(d.layers[0].id),settings:settings);r.pathCoverage=mask;r.pathClear=clear;return r
  }
  func testPathAndCurrentSelectionCoverageMultiplyWithoutReplacingSelection()throws {
    var d=try document();d.setCoverageSelection(try SelectionMask(width:4,height:4,bytes:[64]+Array(repeating:0,count:15)))
    let before=d,path=try SelectionMask(width:4,height:4,bytes:[128,255]+Array(repeating:0,count:14))
    try Command.pixelPaint(request(d,mask:path,opacity:0.5)).apply(to:&d)
    guard case .raster(let pixels)=d.layers[0].content else{return XCTFail("Missing raster")}
    XCTAssertEqual(pixels.pixel(x:0,y:0),Pixel(1,0,0,16.0/255));XCTAssertEqual(pixels.pixel(x:1,y:0),.clear)
    XCTAssertEqual(d.selectionMask,before.selectionMask);XCTAssertEqual(d.selection,before.selection);XCTAssertEqual(d.paths,before.paths)
    var s=EditorSession(document:before);try s.execute(.pixelPaint(request(before,mask:path,opacity:0.5)));XCTAssertEqual(s.document,d);try s.undo();XCTAssertEqual(s.document,before)
  }
  func testClearPreservesStoredRGBWordsAndProtectedAlphaAtAllDepths()throws {
    let mask=try SelectionMask(width:4,height:4,bytes:Array(repeating:255,count:16))
    for depth in PixelDepth.allCases {
      var d=try document(depth);d.layers[0].content = .raster(try Surface(width:4,height:4,depth:depth,fill:Pixel(-0.0,0.1234567,0.75,1),colorEncoding:depth == .f32 ? .linearRGB:.sRGB))
      let before=d
      try Command.pixelPaint(request(d,mask:mask,opacity:0.5,clear:true)).apply(to:&d)
      guard case .raster(let original)=before.layers[0].content,case .raster(let after)=d.layers[0].content else{return XCTFail("Missing raster")}
      var unchanged=true
      _ = try after.combiningStoredSamples(with:original){a,b in
        if a.r.bitPattern != b.r.bitPattern || a.g.bitPattern != b.g.bitPattern || a.b.bitPattern != b.b.bitPattern{unchanged=false}
        return a
      }
      XCTAssertTrue(unchanged,"Clear must retain every stored RGB word, including hidden RGB and signed zero.")
      guard case .raster(let painted)=d.layers[0].content else{return XCTFail("Missing raster")};XCTAssertEqual(painted.pixel(x:0,y:0).a,depth.quantize(0.5))
      d=before;var r=request(d,mask:mask,clear:true);r.settings.preserveTransparency=true;try Command.pixelPaint(r).apply(to:&d);XCTAssertEqual(d,before)
    }
  }
  func testExpansionAndMasksRetainDocumentPlacementAndOutsideSamples()throws {
    var d=try document();d.layers[0].x=2;d.layers[0].y=2;d.layers[0].content = .raster(try Surface(width:4,height:2,fill:Pixel(0,0,1)))
    d.layers[0].mask=try Surface(width:2,height:2,fill:Pixel(0.5,0.5,0.5));let maskTransform=d.layers[0].maskCoordinateTransform
    let mask=try SelectionMask(width:4,height:4,bytes:Array(repeating:255,count:16));try Command.pixelPaint(request(d,mask:mask)).apply(to:&d)
    XCTAssertEqual(d.layers[0].x,0);XCTAssertEqual(d.layers[0].y,0);XCTAssertEqual(d.layers[0].maskCoordinateTransform,maskTransform)
    guard case .raster(let pixels)=d.layers[0].content else{return XCTFail("Missing raster")};XCTAssertEqual(pixels.width,6);XCTAssertEqual(pixels.height,4);XCTAssertEqual(pixels.pixel(x:0,y:0),Pixel(1,0,0));XCTAssertEqual(pixels.pixel(x:5,y:3),Pixel(0,0,1))
    let before=d;var wrong=request(d,mask:try SelectionMask(width:2,height:2,bytes:[255,255,255,255]));XCTAssertThrowsError(try Command.pixelPaint(wrong).apply(to:&d));XCTAssertEqual(d,before)
    wrong=request(d,mask:mask);wrong.target = .mask(d.layers[0].id);XCTAssertThrowsError(try Command.pixelPaint(wrong).apply(to:&d));XCTAssertEqual(d,before)
  }
  func testPortablePathPaintResolvesNewLayerIDsAndClipsReplaySelection()throws {
    let original=try document(),mask=try SelectionMask(width:4,height:4,bytes:Array(repeating:255,count:16)),r=request(original,mask:mask)
    let operation=ActionOperation(recording:.pixelPaint(r),in:original),action=RecordedAction(name:"Path Fill",steps:[.init(name:"Fill Path",operation:operation)])
    try action.validate();var replay=try document();XCTAssertNotEqual(replay.layers[0].id,original.layers[0].id)
    replay.selection=IntRect(x:0,y:0,width:1,height:1);let before=replay;try action.apply(to:&replay)
    guard case .raster(let pixels)=replay.layers[0].content else{return XCTFail("Missing raster")};XCTAssertEqual(pixels.pixel(x:0,y:0),Pixel(1,0,0));XCTAssertEqual(pixels.pixel(x:1,y:0),.clear);XCTAssertEqual(replay.selection,before.selection)
    let decoded=try JSONDecoder().decode(RecordedAction.self,from:JSONEncoder().encode(action));var again=before;try decoded.apply(to:&again);XCTAssertEqual(again,replay)
  }
}
