import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RelightImportTests:XCTestCase {
  struct Entry:Decodable {let name:String,depth:String,width:Int,height:Int,params:RelightSettings,source:String,expected:String,smartExpected:String,cached:String,uncached:String}
  func data(_ name:String)throws->Data{try PcraftImportTests().fixture(name,folder:"Relight")}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func words(_ bytes:Data)->[UInt32]{bytes.withUnsafeBytes{b in (0..<(bytes.count/4)).map{UInt32(littleEndian:b.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}}
  func sample(_ layer:Layer,_ e:Entry)throws->[UInt32] {
    guard case .raster(let pixels)=layer.content else{throw CraftError.invalid("Expected derived pixels")};var result=[UInt32]()
    for y in 0..<e.height{for x in 0..<e.width{let xx=x-layer.x,yy=y-layer.y,p=xx>=0 && yy>=0 && xx<pixels.width && yy<pixels.height ? (pixels.depth == .f32 ? pixels.linearPixel(x:xx,y:yy):pixels.pixel(x:xx,y:yy)):.clear;result += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]}};return result
  }
  func testOriginalCachedRelightAndTypedNative71AtAllDepths()throws {
    for e in try entries(){let input=try data(e.cached),doc=try PcraftImport.read(input),layer=try XCTUnwrap(doc.layers.first),cached=try XCTUnwrap(layer.originalSmartAppearanceLayer())
      XCTAssertEqual(try sample(cached,e),words(try data(e.smartExpected)),"\(e.name)/\(e.depth): exact original cache");XCTAssertEqual(layer.smartFilters?.filters.first?.filter.relight,e.params);XCTAssertEqual(doc.minimumArchiveVersion,71)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(doc))==doc);XCTAssertEqual(try data(e.cached),input)
      var session=EditorSession(document:doc);try session.execute(SmartObjectIO.rasterizationCommand(layer,in:doc));XCTAssertEqual(try Renderer.composite(session.document),try Renderer.composite(doc));try session.undo();XCTAssertTrue(session.document==doc)
    }
  }
  func testUncachedRelightMatchesIndependentOriginalWords()throws {
    var rows=[[String:Any]]()
    for e in try entries(){let doc=try PcraftImport.read(data(e.uncached)),layer=try XCTUnwrap(doc.layers.first),actual=try sample(SmartFilterEngine.renderedLayer(layer,in:doc),e),wanted=words(try data(e.smartExpected)),changed=zip(actual,wanted).filter{$0 != $1}.count
      XCTAssertEqual(changed,0,"\(e.name)/\(e.depth): strict original Relight rerender");rows.append(["name":e.name,"depth":e.depth,"words":wanted.count,"changedWords":changed])
    }
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("relight-source-words.json"))}
  }
  func testOrdinaryRasterAndSourceReplacementRemainEditable()throws {
    for e in try entries() where e.name=="default"{let bytes=try data(e.source),d=try PcraftImport.read(bytes),id=try XCTUnwrap(d.layers.first?.id);var f=RasterFilter(.relight);f.relight=e.params;var session=EditorSession(document:d);try session.execute(.applyFilter(id,f));XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertTrue(session.document==d);XCTAssertEqual(try data(e.source),bytes)}
  }
}
