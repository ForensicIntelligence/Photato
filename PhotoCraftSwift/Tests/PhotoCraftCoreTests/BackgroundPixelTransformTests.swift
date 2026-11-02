import XCTest
@testable import PhotoCraftCore

final class BackgroundPixelTransformTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {var d=try SelectedPixelTransformTests().fixture(depth);d.layers[0].background=true;try d.validate();return d}
  func pixels(_ d:CraftDocument)throws->Surface {try SelectedPixelTransformTests().pixels(d)}
  func testIdentityPreservesHDRWordsAndEmptyHistory()throws {
    var d=try fixture(.f32),s=try Surface(width:16,height:12,depth:.f32,fill:.white,colorEncoding:.linearRGB);s.setLinearPixel(x:4,y:4,Pixel(-0.0,4.5,-0.25));d.layers[0].content = .raster(s);var session=EditorSession(document:d)
    try session.execute(.transformPixels(.init(layerID:d.layers[0].id,matrix:.identity,backgroundColor:.black)));XCTAssertEqual(session.document,d);XCTAssertTrue(session.undoStack.isEmpty);XCTAssertEqual(try pixels(session.document).rgbaData(depth:.f32,colorEncoding:.linearRGB),try s.rgbaData(depth:.f32,colorEncoding:.linearRGB))
  }
  func testHardTranslationUsesSwatchAndKeepsFullCanvasIdentityAtAllDepths()throws {
    for depth in PixelDepth.allCases {let source=try fixture(depth),id=source.layers[0].id,color=Pixel(0.25,0.5,0.75);var d=source
      XCTAssertTrue(SelectedPixelTransform.available(d,layerID:id));try Command.transformPixels(.init(layerID:id,matrix:.init(.translation(6,3)),interpolation:.nearest,backgroundColor:color)).apply(to:&d)
      let result=try pixels(d);XCTAssertEqual(result.pixel(x:3,y:3),color.quantized(depth));XCTAssertEqual(result.pixel(x:10,y:7),try pixels(source).pixel(x:4,y:4));XCTAssertEqual(result.pixel(x:0,y:0),try pixels(source).pixel(x:0,y:0));XCTAssertEqual(result.width,16);XCTAssertEqual(result.height,12);XCTAssertTrue(try result.isOpaque());XCTAssertTrue(d.layers[0].isBackground);XCTAssertEqual(d.layers[0].id,id);XCTAssertEqual(d.layers[0].x,0);XCTAssertEqual(d.layers[0].y,0);try d.validate()
      var modeResult=try source.convertingMode(.init(mode:.rgb,depth:depth));try Command.transformPixels(.init(layerID:id,matrix:.init(.translation(6,3)),interpolation:.nearest,backgroundColor:color)).apply(to:&modeResult);XCTAssertNotNil(modeResult.layers[0].nativeMode);XCTAssertTrue(modeResult.layers[0].isBackground);XCTAssertTrue(try pixels(modeResult).isOpaque());XCTAssertEqual(try pixels(modeResult).pixel(x:3,y:3).r,color.quantized(depth).r,accuracy:0.0001);try modeResult.validate()
      var outside=source;try Command.transformPixels(.init(layerID:id,matrix:.init(.translation(-100,-100)),interpolation:.nearest,backgroundColor:color)).apply(to:&outside);XCTAssertNil(outside.selection);XCTAssertEqual(try pixels(outside).width,16);XCTAssertEqual(try pixels(outside).pixel(x:3,y:3),color.quantized(depth));try outside.validate()
    }
  }
  func testSoftCoverageFillsWithoutAlphaLossAndPreservesUntouchedHDRBits()throws {
    var d=try DocumentCreation.blank(width:8,height:4,depth:.f32),s=try Surface(width:8,height:4,depth:.f32,fill:.white,colorEncoding:.linearRGB);s.setLinearPixel(x:1,y:1,Pixel(-0.0,4.5,-0.25));s.setLinearPixel(x:2,y:1,Pixel(2,0.5,0.125));d.layers[0].content = .raster(s)
    var bytes=[UInt8](repeating:0,count:32);bytes[10]=128;d.setCoverageSelection(try SelectionMask(width:8,height:4,bytes:bytes));try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:.init(.translation(3,0)),interpolation:.nearest,backgroundColor:.black)).apply(to:&d)
    let out=try pixels(d),source=out.linearPixel(x:2,y:1),destination=out.linearPixel(x:5,y:1),k:Float=128/255
    XCTAssertEqual(source.r,2*(1-k),accuracy:1e-6);XCTAssertEqual(source.g,0.5*(1-k),accuracy:1e-6);XCTAssertEqual(destination.r,2*k+(1-k),accuracy:1e-6);XCTAssertEqual(destination.g,0.5*k+(1-k),accuracy:1e-6);XCTAssertEqual(source.a,1);XCTAssertEqual(destination.a,1);XCTAssertEqual(out.linearPixel(x:1,y:1).r.bitPattern,s.linearPixel(x:1,y:1).r.bitPattern);XCTAssertEqual(out.linearPixel(x:1,y:1).g,4.5);XCTAssertTrue(try out.isOpaque())
  }
  func testProjectiveAndInterpolatedTransformsKeepOpaqueBackground()throws {
    let source=try fixture();for method in Resampling.allCases {var d=source;let matrix=try ProjectiveTransform([1,0.1,-2,0,1,0,0.015,0,1]);try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:matrix,interpolation:method,backgroundColor:Pixel(0.2,0.3,0.4))).apply(to:&d);XCTAssertEqual(try pixels(d).width,source.width);XCTAssertTrue(try pixels(d).isOpaque());XCTAssertEqual(d.selectionMask,try SelectionTransform.apply(XCTUnwrap(source.coverageSelection()),projection:matrix,interpolation:method));try d.validate()}
  }
  func testHistoryActionsAndOldRequestJSONArePreserved()throws {
    let source=try fixture(),id=source.layers[0].id,request=SelectedPixelTransformRequest(layerID:id,matrix:.init(.translation(2,1)),interpolation:.nearest,backgroundColor:.black);var session=EditorSession(document:source);try session.startActionRecording(name:"Background pixels");try session.execute(.transformPixels(request));let result=session.document,action=try XCTUnwrap(session.actionRecording?.snapshot);var replay=source;try action.apply(to:&replay);XCTAssertEqual(replay,result);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result);try session.undo();XCTAssertEqual(session.document,source);try session.redo();XCTAssertEqual(session.document,result)
    var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(request)) as? [String:Any]);json.removeValue(forKey:"backgroundColor");let old=try JSONDecoder().decode(SelectedPixelTransformRequest.self,from:JSONSerialization.data(withJSONObject:json));XCTAssertNil(old.backgroundColor)
    var regular=source;try Command.backgroundLayer(.toLayer(id,.init(name:"Regular"))).apply(to:&regular);try Command.transformPixels(old).apply(to:&regular);XCTAssertEqual(try pixels(regular).pixel(x:3,y:3).a,0)
  }
  func testInvalidColorsLocksStaleAndCancellationStayAtomic()async throws {
    let source=try fixture(),id=source.layers[0].id
    for color in [Pixel(0,0,0,0.5),Pixel(.nan,0,0)] {var d=source;XCTAssertThrowsError(try Command.transformPixels(.init(layerID:id,matrix:.identity,backgroundColor:color)).apply(to:&d));XCTAssertEqual(d,source)}
    for lock:LayerProtection in [.image,.all] {var d=source;d.layers[0].protection=lock;XCTAssertFalse(SelectedPixelTransform.available(d,layerID:id));let before=d;XCTAssertThrowsError(try Command.transformPixels(.init(layerID:id,matrix:.init(.translation(1,0)))).apply(to:&d));XCTAssertEqual(d,before)}
    let request=SelectedPixelTransformRequest(layerID:id,matrix:.init(.translation(1,0)),backgroundColor:.black),edit=try PreparedEdit(command:.transformPixels(request),document:source);var session=EditorSession(document:source);try session.execute(.visibility(id,false));let changed=session.document;XCTAssertThrowsError(try session.executePrepared(edit));XCTAssertEqual(session.document,changed)
    let task=Task{while !Task.isCancelled{await Task.yield()};var d=source;try Command.transformPixels(request).apply(to:&d)};task.cancel();do{try await task.value;XCTFail("Canceled transform committed")}catch{XCTAssertTrue(error is CancellationError)}
    var ordinary=source;try Command.backgroundLayer(.toLayer(id,.init(name:"Background"))).apply(to:&ordinary);XCTAssertThrowsError(try Command.transformPixels(request).apply(to:&ordinary))
  }
  func testSparseMaximumCanvasAndVirtualInterpolationSupportStayBounded()throws {
    let canvas=IntRect(x:0,y:0,width:300000,height:300000),padded=IntRect(x:-2,y:-2,width:300004,height:300004)
    XCTAssertEqual(try SelectedPixelTransform.projectedBounds(padded,using:.init(.translation(1,1)),clipping:canvas),canvas)
    var d=try DocumentCreation.blank(width:300000,height:300000);d.selection = .init(x:64,y:64,width:12,height:10);try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:.init(.translation(96,32)),interpolation:.bicubic,backgroundColor:.black)).apply(to:&d);XCTAssertEqual(try pixels(d).pixel(x:65,y:65),.black);XCTAssertTrue(try pixels(d).isOpaque());XCTAssertLessThan(try pixels(d).allocatedBytes,2_097_152);XCTAssertEqual(try pixels(d).width,300000);try d.validate()
  }
  func testAnalyticalOutputsCapturedForIndependentBackgroundReader()throws {
    let source=try fixture(),color=Pixel(20/255,40/255,60/255),programs:[ProjectiveTransform]=[.init(.translation(5,3)),.init(.translation(-12,-8)),.init(Transform2D(a:-1,d:1,tx:11)),try .init([1,0,1,0,1,0,0.015,0,1])];var rows:[[String:Any]]=[]
    for matrix in programs {var d=source;try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:matrix,interpolation:.nearest,backgroundColor:color)).apply(to:&d);rows.append(["matrix":matrix.values,"rgba":try pixels(d).rgbaData(depth:.u8).map(Int.init)])}
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["width":16,"height":12,"background":[20,40,60,255],"rows":rows],options:.sortedKeys).write(to:dir.appendingPathComponent("background-transform-analytical.json"))}
  }
}
