import XCTest
@testable import PhotoCraftCore

final class SelectedPixelTransformTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:16,height:12,depth:depth),s=try Surface(width:16,height:12,depth:depth)
    for y in 0..<12 {for x in 0..<16{s.setPixel(x:x,y:y,Pixel(Float((x*17+y*11)%256)/255,Float((x*7+y*23)%256)/255,Float((x*31+y*3)%256)/255))}}
    d.layers[0].content = .raster(s);d.selection = .init(x:3,y:3,width:5,height:4);return d
  }
  func pixels(_ d:CraftDocument)throws->Surface {guard case .raster(let s)=d.layers[0].content else{throw CraftError.invalid("Expected raster")};return s}
  func pixel(_ d:CraftDocument,_ x:Int,_ y:Int)throws->Pixel {let p=try d.layers[0].coordinateTransform.inverted().point(Double(x)+0.5,Double(y)+0.5);return try pixels(d).pixel(x:Int(floor(p.x)),y:Int(floor(p.y)))}
  func testIdentityRetainsAllStoredWordsAndHistory()throws {
    var d=try fixture(.f32),s=try Surface(width:16,height:12,depth:.f32,colorEncoding:.linearRGB);s.setLinearPixel(x:1,y:1,Pixel(-0.0,2.75,-0.25,0));s.setLinearPixel(x:4,y:4,Pixel(4.5,0.125,-0.0,0.75));d.layers[0].content = .raster(s)
    let original=d;var session=EditorSession(document:d);try session.execute(.transformPixels(.init(layerID:d.layers[0].id,matrix:.identity)))
    XCTAssertTrue(session.document==original);XCTAssertTrue(session.undoStack.isEmpty);XCTAssertEqual(try pixels(session.document).rgbaData(depth:.f32,colorEncoding:.linearRGB),try s.rgbaData(depth:.f32,colorEncoding:.linearRGB))
  }
  func testHardTranslationCutsSourceAndOverlaysDestination()throws {
    let original=try fixture();var d=original;try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:.init(.translation(6,3)),interpolation:.nearest)).apply(to:&d)
    XCTAssertEqual(d.selection,.init(x:9,y:6,width:5,height:4));XCTAssertEqual(try pixel(d,3,3).a,0);XCTAssertEqual(try pixel(d,10,7),try pixel(original,4,4));XCTAssertEqual(try pixel(d,0,0),try pixel(original,0,0));XCTAssertEqual(try pixel(d,15,11),try pixel(original,15,11))
  }
  func testSoftCoverageCutsAndMovesPremultipliedAlpha()throws {
    var d=try CraftDocument(width:8,height:4,depth:.f32),s=try Surface(width:8,height:4,depth:.f32,colorEncoding:.linearRGB);s.setLinearPixel(x:2,y:1,Pixel(3,0.25,0.125))
    d.layers[0].content = .raster(s);var bytes=[UInt8](repeating:0,count:32);bytes[10]=128;d.setCoverageSelection(try SelectionMask(width:8,height:4,bytes:bytes))
    try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:.init(.translation(3,0)),interpolation:.nearest)).apply(to:&d)
    let out=try pixels(d);XCTAssertEqual(out.colorEncoding,.linearRGB);XCTAssertEqual(out.linearPixel(x:2,y:1).a,127/255,accuracy:1e-6);XCTAssertEqual(out.linearPixel(x:5,y:1).a,128/255,accuracy:1e-6);XCTAssertEqual(out.linearPixel(x:5,y:1).r,3,accuracy:1e-6);XCTAssertEqual(d.selectionMask?.byte(at:13),128)
    var solid=try CraftDocument(width:8,height:6,depth:.f32),plane=try Surface(width:8,height:6,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<6 {for x in 0..<8 {plane.setLinearPixel(x:x,y:y,Pixel(3,0.25,0.125))}}
    solid.layers[0].content = .raster(plane);solid.selection = .init(x:0,y:0,width:8,height:6)
    try Command.transformPixels(.init(layerID:solid.layers[0].id,matrix:.init(.translation(0.4,0.3)),interpolation:.bicubic)).apply(to:&solid)
    let transformed=try pixels(solid)
    for y in 0..<transformed.height {for x in 0..<transformed.width {let p=transformed.linearPixel(x:x,y:y);if p.a>1e-6 {XCTAssertEqual(p.r,3,accuracy:0.00001);XCTAssertEqual(p.g,0.25,accuracy:0.00001)}}}

  }
  func testInterpolationProjectiveAndTransformedSourceFrame()throws {
    let original=try fixture();let matrix=try ProjectiveTransform([1,0.1,1,0,1,0,0.015,0,1]);var results:[CraftDocument]=[]
    for method in Resampling.allCases {var d=original;try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:matrix,interpolation:method)).apply(to:&d);try d.validate();XCTAssertEqual(d.selectionMask,try SelectionTransform.apply(XCTUnwrap(original.coverageSelection()),projection:matrix,interpolation:method));results.append(d)}
    XCTAssertFalse(results[0]==results[1])
    var translated=original;translated.layers[0].x=2;translated.layers[0].y=1;let before=translated
    try Command.transformPixels(.init(layerID:translated.layers[0].id,matrix:.init(.translation(5,0)),interpolation:.nearest)).apply(to:&translated)
    XCTAssertEqual(try pixel(translated,9,4),try pixel(before,4,4));XCTAssertEqual(try pixel(translated,0,0),try pixel(before,0,0))
  }
  func testOffCanvasPixelsAndMaskCoordinatesSurvive()throws {
    var d=try fixture();d.layers[0].mask=try Surface(width:16,height:12,fill:.white);let original=d,maskTransform=d.layers[0].maskCoordinateTransform
    try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:.init(.translation(-12,-8)),interpolation:.nearest)).apply(to:&d)
    XCTAssertNil(d.selection);XCTAssertEqual(try pixel(d,-8,-4),try pixel(original,4,4));XCTAssertEqual(d.layers[0].maskCoordinateTransform,maskTransform);XCTAssertEqual(d.layers[0].mask,original.layers[0].mask);XCTAssertEqual(try pixel(d,15,11),try pixel(original,15,11))
  }
  func testSparseMaximumDimensionsRemainBounded()throws {
    let padded=IntRect(x:-2,y:-2,width:300004,height:300004),matrix=ProjectiveTransform(Transform2D.translation(75000,75000) * .scale(0.5,0.5))
    XCTAssertEqual(try SelectedPixelTransform.projectedBounds(padded,using:matrix),.init(x:74999,y:74999,width:150002,height:150002))

    var d=try CraftDocument(width:300000,height:300000),s=try Surface(width:300000,height:300000);s.setPixel(x:65,y:65,.white);d.layers[0].content = .raster(s);d.selection = .init(x:64,y:64,width:12,height:10)
    try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:.init(.translation(96,32)),interpolation:.nearest)).apply(to:&d)
    XCTAssertEqual(try pixel(d,161,97),.white);XCTAssertEqual(try pixel(d,65,65).a,0);XCTAssertLessThan(try pixels(d).allocatedBytes,2_097_152);XCTAssertEqual(d.width,300000)
  }
  func testInvalidLocksAndStalePreparedEditAreAtomic()throws {
    let original=try fixture();let request=SelectedPixelTransformRequest(layerID:original.layers[0].id,matrix:.init(.translation(1,0)))
    for lock in [LayerProtection.image,.position,.transparency,.all] {var d=original;d.layers[0].protection=lock;let before=d;XCTAssertThrowsError(try Command.transformPixels(request).apply(to:&d));XCTAssertTrue(d==before)}
    var missing=original;missing.setCoverageSelection(nil);XCTAssertThrowsError(try Command.transformPixels(request).apply(to:&missing))
    let prepared=try PreparedEdit(command:.transformPixels(request),document:original);var session=EditorSession(document:original);try session.execute(.renameLayer(request.layerID,"Changed"));let changed=session.document;XCTAssertThrowsError(try session.executePrepared(prepared));XCTAssertTrue(session.document==changed)
  }
  func testHistorySemanticActionsNativeArchiveAndCancellation()async throws {
    let original=try fixture(),request=SelectedPixelTransformRequest(layerID:original.layers[0].id,matrix:.init(.translation(2,1)),interpolation:.nearest);var session=EditorSession(document:original)
    try session.startActionRecording(name:"Selected pixels");try session.execute(.transformPixels(request));let result=session.document;XCTAssertEqual(session.undoStack.last?.label,"Free Transform")
    let action=try XCTUnwrap(session.actionRecording?.snapshot);XCTAssertNil(action.steps.first?.operation.unsupportedReason);var replay=original;try action.apply(to:&replay);XCTAssertTrue(replay==result);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result))==result);try session.undo();XCTAssertTrue(session.document==original);try session.redo();XCTAssertTrue(session.document==result)
    let task=Task{while !Task.isCancelled{await Task.yield()};var d=original;try Command.transformPixels(request).apply(to:&d)};task.cancel();do{try await task.value;XCTFail("Canceled transform completed")}catch{XCTAssertTrue(error is CancellationError)}
  }
  func testAnalyticalOutputsCapturedForIndependentReader()throws {
    let original=try fixture(),programs:[ProjectiveTransform]=[.init(.translation(5,3)),.init(Transform2D(a:-1,d:1,tx:11)),.init(Transform2D(a:0,b:1,c:-1,d:0,tx:12)),try .init([1,0,1,0,1,0,0.015,0,1])];var rows:[[String:Any]]=[]
    for matrix in programs {
      var d=original;try Command.transformPixels(.init(layerID:d.layers[0].id,matrix:matrix,interpolation:.nearest)).apply(to:&d)
      var rgba:[Int]=[]
      for y in 0..<12 {for x in 0..<16 {let p=try pixel(d,x,y);rgba += [p.r,p.g,p.b,p.a].map{Int((unit($0)*255).rounded())}}}
      rows.append(["matrix":matrix.values,"rgba":rgba])
    }
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["width":16,"height":12,"rows":rows],options:.sortedKeys).write(to:url.appendingPathComponent("selected-pixel-transform-analytical.json"))}
  }
}
