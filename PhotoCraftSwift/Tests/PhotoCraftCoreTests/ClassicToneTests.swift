import Foundation
import XCTest
@testable import PhotoCraftCore

final class ClassicToneTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->Surface {try ClassicDetailTests().fixture(depth)}
  func testOriginalRustTwelveReferences()throws {
    let url=try XCTUnwrap(Bundle.module.url(forResource:"provenance",withExtension:"json",subdirectory:"Fixtures/ClassicTone")),root=url.deletingLastPathComponent()
    let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any],cases=manifest["cases"] as! [[String:Any]],source=try fixture()
    XCTAssertEqual(cases.count,12);XCTAssertEqual(try source.rgbaData(depth:.u8),try Data(contentsOf:root.appendingPathComponent("input.rgba")))
    for row in cases {
      let kind=try XCTUnwrap(ClassicToneSettings.Kind(rawValue:row["kind"] as! String)),s=try ClassicToneSettings.decodeJSON(JSONSerialization.data(withJSONObject:row["settings"]!),kind:kind),name=row["name"] as! String
      let actual=try ClassicToneEngine.render(source,settings:s).rgbaData(depth:.u8),expected=try Data(contentsOf:root.appendingPathComponent(name+".rgba"))
      let differences=zip(actual,expected).map{abs(Int($0)-Int($1))};XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(differences.filter{$0>0}.count,0,"\(name) max \(differences.max() ?? 0)")
    }
  }
  func testDepthsAlphaIdentityAndEqualizeCDF()throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(depth)
      for kind in ClassicToneSettings.Kind.allCases {
        let result=try ClassicToneEngine.render(source,settings:.init(kind))
        for y in 0..<source.height {for x in 0..<source.width {let a=result.pixel(x:x,y:y),b=source.pixel(x:x,y:y);XCTAssertTrue(a.isFinite);XCTAssertEqual(a.a,b.a);if b.a==0{XCTAssertEqual(a,b)}}}
      }
      XCTAssertEqual(try ClassicToneEngine.render(source,settings:.init(.matchColor)),source)
    }
    var ramp=try Surface(width:4,height:1)
    for i in 0..<4 {let v=Float([30,60,90,120][i])/255;ramp.setPixel(x:i,y:0,Pixel(v,v,v))}
    let equal=try ClassicToneEngine.render(ramp,settings:.init(.equalize))
    for i in 0..<4{XCTAssertEqual(equal.pixel(x:i,y:0).r,Float(i)/3,accuracy:1/255)}
    let selected=try ClassicToneEngine.render(ramp,settings:.init(.equalize),statisticsMask:[0,1,1,0])
    XCTAssertEqual(selected.pixel(x:1,y:0).r,0);XCTAssertEqual(selected.pixel(x:2,y:0).r,1)
  }
  func testStatisticsAlphaAndSelectionWeights()throws {
    var source=try Surface(width:3,height:1,depth:.f32)
    source.setPixel(x:0,y:0,Pixel(1,0,0,1));source.setPixel(x:1,y:0,Pixel(0,1,0,0.5));source.setPixel(x:2,y:0,Pixel(0,0,1,0))
    let result=try ClassicToneEngine.statistics(source,mask:[0.5,1,1])
    let a=ClassicToneEngine.lab(SIMD4(1,0,0,1)),b=ClassicToneEngine.lab(SIMD4(0,1,0,1))
    for c in 0..<3{XCTAssertEqual(result.mean[c],(a[c]+b[c])/2,accuracy:0.001);XCTAssertEqual(result.standardDeviation[c],abs(a[c]-b[c])/2,accuracy:0.001)}
    XCTAssertThrowsError(try ClassicToneEngine.statistics(source,mask:[0,0,1]));XCTAssertThrowsError(try ClassicToneEngine.statistics(source,mask:[1]))
  }
  func testReplaceSampleAdditionSubtractionAndLocalization()throws {
    var source=try Surface(width:3,height:1,fill:Pixel(1,0,0));source.setPixel(x:2,y:0,Pixel(0,0,1))
    var s=ClassicToneSettings(.replaceColor);s.samples=[.init(color:Pixel(1,0,0),point:.init(0,0))];s.hue=120;s.fuzziness=0
    let output=try ClassicToneEngine.render(source,settings:s);XCTAssertEqual(output.pixel(x:0,y:0),Pixel(0,1,0));XCTAssertEqual(output.pixel(x:2,y:0),source.pixel(x:2,y:0))
    s.samples.append(.init(color:Pixel(0,0,1)));XCTAssertEqual(try ClassicToneEngine.replacementMask(source,settings:s),[1,1,1])
    s.samples.append(.init(color:Pixel(1,0,0),subtract:true));XCTAssertEqual(try ClassicToneEngine.replacementMask(source,settings:s),[0,0,1])
    s.samples.removeLast(2);s.localized=true;s.localRadius=1;XCTAssertEqual(try ClassicToneEngine.replacementMask(source,settings:s),[1,0,0])
  }
  func testStrictSettingsAndCancellation()async throws {
    for kind in ClassicToneSettings.Kind.allCases {let s=ClassicToneSettings(kind);XCTAssertEqual(try ClassicToneSettings.decodeJSON(JSONSerialization.data(withJSONObject:s.apiParameters),kind:kind),s)}
    for (kind,fields) in [(ClassicToneSettings.Kind.matchColor,["sourceStatistics":["mean":[0,0,0],"standardDeviation":[1,1,1],"unknown":1]]),(.replaceColor,["samples":[["color":["r":1,"g":0,"b":0,"a":1],"subtract":false,"unknown":1]]]),(.equalize,["equalizeEntireImage":1]),(.hdrToning,["curve":[[0.5,0],[0.5,1]]]),(.shadowsHighlights,["shadowAmount":101])] as [(ClassicToneSettings.Kind,[String:Any])] {
      XCTAssertThrowsError(try ClassicToneSettings.decodeJSON(JSONSerialization.data(withJSONObject:fields),kind:kind))
    }
    let source=try fixture();let task=Task{try Task.checkCancellation();return try ClassicToneEngine.render(source,settings:.init())};task.cancel()
    do{_=try await task.value;XCTFail("Cancelled operation completed")}catch{XCTAssertTrue(error is CancellationError)}
  }
  func testSelectedApplicationWholeTargetAndLocks()throws {
    var d=try CraftDocument(width:17,height:13);d.layers[0].content = .raster(try fixture());d.selection = .init(x:2,y:3,width:4,height:4)
    let original=d,id=d.layers[0].id
    var session=EditorSession(document:d);try session.execute(.toneAdjustment(.init(.init(.equalize),layerID:id)));let selected=session.document
    guard case .raster(let before)=d.layers[0].content,case .raster(let after)=selected.layers[0].content else{return XCTFail()}
    for y in 0..<13{for x in 0..<17{XCTAssertEqual(after.pixel(x:x,y:y).a,before.pixel(x:x,y:y).a);if !(2..<6).contains(x) || !(3..<7).contains(y){XCTAssertEqual(after.pixel(x:x,y:y),before.pixel(x:x,y:y))}}}
    try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,selected)
    var whole=ClassicToneSettings(.equalize);whole.equalizeEntireImage=true;try Command.toneAdjustment(.init(whole,layerID:id)).apply(to:&d);XCTAssertNotEqual(d,selected);XCTAssertEqual(d.selection,original.selection)
    d=original;d.layers[0].locked=true;let locked=d;XCTAssertThrowsError(try Command.toneAdjustment(.init(whole,layerID:id)).apply(to:&d));XCTAssertEqual(d,locked)
  }
}
