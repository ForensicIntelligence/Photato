import XCTest
@testable import PhotoCraftCore

final class DistortionTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8) throws -> Surface {
    var s=try Surface(width:5,height:4,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<4 {for x in 0..<5 {
      let p=Pixel(Float(x)/4,Float(y)/3,Float((x+y)%3)/2)
      if depth == .f32 {s.setLinearPixel(x:x,y:y,p)} else {s.setPixel(x:x,y:y,p)}
    }};return s
  }
  func testDisplaceIntegerCoordinatesBothChannelsAndEdges() throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(depth);var s=DistortionSettings(kind:.displace)
      s.horizontalScale=100;s.verticalScale=100;s.map = .init(width:1,height:1,channels:2,samples:Data([129,127]))
      for edge in DistortionSettings.Edge.allCases {
        s.edge=edge;let output=try DistortionEngine.render(source,kind:.displace,settings:s)
        for y in 0..<4 {for x in 0..<5 {
          let sx=edge == .wrapAround ? (x+1)%5:min(4,x+1),sy=edge == .wrapAround ? (y+3)%4:max(0,y-1)
          let expected:Pixel=edge == .transparent && (x+1>=5 || y-1<0) ? .clear:source.pixel(x:sx,y:sy)
          XCTAssertEqual(output.pixel(x:x,y:y),expected,"\(depth) \(edge) \(x),\(y)")
        }}
      }
      s.map = .init(width:1,height:1,channels:1,samples:Data([128]))
      XCTAssertEqual(try DistortionEngine.render(source,kind:.displace,settings:s),source)
      s.map = .init(width:1,height:1,channels:1,samples:Data([129]));s.edge = .repeatEdge
      let mono=try DistortionEngine.render(source,kind:.displace,settings:s)
      XCTAssertEqual(mono.pixel(x:1,y:1),source.pixel(x:2,y:2))
    }
  }
  func testMapTilingStretchAndPremultipliedHDRSampling() throws {
    var s=DistortionSettings(kind:.displace);s.horizontalScale=100;s.verticalScale=0
    s.map = .init(width:2,height:1,channels:1,samples:Data([128,130]))
    s.fit = .tile;let tile=try DistortionEngine.Mapping(.displace,s,8,4)
    XCTAssertEqual(tile.point(0.5,0.5).0,0.5);XCTAssertEqual(tile.point(1.5,0.5).0,3.5);XCTAssertEqual(tile.point(2.5,0.5).0,2.5)
    s.fit = .stretchToFit;let stretch=try DistortionEngine.Mapping(.displace,s,8,4)
    XCTAssertEqual(stretch.point(0.5,0.5).0,0.5);XCTAssertEqual(stretch.point(3.5,0.5).0,4.25)
    var source=try Surface(width:2,height:1,depth:.f32,colorEncoding:.linearRGB)
    source.setLinearPixel(x:0,y:0,Pixel(3,0,0,1));source.setLinearPixel(x:1,y:0,Pixel(0,0,8,0))
    s.horizontalScale=50;s.map = .init(width:1,height:1,channels:1,samples:Data([129]))
    let output=try DistortionEngine.render(source,kind:.displace,settings:s).linearPixel(x:0,y:0)
    XCTAssertEqual(output.r,3);XCTAssertEqual(output.b,0);XCTAssertEqual(output.a,0.5)
  }
  func testShearCurveKnotsAndKnownTranslation() throws {
    let points:[DistortionSettings.Point]=[.init(0,-0.5),.init(0.2,0.7),.init(0.8,-0.1),.init(1,0.3)]
    for p in points {XCTAssertEqual(DistortionEngine.curve(points,at:p.position),p.offset,accuracy:1e-12)}
    XCTAssertEqual(DistortionEngine.curve(points,at:-1),-0.5);XCTAssertEqual(DistortionEngine.curve(points,at:2),0.3)
    let source=try fixture();var s=DistortionSettings(kind:.shear);s.points=[.init(0,0.4),.init(1,0.4)]
    let output=try DistortionEngine.render(source,kind:.shear,settings:s)
    for y in 0..<4 {for x in 0..<5 {XCTAssertEqual(output.pixel(x:x,y:y),source.pixel(x:(x+4)%5,y:y))}}
  }
  func testAnalyticRadialAndPolarCoordinates() throws {
    var s=DistortionSettings(kind:.twirl);s.angle=90
    var p=try DistortionEngine.Mapping(.twirl,s,8,8).point(6,4)
    XCTAssertEqual(p.0,4+sqrt(2),accuracy:1e-12);XCTAssertEqual(p.1,4+sqrt(2),accuracy:1e-12)
    s = .init(kind:.pinch);s.amount=100;p=try DistortionEngine.Mapping(.pinch,s,8,8).point(6,4)
    XCTAssertEqual(p.0,4+2*sqrt(2),accuracy:1e-12);XCTAssertEqual(p.1,4)
    s = .init(kind:.spherize);s.amount=100;p=try DistortionEngine.Mapping(.spherize,s,8,8).point(6,4)
    XCTAssertEqual(p.0,4+4.0/3,accuracy:1e-12);XCTAssertEqual(p.1,4)
    s.sphereMode = .horizontalOnly;p=try DistortionEngine.Mapping(.spherize,s,8,8).point(6,1)
    XCTAssertEqual(p.0,4+4.0/3,accuracy:1e-12);XCTAssertEqual(p.1,1)
    s.sphereMode = .verticalOnly;p=try DistortionEngine.Mapping(.spherize,s,8,8).point(1,6)
    XCTAssertEqual(p.0,1);XCTAssertEqual(p.1,4+4.0/3,accuracy:1e-12)
    s = .init(kind:.polarCoordinates);p=try DistortionEngine.Mapping(.polarCoordinates,s,8,8).point(4,2)
    XCTAssertEqual(p.0,0);XCTAssertEqual(p.1,4)
    s.polarMode = .polarToRectangular;p=try DistortionEngine.Mapping(.polarCoordinates,s,8,8).point(0,4)
    XCTAssertEqual(p.0,4);XCTAssertEqual(p.1,2)
    s = .init(kind:.zigzag);s.amount=100;s.ridges=1;s.zigzagStyle = .outFromCenter
    p=try DistortionEngine.Mapping(.zigzag,s,8,8).point(5,4);XCTAssertEqual(p.0,5.75,accuracy:1e-12);XCTAssertEqual(p.1,4)
    for kind in [RasterFilter.Kind.twirl,.pinch,.spherize,.zigzag] {
      let source=try fixture(),out=try DistortionEngine.render(source,kind:kind,settings:.init(kind:kind))
      XCTAssertEqual(out.pixel(x:0,y:0),source.pixel(x:0,y:0));XCTAssertEqual(out.pixel(x:4,y:3),source.pixel(x:4,y:3))
    }
  }
  func testWaveSeedAllGeneratorsTypesAndAxisScales() throws {
    let source=try fixture();var s=DistortionSettings(kind:.wave);s.generators=999;s.edge = .wrapAround
    let first=try DistortionEngine.render(source,kind:.wave,settings:s)
    XCTAssertEqual(first,try DistortionEngine.render(source,kind:.wave,settings:s))
    s.generators=64;XCTAssertNotEqual(first,try DistortionEngine.render(source,kind:.wave,settings:s))
    s.generators=999;s.seed=2;XCTAssertNotEqual(first,try DistortionEngine.render(source,kind:.wave,settings:s))
    var results=[Surface]()
    for type in DistortionSettings.Wave.allCases {s.waveType=type;results.append(try DistortionEngine.render(source,kind:.wave,settings:s))}
    XCTAssertNotEqual(results[0],results[1]);XCTAssertNotEqual(results[1],results[2])
    let full=try DistortionEngine.Mapping(.wave,s,5,4);s.horizontalScale=1
    let scaled=try DistortionEngine.Mapping(.wave,s,5,4)
    XCTAssertEqual(scaled.point(1.5,2.5).0-1.5,(full.point(1.5,2.5).0-1.5)/100,accuracy:1e-12)
    XCTAssertEqual(scaled.point(1.5,2.5).1,full.point(1.5,2.5).1)
  }
  func testIdentityPreservesHiddenColorAndStrictInputValidation() throws {
    var source=try fixture(.f32);source.setLinearPixel(x:0,y:0,Pixel(3,-0.2,7,0))
    for kind in [RasterFilter.Kind.displace,.shear,.pinch,.spherize,.twirl,.ripple,.zigzag] {
      var s=DistortionSettings(kind:kind);s.amount=0;s.angle=0;s.horizontalScale=0;s.verticalScale=0
      if kind == .displace {s.map = .init(width:1,height:1,channels:1,samples:Data([128]))}
      XCTAssertEqual(try DistortionEngine.render(source,kind:kind,settings:s),source)
    }
    let invalid=[#"{"kind":"wave","distortion":{"generators":1000}}"#,#"{"kind":"wave","distortion":{"generators":1.5}}"#,
      #"{"kind":"wave","distortion":{"wavelengthMin":120}}"#,#"{"kind":"wave","distortion":{"horizontalScale":0}}"#,
      #"{"kind":"pinch","distortion":{"amount":true}}"#,#"{"kind":"pinch","distortion":{"angle":20}}"#,
      #"{"kind":"twirl","distortion":{"angle":1000}}"#,#"{"kind":"zigzag","distortion":{"ridges":21}}"#,
      #"{"kind":"shear","distortion":{"points":[{"position":0,"offset":0},{"position":0,"offset":1},{"position":1,"offset":0}]}}"#,
      #"{"kind":"displace"}"#,#"{"kind":"displace","distortion":{"map":{"width":2,"height":1,"channels":1,"samples":"gA=="}}}"#,
      #"{"kind":"displace","distortion":{"map":{"width":1,"height":1,"channels":1,"samples":"gA==","path":"/tmp/no"}}}"#]
    for json in invalid {XCTAssertThrowsError(try RasterFilter.decodeJSON(Data(json.utf8)),json)}
    var original=DistortionSettings(kind:.shear),copy=original;copy.points[0].offset=0.5
    XCTAssertEqual(original.points[0].offset,0);XCTAssertEqual(copy.points[0].offset,0.5)
    original.points[1].position=0;XCTAssertThrowsError(try original.validate(kind:.shear))
  }
  func testCancellationRejectsBeforeMutation() async throws {
    let original=try RasterFilterTests().fixture();let worker=Task { ()throws->CraftDocument in
      withUnsafeCurrentTask { $0?.cancel() };var d=original;try Command.applyFilter(d.layers[0].id,RasterFilter(.wave)).apply(to:&d);return d
    };worker.cancel()
    do {_=try await worker.value;XCTFail("Cancelled render must throw")}catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
  }
}
