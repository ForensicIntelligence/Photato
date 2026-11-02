import XCTest
@testable import PhotoCraftCore

final class BackgroundLayerTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {try DocumentCreation.blank(width:9,height:7,depth:depth,background:.white)}
  func pixels(_ document:CraftDocument)throws->Surface {guard case .raster(let value)=document.layers[0].content else{throw CraftError.invalid("Expected raster")};return value}
  func testExplicitIdentityCreationAndLegacyNameDoNotConflate()throws {
    let legacy=try CraftDocument(width:9,height:7);XCTAssertEqual(legacy.layers[0].name,"Background");XCTAssertFalse(legacy.layers[0].isBackground)
    XCTAssertFalse(try NativeArchive.decode(NativeArchive.encodeChunked(legacy)).layers[0].isBackground)
    for depth in PixelDepth.allCases {let d=try fixture(depth);XCTAssertTrue(d.layers[0].isBackground);XCTAssertTrue(d.isPositionLocked(d.layers[0].id));XCTAssertTrue(d.isTransparencyLocked(d.layers[0].id));XCTAssertFalse(d.isImageLocked(d.layers[0].id));try d.validate()}
    XCTAssertFalse(try DocumentCreation.blank(width:9,height:7,background:.clear).layers[0].isBackground)
  }
  func testConversionOptionsUndoAndRecordedSemanticReplay()throws {
    let original=try fixture();var session=EditorSession(document:original);let id=original.layers[0].id
    try session.startActionRecording(name:"Background");var options=NewPixelLayerOptions(name:"Image");options.mode = .multiply;options.opacity=0.625;options.color = .red
    try session.execute(.backgroundLayer(.toLayer(id,options)));XCTAssertFalse(session.document.layers[0].isBackground);XCTAssertEqual(session.document.layers[0].name,"Image");XCTAssertEqual(session.document.layers[0].opacity,0.625);XCTAssertEqual(session.document.layers[0].blendMode,.multiply);XCTAssertEqual(session.document.layers[0].protection,[])
    var replay=original;try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&replay);XCTAssertEqual(replay,session.document);try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,replay)
  }
  func testFromLayerFillsTransparencyPadsCanvasMovesToBottomAndKeepsID()throws {
    var d=try CraftDocument(width:9,height:7);var layer=Layer(name:"Float",content:.raster(try Surface(width:3,height:2,fill:Pixel(1,0,0,0.5))));layer.x=2;layer.y=3;layer.opacity=0.4;layer.blendMode = .screen;let id=layer.id;d.layers.append(layer)
    try Command.backgroundLayer(.fromLayer(id,.black)).apply(to:&d);XCTAssertEqual(d.layers[0].id,id);XCTAssertEqual(d.layers[0].name,"Background");XCTAssertEqual(d.layers[0].opacity,1);XCTAssertEqual(d.layers[0].blendMode,.normal);XCTAssertEqual(try pixels(d).pixel(x:0,y:0),.black);XCTAssertEqual(try pixels(d).pixel(x:2,y:3).a,1);XCTAssertEqual(try pixels(d).pixel(x:2,y:3).r,128/255,accuracy:1/255);try d.validate()
    XCTAssertThrowsError(try Command.backgroundLayer(.fromLayer(d.layers[1].id,.white)).apply(to:&d))
  }
  func testClearCutAndEraserUseBackgroundSwatchAtEveryDepth()throws {
    for depth in PixelDepth.allCases {let original=try fixture(depth),id=original.layers[0].id,color=Pixel(0.25,0.5,0.75)
      var cleared=original;cleared.selection = .init(x:2,y:2,width:3,height:2);try Command.backgroundLayer(.clear(id,color)).apply(to:&cleared);XCTAssertEqual(try pixels(cleared).pixel(x:0,y:0),.white);XCTAssertEqual(try pixels(cleared).pixel(x:3,y:2),color.quantized(depth));XCTAssertTrue(try pixels(cleared).isOpaque())
      var cut=original;cut.selection=cleared.selection;try Command.cut([id],background:color).apply(to:&cut);XCTAssertEqual(cut,cleared)
      var erased=original,brush=Brush();brush.settings = .init();brush.erase=true;brush.backgroundColor=color;brush.size=3;brush.hardness=1
      try Command.stroke(id,[.init(x:4.5,y:3.5)],brush).apply(to:&erased);XCTAssertEqual(try pixels(erased).pixel(x:4,y:3),color.quantized(depth));XCTAssertTrue(try pixels(erased).isOpaque());try erased.validate()
      let retained=try DocumentBrushStrokeSession(document:original,layerID:id,brush:brush);_ = try retained.append([.init(x:4.5,y:3.5)],includingReleaseTail:false);let prepared=try retained.prepareEdit(points:[.init(x:4.5,y:3.5)]);var replay=EditorSession(document:original);try replay.executePrepared(prepared);XCTAssertEqual(replay.document,erased)
    }
  }
  func testSoftClearRetainsHDRAndUntouchedStoredWords()throws {
    var d=try fixture(.f32),s=try Surface(width:9,height:7,depth:.f32,fill:.white,colorEncoding:.linearRGB);s.setLinearPixel(x:1,y:1,Pixel(-0.0,4.5,-0.25));s.setLinearPixel(x:4,y:3,Pixel(2,0.5,-0.125));d.layers[0].content = .raster(s)
    var bytes=[UInt8](repeating:0,count:63);bytes[31]=128;d.setCoverageSelection(try SelectionMask(width:9,height:7,bytes:bytes));try Command.backgroundLayer(.clear(d.layers[0].id,.black)).apply(to:&d)
    let out=try pixels(d),p=out.linearPixel(x:4,y:3);XCTAssertEqual(p.r,2*127/255,accuracy:1e-6);XCTAssertEqual(p.g,0.5*127/255,accuracy:1e-6);XCTAssertEqual(p.a,1);XCTAssertEqual(out.linearPixel(x:1,y:1).r.bitPattern,s.linearPixel(x:1,y:1).r.bitPattern);XCTAssertEqual(out.linearPixel(x:1,y:1).g,4.5)
  }
  func testOpacityProofIsCOWAndPartialPaddingIsNotContent()throws {
    let source=try Surface(width:65,height:3,fill:.white);XCTAssertTrue(try source.isOpaque());var copy=source;copy.setPixel(x:64,y:2,.clear);XCTAssertFalse(try copy.isOpaque());XCTAssertTrue(try source.isOpaque())
    var edge=try Surface(width:1,height:1);edge.setPixel(x:0,y:0,.white);XCTAssertTrue(try edge.isOpaque());let round=try JSONDecoder().decode(Surface.self,from:JSONEncoder().encode(edge));XCTAssertTrue(try round.isOpaque());var changed=round;changed.mapPixels{_,_,p in Pixel(p.r,p.g,p.b,0.5)};XCTAssertFalse(try changed.isOpaque());XCTAssertTrue(try round.isOpaque())
  }
  func testNative83RetainsIdentityAndRejectsForgedBackgrounds()throws {
    let d=try fixture();let data=try NativeArchive.encodeChunked(d);XCTAssertEqual(data.prefix(16),NativeIndexedArchive.containerHeader(83));XCTAssertEqual(try NativeArchive.decode(data),d)
    for change in 0..<5 {var bad=d;switch change{case 0:bad.layers[0].opacity=0.5;case 1:bad.layers[0].x=1;case 2:bad.layers[0].content = .raster(try Surface(width:9,height:7));case 3:var extra=bad.layers[0];extra.id=UUID();bad.layers.append(extra);default:bad.layers[0].mask=try Surface(width:9,height:7,fill:.white)};XCTAssertThrowsError(try bad.validate())}
  }
  func testDuplicationAndNewBelowKeepExactlyOneBottomBackground()throws {
    var d=try fixture();let id=d.layers[0].id;try Command.duplicateLayer(id).apply(to:&d);XCTAssertEqual(d.layers.filter(\.isBackground).count,1);XCTAssertFalse(d.layers[1].isBackground);XCTAssertEqual(d.layers[1].protection,[]);d.activeLayerID=id
    let layer=try NewPixelLayerOptions(name:"Below").layer(in:d);try d.insertNewLayer(layer,below:true);XCTAssertEqual(d.layers[0].id,id);XCTAssertEqual(d.layers[1].id,layer.id);try d.validate()
  }
  func testCanvasGeometryRetainsFullCanvasOpaqueBackground()throws {
    var d=try fixture();let id=d.layers[0].id;try Command.canvasSize(13,11,.center,.black).apply(to:&d);XCTAssertEqual(d.layers.count,1);XCTAssertEqual(try pixels(d).pixel(x:0,y:0),.black);XCTAssertEqual(d.layers[0].id,id)
    for command:Command in [.crop(.init(x:1,y:1,width:7,height:5)),.imageSize(14,10,72,.nearest),.rotateCanvas(.clockwise)] {try command.apply(to:&d);XCTAssertEqual(try pixels(d).width,d.width);XCTAssertEqual(try pixels(d).height,d.height);XCTAssertTrue(try pixels(d).isOpaque());XCTAssertEqual(d.layers[0].x,0);XCTAssertEqual(d.layers[0].y,0);try d.validate()}
  }
  func testUnsupportedMutationsAreAtomicAndConversionIsRequired()throws {
    let source=try fixture(),id=source.layers[0].id
    for command:Command in [.opacity(id,0.5),.renameLayer(id,"Name"),.transform(id,.translation(1,1),.nearest),.protection([id:[]])] {var session=EditorSession(document:source);XCTAssertThrowsError(try session.execute(command));XCTAssertEqual(session.document,source);XCTAssertTrue(session.undoStack.isEmpty)}
  }
  func testMagicEraserPromotesBackgroundBeforeRemovingPixels()throws {
    let d=try fixture(),request=PaintToolRequest(tool:.magicEraser,target:.pixels(d.layers[0].id),points:[.init(x:4,y:3)],brush:Brush());let result=try PaintingEdit.prepare(request,in:d).result;XCTAssertFalse(result.layers[0].isBackground);XCTAssertEqual(result.layers[0].name,"Layer 0");XCTAssertEqual(try pixels(result).pixel(x:4,y:3).a,0);try result.validate()
  }
  func testSparseMaximumCanvasDoesNotMaterializeAnOpaquePlane()throws {
    var d=try DocumentCreation.blank(width:300000,height:300000);XCTAssertEqual(try pixels(d).tileCount,0);try Command.backgroundLayer(.clear(d.layers[0].id,.black)).apply(to:&d);XCTAssertEqual(try pixels(d).tileCount,0);XCTAssertEqual(try pixels(d).pixel(x:299999,y:299999),.black);try d.validate()
  }
}
