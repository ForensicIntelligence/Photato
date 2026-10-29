import Foundation
import XCTest
@testable import PhotoCraftCore

final class ClassicDetailTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->Surface {
    var s=try Surface(width:17,height:13,depth:depth)
    for y in 0..<13 {for x in 0..<17 {s.setPixel(x:x,y:y,Pixel(Float((x*47+y*11)%256)/255,Float((x*13+y*61)%256)/255,Float((x*83+y*29)%256)/255,Float([0,64,128,192,255][(x+2*y)%5])/255))}}
    return s
  }
  func testOriginalRust44References()throws {
    let url=try XCTUnwrap(Bundle.module.url(forResource:"provenance",withExtension:"json",subdirectory:"Fixtures/ClassicDetail")),root=url.deletingLastPathComponent()
    let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any],cases=manifest["cases"] as! [[String:Any]],source=try fixture()
    XCTAssertEqual(cases.count,44);XCTAssertEqual(try source.rgbaData(depth:.u8),try Data(contentsOf:root.appendingPathComponent("input.rgba")))
    var measurements=[[String:Any]]()
    for row in cases {
      let f=try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:row["filter"]!)),name=row["name"] as! String
      let actual=try ClassicDetailEngine.render(source,kind:f.kind,settings:f.classicDetail!).rgbaData(depth:.u8),expected=try Data(contentsOf:root.appendingPathComponent(name+".rgba"))
      let diffs=zip(actual,expected).map{abs(Int($0)-Int($1))},count=diffs.filter{$0>0}.count,maxDiff=diffs.max() ?? 0
      measurements.append(["name":name,"differentSamples":count,"maximumByteDifference":maxDiff]);XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(count,0,"\(name), max \(maxDiff)")
    }
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/classic-detail-oracle-comparisons");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(UUID().uuidString+".json"))
  }
  func testMedianAndDustAgainstIndependentSortedNeighborhoods()throws {
    for depth in [PixelDepth.u8,.u16] {let source=try fixture(depth)
      for radius in [1,3] {for threshold in [Float?.none,Float(30)/255] {
        let kind:RasterFilter.Kind=threshold==nil ? .median:.dustAndScratches;var s=ClassicDetailSettings(kind:kind);s.radius=Double(radius);s.threshold=threshold==nil ? 0:30
        let actual=try ClassicDetailEngine.render(source,kind:kind,settings:s)
        for y in 0..<13 {for x in 0..<17 {
          let before=source.pixel(x:x,y:y);var expected=SIMD4(before.r,before.g,before.b,before.a)
          for c in 0..<4 {var values=[Float]();for dy in -radius...radius {for dx in -radius...radius where dx*dx+dy*dy<=radius*radius+radius {let p=source.pixel(x:min(16,max(0,x+dx)),y:min(12,max(0,y+dy)));values.append(SIMD4(p.r,p.g,p.b,p.a)[c])}};values.sort();let m=values[values.count/2];if threshold==nil || abs(expected[c]-m)>threshold! {expected[c]=m}}
          XCTAssertEqual(actual.pixel(x:x,y:y),Pixel(expected.x,expected.y,expected.z,expected.w))
        }}
      }}
    }
  }
  func testShapeConstantFieldsAndPremultipliedAlpha()throws {
    for shape in ClassicDetailSettings.Shape.allCases {
      let source=try Surface(width:5,height:4,fill:Pixel(0.25,0.5,0.75,0.5));var s=ClassicDetailSettings(kind:.shapeBlur);s.shape=shape;s.radius=9
      XCTAssertEqual(try ClassicDetailEngine.render(source,kind:.shapeBlur,settings:s),source)
    }
    var source=try Surface(width:7,height:7);source.setPixel(x:3,y:3,Pixel(1,0,0,1));var s=ClassicDetailSettings(kind:.shapeBlur);s.radius=5;s.shape = .square
    let result=try ClassicDetailEngine.render(source,kind:.shapeBlur,settings:s)
    for y in 0..<7 {for x in 0..<7 {let p=result.pixel(x:x,y:y);XCTAssertEqual(p.r,1);XCTAssertEqual(p.g,0);XCTAssertEqual(p.b,0);XCTAssertGreaterThan(p.a,0)}}
  }
  func testRadialQualityCenterSelectionAndHDR()throws {
    var source=try Surface(width:33,height:25,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<25 {for x in 0..<33 {source.setLinearPixel(x:x,y:y,Pixel(Float((x*5+y*11)%17)-2,Float((x+y)%9),0.5,Float((x*7+y)%5)/4))}}
    var settings=ClassicDetailSettings(kind:.radialBlur);settings.amount=100;let area=IntRect(x:4,y:3,width:24,height:19)
    let good=try ClassicDetailEngine.render(source,kind:.radialBlur,settings:settings,area:area)
    settings.radialQuality = .draft;let draft=try ClassicDetailEngine.render(source,kind:.radialBlur,settings:settings,area:area);XCTAssertNotEqual(good,draft)
    settings.centerX=0.2;settings.centerY=0.8;settings.method = .zoom;let offset=try ClassicDetailEngine.render(source,kind:.radialBlur,settings:settings,area:area);XCTAssertNotEqual(offset,draft)
    var hdr=false
    for y in 0..<25 {for x in 0..<33 {let p=offset.linearPixel(x:x,y:y);XCTAssertTrue(p.isFinite);hdr = hdr || p.r>1;if !(4..<28).contains(x) || !(3..<22).contains(y){XCTAssertEqual(p,source.linearPixel(x:x,y:y))}}};XCTAssertTrue(hdr)
  }
  func testSmartModesAndSurfaceAlpha()throws {
    let source=try fixture();var s=ClassicDetailSettings(kind:.smartBlur);s.mode = .edgeOnly
    let edges=try ClassicDetailEngine.render(source,kind:.smartBlur,settings:s)
    for y in 0..<13 {for x in 0..<17 {let p=edges.pixel(x:x,y:y);XCTAssertTrue(p.r==0 || p.r==1);XCTAssertEqual(p.r,p.g);XCTAssertEqual(p.g,p.b);XCTAssertEqual(p.a,source.pixel(x:x,y:y).a)}}
    for radius in [1.0,8.0,20.0] {var settings=ClassicDetailSettings(kind:.surfaceBlur);settings.radius=radius
      let result=try ClassicDetailEngine.render(source,kind:.surfaceBlur,settings:settings)
      for y in 0..<13 {for x in 0..<17 {XCTAssertEqual(result.pixel(x:x,y:y).a,source.pixel(x:x,y:y).a)}}
    }
  }
  func testCroppedStorageMasksSelectionProtectionAndUndo()throws {
    var d=try CraftDocument(width:9,height:7);d.layers[0].content = .raster(try Surface(width:2,height:2,fill:.white));d.layers[0].x=3;d.layers[0].y=2;d.layers[0].mask=try Surface(width:2,height:2,fill:.white)
    let transform=d.layers[0].maskCoordinateTransform,id=d.layers[0].id;var session=EditorSession(document:d)
    try session.execute(.applyFilter(id,RasterFilter(.blurMore)));let changed=session.document
    XCTAssertNotEqual(changed,d);XCTAssertEqual(changed.layers[0].maskCoordinateTransform,transform);XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(changed)),changed)
    try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,changed)
    d=try CraftDocument(width:17,height:13);d.layers[0].content = .raster(try fixture());d.selection = .init(x:3,y:2,width:7,height:6);d.layers[0].protection=[.transparency]
    let before=d;try Command.applyFilter(d.layers[0].id,RasterFilter(.blurMore)).apply(to:&d)
    guard case .raster(let a)=d.layers[0].content,case .raster(let b)=before.layers[0].content else{return XCTFail()}
    for y in 0..<13{for x in 0..<17{XCTAssertEqual(a.pixel(x:x,y:y).a,b.pixel(x:x,y:y).a);if !(3..<10).contains(x) || !(2..<8).contains(y){XCTAssertEqual(a.pixel(x:x,y:y),b.pixel(x:x,y:y))}}}
  }
  func testStrictSettingsDepthAndAtomicity()throws {
    for json in [#"{"kind":"blur","classicDetail":{"radius":1}}"#,#"{"kind":"smartBlur","classicDetail":{"threshold":0}}"#,#"{"kind":"shapeBlur","classicDetail":{"radius":4}}"#,#"{"kind":"radialBlur","classicDetail":{"amount":10.5}}"#,#"{"kind":"radialBlur","classicDetail":{"centerX":-0.1}}"#,#"{"kind":"median","classicDetail":{"radius":501}}"#,#"{"kind":"dustAndScratches","classicDetail":{"radius":101}}"#] {XCTAssertThrowsError(try RasterFilter.decodeJSON(Data(json.utf8)))}
    for kind in RasterFilter.Kind.allCases.filter(\.isClassicDetail) {let f=RasterFilter(kind);XCTAssertEqual(try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:["kind":kind.rawValue,"classicDetail":f.classicDetail!.apiParameters(kind:kind)])),f)
      for depth in PixelDepth.allCases where !ClassicDetailSettings.depths(kind).contains(depth) {var d=try CraftDocument(width:17,height:13,depth:depth);d.layers[0].content = .raster(try fixture(depth));let before=d;XCTAssertThrowsError(try Command.applyFilter(d.layers[0].id,f).apply(to:&d));XCTAssertEqual(d,before)}
    }
    var settings=ClassicDetailSettings(kind:.radialBlur);settings.centerX = .nan;XCTAssertThrowsError(try settings.validate(kind:.radialBlur))
    var d=try CraftDocument(width:17,height:13);d.layers[0].content = .raster(try fixture());d.layers[0].locked=true;let before=d;XCTAssertThrowsError(try Command.applyFilter(d.layers[0].id,RasterFilter(.blur)).apply(to:&d));XCTAssertEqual(d,before)
    XCTAssertThrowsError(try ClassicDetailEngine.budget(ClassicDetailEngine.maximumVisits+1))
  }
  func testCancellationAndBudget()async throws {
    let source=try fixture();let task=Task {try Task.checkCancellation();return try ClassicDetailEngine.render(source,kind:.shapeBlur,settings:.init(kind:.shapeBlur))};task.cancel()
    do{_ = try await task.value;XCTFail("Cancelled work returned a result")}catch{XCTAssertTrue(error is CancellationError)}
    let source2=try Surface(width:1024,height:1024);var s=ClassicDetailSettings(kind:.shapeBlur);s.radius=1000
    XCTAssertThrowsError(try ClassicDetailEngine.render(source2,kind:.shapeBlur,settings:s))
  }
}
