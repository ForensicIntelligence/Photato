import XCTest
import PhotoCraftCore

final class SelectionTransformTests:XCTestCase {
  func source()throws->SelectionMask {let w=10,h=8;return try SelectionMask(width:w,height:h,bytes:(0..<(w*h)).map{i in let x=i%w,y=i/w;return x>=2 && x<8 && y>=2 && y<6 ? UInt8((x*17+y*29)%256):0})}
  func testGridTranslationFlipsAndQuarterTurnsPreserveCoverage()throws {
    let mask=try source(),w=mask.width,h=mask.height
    for transform in [Transform2D.translation(1,1),Transform2D(a:-1,d:1,tx:Double(w)),Transform2D(a:1,d:-1,ty:Double(h)),Transform2D(a:0,b:1,c:-1,d:0,tx:Double(h))] {
      let inverse=try transform.inverted(),out=try SelectionTransform.apply(mask,projection:.init(transform))
      let expected=(0..<(w*h)).map{i->UInt8 in let p=inverse.point(Double(i%w)+0.5,Double(i/w)+0.5),x=Int(floor(p.x)),y=Int(floor(p.y));return x>=0 && y>=0 && x<w && y<h ? mask.byte(at:y*w+x):0}
      XCTAssertEqual(try out.bytes,expected)
    }
  }
  func testBilinearHalfPixelUsesNumericGrayAndZeroExterior()throws {
    let mask=try SelectionMask(width:4,height:3,bytes:Array(repeating:[UInt8(0),128,255,64],count:3).flatMap{$0})
    let out=try SelectionTransform.apply(mask,projection:.init(.translation(0.5,0)),interpolation:.bilinear)
    XCTAssertEqual(try out.bytes,Array(repeating:[UInt8(0),64,192,160],count:3).flatMap{$0})
  }
  func testQuadProjectionMapsCornersAndRetainsNonAffineGeometry()throws {
    let bounds=IntRect(x:2,y:3,width:12,height:8),corners:[PathPoint]=[.init(1,2),.init(17,1),.init(15,14),.init(3,12)]
    let matrix=try SelectionTransform.projection(bounds:bounds,corners:corners),original:[PathPoint]=[.init(2,3),.init(14,3),.init(14,11),.init(2,11)]
    XCTAssertNil(try matrix.affineValue());for i in 0..<4 {let p=try matrix.point(original[i].x,original[i].y);XCTAssertEqual(p.x,corners[i].x,accuracy:1e-8);XCTAssertEqual(p.y,corners[i].y,accuracy:1e-8)}
    let mask=try SelectionMask.make(.rectangle(bounds),width:24,height:20),out=try SelectionTransform.apply(mask,projection:matrix,interpolation:.bilinear);XCTAssertNotNil(out.bounds);XCTAssertTrue(try out.bytes.contains{$0>0 && $0<255})
  }
  func testAllInterpolationModesCapturedForIndependentReader()throws {
    let mask=try source(),programs:[(ProjectiveTransform,Resampling)]=[(.init(.translation(1,1)),.nearest),(.init(Transform2D(a:-1,d:1,tx:10)),.nearest),(.init(.translation(0.5,0)),.bilinear),(try .init([1,0,1,0,1,0,0.01,0,1]),.nearest)]
    var rows:[[String:Any]]=[]
    for (matrix,method) in programs {let out=try SelectionTransform.apply(mask,projection:matrix,interpolation:method);rows.append(["matrix":matrix.values,"interpolation":method.rawValue,"bytes":try out.bytes.map{Int($0)}])}
    let cubic=try SelectionTransform.apply(mask,projection:.init(.translation(0.3,0.4)),interpolation:.bicubic);XCTAssertNotEqual(cubic,try SelectionTransform.apply(mask,projection:.init(.translation(0.3,0.4)),interpolation:.nearest))
    if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:["width":10,"height":8,"rows":rows],options:.sortedKeys).write(to:url.appendingPathComponent("selection-transform-analytical.json"))}
  }
  func testFullCanvasAndOutOfCanvasClipping()throws {
    let full=try SelectionMask.make(.rectangle(.init(x:0,y:0,width:8,height:6)),width:8,height:6,antiAlias:false)
    let shifted=try SelectionTransform.apply(full,projection:.init(.translation(1,0)),interpolation:.nearest)
    XCTAssertEqual(shifted.bounds,.init(x:1,y:0,width:7,height:6));XCTAssertEqual(shifted.coverage(x:0,y:2),0);XCTAssertEqual(shifted.coverage(x:7,y:2),1)
    XCTAssertNil(try SelectionTransform.apply(full,projection:.init(.translation(100,100))).bounds)
  }
  func testSparseMaximumDimensionsUseTiledProjectiveSupport()throws {
    let mask=try SelectionMask.make(.rectangle(.init(x:64,y:64,width:12,height:10)),width:300_000,height:300_000,antiAlias:false)
    let matrix=try ProjectiveTransform([1,0,10,0,1,12,0.00001,0,1]),out=try SelectionTransform.apply(mask,projection:matrix,interpolation:.bilinear)
    XCTAssertTrue(out.isPaged);XCTAssertNotNil(out.bounds);XCTAssertLessThan(out.allocatedBytes,1_048_576)
  }
  func testHistoryActionsArchivesAndLayerPreservation()throws {
    var original=try CraftDocument(width:10,height:8);original.setCoverageSelection(try source());let matrix=ProjectiveTransform(.translation(1,1));var session=EditorSession(document:original)
    try session.startActionRecording(name:"Transform selection");try session.execute(SelectionTransform.command(in:original,projection:matrix))
    XCTAssertEqual(session.undoStack.last?.label,"Transform Selection");XCTAssertEqual(session.document.layers,original.layers)
    var replay=original;try XCTUnwrap(session.actionRecording?.snapshot).apply(to:&replay);XCTAssertTrue(replay==session.document);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(session.document))==session.document)
    let result=session.document;try session.undo();XCTAssertTrue(session.document==original);try session.redo();XCTAssertTrue(session.document==result)
  }
  func testInvalidQuadHorizonAndCancellation()async throws {
    XCTAssertThrowsError(try SelectionTransform.projection(bounds:.init(x:0,y:0,width:8,height:8),corners:[.init(0,0),.init(8,8),.init(8,0),.init(0,8)]))
    let mask=try source(),horizon=try ProjectiveTransform([1,0,0,0,1,0,1,0,-5]);XCTAssertThrowsError(try SelectionTransform.apply(mask,projection:horizon))
    XCTAssertThrowsError(try SelectionTransform.command(in:CraftDocument(width:4,height:4),projection:.identity))
    let task=Task {while !Task.isCancelled{await Task.yield()};return try SelectionTransform.apply(mask,projection:.identity)};task.cancel();do{_=try await task.value;XCTFail("Cancelled transform completed")}catch{XCTAssertTrue(error is CancellationError)}
  }
}
