import Foundation
import XCTest
@testable import PhotoCraftCore

final class StylizeTests:XCTestCase {
  func sample(_ w:Int=32,_ h:Int=24)throws->Surface {
    var s=try Surface(width:w,height:h)
    for y in 0..<h {for x in 0..<w {s.setPixel(x:x,y:y,Pixel(Float((x*17+y*3)%256)/255,Float((x*5+y*23)%256)/255,Float((x*11+y*7)%256)/255,Float(64+(x+y)%192)/255))}}
    return s
  }
  func testOriginalRustStylizeOutputsIncludingOilTileBoundaries()throws {
    let base=try XCTUnwrap(Bundle.module.url(forResource:"provenance",withExtension:"json",subdirectory:"Fixtures/Stylize"))
    let proof=try JSONSerialization.jsonObject(with:Data(contentsOf:base)) as! [String:Any],cases=proof["cases"] as! [[String:Any]];XCTAssertEqual(cases.count,27)
    var measurements=[[String:Any]]()
    for row in cases {
      let name=row["name"] as! String,kind=try XCTUnwrap(RasterFilter.Kind(rawValue:row["kind"] as! String)),source=try sample(row["width"] as! Int,row["height"] as! Int)
      let settings=try StylizeSettings.decodeJSON(JSONSerialization.data(withJSONObject:row["settings"]!),kind:kind)
      let actual=try StylizeEngine.render(source,kind:kind,settings:settings).rgbaData(depth:.u8),expected=try Data(contentsOf:base.deletingLastPathComponent().appendingPathComponent(name+".rgba"))
      let differences=zip(actual,expected).map{abs(Int($0)-Int($1))};let maximum=differences.max() ?? 0,count=differences.filter{$0>0}.count
      measurements.append(["name":name,"maximumByteDifference":maximum,"differentSamples":count]);XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(count,0,"\(name): max difference \(maximum)")
    }
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/stylize-oracle-comparisons");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(UUID().uuidString+".json"))
  }
  func testSolarizeHDRAndAlphaAreNotClampedByTheEngine()throws {
    var s=try Surface(width:1,height:1,depth:.f32,colorEncoding:.linearRGB);s.setLinearPixel(x:0,y:0,Pixel(-0.25,0.5,2,0.4))
    let p=try StylizeEngine.render(s,kind:.solarize,settings:.init(kind:.solarize)).linearPixel(x:0,y:0)
    XCTAssertEqual(p,Pixel(-0.25,0.5,-1,0.4))
  }
  func testFlatFindEdgesEmbossAndTraceContourCrossing()throws {
    let flat=try Surface(width:3,height:3,fill:Pixel(0.25,0.5,0.75,0.5))
    for (kind,expected) in [(RasterFilter.Kind.findEdges,Float(1)),(.emboss,Float(128)/255)] {
      let r=try StylizeEngine.render(flat,kind:kind,settings:.init(kind:kind));for y in 0..<3 {for x in 0..<3 {let p=r.pixel(x:x,y:y);XCTAssertEqual(p.r,expected);XCTAssertEqual(p.r,p.g);XCTAssertEqual(p.g,p.b);XCTAssertEqual(p.a,flat.pixel(x:x,y:y).a)}}
    }
    var s=try Surface(width:3,height:1);for x in 0..<3 {s.setPixel(x:x,y:0,Pixel(Float(x)/2,Float(x)/2,Float(x)/2,1))}
    var settings=StylizeSettings(kind:.traceContour);settings.level=128
    let lower=try StylizeEngine.render(s,kind:.traceContour,settings:settings);settings.edge = .upper;let upper=try StylizeEngine.render(s,kind:.traceContour,settings:settings)
    XCTAssertEqual((0..<3).map{lower.pixel(x:$0,y:0).r},[1,0,1]);XCTAssertEqual((0..<3).map{upper.pixel(x:$0,y:0).r},[1,1,0])
  }
  func testOilUnlitConstantHDRAndCoverageAcrossTiles()throws {
    let s=try Surface(width:270,height:2,depth:.f32,fill:Pixel(2,0.5,0.25,0.3));var settings=StylizeSettings(kind:.oilPaint);settings.lighting=false;settings.scale=0;settings.stylization=0
    let r=try StylizeEngine.render(s,kind:.oilPaint,settings:settings)
    for x in 0..<270 {let p=r.linearPixel(x:x,y:0),before=s.linearPixel(x:x,y:0);XCTAssertEqual(p.r,before.r,accuracy:1e-5);XCTAssertEqual(p.g,before.g,accuracy:1e-5);XCTAssertEqual(p.b,before.b,accuracy:1e-5);XCTAssertEqual(p.a,before.a)}
  }
  func testModesSeedsAndSmallExtentExtrusion()throws {
    let s=try sample();for kind in [RasterFilter.Kind.diffuse,.tiles,.wind] {
      var a=StylizeSettings(kind:kind);a.seed=1;let output=try StylizeEngine.render(s,kind:kind,settings:a);XCTAssertEqual(output,try StylizeEngine.render(s,kind:kind,settings:a));a.seed=2;XCTAssertNotEqual(output,try StylizeEngine.render(s,kind:kind,settings:a))
    }
    var settings=StylizeSettings(kind:.extrude);settings.size=2;settings.depth=255
    for type in StylizeSettings.ExtrudeType.allCases {settings.type=type;let output=try StylizeEngine.render(try sample(1,1),kind:.extrude,settings:settings);XCTAssertEqual(output.width,1);XCTAssertTrue(output.pixel(x:0,y:0).isFinite)}
  }
  func testStrictJSONStorageAndValueSemantics()throws {
    for text in [#"{"kind":"emboss","stylize":{"height":101}}"#,#"{"kind":"emboss","stylize":{"height":1.5}}"#,#"{"kind":"diffuse","stylize":{"mode":"wrong"}}"#,#"{"kind":"extrude","stylize":{"size":1}}"#,#"{"kind":"extrude","stylize":{"solidFrontFaces":1}}"#,#"{"kind":"oilPaint","stylize":{"shine":11}}"#,#"{"kind":"wind","stylize":{"seed":-1}}"#,#"{"kind":"tiles","stylize":{"count":true}}"#,#"{"kind":"traceContour","stylize":{"level":256}}"#,#"{"kind":"findEdges","stylize":{}}"#] {XCTAssertThrowsError(try RasterFilter.decodeJSON(Data(text.utf8)),text)}
    let original=StylizeSettings(kind:.emboss);var copy=original;copy.height=8;XCTAssertEqual(original.height,3)
    copy.foreground=Pixel(.nan,0,0);XCTAssertThrowsError(try copy.validate(kind:.emboss))
    for kind in RasterFilter.Kind.allCases.filter(\.isStylize) {let f=RasterFilter(kind);XCTAssertEqual(try JSONDecoder().decode(RasterFilter.self,from:JSONEncoder().encode(f)),f)}
  }
  func testCancellationAcrossEveryStylizeFilter()async throws {
    let original=try RasterFilterTests().fixture()
    for kind in RasterFilter.Kind.allCases.filter(\.isStylize) {
      let task=Task {()throws->CraftDocument in withUnsafeCurrentTask{$0?.cancel()};var d=original;try Command.applyFilter(d.layers[0].id,RasterFilter(kind)).apply(to:&d);return d};task.cancel()
      do {_=try await task.value;XCTFail("Expected cancellation")}catch is CancellationError {}catch {XCTFail("Unexpected: \(error)")}
    }
  }
}
