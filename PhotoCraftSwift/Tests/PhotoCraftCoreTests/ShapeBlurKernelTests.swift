import CoreGraphics
import XCTest
@testable import PhotoCraftCore

final class ShapeBlurKernelTests:XCTestCase {
  func triangle()throws->ShapeBlurKernel {
    try .init(name:"Owned asymmetric triangle",path:VectorPath(components:[.init(knots:[PathPoint(0,0.17),.init(0.91,0),.init(1,1)].map{PathKnot($0)},closed:true)]))
  }
  func settings()throws->ClassicDetailSettings {var s=ClassicDetailSettings(kind:.shapeBlur);s.radius=5;s.kernel=try triangle();return s}
  func testCustomRectangleAgainstIndependentDirectSumsAllDepths()throws {
    let rectangle=VectorPath(components:[.init(knots:[PathPoint(0,0),.init(1,0),.init(1,1),.init(0,1)].map{PathKnot($0)},closed:true)])
    var settings=ClassicDetailSettings(kind:.shapeBlur);settings.radius=5;settings.kernel=try .init(name:"Owned square",path:rectangle)
    // An axis-aligned square fills all121pixel cells. Direct sums are independent
    // of CoreGraphics, run merging, prefix sums and the convolution implementation.
    for depth in PixelDepth.allCases {
      var input=try Surface(width:11,height:9,depth:depth)
      for y in 0..<9 {for x in 0..<11 {input.setPixel(x:x,y:y,Pixel(Float((x*7+y*3)%17)/16,Float(x%5)/4,Float(y%7)/6,Float((x+y)%4)/3))}}
      let output=try ClassicDetailEngine.render(input,kind:.shapeBlur,settings:settings);var expected=input
      for y in 0..<9 {for x in 0..<11 {
        var sum=SIMD4<Double>.zero
        for dy in -5...5 {for dx in -5...5 {
          let xx=min(10,max(0,x-dx)),yy=min(8,max(0,y-dy)),p=depth == .f32 ? input.linearPixel(x:xx,y:yy):input.pixel(x:xx,y:yy)
          sum+=SIMD4(Double(p.r*p.a),Double(p.g*p.a),Double(p.b*p.a),Double(p.a))
        }}
        sum/=121;let p=SIMD4<Float>(Float(sum.x),Float(sum.y),Float(sum.z),Float(sum.w))
        let pixel=p.w>1e-7 ? Pixel(p.x/p.w,p.y/p.w,p.z/p.w,p.w):Pixel(0,0,0,p.w)
        if depth == .f32 {expected.setLinearPixel(x:x,y:y,pixel)}else{expected.setPixel(x:x,y:y,pixel)}
      }}
      XCTAssertEqual(try output.rgbaData(depth:depth),try expected.rgbaData(depth:depth),"\(depth)")
    }
  }
  func photoshopTriangle()throws->ClassicDetailSettings {
    var s=ClassicDetailSettings(kind:.shapeBlur);s.radius=5
    s.kernel=try .init(name:"Photato 446 owned triangle",path:.init(components:[.init(knots:[PathPoint(10,23),.init(83,10),.init(90,90)].map{PathKnot($0)},closed:true)]));return s
  }
  func reference(_ name:String,_ ext:String)throws->Data {
    try Data(contentsOf:XCTUnwrap(Bundle.module.url(forResource:name,withExtension:ext,subdirectory:"Fixtures/ShapeBlurOwned")))
  }
  func captureComparison(_ actual:Data,_ expected:Data,name:String)throws {
    let folder=URL(fileURLWithPath:ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] ?? NSTemporaryDirectory()).appendingPathComponent("shape-blur-"+UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try actual.write(to:folder.appendingPathComponent(name+"-actual.bin"));try expected.write(to:folder.appendingPathComponent(name+"-expected.bin"))
    let differences=zip(actual,expected).filter{$0 != $1}.count
    try JSONSerialization.data(withJSONObject:["reference":"Photoshop2026owned triangle radius5","actualBytes":actual.count,"expectedBytes":expected.count,"differentBytes":differences,"byteIdentical":actual==expected],options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(name+".json"))
  }
  func testPhotoshopOwnedTriangleEightBitReference()throws {
    var input=try Surface(width:100,height:100,depth:.u8,fill:Pixel(0,0,0,1));input.setPixel(x:50,y:50,.white)
    let output=try ClassicDetailEngine.render(input,kind:.shapeBlur,settings:photoshopTriangle()),actual=try output.rgbaData(depth:.u8),expected=try reference("triangle-radius5-rgb8","rgba")
    try captureComparison(actual,expected,name:"RGB8");XCTAssertEqual(actual,expected,"Independent Photoshop RGB8 output remains an exact gate.")
  }
  func testPhotoshopOwnedTriangleFloatReference()throws {
    var input=try Surface(width:100,height:100,depth:.f32,fill:Pixel(0,0,0,1),colorEncoding:.linearRGB);input.setLinearPixel(x:50,y:50,.white)
    let output=try ClassicDetailEngine.render(input,kind:.shapeBlur,settings:photoshopTriangle()),expected=try reference("triangle-radius5-rgb32","planar-be32")
    var actual=Data();actual.reserveCapacity(120000);var badAlpha=0
    for c in 0..<3 {for y in 0..<100 {for x in 0..<100 {
      let p=output.linearPixel(x:x,y:y),v=c==0 ? p.r:c==1 ? p.g:p.b
      if p.a.bitPattern != Float(1).bitPattern {badAlpha+=1}
      var word=v.bitPattern.bigEndian;withUnsafeBytes(of:&word){actual.append(contentsOf:$0)}
    }}}
    XCTAssertEqual(badAlpha,0);try captureComparison(actual,expected,name:"RGB32")
    XCTAssertEqual(actual,expected,"Independent Photoshop Float32 words remain an exact gate.")
  }
  func testSettingsRoundTripOldNilEncodingAndStrictNestedAPI()throws {
    let old=ClassicDetailSettings(kind:.shapeBlur),oldData=try JSONEncoder().encode(old)
    XCTAssertFalse(String(decoding:oldData,as:UTF8.self).contains("kernel"))
    XCTAssertEqual(try JSONDecoder().decode(ClassicDetailSettings.self,from:oldData),old)
    let s=try settings(),data=try JSONSerialization.data(withJSONObject:s.apiParameters(kind:.shapeBlur))
    XCTAssertEqual(try ClassicDetailSettings.decodeJSON(data,kind:.shapeBlur),s)
    var raw=s.apiParameters(kind:.shapeBlur),kernel=raw["kernel"] as! [String:Any],path=kernel["path"] as! [String:Any]
    path["unknown"]=true;kernel["path"]=path;raw["kernel"]=kernel
    XCTAssertThrowsError(try ClassicDetailSettings.decodeJSON(JSONSerialization.data(withJSONObject:raw),kind:.shapeBlur))
    var incompatible=s;incompatible.shape = .heart;XCTAssertThrowsError(try incompatible.validate(kind:.shapeBlur))
    XCTAssertThrowsError(try s.validate(kind:.radialBlur))
  }
  func testBooleanHoleAspectAndInvalidGeometry()throws {
    func box(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ operation:PathOperation = .combine)->PathComponent {
      .init(knots:[PathPoint(x,y),.init(x+w,y),.init(x+w,y+h),.init(x,y+h)].map{PathKnot($0)},closed:true,operation:operation)
    }
    let kernel=try ShapeBlurKernel(name:"Owned frame",path:.init(components:[box(10,20,20,10),box(15,22,10,6,.subtract)]))
    let scaled=try kernel.scaledPath(radius:10)
    XCTAssertEqual(scaled.boundingBoxOfPath.width,20,accuracy:1e-9);XCTAssertEqual(scaled.boundingBoxOfPath.height,10,accuracy:1e-9)
    XCTAssertFalse(scaled.contains(.zero));XCTAssertTrue(scaled.contains(CGPoint(x:8,y:0)))
    let preview=try VectorPathGeometry.filledPath(kernel.previewPath()).boundingBoxOfPath;XCTAssertEqual(preview.width,1,accuracy:1e-12);XCTAssertEqual(preview.height,0.5,accuracy:1e-12);XCTAssertEqual(preview.minY,0.25,accuracy:1e-12)
    XCTAssertThrowsError(try ShapeBlurKernel(name:"Empty",path:.init()))
    XCTAssertThrowsError(try ShapeBlurKernel(name:"Outside",path:.init(components:[box(0,0,1,1)],inverted:true)))
    XCTAssertThrowsError(try ShapeBlurKernel(name:"",path:kernel.path))
    var invalid=kernel;invalid.path.components[0].knots[0].anchor.x = .infinity;XCTAssertThrowsError(try invalid.validate())
  }
  func testCustomBudgetAndCancellationLeaveInputUnchanged()async throws {
    let input=try Surface(width:17,height:13,fill:Pixel(0.2,0.4,0.6,0.5)),s=try settings(),original=input
    let worker=Task {try Task.checkCancellation();return try ClassicDetailEngine.render(input,kind:.shapeBlur,settings:s)};worker.cancel()
    do{_ = try await worker.value;XCTFail("Expected cancellation")}catch is CancellationError{}catch{XCTFail("\(error)")}
    XCTAssertEqual(input,original)
    var complex=s;let points=(0..<100).map{n in PathKnot(PathPoint(cos(Double(n)*0.0628),sin(Double(n)*0.0628)))}
    complex.kernel=try ShapeBlurKernel(name:"Complex",path:.init(components:[.init(knots:points,closed:true)]));complex.radius=1000
    XCTAssertThrowsError(try ClassicDetailEngine.render(input,kind:.shapeBlur,settings:complex))
  }
}
