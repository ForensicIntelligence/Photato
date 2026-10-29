import Foundation
import XCTest
@testable import PhotoCraftCore

final class RenderFilterTests:XCTestCase {
  func sample(_ w:Int=32,_ h:Int=24)throws->Surface {
    var s=try Surface(width:w,height:h)
    for y in 0..<h {for x in 0..<w {s.setPixel(x:x,y:y,Pixel(Float((x*17+y*3)%256)/255,Float((x*5+y*23)%256)/255,Float((x*11+y*7)%256)/255,Float(64+(x+y)%192)/255))}}
    return s
  }
  func testOriginalRustRenderPixelsForColorsSeedsAndEveryLens()throws {
    let base=try XCTUnwrap(Bundle.module.url(forResource:"provenance",withExtension:"json",subdirectory:"Fixtures/Render"))
    let proof=try JSONSerialization.jsonObject(with:Data(contentsOf:base)) as! [String:Any],cases=proof["cases"] as! [[String:Any]];XCTAssertEqual(cases.count,12)
    var measurements=[[String:Any]]()
    for row in cases {
      let name=row["name"] as! String,kind=try XCTUnwrap(RasterFilter.Kind(rawValue:row["kind"] as! String)),source=try sample(row["width"] as! Int,row["height"] as! Int)
      let settings=try RenderSettings.decodeJSON(JSONSerialization.data(withJSONObject:row["settings"]!),kind:kind)
      let actual=try RenderFilterEngine.render(source,kind:kind,settings:settings).rgbaData(depth:.u8),expected=try Data(contentsOf:base.deletingLastPathComponent().appendingPathComponent(name+".rgba"))
      let differences=zip(actual,expected).map{abs(Int($0)-Int($1))};let maximum=differences.max() ?? 0,count=differences.filter{$0>0}.count
      measurements.append(["name":name,"maximumByteDifference":maximum,"differentSamples":count]);XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(count,0,"\(name): max difference \(maximum)")
    }
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/render-oracle-comparisons");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(UUID().uuidString+".json"))
  }
  func testOpaqueGenerationAndDifferenceFlareHDRAlpha()throws {
    let clear=try Surface(width:3,height:2)
    for kind in [RasterFilter.Kind.clouds,.fibers] {
      var s=RenderSettings(kind:kind);s.foreground=Pixel(0,1,0,0.2);s.background=Pixel(0,1,0,0.8)
      let result=try RenderFilterEngine.render(clear,kind:kind,settings:s)
      for y in 0..<2 {for x in 0..<3 {XCTAssertEqual(result.pixel(x:x,y:y),Pixel(0,1,0,1))}}
    }
    var source=try Surface(width:1,height:1,depth:.f32,colorEncoding:.linearRGB);source.setLinearPixel(x:0,y:0,Pixel(-0.25,0.5,2,0.375))
    var settings=RenderSettings(kind:.differenceClouds);settings.foreground = .white;settings.background = .white
    let difference=try RenderFilterEngine.render(source,kind:.differenceClouds,settings:settings).linearPixel(x:0,y:0)
    XCTAssertEqual(difference,Pixel(1.25,0.5,1,0.375))
    let flare=try RenderFilterEngine.render(source,kind:.lensFlare,settings:.init(kind:.lensFlare)).linearPixel(x:0,y:0)
    XCTAssertEqual(flare,Pixel(1,1,1,0.375))
  }
  func testSeedsRepeatAndDocumentSpaceCoordinatesSurviveCrops()throws {
    for kind in [RasterFilter.Kind.clouds,.differenceClouds,.fibers] {
      let source=try sample(),empty=try Surface(width:4,height:3);var s=RenderSettings(kind:kind);s.seed=42
      let a=try RenderFilterEngine.render(source,kind:kind,settings:s)
      XCTAssertEqual(a,try RenderFilterEngine.render(source,kind:kind,settings:s));s.seed=43;XCTAssertNotEqual(a,try RenderFilterEngine.render(source,kind:kind,settings:s))
      if kind != .differenceClouds {
        let full=try RenderFilterEngine.render(source,kind:kind,settings:s)
        let crop=try RenderFilterEngine.render(empty,kind:kind,settings:s,canvasWidth:32,canvasHeight:24,pixelToDocument:.translation(9,7))
        for y in 0..<3 {for x in 0..<4 {XCTAssertEqual(crop.pixel(x:x,y:y),full.pixel(x:x+9,y:y+7))}}
      }
    }
  }
  func testGeneratedSelectionExpandsStorageAndKeepsMaskPlacement()throws {
    for kind in [RasterFilter.Kind.clouds,.fibers] {for linked in [true,false] {
      var d=try CraftDocument(width:10,height:8);d.layers[0].content = .raster(try Surface(width:2,height:2,fill:Pixel(1,0,0,0.5)))
      d.layers[0].x=4;d.layers[0].y=3;d.layers[0].protection=[.position];d.layers[0].mask=try Surface(width:2,height:2,fill:.white)
      var properties=d.layers[0].effectiveMaskProperties;properties.linked=linked;d.layers[0].maskProperties=properties
      let original=d,mask=d.layers[0].maskCoordinateTransform,id=d.layers[0].id
      d.selection = .init(x:2,y:1,width:3,height:4);let selected=d
      var f=RasterFilter(kind);f.renderSettings?.foreground=Pixel(0,1,0);f.renderSettings?.background=Pixel(0,1,0)
      var session=EditorSession(document:d);try session.execute(.applyFilter(id,f));let edited=session.document
      XCTAssertEqual(edited.layers[0].maskCoordinateTransform,mask);XCTAssertEqual(edited.layers[0].mask,original.layers[0].mask)
      guard case .raster(let p)=edited.layers[0].content else {return XCTFail()}
      let inverse=try edited.layers[0].coordinateTransform.inverted()
      for y in 0..<8 {for x in 0..<10 {
        let q=inverse.point(Double(x)+0.5,Double(y)+0.5),value=p.pixel(x:Int(floor(q.x)),y:Int(floor(q.y)))
        if (2..<5).contains(x) && (1..<5).contains(y) {XCTAssertEqual(value,Pixel(0,1,0))}
        else if (4..<6).contains(x) && (3..<5).contains(y) {XCTAssertEqual(value,Pixel(1,0,0,Float(128)/255))}
        else {XCTAssertEqual(value,.clear)}
      }}
      try session.undo();XCTAssertEqual(session.document,selected);try session.redo();XCTAssertEqual(session.document,edited)
    }}
  }
  func testTransparencyLockAndFractionalSelectionRemainAtomic()throws {
    var d=try CraftDocument(width:4,height:3);var pixels=try Surface(width:4,height:3);pixels.setPixel(x:1,y:1,Pixel(1,0,0,0.5));d.layers[0].content = .raster(pixels);d.layers[0].protection=[.transparency]
    var f=RasterFilter(.clouds);f.renderSettings?.foreground=Pixel(0,1,0);f.renderSettings?.background=Pixel(0,1,0)
    let id=d.layers[0].id;try Command.applyFilter(id,f).apply(to:&d)
    guard case .raster(let result)=d.layers[0].content else{return XCTFail()}
    XCTAssertEqual(result.pixel(x:1,y:1),Pixel(0,1,0,Float(128)/255));XCTAssertEqual(result.pixel(x:0,y:0),.clear)
    var fraction=try CraftDocument(width:4,height:1);fraction.layers[0].content = .raster(try Surface(width:4,height:1,fill:Pixel(1,0,0)))
    try Command.selectionCoverage(SelectionMask(width:4,height:1,bytes:[0,64,128,255]),.replace).apply(to:&fraction)
    try Command.applyFilter(fraction.layers[0].id,f).apply(to:&fraction)
    guard case .raster(let partial)=fraction.layers[0].content else{return XCTFail()}
    for (x,coverage) in [Float(0),Float(64)/255,Float(128)/255,Float(1)].enumerated() {let p=partial.pixel(x:x,y:0);XCTAssertEqual(p.r,1-coverage,accuracy:1/255);XCTAssertEqual(p.g,coverage,accuracy:1/255);XCTAssertEqual(p.a,1)}
    let original=d;f.renderSettings?.variance = .nan;XCTAssertThrowsError(try Command.applyFilter(id,f).apply(to:&d));XCTAssertEqual(d,original)
  }
  func testStrictSettingsJSONValueSemanticsAndLimits()throws {
    for text in [#"{"kind":"clouds","render":{"seed":-1}}"#,#"{"kind":"clouds","render":{"brightness":100}}"#,#"{"kind":"fibers","render":{"variance":0}}"#,#"{"kind":"fibers","render":{"strength":true}}"#,#"{"kind":"lensFlare","render":{"lens":"invalid"}}"#,#"{"kind":"lensFlare","render":{"centerX":2}}"#,#"{"kind":"lensFlare","render":{"brightness":301}}"#,#"{"kind":"clouds","render":{"foreground":{"r":0,"g":0,"b":0,"a":1,"x":2}}}"#] {XCTAssertThrowsError(try RasterFilter.decodeJSON(Data(text.utf8)),text)}
    let original=RenderSettings(kind:.fibers);var copy=original;copy.variance=30;XCTAssertEqual(original.variance,16)
    for kind in RasterFilter.Kind.allCases.filter(\.isRender) {let f=RasterFilter(kind);XCTAssertEqual(try JSONDecoder().decode(RasterFilter.self,from:JSONEncoder().encode(f)),f)}
    XCTAssertThrowsError(try RenderFilterEngine.render(sample(),kind:.clouds,settings:.init(kind:.clouds),canvasWidth:10000,canvasHeight:10000))
  }
  func testCancellationDoesNotPublishPartialGeneratedPixels()async throws {
    let original=try RasterFilterTests().fixture()
    for kind in RasterFilter.Kind.allCases.filter(\.isRender) {
      let task=Task {()throws->CraftDocument in withUnsafeCurrentTask{$0?.cancel()};var d=original;try Command.applyFilter(d.layers[0].id,RasterFilter(kind)).apply(to:&d);return d};task.cancel()
      do {_=try await task.value;XCTFail("Expected cancellation")}catch is CancellationError {}catch {XCTFail("Unexpected: \(error)")}
    }
  }
}
