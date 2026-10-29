import Foundation
import XCTest
@testable import PhotoCraftCore

final class PixelateTests:XCTestCase {
  func sample() throws -> Surface {
    var s=try Surface(width:32,height:24)
    for y in 0..<24 {for x in 0..<32 {s.setPixel(x:x,y:y,Pixel(Float((x*17+y*3)%256)/255,Float((x*5+y*23)%256)/255,Float((x*11+y*7)%256)/255,Float(64+(x+y)%192)/255))}}
    return s
  }
  func testOriginalRustPixelateOutputsAreByteIdentical() throws {
    let base=try XCTUnwrap(Bundle.module.url(forResource:"provenance",withExtension:"json",subdirectory:"Fixtures/Pixelate"))
    let proof=try JSONSerialization.jsonObject(with:Data(contentsOf:base)) as! [String:Any],cases=proof["cases"] as! [[String:Any]]
    XCTAssertEqual(cases.count,18)
    let source=try sample();var measurements=[[String:Any]]()
    for row in cases {
      let name=row["name"] as! String,kind=try XCTUnwrap(RasterFilter.Kind(rawValue:row["kind"] as! String))
      let s=try PixelateSettings.decodeJSON(JSONSerialization.data(withJSONObject:row["settings"]!),kind:kind)
      let actual=try PixelateEngine.render(source,kind:kind,settings:s).rgbaData(depth:.u8),expected=try Data(contentsOf:base.deletingLastPathComponent().appendingPathComponent(name+".rgba"))
      let differences=zip(actual,expected).map{abs(Int($0)-Int($1))}
      measurements.append(["name":name,"maximumByteDifference":differences.max() ?? 0,"differentSamples":differences.filter{$0>0}.count])
      XCTAssertEqual(actual,expected,name)
    }
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/pixelate-oracle-comparisons")
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(UUID().uuidString+".json"))
  }
  func testFragmentFourOffsetsPremultipliedAlphaAndHDR() throws {
    var s=try Surface(width:9,height:9,depth:.f32)
    s.setLinearPixel(x:0,y:4,Pixel(2,0,0,0.25));s.setLinearPixel(x:8,y:4,Pixel(0,3,0,0.5));s.setLinearPixel(x:4,y:0,Pixel(0,0,4,1));s.setLinearPixel(x:4,y:8,Pixel(99,66,44,0))
    let result=try PixelateEngine.render(s,kind:.fragment,settings:.init(kind:.fragment)),p=result.linearPixel(x:4,y:4)
    XCTAssertEqual(p.a,1.75/4,accuracy:1e-7);XCTAssertEqual(p.r,0.5/1.75,accuracy:1e-6);XCTAssertEqual(p.g,1.5/1.75,accuracy:1e-6);XCTAssertEqual(p.b,4/1.75,accuracy:1e-6)
    XCTAssertEqual(result.linearPixel(x:1,y:1),.clear)
  }
  func testFacetFlatFieldsAndFragmentClampedEdges() throws {
    for depth in PixelDepth.allCases {
      let s=try Surface(width:1,height:1,depth:depth,fill:Pixel(0.25,0.5,0.75,0.5))
      for kind in [RasterFilter.Kind.facet,.fragment,.crystallize] {let out=try PixelateEngine.render(s,kind:kind,settings:.init(kind:kind));let p=out.pixel(x:0,y:0),before=s.pixel(x:0,y:0);XCTAssertEqual(p.r,before.r,accuracy:1e-6);XCTAssertEqual(p.a,before.a,accuracy:1e-6)}
    }
    XCTAssertEqual(PixelateEngine.floorDiv(-1,3),-1);XCTAssertEqual(PixelateEngine.floorDiv(-3,3),-1);XCTAssertEqual(PixelateEngine.floorDiv(-4,3),-2)
  }
  func testAllPatternsDeterministicDistinctAndPreserveAlpha() throws {
    let s=try sample();var results=[Data]()
    for pattern in PixelateSettings.Pattern.allCases {
      var settings=PixelateSettings(kind:.mezzotint);settings.pattern=pattern;settings.seed=91
      let a=try PixelateEngine.render(s,kind:.mezzotint,settings:settings);XCTAssertEqual(a,try PixelateEngine.render(s,kind:.mezzotint,settings:settings))
      for y in 0..<24 {for x in 0..<32 {let p=a.pixel(x:x,y:y);XCTAssertEqual(p.a,s.pixel(x:x,y:y).a);XCTAssertTrue([0,1].contains(p.r));XCTAssertTrue([0,1].contains(p.g));XCTAssertTrue([0,1].contains(p.b))}}
      results.append(try a.rgbaData(depth:.u8));settings.seed=92;XCTAssertNotEqual(a,try PixelateEngine.render(s,kind:.mezzotint,settings:settings))
    }
    XCTAssertEqual(Set(results).count,10)
  }
  func testHalftoneRGBChannelAnglesAndPointillizeBackground() throws {
    let s=try sample();var settings=PixelateSettings(kind:.colorHalftone)
    let a=try PixelateEngine.render(s,kind:.colorHalftone,settings:settings);settings.angles[3] = -45;XCTAssertEqual(a,try PixelateEngine.render(s,kind:.colorHalftone,settings:settings))
    settings.angles[0]=0;XCTAssertNotEqual(a,try PixelateEngine.render(s,kind:.colorHalftone,settings:settings))
    let white=try Surface(width:6,height:8,fill:.white);XCTAssertEqual(white,try PixelateEngine.render(white,kind:.colorHalftone,settings:settings))
    settings = .init(kind:.pointillize);settings.seed=77;settings.background = .black;let black=try PixelateEngine.render(s,kind:.pointillize,settings:settings)
    settings.background = .white;XCTAssertNotEqual(black,try PixelateEngine.render(s,kind:.pointillize,settings:settings))
  }
  func testStrictJSONRangesUnknownFieldsAndValueSemantics() throws {
    let invalid=[#"{"kind":"colorHalftone","pixelate":{"maxRadius":3}}"#,#"{"kind":"colorHalftone","pixelate":{"angles":[1,2,3]}}"#,#"{"kind":"colorHalftone","pixelate":{"angles":[0,0,0,361]}}"#,#"{"kind":"crystallize","pixelate":{"cellSize":301}}"#,#"{"kind":"crystallize","pixelate":{"cellSize":3.5}}"#,#"{"kind":"crystallize","pixelate":{"seed":-1}}"#,#"{"kind":"crystallize","pixelate":{"cellSize":true}}"#,#"{"kind":"mezzotint","pixelate":{"pattern":"unknown"}}"#,#"{"kind":"mezzotint","pixelate":{"cellSize":3}}"#,#"{"kind":"pointillize","pixelate":{"background":{"r":1,"g":0,"b":0,"a":1,"extra":0}}}"#,#"{"kind":"facet","pixelate":{}}"#]
    for text in invalid {XCTAssertThrowsError(try RasterFilter.decodeJSON(Data(text.utf8)),text)}
    let original=PixelateSettings(kind:.colorHalftone);var copy=original;copy.angles[0]=0;XCTAssertEqual(original.angles[0],108)
    var malformed=PixelateSettings(kind:.facet);malformed.angles=[];XCTAssertThrowsError(try malformed.validate(kind:.facet))
    for kind in RasterFilter.Kind.allCases.filter(\.isPixelate) {XCTAssertEqual(try JSONDecoder().decode(RasterFilter.self,from:JSONEncoder().encode(RasterFilter(kind))),RasterFilter(kind))}
  }
  func testCancellationDoesNotMutateTheDocument() async throws {
    let original=try RasterFilterTests().fixture();let worker=Task { ()throws->CraftDocument in
      withUnsafeCurrentTask{$0?.cancel()};var d=original;try Command.applyFilter(d.layers[0].id,RasterFilter(.crystallize)).apply(to:&d);return d
    };worker.cancel();do {_=try await worker.value;XCTFail("Expected cancellation")}catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
  }
}
