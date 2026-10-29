import Foundation
import XCTest
@testable import PhotoCraftCore

final class OtherVideoTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->Surface {
    var s=try Surface(width:17,height:13,depth:depth)
    for y in 0..<13 {for x in 0..<17 {s.setPixel(x:x,y:y,Pixel(Float((x*47+y*11)%256)/255,Float((x*13+y*61)%256)/255,Float((x*83+y*29)%256)/255,Float([0,64,128,192,255][(x+2*y)%5])/255))}}
    return s
  }
  func testOriginalRust44References()throws {
    let url=try XCTUnwrap(Bundle.module.url(forResource:"provenance",withExtension:"json",subdirectory:"Fixtures/OtherVideo")),root=url.deletingLastPathComponent()
    let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any],cases=manifest["cases"] as! [[String:Any]],source=try fixture()
    XCTAssertEqual(cases.count,44);XCTAssertEqual(try source.rgbaData(depth:.u8),try Data(contentsOf:root.appendingPathComponent("input.rgba")))
    var measurements=[[String:Any]]()
    for row in cases {
      let f=try RasterFilter.decodeJSON(JSONSerialization.data(withJSONObject:row["filter"]!)),name=row["name"] as! String
      let actual=try OtherVideoEngine.render(source,kind:f.kind,settings:f.otherVideo!).rgbaData(depth:.u8),expected=try Data(contentsOf:root.appendingPathComponent(name+".rgba"))
      let diffs=zip(actual,expected).map{abs(Int($0)-Int($1))},count=diffs.filter{$0>0}.count,maxDiff=diffs.max() ?? 0
      measurements.append(["name":name,"differentSamples":count,"maximumByteDifference":maxDiff]);XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(count,0,"\(name), max \(maxDiff)")
    }
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/other-video-oracle-comparisons");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(UUID().uuidString+".json"))
  }
  func testExtremaIndependentDirectWindowAndShape()throws {
    let source=try fixture()
    for maximum in [true,false] {for radius in [1.0,2.5,5.0] {
      var settings=OtherVideoSettings();settings.radius=radius;settings.preserve = .roundness
      let actual=try OtherVideoEngine.render(source,kind:maximum ? .maximum:.minimum,settings:settings),r=Int(radius)
      for y in 0..<13 {for x in 0..<17 {
        var v=SIMD4<Float>(repeating:maximum ? -1:2)
        for dy in -r...r {for dx in -r...r where Double(dx*dx+dy*dy)<=radius*radius {
          let p=source.pixel(x:min(16,max(0,x+dx)),y:min(12,max(0,y+dy))),q=SIMD4(p.r,p.g,p.b,p.a)
          for c in 0..<4 {v[c]=maximum ? max(v[c],q[c]):min(v[c],q[c])}
        }}
        XCTAssertEqual(actual.pixel(x:x,y:y),Pixel(v.x,v.y,v.z,v.w))
      }}
    }}
  }
  func testCustomAlphaHighDepthAndNoop()throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(depth);var s=OtherVideoSettings()
      XCTAssertEqual(try OtherVideoEngine.render(source,kind:.customFilter,settings:s),source)
      s.kernel=[Int](repeating:0,count:25);s.offset=255;XCTAssertEqual(try OtherVideoEngine.render(source,kind:.customFilter,settings:s),source)
      s.kernel[12]=1;s.scale=2;s.offset=0
      let edited=try OtherVideoEngine.render(source,kind:.customFilter,settings:s)
      for y in 0..<13 {for x in 0..<17 {XCTAssertEqual(edited.pixel(x:x,y:y).a,source.pixel(x:x,y:y).a)}}
    }
    var hdr=try Surface(width:1,height:1,depth:.f32,colorEncoding:.linearRGB);hdr.setLinearPixel(x:0,y:0,Pixel(-0.5,3,8,0.3));var s=OtherVideoSettings();s.scale=2
    XCTAssertEqual(try OtherVideoEngine.render(hdr,kind:.customFilter,settings:s).linearPixel(x:0,y:0),Pixel(-0.25,1.5,4,0.3))
  }
  func testDeInterlaceUsesOneBasedBoundsAndPremultipliedInterpolation()throws {
    var source=try Surface(width:1,height:5,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<5 {source.setLinearPixel(x:0,y:y,Pixel(Float(y),0,0,y==1 ? 0.25:1))}
    var s=OtherVideoSettings();s.eliminate = .even
    let actual=try OtherVideoEngine.render(source,kind:.deInterlace,settings:s,area:.init(x:0,y:1,width:1,height:3))
    XCTAssertEqual(actual.linearPixel(x:0,y:0),source.linearPixel(x:0,y:0));XCTAssertEqual(actual.linearPixel(x:0,y:1),source.linearPixel(x:0,y:1))
    XCTAssertEqual(actual.linearPixel(x:0,y:2),Pixel(2.6,0,0,0.625));XCTAssertEqual(actual.linearPixel(x:0,y:4),source.linearPixel(x:0,y:4))
    XCTAssertEqual(try OtherVideoEngine.render(try Surface(width:1,height:1,fill:.white),kind:.deInterlace,settings:s).pixel(x:0,y:0),.white)
  }
  func testOffsetSelectionDomainCroppedExpansionMaskAndHistory()throws {
    var d=try CraftDocument(width:8,height:6);d.layers[0].content = .raster(try Surface(width:2,height:2,fill:.white));d.layers[0].x=2;d.layers[0].y=2
    d.layers[0].mask=try Surface(width:2,height:2,fill:.white);let maskTransform=d.layers[0].maskCoordinateTransform,id=d.layers[0].id
    var f=RasterFilter(.offset);f.otherVideo?.horizontal=3;f.otherVideo?.undefinedAreas = .transparent
    var session=EditorSession(document:d);try session.execute(.applyFilter(id,f));let changed=session.document
    XCTAssertEqual(changed.layers[0].maskCoordinateTransform,maskTransform)
    guard case .raster(let out)=changed.layers[0].content else {return XCTFail()};XCTAssertEqual(changed.layers[0].x,0);XCTAssertEqual(out.pixel(x:5,y:2),.white);XCTAssertEqual(out.pixel(x:2,y:2),.clear)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(changed)),changed);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.document,changed)
    var selected=try CraftDocument(width:17,height:13);selected.layers[0].content = .raster(try fixture());selected.selection = .init(x:3,y:2,width:7,height:5)
    let before=selected;f.otherVideo?.horizontal=2;f.otherVideo?.vertical = -1;f.otherVideo?.undefinedAreas = .wrap;try Command.applyFilter(selected.layers[0].id,f).apply(to:&selected)
    guard case .raster(let a)=selected.layers[0].content,case .raster(let b)=before.layers[0].content else {return XCTFail()}
    for y in 0..<13 {for x in 0..<17 {
      if (3..<10).contains(x) && (2..<7).contains(y) {XCTAssertEqual(a.pixel(x:x,y:y),b.pixel(x:3+(x-3-2+7)%7,y:2+(y-2+1)%5))}
      else {XCTAssertEqual(a.pixel(x:x,y:y),b.pixel(x:x,y:y))}
    }}
  }
  func testStrictSettingsPresetAndAtomicGuards()throws {
    for input in ["{\"kind\":\"maximum\",\"otherVideo\":{\"radius\":0.2}}","{\"kind\":\"minimum\",\"otherVideo\":{\"radius\":501}}","{\"kind\":\"customFilter\",\"otherVideo\":{\"kernel\":[1]}}","{\"kind\":\"offset\",\"otherVideo\":{\"horizontal\":1.5}}","{\"kind\":\"hsbHsl\",\"otherVideo\":{\"inputMode\":\"lab\"}}","{\"kind\":\"ntscColors\",\"otherVideo\":{\"scale\":1}}"] {XCTAssertThrowsError(try RasterFilter.decodeJSON(Data(input.utf8)))}
    var s=OtherVideoSettings();s.scale=5;s.kernel[0] = -2;s.offset=23
    XCTAssertEqual(try OtherVideoSettings.decodeCustomPreset(s.encodedCustomPreset()),s)
    XCTAssertThrowsError(try OtherVideoSettings.decodeCustomPreset(Data("{\"kind\":\"offset\"}".utf8)))
    s.horizontal=Int.min;XCTAssertThrowsError(try s.validate(kind:.offset))
    var d=try CraftDocument(width:17,height:13);d.layers[0].content = .raster(try fixture());var f=RasterFilter(.offset);f.otherVideo?.horizontal=35;let before=d
    XCTAssertThrowsError(try Command.applyFilter(d.layers[0].id,f).apply(to:&d));XCTAssertEqual(d,before)
    d.layers[0].locked=true;let locked=d;XCTAssertThrowsError(try Command.applyFilter(d.layers[0].id,RasterFilter(.maximum)).apply(to:&d));XCTAssertEqual(d,locked)
  }
  func testCancellationAndRoundnessBudget()async throws {
    var settings=OtherVideoSettings();settings.radius=500;settings.preserve = .roundness
    XCTAssertThrowsError(try OtherVideoEngine.render(Surface(width:1024,height:512),kind:.maximum,settings:settings))
    let config=settings
    let task=Task.detached {try Task.checkCancellation();return try OtherVideoEngine.render(Surface(width:256,height:256),kind:.maximum,settings:config)};task.cancel()
    do {_ = try await task.value;XCTFail("Cancelled work should not publish output")} catch is CancellationError {} catch {XCTFail("Unexpected error: \(error)")}
  }
}
