import XCTest
@testable import PhotoCraftCore

final class LargeCropTests:XCTestCase {
  func sparse(_ depth:PixelDepth = .f32,width:Int=300000,height:Int=300000)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth),s=try Surface(width:width,height:height,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    if depth == .f32{s.setLinearPixel(x:width/2,y:height/2,Pixel(4,-0.25,-0.0,0.5));s.setLinearPixel(x:width-2,y:height-2,Pixel(2,0.5,0.25,0))}else{s.setPixel(x:width/2,y:height/2,Pixel(1,0,0,0.5));s.setPixel(x:width-2,y:height-2,Pixel(0.2,0.4,0.8,0))};d.layers[0].content = .raster(s);return d
  }
  func testMaximumRGBDeleteAndRetainPreserveRawSamplesMasksHistoryAndArchive()throws {
    for depth in PixelDepth.allCases {var original=try sparse(depth);original.layers[0].mask=try Surface(width:4,height:3,depth:depth,fill:.white);var properties=MaskProperties();properties.transform = .translation(150000,150000);properties.linked=false;original.layers[0].maskProperties=properties
      for deleting in [false,true] {var request=CropRequest(x:1,y:1,width:299999,height:299999);request.deleteCroppedPixels=deleting;let result=try CropGeometry.applying(request,to:original);XCTAssertEqual(result.width,299999);XCTAssertEqual(result.layers[0].mask,original.layers[0].mask);XCTAssertEqual(result.layers[0].maskCoordinateTransform,request.transform*original.layers[0].maskCoordinateTransform)
        guard case .raster(let s)=result.layers[0].content,case .raster(let before)=original.layers[0].content else{return XCTFail("Raster")};XCTAssertLessThan(s.allocatedBytes,2*1024*1024);XCTAssertLessThan(s.tileCount,20)
        for (x,y) in [(150000,150000),(299998,299998)] {let rx=x-1-result.layers[0].x,ry=y-1-result.layers[0].y;XCTAssertTrue((depth == .f32 ? s.linearPixel(x:rx,y:ry):s.pixel(x:rx,y:ry)).hasSameBits(as:depth == .f32 ? before.linearPixel(x:x,y:y):before.pixel(x:x,y:y)))}
        var session=EditorSession(document:original);try session.execute(.cropDocument(.init(source:original,result:result)));try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,result);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
      }
    }
  }
  func testImplicitMaximumCropAndWholeWhiteSavedChannelDoNotMaterializePlane()throws {
    var d=try CraftDocument(width:300000,height:300000);d.alphaChannels=[AlphaChannel(name:"White",pixels:try Surface(width:300000,height:300000,fill:.white))]
    let result=try CropGeometry.applying(.init(x:100,y:200,width:299000,height:298000),to:d);guard case .raster(let s)=result.layers[0].content else{return XCTFail("Raster")};XCTAssertEqual(s.tileCount,0);XCTAssertEqual(s.defaultPixel,.white);XCTAssertEqual(result.alphaChannels?.first?.pixels.tileCount,0);XCTAssertEqual(result.alphaChannels?.first?.pixels.pixel(x:298999,y:297999),.white)
  }
  func testMultipleLargeLayersNoLongerHaveAnAggregate64MegapixelDeleteBudget()throws {
    var d=try sparse(.u16,width:10000,height:10000);var copy=d.layers[0];copy.id=UUID();copy.name="Second";d.layers.append(copy)
    let result=try CropGeometry.applying(.init(x:1,y:2,width:9999,height:9998),to:d);XCTAssertEqual(result.layers.count,2);for layer in result.layers{guard case .raster(let s)=layer.content else{return XCTFail("Raster")};XCTAssertLessThan(s.allocatedBytes,2*1024*1024);XCTAssertEqual(s.width,9999)}
  }
  func testRotatedMaximumSparseSourceClipsOversizeProjectedBoundsBeforePaging()throws {
    let d=try sparse();var request=CropRequest(x:0,y:0,width:300000,height:300000);request.angle=45
    let result=try CropGeometry.applying(request,to:d);guard case .raster(let s)=result.layers[0].content else{return XCTFail("Raster")};XCTAssertEqual(s.width,300000);XCTAssertEqual(s.height,300000);XCTAssertEqual(s.colorEncoding,.linearRGB);XCTAssertLessThan(s.allocatedBytes,2*1024*1024);XCTAssertLessThan(s.tileCount,30);XCTAssertGreaterThan(s.linearPixel(x:150000,y:150000).r,1)
  }
  func testRawMappedExtractionPreservesHiddenHDRAndImplicitSignedZero()throws {
    let fill=Pixel(-0.0,4,-0.25,0.5);var source=try Surface(width:1025,height:150,depth:.f32,fill:fill).interpretingSamples(as:.linearRGB);source.setLinearPixel(x:1023,y:148,Pixel(2,-0.0,0.25,0));source=try source.spillingTiles(to:RasterTileStore())
    let result=try source.cropped(to:.init(x:3,y:4,width:1021,height:145));XCTAssertTrue(result.linearPixel(x:1020,y:144).hasSameBits(as:source.linearPixel(x:1023,y:148)));XCTAssertTrue(result.linearPixel(x:0,y:0).hasSameBits(as:fill));XCTAssertGreaterThan(result.mappedBytes,0)
  }
  func testValidationCancellationAndOwnedIntegerCropVectors()async throws {
    let d=try sparse(.u8);for request in [CropRequest(x:0,y:0,width:300001,height:1),CropRequest(x:0,y:0,width:1,height:0)]{XCTAssertThrowsError(try CropGeometry.applying(request,to:d))}
    let job=Task{try CropGeometry.applying(.init(x:1,y:1,width:299999,height:299999),to:d)};job.cancel();do{_=try await job.value;XCTFail("Cancel")}catch is CancellationError{}catch{XCTFail("Unexpected \(error)")}
    guard let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else{return};var source=try CraftDocument(width:8,height:6),pixels=try Surface(width:8,height:6)
    for y in 0..<6{for x in 0..<8{pixels.setPixel(x:x,y:y,Pixel(Float(x*20)/255,Float(y*30)/255,50.0/255,(x+y)%3==0 ? 64.0/255:1))}};source.layers[0].content = .raster(pixels);var rows:[[String:Any]]=[]
    for x in [-1,2]{for y in [-1,1]{for deleting in [false,true]{var request=CropRequest(x:x,y:y,width:4,height:3);request.deleteCroppedPixels=deleting;let result=try CropGeometry.applying(request,to:source),layer=result.layers[0];guard case .raster(let s)=layer.content else{throw CraftError.invalid("Raster")};var output=try Surface(width:4,height:3);for j in 0..<3{for i in 0..<4{output.setPixel(x:i,y:j,s.pixel(x:i-layer.x,y:j-layer.y))}};rows.append(["x":x,"y":y,"delete":deleting,"rgba":Array(try output.rgbaData(depth:.u8))])}}}
    try FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["width":4,"height":3,"rows":rows],options:[.sortedKeys]).write(to:URL(fileURLWithPath:folder).appendingPathComponent("large-crop-integer-analytical.json"))
  }
  func testMaximumExplicitBackgroundCropStaysOpaqueAndCanvasAligned()throws {
    var source=try CraftDocument(width:300000,height:300000);source.layers[0].background=true;try source.validate()
    let request=CropRequest(x:1,y:1,width:299999,height:299999),result=try CropGeometry.applying(request,to:source);XCTAssertTrue(result.layers[0].isBackground);XCTAssertEqual(result.layers[0].x,0);XCTAssertEqual(result.layers[0].y,0);guard case .raster(let pixels)=result.layers[0].content else{return XCTFail("Background")};XCTAssertEqual(pixels.width,299999);XCTAssertEqual(pixels.height,299999);XCTAssertEqual(pixels.tileCount,0);XCTAssertTrue(try pixels.isOpaque());var retain=request;retain.deleteCroppedPixels=false;XCTAssertThrowsError(try CropGeometry.applying(retain,to:source));XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
  }
  func testExpandedRotatedBackgroundFillsGapsAndPreservesIdentityAllDepths()throws {
    for depth in PixelDepth.allCases {var source=try CraftDocument(width:12,height:8,depth:depth);source.layers[0].background=true;var request=CropRequest(x:-2,y:-2,width:16,height:12);request.angle=15;request.backgroundColor=Pixel(1,0,0);let result=try CropGeometry.applying(request,to:source);XCTAssertEqual(result.layers[0].id,source.layers[0].id);XCTAssertTrue(result.layers[0].isBackground);guard case .raster(let pixels)=result.layers[0].content else{return XCTFail("Background")};XCTAssertTrue(try pixels.isOpaque());XCTAssertEqual(pixels.width,16);XCTAssertEqual(pixels.height,12);XCTAssertEqual(pixels.pixel(x:0,y:0),Pixel(1,0,0));XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)}
  }

}
