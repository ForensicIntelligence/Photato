import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LightingImportTests:XCTestCase {
  struct Entry:Decodable{let name:String,depth:String,width:Int,height:Int,params:LightingSettings,cached:String,uncached:String,smartExpected:String,source:String}
  func data(_ name:String)throws->Data{try PcraftImportTests().fixture(name,folder:"Lighting")}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func words(_ data:Data)->[UInt32]{data.withUnsafeBytes{b in (0..<(data.count/4)).map{UInt32(littleEndian:b.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}}
  func samples(_ layer:Layer,_ e:Entry)throws->[UInt32]{guard case .raster(let s)=layer.content else{throw CraftError.invalid("Expected lighting pixels.")};var out=[UInt32]();for y in 0..<e.height{for x in 0..<e.width{let xx=x-layer.x,yy=y-layer.y,p=xx>=0 && yy>=0 && xx<s.width && yy<s.height ? (s.depth == .f32 ? s.linearPixel(x:xx,y:yy):s.pixel(x:xx,y:yy)):.clear;out += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]}};return out}
  func testOriginalCachedProgramsTypedControlsNative72AndHistory()throws{
    var rows=[[String:Any]]()
    for e in try entries(){let input=try data(e.cached),d=try PcraftImport.read(input),layer=try XCTUnwrap(d.layers.first),cache=try XCTUnwrap(layer.originalSmartAppearanceLayer()),wanted=words(try data(e.smartExpected)),actual=try samples(cache,e),changed=zip(actual,wanted).filter{$0 != $1}.count
      XCTAssertEqual(changed,0,"\(e.name)/\(e.depth): exact original cache");var expected=e.params;if expected.lights.isEmpty{expected.lights=try XCTUnwrap(entries().first{$0.name=="default" && $0.depth==e.depth}).params.lights};XCTAssertEqual(layer.smartFilters?.filters.first?.filter.lighting,expected);XCTAssertEqual(d.minimumArchiveVersion,72);XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(d))==d)
      var session=EditorSession(document:d);try session.execute(SmartObjectIO.rasterizationCommand(layer,in:d));XCTAssertEqual(try Renderer.composite(session.document),try Renderer.composite(d));try session.undo();XCTAssertTrue(session.document==d);XCTAssertEqual(try data(e.cached),input)
      rows.append(["name":e.name,"depth":e.depth,"words":wanted.count,"changedWords":changed])
    };try capture(rows,"lighting-cached-words.json")
  }
  func testUncachedProgramsMatchIndependentOriginalWordsExactly()throws{
    var rows=[[String:Any]]()
    for e in try entries(){let d=try PcraftImport.read(data(e.uncached)),layer=try XCTUnwrap(d.layers.first),wanted=words(try data(e.smartExpected)),actual=try samples(SmartFilterEngine.renderedLayer(layer,in:d),e),changed=zip(actual,wanted).filter{$0 != $1}.count;XCTAssertEqual(changed,0,"\(e.name)/\(e.depth): strict original lighting rerender");let first=zip(actual,wanted).enumerated().filter{$0.element.0 != $0.element.1}.prefix(16).map{["index":$0.offset,"actual":$0.element.0,"expected":$0.element.1] as [String:Any]};rows.append(["name":e.name,"depth":e.depth,"words":wanted.count,"changedWords":changed,"firstDifferences":first])};try capture(rows,"lighting-source-words.json")
  }
  func testOriginalRootListDispatchAndOrdinaryRasterSourceRetention()throws{
    XCTAssertEqual(PcraftImport.sourceSmartFilterCommands.count,110);XCTAssertEqual(PcraftImport.unsupportedSourceSmartFilterCommands,[])
    for e in try entries() where ["default","root-fallback","ignored-fallback","off-canvas"].contains(e.name){let input=try data(e.source),d=try PcraftImport.read(input);var f=RasterFilter(.lightingEffects);f.lighting=e.params;var session=EditorSession(document:d);try session.execute(.applyFilter(d.layers[0].id,f));XCTAssertEqual(session.undoStack.count,1);try session.undo();XCTAssertTrue(session.document==d);XCTAssertEqual(try data(e.source),input)}
  }
  func capture(_ rows:[[String:Any]],_ name:String)throws{if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent(name))}}
}
