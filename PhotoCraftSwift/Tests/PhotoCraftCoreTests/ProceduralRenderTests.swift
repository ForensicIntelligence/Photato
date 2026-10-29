import Foundation
import XCTest
@testable import PhotoCraftCore

final class ProceduralRenderTests:XCTestCase {
  static let points=[PathPoint(20,80),PathPoint(40,64),PathPoint(80,70),PathPoint(108,25)]
  static var path:VectorPath {VectorPath(components:[PathComponent(knots:points.map{PathKnot($0)})])}
  func sample(_ depth:PixelDepth = .u8)throws->Surface {
    var s=try Surface(width:128,height:96,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<96 {for x in 0..<128 {s.setPixel(x:x,y:y,Pixel(Float((17*x+3*y)%256)/255,Float((5*x+23*y)%256)/255,Float((11*x+7*y)%256)/255,Float(64+(x+y)%192)/255))}};return s
  }
  func testOriginalRustPixelsForAllTreeFrameAndFlameVariants()throws {
    let url=try XCTUnwrap(Bundle.module.url(forResource:"provenance",withExtension:"json",subdirectory:"Fixtures/ProceduralRender"))
    let proof=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any],cases=proof["cases"] as! [[String:Any]];XCTAssertEqual(cases.count,70)
    var measurements=[[String:Any]]();let source=try sample()
    for c in cases {
      let kind=try XCTUnwrap(ProceduralRenderSettings.Kind(rawValue:c["kind"] as! String)),name=c["name"] as! String,data=try JSONSerialization.data(withJSONObject:c["parameters"]!)
      var s=ProceduralRenderSettings(kind)
      switch kind {case .flame:s.flame=try JSONDecoder().decode(FlameSettings.self,from:data);case .tree:s.tree=try JSONDecoder().decode(TreeSettings.self,from:data);case .pictureFrame:s.frame=try JSONDecoder().decode(PictureFrameSettings.self,from:data)}
      let actual=try ProceduralRenderEngine.render(source,settings:s,paths:[Self.points]).rgbaData(depth:.u8),expected=try Data(contentsOf:url.deletingLastPathComponent().appendingPathComponent(name+".rgba"))
      let differences=zip(actual,expected).map{abs(Int($0)-Int($1))},count=differences.filter{$0>0}.count,maxDifference=differences.max() ?? 0
      var measurement:[String:Any]=["name":name,"maximumByteDifference":maxDifference,"differentSamples":count]
      if count>0,let paint=try ProceduralRenderEngine.paint(s,width:128,height:96,paths:[Self.points]) {
        measurement["firstDifferences"]=differences.indices.filter{differences[$0]>0}.prefix(12).map {offset -> [String:Any] in
          let x=offset/4%128,y=offset/4/128,p=paint.values[(y-paint.rect.y)*paint.rect.width+x-paint.rect.x],d=source.pixel(x:x,y:y)
          let o=ProceduralRenderEngine.over(p,d,coverage:1,preserve:false)
          return ["x":x,"y":y,"channel":offset%4,"actual":actual[offset],"expected":expected[offset],"paint":[p.x,p.y,p.z,p.w],"destination":[d.r,d.g,d.b,d.a],"over":[o.r,o.g,o.b,o.a]]
        }
      }
      measurements.append(measurement);XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(count,0,"\(name): max difference\(maxDifference)")
    }
    let folder=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("artifacts/procedural-oracle-comparisons");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(UUID().uuidString+".json"))
  }
  func testPrimitiveCoverageCompositingAndTransparencyLock()throws {
    typealias G=ProceduralGeometry
    let p=G.Primitive.disc(G.Point(0.5,0.5),2,G.Color(1,0,0,0.5)),paint=try G.rasterize([p],in:IntRect(x:0,y:0,width:1,height:1))[0]
    XCTAssertEqual(paint,G.Color(0.5,0,0,0.5))
    let result=ProceduralRenderEngine.over(paint,Pixel(0,0,1,0.5),coverage:1,preserve:false)
    XCTAssertEqual(result.r,2/3,accuracy:1e-6);XCTAssertEqual(result.b,1/3,accuracy:1e-6);XCTAssertEqual(result.a,0.75)
    XCTAssertEqual(ProceduralRenderEngine.over(paint,Pixel(0,0,1,0.5),coverage:1,preserve:true),Pixel(0.5,0,0.5,0.5))
    let hidden=Pixel(0.2,0.7,0.8,0);XCTAssertEqual(ProceduralRenderEngine.over(paint,hidden,coverage:1,preserve:true),hidden)
    XCTAssertEqual(ProceduralRenderEngine.over(paint,hidden,coverage:0,preserve:false),hidden)
    XCTAssertEqual(try G.rasterize([p,p.softened(1,.add)],in:.init(x:0,y:0,width:1,height:1))[0],G.Color(1,0,0,0.75))
    XCTAssertEqual(try G.rasterize([p,p.softened(1,.lighten)],in:.init(x:0,y:0,width:1,height:1))[0],paint)
  }
  func testSeedRepeatabilityAndNativeGenerationAcrossDepths()throws {
    for kind in ProceduralRenderSettings.Kind.allCases {
      var s=ProceduralRenderSettings(kind);s.flame.width=14;s.flame.length=40;s.tree.seed=42;s.frame.seed=42;s.flame.seed=42
      let source=try sample(),a=try ProceduralRenderEngine.render(source,settings:s,paths:[Self.points]);XCTAssertEqual(a,try ProceduralRenderEngine.render(source,settings:s,paths:[Self.points]))
      s.tree.seed=43;s.frame.seed=43;s.flame.seed=43;XCTAssertNotEqual(a,try ProceduralRenderEngine.render(source,settings:s,paths:[Self.points]))
      for depth in [PixelDepth.u16,.f32] {let original=try sample(depth),rendered=try ProceduralRenderEngine.render(original,settings:s,paths:[Self.points]);XCTAssertNotEqual(original,rendered);XCTAssertEqual(original.colorEncoding,rendered.colorEncoding);XCTAssertEqual(rendered.depth,depth)}
    }
  }
  func testSelectionStorageMasksHistoryAndNativePersistence()throws {
    for kind in ProceduralRenderSettings.Kind.allCases {for linked in [true,false] {
      var d=try CraftDocument(width:128,height:96);d.layers[0].content = .raster(try Surface(width:4,height:4,fill:Pixel(1,0,0,0.5)));d.layers[0].x=60;d.layers[0].y=40;d.layers[0].protection=[.position]
      d.layers[0].mask=try Surface(width:4,height:4,fill:.white);var properties=d.layers[0].effectiveMaskProperties;properties.linked=linked;d.layers[0].maskProperties=properties;d.selection = .init(x:0,y:0,width:64,height:96)
      let mask=d.layers[0].maskCoordinateTransform,original=d;var session=EditorSession(document:d)
      let request=ProceduralRenderRequest(.init(kind),layerID:d.layers[0].id,path:kind == .flame ? Self.path:nil)
      try session.execute(.proceduralRender(request));let edited=session.document;XCTAssertNotEqual(edited,original);XCTAssertEqual(edited.layers[0].mask,original.layers[0].mask);XCTAssertEqual(edited.layers[0].maskCoordinateTransform,mask)
      guard case .raster(let pixels)=edited.layers[0].content else{return XCTFail()};let inv=try edited.layers[0].coordinateTransform.inverted()
      for y in 0..<96 {for x in 64..<128 {let q=inv.point(Double(x)+0.5,Double(y)+0.5);XCTAssertEqual(pixels.pixel(x:Int(floor(q.x)),y:Int(floor(q.y))),.clear)}}
      let data=try NativeArchive.encode(edited);XCTAssertEqual(try NativeArchive.decode(data),edited)
      try session.undo();XCTAssertEqual(session.document,original);try session.redo();XCTAssertEqual(session.document,edited)
    }}
  }
  func testNewLayerNoOpAndInvalidRequestsAreAtomic()throws {
    var d=try CraftDocument(width:128,height:96);d.paths=[NamedPath(path:Self.path)];let original=d
    var s=ProceduralRenderSettings(.flame);s.flame.opacity=0
    try Command.proceduralRender(.init(s,newLayer:true)).apply(to:&d);XCTAssertEqual(d,original)
    s.flame.opacity=75;try Command.proceduralRender(.init(s,newLayer:true)).apply(to:&d);XCTAssertEqual(d.layers.count,2);XCTAssertEqual(d.layers[0],original.layers[0]);XCTAssertEqual(d.paths,original.paths);XCTAssertEqual(d.layers.last?.name,"Flame")
    let before=d;s.tree.size = .nan;XCTAssertThrowsError(try Command.proceduralRender(.init(s)).apply(to:&d));XCTAssertEqual(d,before)
    var locked=original;locked.layers[0].protection=[.image];let initial=locked
    XCTAssertThrowsError(try Command.proceduralRender(.init(.init(.tree))).apply(to:&locked));XCTAssertEqual(locked,initial)
    XCTAssertThrowsError(try ProceduralRenderEngine.render(sample(),settings:.init(.flame)))
    var huge=ProceduralRenderSettings(.flame);huge.flame.interval=1;huge.flame.flameType = .multipleFlamesAlongPath
    XCTAssertThrowsError(try ProceduralRenderEngine.render(sample(),settings:huge,paths:[[PathPoint(0,0),PathPoint(1_000_000,0)]]))
  }
  func testSettingsRoundTripRangesAndImmutableCopies()throws {
    for kind in ProceduralRenderSettings.Kind.allCases {let request=ProceduralRenderRequest(.init(kind),path:kind == .flame ? Self.path:nil);XCTAssertEqual(try JSONDecoder().decode(ProceduralRenderRequest.self,from:JSONEncoder().encode(request)),request);try request.validate()}
    let original=ProceduralRenderSettings(.tree);var copy=original;copy.tree.seed=42;XCTAssertEqual(original.tree.seed,0)
    var bad=original;bad.tree.baseTreeType=35;XCTAssertThrowsError(try bad.validate());bad=original;bad.tree.leavesColor.r = .infinity;XCTAssertThrowsError(try bad.validate())
    bad=original;bad.frame.lines=6;XCTAssertThrowsError(try bad.validate());bad=original;bad.flame.quality = -1;XCTAssertThrowsError(try bad.validate())
    XCTAssertThrowsError(try ProceduralRenderEngine.primitives(original,width:32768,height:32768,paths:[]))
  }
  func testCancellationDoesNotPublishPartialRender()async throws {
    let original=try CraftDocument(width:128,height:96)
    for kind in ProceduralRenderSettings.Kind.allCases {
      let task=Task {()throws->CraftDocument in withUnsafeCurrentTask{$0?.cancel()};var d=original;try Command.proceduralRender(.init(.init(kind),path:kind == .flame ? Self.path:nil)).apply(to:&d);return d};task.cancel()
      do{_=try await task.value;XCTFail("Expected cancellation")}catch is CancellationError{}catch{XCTFail("Unexpected: \(error)")}
    }
  }
}
