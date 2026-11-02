import XCTest
@testable import PhotoCraftCore

final class ProjectiveLayerTransformTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument{try LayerCollectionTransformTests().fixture(depth)}
  func projection()throws->ProjectiveTransform{try .init([1,0.1,2,0.05,1,1,0.01,0.005,1])}
  func testHomogeneousCompositionMatchesIndependentPointArithmetic()throws {
    // Retained rendering keeps the established projective sampling arithmetic.
    // Compare actual HDR channel words, not Surface backing-store identities.
    var pixels=try Surface(width:8,height:6,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<6{for x in 0..<8{pixels.setLinearPixel(x:x,y:y,Pixel(Float(x)*0.21-0.1,Float(y)*0.3,Float(x+y)*0.12,0.2+Float((x+y)%4)*0.2))}}
    let projection=try self.projection(),mapping=try ProjectiveRaster.mapping(projection,width:8,height:6,transform:.identity)
    for method in Resampling.allCases{let old=try WarpRaster.render(pixels,using:mapping,method:method),paged=try ProjectiveRaster.renderPaged(pixels,placement:projection,bounds:mapping.bounds,method:method)
      for y in 0..<old.height{for x in 0..<old.width{let a=old.linearPixel(x:x,y:y),b=paged.linearPixel(x:x,y:y);XCTAssertEqual([a.r,a.g,a.b,a.a].map(\.bitPattern),[b.r,b.g,b.b,b.a].map(\.bitPattern))}}
    }
    let a=try self.projection(),b=try ProjectiveTransform([1,0.2,3,0,1,-2,0.002,0.001,1]),c=try a.followed(by:b)
    for y in stride(from:0.5,through:30.5,by:3){for x in stride(from:0.5,through:40.5,by:4){let p=try a.point(x,y),q=try b.point(p.x,p.y),z=try c.point(x,y);XCTAssertEqual(z.x,q.x,accuracy:1e-10);XCTAssertEqual(z.y,q.y,accuracy:1e-10)}}
  }
  func testInversePlacementThreeDepthsAndInterpolationRetainGeometryAndProfile()throws {
    for depth in PixelDepth.allCases{for method in Resampling.allCases {let source=try fixture(depth),p=try projection();var d=source;try Command.transformLayers(.init(layerIDs:d.layers.map(\.id),projection:p,interpolation:method)).apply(to:&d);try d.validate();XCTAssertEqual(d.layers.map(\.id),source.layers.map(\.id));XCTAssertEqual(d.workingICC,source.workingICC);for i in d.layers.indices{guard case .raster(let output)=d.layers[i].content,case .raster(let input)=source.layers[i].content else{return XCTFail()};XCTAssertEqual(output.depth,depth);let full=try p.preceded(by:source.layers[i].coordinateTransform),inverse=try full.inverted();for y in 0..<output.height{for x in 0..<output.width{let q=try inverse.point(Double(d.layers[i].x+x)+0.5,Double(d.layers[i].y+y)+0.5),inside=q.x>=0 && q.y>=0 && q.x<Double(input.width) && q.y<Double(input.height);if inside && method == .nearest{XCTAssertEqual(output.pixel(x:x,y:y),input.pixel(x:Int(floor(q.x)),y:Int(floor(q.y))))};if !inside{XCTAssertEqual(output.pixel(x:x,y:y).a,0)}}}}}}
  }
  func testLinkedAndUnlinkedRawMaskControlsStayIndependent()throws {
    for depth in PixelDepth.allCases{for linked in [false,true]{var source=try fixture(depth),mask=try Surface(width:3,height:2,depth:depth,fill:.white);mask.setPixel(x:1,y:1,.black);source.layers[0].mask=mask;var props=MaskProperties();props.linked=linked;props.enabled=false;props.inverted=true;props.density=0.7;props.feather=2;props.outside=0.25;source.layers[0].maskProperties=props;var d=source;try Command.transformLayers(.init(layerIDs:d.layers.map(\.id),projection:projection(),interpolation:.nearest)).apply(to:&d);let out=d.layers[0].effectiveMaskProperties;XCTAssertEqual(out.enabled,false);XCTAssertEqual(out.inverted,true);XCTAssertEqual(out.linked,linked);XCTAssertEqual(out.density,props.density);XCTAssertEqual(out.feather,props.feather);XCTAssertEqual(out.outside,props.outside);if !linked{XCTAssertEqual(d.layers[0].mask,mask);XCTAssertEqual(d.layers[0].maskCoordinateTransform,source.layers[0].maskCoordinateTransform)}else{XCTAssertNotEqual(d.layers[0].maskCoordinateTransform,source.layers[0].maskCoordinateTransform)}}}
  }
  func testSmartSourcesRemainIntactAcrossRepeatedProjectiveAndAffineEdits()throws {
    var source=try fixture(.f32);guard case .raster(let pixels)=source.layers[0].content else{return XCTFail()};source.layers[0].smartObject=try SmartObject(fileName:"owned.png",mediaType:"image/png",data:Data([1,2,3]),width:pixels.width,height:pixels.height);let before=source.layers[0],p=try projection();var d=source
    for _ in 0..<2{try Command.transformLayers(.init(layerIDs:d.layers.map(\.id),projection:p,interpolation:.nearest)).apply(to:&d)}
    XCTAssertEqual(d.layers[0].content,before.content);XCTAssertEqual(d.layers[0].smartObject,before.smartObject);let q=try p.preceded(by:before.coordinateTransform).followed(by:p),a=try XCTUnwrap(d.layers[0].sourceProjection).point(1,1),b=try q.point(1,1);XCTAssertEqual(a.x,b.x,accuracy:1e-10);XCTAssertEqual(a.y,b.y,accuracy:1e-10);try Command.transformLayers(.init(layerIDs:d.layers.map(\.id),matrix:.translation(3,2))).apply(to:&d);XCTAssertEqual(d.layers[0].content,before.content);XCTAssertNoThrow(try WarpRaster.baked(d.layers[0],in:d))
  }
  func testParentChildRootsMapOnceWithGroupAndLayerMasks()throws {
    var source=try fixture();try Command.groupLayers(source.layers.map(\.id),"Group").apply(to:&source);let parent=try XCTUnwrap(source.activeLayerID),child=source.layers.first{!$0.isGroup}!.id;source.layers[source.layers.firstIndex{$0.id==parent}!].mask=try Surface(width:20,height:16,fill:.white)
    let p=try projection();var a=source,b=source;try Command.transformLayers(.init(layerIDs:[parent,child],projection:p,interpolation:.nearest)).apply(to:&a);try Command.transformLayers(.init(layerIDs:[parent],projection:p,interpolation:.nearest)).apply(to:&b);XCTAssertEqual(a,b);XCTAssertEqual(a.layers.map(\.parentID),source.layers.map(\.parentID));XCTAssertEqual(a.layers.map(\.id),source.layers.map(\.id))
  }
  func testUnsupportedTargetsAndSourceHorizonsFailWithoutPartialPublication()throws {
    for kind in 0..<6{var d=try fixture();switch kind{case 0:d.layers[1].protection = .position;case 1:d.layers[1].content = .text(.init(text:"Owned",fontName:"HelveticaNeue",size:12,color:.black));case 2:d.layers[1].content = .shape(.init(kind:.rectangle,width:4,height:3,color:.white));case 3:d.layers[1].vectorMask=VectorMask();case 4:d.selection = .init(x:0,y:0,width:2,height:2);default:d.layers[1].protection = .image};let before=d;XCTAssertFalse(ProjectiveLayerTransform.available(d,layerIDs:d.layers.map(\.id)));XCTAssertThrowsError(try Command.transformLayers(.init(layerIDs:d.layers.map(\.id),projection:projection())).apply(to:&d));XCTAssertEqual(d,before)}
    for gap in [false,true]{var d=try fixture();if gap{d.layers[1].x=15};let before=d;XCTAssertThrowsError(try Command.transformLayers(.init(layerIDs:d.layers.map(\.id),projection:ProjectiveTransform([1,0,0,0,1,0,-0.1,0,1]))).apply(to:&d));XCTAssertEqual(d,before)}
  }
  func testOneHistoryPortableProjectiveActionsCancellationAndAffineCompatibility()async throws {
    let source=try fixture(),p=try projection();var s=EditorSession(document:source);try s.startActionRecording(name:"Perspective");try s.execute(.transformLayers(.init(layerIDs:source.layers.map(\.id),projection:p,interpolation:.nearest)));XCTAssertEqual(s.undoStack.count,1);var replay=source;try XCTUnwrap(s.actionRecording?.snapshot).apply(to:&replay);XCTAssertEqual(replay,s.document);try s.undo();XCTAssertEqual(s.document,source);try s.redo();XCTAssertEqual(s.document,replay)
    var a=source,b=source;let affine=Transform2D.translation(2,3);try Command.transformLayers(.init(layerIDs:a.layers.map(\.id),projection:.init(affine))).apply(to:&a);try Command.transformLayers(.init(layerIDs:b.layers.map(\.id),matrix:affine)).apply(to:&b);XCTAssertEqual(a,b)
    let task=Task{while !Task.isCancelled{await Task.yield()};var d=source;try Command.transformLayers(.init(layerIDs:d.layers.map(\.id),projection:p)).apply(to:&d)};task.cancel();do{try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
  }
  func testSparseMaximumDimensionsProjectWithoutDenseCoordinateGrid()throws {
    var d=try CraftDocument(width:300000,height:300000),pixels=try Surface(width:300000,height:300000);pixels.setPixel(x:65,y:65,.white);let layer=Layer(name:"Large",content:.raster(pixels));d.layers=[layer];d.activeLayerID=layer.id;try Command.transformLayers(.init(layerIDs:[layer.id],projection:ProjectiveTransform([1,0,0,0,1,0,0.0000001,0,1]),interpolation:.nearest)).apply(to:&d);guard case .raster(let out)=d.layers[0].content else{return XCTFail()};XCTAssertEqual(out.height,300000);XCTAssertGreaterThan(out.width,290000);XCTAssertLessThan(out.allocatedBytes,2_097_152);XCTAssertEqual(out.pixel(x:65,y:65),.white)
  }
}
