import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PcraftSmartImportTests:XCTestCase {
  struct Entry:Decodable {let name:String,depth:String,file:String,expected:String,cached:Bool,width:Int,height:Int}
  func file(_ name:String)throws->Data{try PcraftImportTests().fixture(name,folder:"PcraftSmart")}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:file("cases.json"))}
  func samples(_ layer:Layer,entry:Entry)throws->[UInt32] {
    guard case .raster(let pixels)=layer.content else{throw CraftError.invalid("Expected projected raster.")}
    XCTAssertEqual(layer.affine,nil)
    var words=[UInt32]();words.reserveCapacity(entry.width*entry.height*4)
    for y in 0..<entry.height{for x in 0..<entry.width{
      let sx=x-layer.x,sy=y-layer.y
      let value=sx>=0 && sy>=0 && sx<pixels.width && sy<pixels.height ? (pixels.depth == .f32 ? pixels.linearPixel(x:sx,y:sy):pixels.pixel(x:sx,y:sy)):.clear
      words.append(contentsOf:[value.r.bitPattern,value.g.bitPattern,value.b.bitPattern,value.a.bitPattern])
    }};return words
  }
  func expected(_ entry:Entry)throws->[UInt32] {
    let data=try file(entry.expected);XCTAssertEqual(data.count,entry.width*entry.height*16)
    return data.withUnsafeBytes{raw in (0..<(data.count/4)).map{UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}
  }
  func compare(cached:Bool)throws {
    var measurements=[[String:Any]]()
    for entry in try entries() where entry.cached==cached && !["linked-cached","unsupported-cached"].contains(entry.name) {
      let input=try file(entry.file),doc=try PcraftImport.read(input),layer=try XCTUnwrap(doc.layers.first)
      let projected:Layer
      if cached{projected=try XCTUnwrap(layer.originalSmartAppearanceLayer())}else{projected=try SmartFilterEngine.renderedLayer(layer,in:doc)}
      let actual=try samples(projected,entry:entry),wanted=try expected(entry),different=zip(actual,wanted).filter{$0 != $1}.count
      measurements.append(["name":entry.name,"depth":entry.depth,"words":wanted.count,"changedWords":different,"cached":cached])
      XCTAssertEqual(actual.count,wanted.count);XCTAssertEqual(different,0,"\(entry.name)/\(entry.depth): strict original Smart render words")
      XCTAssertNotNil(layer.smartObject);XCTAssertEqual(layer.smartObject?.mediaType,PcraftImport.mediaType)
      XCTAssertNotNil(layer.pristineSmartAppearance);XCTAssertEqual(try file(entry.file),input)
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
      try JSONSerialization.data(withJSONObject:measurements,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(cached ? "source-smart-cache-words.json":"source-smart-uncached-words.json"))
    }
  }
  func testOriginalCachedSmartSamplesMatchExactlyAtAllDepths()throws{try compare(cached:true)}
  func testUncachedSmartRenderingMatchesExactOriginalEngineWords()throws{try compare(cached:false)}
  func testOriginalSourceSharedIdentityNestedStackControlsAndNative70()throws {
    for bits in ["u8","u16","f32"] {
      for name in ["affine-cached","projective-cached","warp-cached","filtermask-cached","mask-cached","nested-cached","shared"] {
        let input=try file("\(name)-\(bits).pcraft"),doc=try PcraftImport.read(input),layer=try XCTUnwrap(doc.layers.first),object=try XCTUnwrap(layer.smartObject)
        XCTAssertEqual(doc.minimumArchiveVersion,70);XCTAssertFalse(object.data.isEmpty);XCTAssertEqual(layer.importedSmartAppearance?.placedRecord,Data("OWNED-PHOTATO-PLACED-RECORD".utf8))
        let child=try SmartObjectIO.sourceDocument(object);XCTAssertEqual(child.width,object.width);XCTAssertEqual(child.height,object.height)
        XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(doc))==doc)
        if name=="projective-cached"{XCTAssertNotNil(layer.sourceProjection)}
        if name=="warp-cached"{XCTAssertEqual(layer.warp?.style,.arch);XCTAssertEqual(layer.warp?.sourceBounds?.width,16)}
        if name=="mask-cached"{XCTAssertEqual(layer.maskCoordinateTransform,.identity);XCTAssertEqual(layer.effectiveMaskProperties.density,0.8)}
        if name=="filtermask-cached"{XCTAssertEqual(layer.smartFilters?.maskProperties.transform,.identity);XCTAssertEqual(layer.smartFilters?.filters.first?.opacity,0.65)}
        if name=="nested-cached"{XCTAssertNotNil(child.layers.first?.smartObject)}
        if name=="shared"{XCTAssertEqual(doc.layers.count,2);XCTAssertEqual(doc.layers[0].smartObject?.sourceID,doc.layers[1].smartObject?.sourceID)}
      }
      for mode in ImageStackMode.allCases {
        let doc=try PcraftImport.read(file("stack-\(mode.rawValue)-\(bits).pcraft"))
        XCTAssertEqual(doc.layers.first?.smartObject?.stackMode,mode)
      }
    }
  }
  func testCachedRasterizationResetAndProjectedReplacementAreUndoable()throws {
    for bits in ["u8","u16","f32"] {
      let original=try PcraftImport.read(file("projective-cached-\(bits).pcraft")),layer=try XCTUnwrap(original.layers.first),id=layer.id
      let before=try Renderer.composite(original)
      var session=EditorSession(document:original);try session.execute(SmartObjectIO.rasterizationCommand(layer,in:original))
      XCTAssertNil(session.document.layers.first?.smartObject);XCTAssertNil(session.document.layers.first?.sourceProjection);XCTAssertNil(session.document.layers.first?.importedSmartAppearance)
      XCTAssertTrue(try Renderer.composite(session.document)==before);try session.undo();XCTAssertTrue(session.document==original)
      try session.execute(.resetSmartObjectTransform(id));XCTAssertNil(session.document.layers.first?.sourceProjection);try session.undo();XCTAssertTrue(session.document==original)
      let object=try SmartObject(fileName:"Owned replacement.png",mediaType:"image/png",data:Data([1]),width:32,height:24)
      let pixels=try Surface(width:32,height:24,depth:original.depth,fill:.white)
      try session.execute(.replaceSmartObject(id,object,pixels,preserveSize:true,allInstances:false))
      let updated=try XCTUnwrap(session.document.layers.first?.sourceProjection),old=try XCTUnwrap(layer.sourceProjection)
      let a=try updated.point(32,24),b=try old.point(16,12);XCTAssertEqual(a.x,b.x,accuracy:1e-12);XCTAssertEqual(a.y,b.y,accuracy:1e-12)
      XCTAssertNil(session.document.layers.first?.pristineSmartAppearance);try session.undo();XCTAssertTrue(session.document==original)
    }
    var doc=try PcraftImport.read(file("warp-cached-u8.pcraft"));let id=doc.layers[0].id
    let source=try SmartObject(fileName:"Replacement.png",mediaType:"image/png",data:Data([1]),width:32,height:24)
    try Command.replaceSmartObject(id,source,Surface(width:32,height:24),preserveSize:true,allInstances:false).apply(to:&doc)
    XCTAssertEqual(doc.layers[0].warp?.sourceBounds?.width,32);XCTAssertEqual(doc.layers[0].warp?.sourceBounds?.height,24)
  }
  func testUnsupportedLinkedUnknownProgramBudgetAndCancellationRemainAtomic()async throws {
    for bits in ["u8","u16","f32"]{for name in ["linked-cached","unsupported-cached"]{XCTAssertThrowsError(try PcraftImport.read(file("\(name)-\(bits).pcraft")))}}
    let input=try file("affine-cached-u8.pcraft");XCTAssertThrowsError(try PcraftImport.read(input,rasterByteLimit:1))
    let project=try PcraftImportTests().source(input){doc in var layers=doc["layers"]as![[String:Any]],content=layers[0]["content"]as![String:Any];content["unknown"]=true;layers[0]["content"]=content;doc["layers"]=layers}
    XCTAssertThrowsError(try PcraftImportTests().convert(project))
    let task=Task{while !Task.isCancelled{await Task.yield()};return try PcraftImport.read(input)};task.cancel();do{_ = try await task.value;XCTFail("Cancelled import")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try file("affine-cached-u8.pcraft"),input)
  }
}
