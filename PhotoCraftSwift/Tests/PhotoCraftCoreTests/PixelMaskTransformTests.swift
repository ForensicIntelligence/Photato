import XCTest
@testable import PhotoCraftCore

final class PixelMaskTransformTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument{
    var d=try CraftDocument(width:20,height:16,depth:depth),mask=try Surface(width:8,height:6,depth:depth,fill:.black)
    for y in 0..<6{for x in 0..<8{let v=Float(10+x*17+y*13)/255;mask.setPixel(x:x,y:y,Pixel(v,v,v))}}
    d.layers[0].mask=mask;var p=MaskProperties();p.linked=false;d.layers[0].maskProperties=p;return d
  }
  func testGridTransformsPreserveThreeDepthsRawValuesAndLayerContent()throws{
    for depth in PixelDepth.allCases{let original=try fixture(depth),id=original.layers[0].id
      for matrix in [Transform2D.translation(-3,4),.init(a:-1,d:1,tx:8),.init(a:0,b:1,c:-1,d:0,tx:6)]{var d=original;try Command.transformPixelMask(.init(layerID:id,matrix:.init(matrix))).apply(to:&d);let layer=d.layers[0],mask=try XCTUnwrap(layer.mask),source=try XCTUnwrap(original.layers[0].mask),inverse=try matrix.inverted(),origin=layer.maskCoordinateTransform
        for y in 0..<mask.height{for x in 0..<mask.width{let p=origin.point(Double(x)+0.5,Double(y)+0.5),q=inverse.point(p.x,p.y);XCTAssertEqual(mask.pixel(x:x,y:y),source.pixel(x:Int(floor(q.x)),y:Int(floor(q.y))))}}
        var unchanged=layer;unchanged.mask=original.layers[0].mask;unchanged.maskProperties=original.layers[0].maskProperties;XCTAssertEqual(unchanged,original.layers[0]);try d.validate()
      }
    }
    var raw=try fixture(.f32);raw.layers[0].mask?.setPixel(x:2,y:2,Pixel(-0.0,-0.0,-0.0));try Command.transformPixelMask(.init(layerID:raw.layers[0].id,matrix:.init(.translation(1,0)))).apply(to:&raw);XCTAssertEqual(raw.layers[0].mask?.pixel(x:2,y:2).r.bitPattern,Float(-0.0).bitPattern)
  }
  func testProjectiveModesPreserveOutsideDensityFeatherInversionAndPlacement()throws{
    var source=try fixture(.u16);source.layers[0].x=3;source.layers[0].y = -2;source.layers[0].affine = .rotation(10);var p=source.layers[0].effectiveMaskProperties;p.transform = .translation(-1,4);p.outside=0.6;p.enabled=false;p.inverted=true;p.density=0.7;p.feather=2;source.layers[0].maskProperties=p
    for method in Resampling.allCases{var d=source;try Command.transformPixelMask(.init(layerID:d.layers[0].id,matrix:try .init([1,0.1,2,0.1,1,-1,0.005,0.002,1]),interpolation:method)).apply(to:&d);var properties=d.layers[0].effectiveMaskProperties;properties.transform=p.transform;XCTAssertEqual(properties,p);XCTAssertEqual(d.layers[0].content,source.layers[0].content);XCTAssertEqual(d.layers[0].coordinateTransform,source.layers[0].coordinateTransform);XCTAssertEqual(d.layers[0].mask?.depth,.u16);try d.validate()}
  }
  func testBilinearScalarSamplingUsesExteriorAndNoColorTransfer()throws{
    var d=try fixture(.f32),s=try Surface(width:2,height:2,depth:.f32,fill:.black);s.setPixel(x:0,y:0,Pixel(0.2,0.2,0.2));s.setPixel(x:1,y:0,Pixel(0.8,0.8,0.8));s.setPixel(x:0,y:1,Pixel(0.4,0.4,0.4));s.setPixel(x:1,y:1,.white);d.layers[0].mask=s;d.layers[0].maskProperties?.outside=0.6
    try Command.transformPixelMask(.init(layerID:d.layers[0].id,matrix:.init(.scale(2,2)),interpolation:.bilinear)).apply(to:&d);let out=try XCTUnwrap(d.layers[0].mask);XCTAssertEqual(out.pixel(x:1,y:1).r,0.4,accuracy:1e-6);XCTAssertEqual(out.pixel(x:0,y:0).r,0.375,accuracy:1e-6);XCTAssertEqual(out.pixel(x:0,y:0).a,1)
  }
  func testInvalidContextsAndHorizonFailAtomically()throws{
    let source=try fixture(),id=source.layers[0].id
    for context in 0..<5{var d=source;switch context{case 0:d.layers[0].maskProperties?.linked=true;case 1:d.selection = .init(x:0,y:0,width:2,height:2);case 2:d.layers[0].protection = .position;case 3:d.layers[0].protection = .image;default:d.layers[0].mask=nil;d.layers[0].maskProperties=nil};let before=d;XCTAssertFalse(PixelMaskTransform.available(d,layerID:id));XCTAssertThrowsError(try Command.transformPixelMask(.init(layerID:id,matrix:.init(.translation(1,0)))).apply(to:&d));XCTAssertEqual(d,before)}
    for matrix in [try ProjectiveTransform([1,0,0,0,1,0,1,0,-4]),ProjectiveTransform(.scale(100000,100000))]{var d=source;XCTAssertThrowsError(try Command.transformPixelMask(.init(layerID:id,matrix:matrix)).apply(to:&d));XCTAssertEqual(d,source)}
  }
  func testHistorySemanticActionsAndStalePreparedPreserveTargets()throws{
    let source=try fixture(),id=source.layers[0].id;var session=EditorSession(document:source);try session.startActionRecording(name:"Mask");let command=Command.transformPixelMask(.init(layerID:id,matrix:.init(.translation(-4,2))));try session.execute(command);let result=session.document;XCTAssertEqual(session.undoStack.count,1);XCTAssertEqual(session.undoStack.last?.label,"Free Transform");var replay=source;try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&replay);XCTAssertEqual(replay,result);try session.undo();XCTAssertEqual(session.document,source);try session.redo();XCTAssertEqual(session.document,result)
    let edit=try PreparedEdit(command:command,document:source);var stale=EditorSession(document:source);try stale.execute(.renameLayer(id,"Changed"));let before=stale.document;XCTAssertThrowsError(try stale.executePrepared(edit));XCTAssertEqual(stale.document,before)
  }
  func testSparseMaximumPlaneAndConstantExteriorRemainBounded()throws{
    for outside:Float in [0,1]{var d=try CraftDocument(width:300000,height:300000),mask=try Surface(width:300000,height:300000,fill:Pixel(outside,outside,outside));mask.setPixel(x:65,y:65,Pixel(1-outside,1-outside,1-outside));d.layers[0].mask=mask;var p=MaskProperties();p.linked=false;p.outside=outside;d.layers[0].maskProperties=p;try Command.transformPixelMask(.init(layerID:d.layers[0].id,matrix:.init(.translation(16,32)),interpolation:.nearest)).apply(to:&d);XCTAssertEqual(d.layers[0].mask?.width,300000);XCTAssertEqual(d.layers[0].mask?.pixel(x:65,y:65).r,1-outside);XCTAssertLessThan(try XCTUnwrap(d.layers[0].mask).allocatedBytes,2_097_152);XCTAssertEqual(d.layers[0].maskCoordinateTransform.tx,16)}
  }
  func testIdentityAndCancellationPublishNothing()async throws{
    let source=try fixture(.f32);var session=EditorSession(document:source);try session.execute(.transformPixelMask(.init(layerID:source.layers[0].id,matrix:.identity)));XCTAssertEqual(session.document,source);XCTAssertTrue(session.undoStack.isEmpty)
    let task=Task{while !Task.isCancelled{await Task.yield()};var d=source;try Command.transformPixelMask(.init(layerID:d.layers[0].id,matrix:.init(.translation(1,0)))).apply(to:&d)};task.cancel();do{try await task.value;XCTFail("Canceled mask transform committed")}catch{XCTAssertTrue(error is CancellationError)}
  }
  func testAnalyticalMaskOutputsCapturedForIndependentReader()throws{
    var rows:[[String:Any]]=[]
    for matrix in [ProjectiveTransform(.translation(-3,4)),.init(.init(a:-1,d:1,tx:8)),.init(.init(a:0,b:1,c:-1,d:0,tx:6)),try .init([1,0,1,0,1,-1,0.05,0.02,1])]{var d=try fixture();try Command.transformPixelMask(.init(layerID:d.layers[0].id,matrix:matrix,interpolation:.nearest)).apply(to:&d);let l=d.layers[0],mask=try XCTUnwrap(l.mask);var values:[Int]=[];for y in 0..<mask.height{for x in 0..<mask.width{values.append(Int((mask.pixel(x:x,y:y).r*255).rounded()))}};rows.append(["matrix":matrix.values,"width":mask.width,"height":mask.height,"x":l.maskCoordinateTransform.tx,"y":l.maskCoordinateTransform.ty,"values":values])}
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["sourceWidth":8,"sourceHeight":6,"rows":rows],options:.sortedKeys).write(to:dir.appendingPathComponent("mask-transform-analytical.json"))}
  }
}
