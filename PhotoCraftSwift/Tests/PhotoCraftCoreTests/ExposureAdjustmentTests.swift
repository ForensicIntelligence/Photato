import XCTest
@testable import PhotoCraftCore

final class ExposureAdjustmentTests: XCTestCase {
  func testDefaultsRangesLegacyEncodingAndIdentityBits() throws {
    let value=ClassicAdjustment.exposure();try value.validate();XCTAssertTrue(value.isIdentity)
    let p=Pixel(2.5,-0.125,0.375,0.6)
    for depth in PixelDepth.allCases {XCTAssertTrue(ClassicAdjustmentTransfer(value,depth:depth).apply(p).hasSameBits(as:p))}
    for e in [ExposureAdjustment(exposure:20.1),.init(offset:-0.501),.init(gammaCorrection:0),.init(gammaCorrection:10),.init(exposure:.infinity),.init(offset:.nan)] {XCTAssertThrowsError(try e.validate())}
    for kind in ClassicAdjustment.Kind.allCases where kind != .exposure {
      let old=ClassicAdjustment(kind),data=try JSONEncoder().encode(old)
      XCTAssertNil((try JSONSerialization.jsonObject(with:data)as?[String:Any])?["exposureSettings"])
      XCTAssertEqual(try JSONDecoder().decode(ClassicAdjustment.self,from:data),old)
    }
    var bad=ClassicAdjustment(.vibrance);bad.exposureSettings = .init();XCTAssertThrowsError(try bad.validate())
    bad = .init(.exposure);bad.exposureSettings=nil;XCTAssertThrowsError(try bad.validate())
  }
  func testLinearControlsPreserveAlphaHiddenValuesAndHDR() throws {
    let settings=ExposureAdjustment(exposure:1,offset:0.125,gammaCorrection:2)
    let linear=Pixel(0.25,1,4,0.375),encoded=SRGBTransfer.encoded(linear)
    let out=SRGBTransfer.linear(ClassicAdjustmentTransfer(.exposure(settings),depth:.f32).apply(encoded))
    for (actual,expected) in zip([out.r,out.g,out.b],[sqrt(Float(0.625)),sqrt(Float(2.125)),sqrt(Float(8.125))]) {XCTAssertEqual(actual,expected,accuracy:0.000002)}
    XCTAssertEqual(out.a,linear.a);XCTAssertGreaterThan(out.b,1)
    let hidden=Pixel(0.7,0.2,0.9,0)
    XCTAssertTrue(ClassicAdjustmentTransfer(.exposure(settings),depth:.f32).apply(hidden).hasSameBits(as:hidden))
    let q=ClassicAdjustmentTransfer(.exposure(.init(exposure:1)),depth:.u8).apply(Pixel(0.5,0.25,0.1))
    XCTAssertEqual(q.r,Float(pow(2.0*pow(0.5,2.2),1/2.2)),accuracy:0.000001)
    XCTAssertEqual(Adjustment.exposure(1).apply(Pixel(0.5,0.25,0.1)),Pixel(1,0.5,0.2))
    XCTAssertNotEqual(q,Adjustment.exposure(1).apply(Pixel(0.5,0.25,0.1)))
  }
  func testNative67SelectionHistoryAndMaximumSparseDocument() throws {
    var d=try CraftDocument(width:5,height:3,depth:.f32)
    d.layers[0].content = .raster(try Surface(width:5,height:3,depth:.f32,fill:Pixel(0.3,0.4,0.5,0.7)))
    d.selection = .init(x:1,y:0,width:2,height:3)
    let value=ClassicAdjustment.exposure(.init(exposure:0.5,offset:0.02,gammaCorrection:1.1))
    var session=EditorSession(document:d);let layer=try value.layer(in:d)
    XCTAssertEqual(layer.mask?.pixel(x:0,y:0),.black);XCTAssertEqual(layer.mask?.pixel(x:1,y:0),.white)
    try session.execute(.addLayer(layer));XCTAssertEqual(session.document.minimumArchiveVersion,67)
    let data=try NativeArchive.encode(session.document)
    XCTAssertEqual(try NativeArchive.decode(data),session.document)
    XCTAssertEqual(try NativeArchive.decodePaged(data),session.document)
    var downgraded=data;downgraded.replaceSubrange(8..<12,with:[0,0,0,66]);XCTAssertThrowsError(try NativeArchive.decode(downgraded))
    try session.undo();XCTAssertEqual(session.document,d);try session.redo()
    var maximum=try CraftDocument(width:300_000,height:300_000)
    maximum.layers.append(try value.layer(in:maximum));try maximum.validate()
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(maximum)),maximum)
  }
  func testAdjustmentBrushUsesFullControlsWithTransactionalUndo() throws {
    var d=try CraftDocument(width:9,height:7)
    d.layers[0].content = .raster(try Surface(width:9,height:7,fill:Pixel(0.2,0.4,0.6)))
    let value=ClassicAdjustment.exposure(.init(exposure:0.5,offset:0.01,gammaCorrection:1.2))
    var brush=Brush();brush.size=3
    let request=AdjustmentBrushRequest(adjustment:.classic(value),points:[.init(x:4,y:3)],brush:brush)
    XCTAssertEqual(AdjustmentBrushKind(adjustment:request.adjustment),.exposure)
    var session=EditorSession(document:d);try session.execute(.adjustmentBrush(request))
    XCTAssertEqual(session.document.layers.last?.content,.adjustment(.classic(value)))
    try session.undo();XCTAssertEqual(session.document,d);try session.redo()
  }
}
