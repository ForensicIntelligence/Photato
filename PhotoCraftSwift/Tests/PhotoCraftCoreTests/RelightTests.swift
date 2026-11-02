import Foundation
import XCTest
@testable import PhotoCraftCore

final class RelightTests:XCTestCase {
  struct Entry:Decodable {let name:String,depth:String,width:Int,height:Int,params:RelightSettings,input:String,expected:String}
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/Relight")
  func data(_ name:String)throws->Data{try Data(contentsOf:root.appendingPathComponent(name))}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func words(_ data:Data)->[UInt32]{data.withUnsafeBytes{b in (0..<(data.count/4)).map{UInt32(littleEndian:b.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}}
  func input(_ e:Entry)throws->Surface {
    let raw=words(try data(e.input));XCTAssertEqual(raw.count,e.width*e.height*4);var surface=try Surface(width:e.width,height:e.height,depth:.f32,colorEncoding:.linearRGB)
    for y in 0..<e.height{for x in 0..<e.width{let i=(y*e.width+x)*4;surface.setLinearPixel(x:x,y:y,Pixel(Float(bitPattern:raw[i]),Float(bitPattern:raw[i+1]),Float(bitPattern:raw[i+2]),Float(bitPattern:raw[i+3])))}};return surface
  }
  func testIndependentOriginalFloat32KernelWordsExactly()throws {
    var result=[[String:Any]]()
    for entry in try entries() where entry.depth=="f32" {
      let source=try input(entry),rendered=try RelightEngine.render(source,settings:entry.params),wanted=words(try data(entry.expected));var actual=[UInt32]()
      for y in 0..<entry.height{for x in 0..<entry.width{let p=rendered.linearPixel(x:x,y:y);actual += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]}}
      let changed=zip(actual,wanted).filter{$0 != $1}.count;XCTAssertEqual(changed,0,"\(entry.name): strict original Relight words")
      result.append(["name":entry.name,"words":wanted.count,"changedWords":changed]);XCTAssertEqual(try input(entry),source)
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("relight-core-words.json"))}
  }
  func testIdentityAlphaHDRAndSchemaValidation()throws {
    let entry=try XCTUnwrap(entries().first{$0.depth=="f32" && $0.name=="transparent"}),source=try input(entry);var zero=RelightSettings();zero.intensity=0
    XCTAssertTrue(try RelightEngine.render(source,settings:zero)==source)
    var s=RelightSettings();s.warmth=60;let edited=try RelightEngine.render(source,settings:s)
    var hdr=false
    for y in 0..<source.height{for x in 0..<source.width{let a=source.linearPixel(x:x,y:y),b=edited.linearPixel(x:x,y:y);XCTAssertEqual(a.a.bitPattern,b.a.bitPattern);if a.a==0{XCTAssertTrue(a.hasSameBits(as:b))};hdr = hdr || b.r>1 || b.g>1 || b.b>1}}
    XCTAssertTrue(hdr);XCTAssertNotEqual(source,edited)
    for bad in ["{\"intensity\":101}","{\"angle\":true}","{\"warmth\":-101}","{\"softness\":0}","{\"unknown\":1}"]{XCTAssertThrowsError(try RelightSettings.decodeJSON(Data(bad.utf8)))}
    var filter=RasterFilter(.relight);XCTAssertEqual(try RasterFilter.decodeJSON(Data("{\"kind\":\"relight\"}".utf8)),filter)
    filter.relight=nil;XCTAssertThrowsError(try filter.validate())
    let sparse=try Surface(width:300_000,height:300_000,depth:.f32);XCTAssertTrue(try RelightEngine.render(sparse,settings:zero)==sparse)
    XCTAssertThrowsError(try RelightEngine.render(sparse,settings:.init()))
  }
  func testCancellationIsObservedWithoutInputMutation()async throws {
    let entry=try XCTUnwrap(entries().first{$0.depth=="f32"}),source=try input(entry)
    let worker=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try RelightEngine.render(source,settings:.init())}
    do{_ = try await worker.value;XCTFail("Cancelled Relight must reject")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try input(entry),source)
  }
  func testRasterSelectionLocksSmartHistoryAndNative71()throws {
    let entry=try XCTUnwrap(entries().first{$0.depth=="f32"}),source=try input(entry)
    var d=try CraftDocument(width:source.width,height:source.height,depth:.f32);d.layers[0].content = .raster(source);let id=d.layers[0].id;d.selection=IntRect(x:4,y:3,width:7,height:5)
    var session=EditorSession(document:d);let f=RasterFilter(.relight);try session.execute(.applyFilter(id,f));let changed=session.document;XCTAssertEqual(session.undoStack.count,1)
    guard case .raster(let pixels)=changed.layers[0].content else{return XCTFail("Expected raster")}
    for y in 0..<source.height{for x in 0..<source.width where !(4..<11).contains(x) || !(3..<8).contains(y){XCTAssertTrue(pixels.linearPixel(x:x,y:y).hasSameBits(as:source.linearPixel(x:x,y:y)))}}
    try session.undo();XCTAssertTrue(session.document==d);try session.redo();XCTAssertTrue(session.document==changed)
    d.selection=nil;d.layers[0].smartObject=try SmartObject(fileName:"Owned.png",mediaType:"image/png",data:Data([1]),width:source.width,height:source.height)
    var smart=EditorSession(document:d);try smart.execute(.applyFilter(id,f));XCTAssertEqual(smart.document.minimumArchiveVersion,71);XCTAssertEqual(smart.document.layers[0].smartFilters?.filters.first?.filter,f)
    XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(smart.document))==smart.document);try smart.undo();XCTAssertTrue(smart.document==d)
    d.layers[0].locked=true;var protected=d;XCTAssertThrowsError(try Command.applyFilter(id,f).apply(to:&protected));XCTAssertTrue(protected==d)
  }
}
