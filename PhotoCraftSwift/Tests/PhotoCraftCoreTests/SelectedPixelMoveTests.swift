import XCTest
@testable import PhotoCraftCore

final class SelectedPixelMoveTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,background:Bool=false)throws->CraftDocument {var d=try SelectedPixelTransformTests().fixture(depth);if background{d.layers[0].background=true};return d}
  func pixels(_ d:CraftDocument)throws->Surface {try SelectedPixelTransformTests().pixels(d)}
  func testMoveAndSameLayerCopiesAtThreeDepthsWithBackgroundAndNativePlanes()throws {
    for depth in PixelDepth.allCases {for background in [false,true] {for copy in [false,true] {let source=try fixture(depth,background:background),id=source.layers[0].id,color=Pixel(0.25,0.5,0.75);var d=source
      let request=SelectedPixelMoveRequest(layerID:id,dx:6,dy:3,copy:copy,backgroundColor:background ? color:nil);try Command.movePixels(request).apply(to:&d);XCTAssertEqual(d.layers.count,1);XCTAssertEqual(d.layers[0].id,id);XCTAssertEqual(d.layers[0].isBackground,background);XCTAssertEqual(try pixels(d).pixel(x:10,y:7),try pixels(source).pixel(x:4,y:4))
      if copy{XCTAssertEqual(try pixels(d).pixel(x:3,y:3),try pixels(source).pixel(x:3,y:3))}else if background{XCTAssertEqual(try pixels(d).pixel(x:3,y:3),color.quantized(depth))}else{XCTAssertEqual(try pixels(d).pixel(x:3,y:3).a,0)}
      if background{XCTAssertTrue(try pixels(d).isOpaque());XCTAssertEqual(try pixels(d).width,16)};try d.validate()
      var native=try source.convertingMode(.init(mode:.rgb,depth:depth));try Command.movePixels(request).apply(to:&native);XCTAssertNotNil(native.layers[0].nativeMode);XCTAssertEqual(native.layers[0].isBackground,background);try native.validate()
    }}}
  }
  func testSoftCopyCompositesOverUnchangedSourceAndRetainsHDRWords()throws {
    var d=try CraftDocument(width:8,height:4,depth:.f32),s=try Surface(width:8,height:4,depth:.f32,colorEncoding:.linearRGB);s.setLinearPixel(x:2,y:1,Pixel(3,0.25,0.125,0.5));s.setLinearPixel(x:5,y:1,Pixel(0.2,0.4,0.6,0.25));s.setLinearPixel(x:1,y:1,Pixel(-0.0,4.5,-0.25,0));d.layers[0].content = .raster(s);var bytes=[UInt8](repeating:0,count:32);bytes[10]=128;d.setCoverageSelection(try SelectionMask(width:8,height:4,bytes:bytes));try Command.movePixels(.init(layerID:d.layers[0].id,dx:3,dy:0,copy:true)).apply(to:&d)
    let out=try pixels(d),a:Float=0.5*128/255,b:Float=0.25*(1-a),total=a+b,p=out.linearPixel(x:5,y:1);XCTAssertEqual(p.a,total,accuracy:1e-6);XCTAssertEqual(p.r,(3*a+0.2*b)/total,accuracy:1e-6);XCTAssertEqual(out.linearPixel(x:2,y:1),s.linearPixel(x:2,y:1));XCTAssertEqual(out.linearPixel(x:1,y:1).r.bitPattern,s.linearPixel(x:1,y:1).r.bitPattern);XCTAssertEqual(out.linearPixel(x:1,y:1).g,4.5)
  }
  func testOffsetsConstraintsAndIdentityAreDeterministic()throws {
    let id=UUID(),cases:[(Double,Double,Bool,Int,Int)]=[(10,4,true,11,0),(10,6,true,8,8),(-10,6,true,-8,8),(0.49,0.49,false,0,0),(0.49,0.49,true,0,0),(-1.5,2.5,false,-2,3)]
    for (x,y,constrain,dx,dy) in cases {let result=try SelectedPixelMoveRequest(layerID:id,dx:x,dy:y,constrain:constrain).offset();XCTAssertEqual(result.x,dx);XCTAssertEqual(result.y,dy)}
    for background in [false,true] {let source=try fixture(.f32,background:background);var session=EditorSession(document:source);try session.execute(.movePixels(.init(layerID:source.layers[0].id,dx:0,dy:0,copy:true)));XCTAssertEqual(session.document,source);XCTAssertTrue(session.undoStack.isEmpty)}
  }
  func testRepeatedCopiesUseTheLastSelectedDuplicateAndUndoIndividually()throws {
    var d=try CraftDocument(width:16,height:8),s=try Surface(width:16,height:8);s.setPixel(x:3,y:3,.white);d.layers[0].content = .raster(s);d.selection = .init(x:3,y:3,width:1,height:1);let original=d;var session=EditorSession(document:d);try session.startActionRecording(name:"Copies")
    for _ in 0..<4{try session.execute(.movePixels(.init(layerID:d.layers[0].id,dx:1,dy:0,copy:true)))}
    XCTAssertEqual(session.document.layers.count,1);XCTAssertEqual(session.document.selection?.x,7);for x in 3...7{XCTAssertEqual(try pixels(session.document).pixel(x:x,y:3),.white)};XCTAssertEqual(session.undoStack.count,4);var replay=original;try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&replay);XCTAssertEqual(replay,session.document);for _ in 0..<4{try session.undo()};XCTAssertEqual(session.document,original)
    var islands=original,plane=try Surface(width:16,height:8);plane.setPixel(x:3,y:3,Pixel(1,0,0));plane.setPixel(x:10,y:5,.white);islands.layers[0].content = .raster(plane);var bytes=[UInt8](repeating:0,count:128);bytes[51]=255;bytes[90]=255;islands.setCoverageSelection(try SelectionMask(width:16,height:8,bytes:bytes));try Command.movePixels(.init(layerID:islands.layers[0].id,dx:2,dy:1)).apply(to:&islands);XCTAssertEqual(try pixels(islands).pixel(x:5,y:4),Pixel(1,0,0));XCTAssertEqual(try pixels(islands).pixel(x:12,y:6),.white);XCTAssertEqual(try pixels(islands).pixel(x:3,y:3).a,0);XCTAssertEqual(try pixels(islands).pixel(x:10,y:5).a,0)
  }
  func testOffCanvasCopiesRetainStorageAndMaskCoordinatesButBackgroundClips()throws {
    var source=try fixture();source.layers[0].mask=try Surface(width:16,height:12,fill:.white);let mask=source.layers[0].mask,transform=source.layers[0].maskCoordinateTransform;var d=source;try Command.movePixels(.init(layerID:d.layers[0].id,dx:-12,dy:-8,copy:true)).apply(to:&d);XCTAssertNil(d.selection);XCTAssertEqual(try SelectedPixelTransformTests().pixel(d,-8,-4),try pixels(source).pixel(x:4,y:4));XCTAssertEqual(d.layers[0].mask,mask);XCTAssertEqual(d.layers[0].maskCoordinateTransform,transform)
    var background=try fixture(background:true);try Command.movePixels(.init(layerID:background.layers[0].id,dx:-100,dy:-100,copy:true)).apply(to:&background);XCTAssertEqual(try pixels(background).width,16);XCTAssertTrue(try pixels(background).isOpaque());XCTAssertNil(background.selection)
  }
  func testInvalidLocksStalePreparedAndCancelledWorkAreAtomic()async throws {
    let original=try fixture(),id=original.layers[0].id
    for number in [Double.nan,.infinity,1_000_001] {var d=original;XCTAssertThrowsError(try Command.movePixels(.init(layerID:id,dx:number,dy:0)).apply(to:&d));XCTAssertEqual(d,original)}
    for flags:LayerProtection in [.image,.position,.transparency,.all] {var d=original;d.layers[0].protection=flags;let before=d;XCTAssertThrowsError(try Command.movePixels(.init(layerID:id,dx:1,dy:0,copy:true)).apply(to:&d));XCTAssertEqual(d,before)}
    let request=SelectedPixelMoveRequest(layerID:id,dx:1,dy:0),edit=try PreparedEdit(command:.movePixels(request),document:original);var session=EditorSession(document:original);try session.execute(.renameLayer(id,"Changed"));let changed=session.document;XCTAssertThrowsError(try session.executePrepared(edit));XCTAssertEqual(session.document,changed)
    let task=Task{while !Task.isCancelled{await Task.yield()};var d=original;try Command.movePixels(request).apply(to:&d)};task.cancel();do{try await task.value;XCTFail("Canceled movement committed")}catch{XCTAssertTrue(error is CancellationError)}
  }
  func testSparseMaximumCopiesStayBoundedAndOldRequestJSONStillDecodes()throws {
    var d=try CraftDocument(width:300000,height:300000),s=try Surface(width:300000,height:300000);s.setPixel(x:65,y:65,.white);d.layers[0].content = .raster(s);d.selection = .init(x:64,y:64,width:12,height:10);try Command.movePixels(.init(layerID:d.layers[0].id,dx:96,dy:32,copy:true)).apply(to:&d);XCTAssertEqual(try pixels(d).pixel(x:65,y:65),.white);XCTAssertEqual(try pixels(d).pixel(x:161,y:97),.white);XCTAssertLessThan(try pixels(d).allocatedBytes,2_097_152)
    let request=SelectedPixelTransformRequest(layerID:d.layers[0].id,matrix:.identity);let old=try JSONDecoder().decode(SelectedPixelTransformRequest.self,from:JSONEncoder().encode(request));XCTAssertNil(old.copy)
  }
  func testAnalyticalMoveCopyOutputsCapturedForIndependentReader()throws {
    var rows:[[String:Any]]=[]
    for (background,copy,dx,dy) in [(false,false,5,3),(false,true,2,1),(true,false,-12,-8),(true,true,2,1)] {var d=try fixture(background:background);try Command.movePixels(.init(layerID:d.layers[0].id,dx:Double(dx),dy:Double(dy),copy:copy,backgroundColor:background ? Pixel(20/255,40/255,60/255):nil)).apply(to:&d);var rgba:[Int]=[];for y in 0..<12{for x in 0..<16{let p=try SelectedPixelTransformTests().pixel(d,x,y);rgba += [p.r,p.g,p.b,p.a].map{Int((unit($0)*255).rounded())}}};rows.append(["background":background,"copy":copy,"dx":dx,"dy":dy,"rgba":rgba])}
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["width":16,"height":12,"backgroundColor":[20,40,60,255],"rows":rows],options:.sortedKeys).write(to:dir.appendingPathComponent("pixel-move-analytical.json"))}
  }
}
