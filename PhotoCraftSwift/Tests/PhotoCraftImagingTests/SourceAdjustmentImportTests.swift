import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class SourceAdjustmentImportTests:XCTestCase {
  let helper=SourceAdjustmentFixture()
  func testEverySourceKindRetainsEditableFloatControlsAndNative74()throws {
    for e in try helper.entries() {
      let bytes=try helper.data(e.project),d=try PcraftImport.read(bytes);XCTAssertEqual(d.layers.count,2)
      if e.settings.kind == .exposure {guard case .adjustment(.classic(let a))=d.layers[1].content else {return XCTFail("Existing Exposure representation changed")};XCTAssertEqual(a.exposureSettings?.exposure,e.settings.parameters["exposure"]);XCTAssertEqual(d.minimumArchiveVersion,67)}
      else {guard case .adjustment(.source(let a))=d.layers[1].content else {return XCTFail("Typed original adjustment")};XCTAssertEqual(a,e.settings,"\(e.name)/\(e.depth)");XCTAssertEqual(d.minimumArchiveVersion,74)}
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d);XCTAssertEqual(try helper.data(e.project),bytes)
      var session=EditorSession(document:d);try session.execute(.opacity(d.layers[1].id,0.375));try session.undo();XCTAssertEqual(session.document,d)
    }
  }
  func testOriginalDepthEncodedCompositeWordsExactly()throws {
    var rows=[[String:Any]]()
    for e in try helper.entries() {
      let d=try PcraftImport.read(helper.data(e.project)),working=try Renderer.composite(d),surface=try working.quantizedStoredDepth(d.depth),expected=helper.words(try helper.data(e.mergedStored)),rawExpected=helper.words(try helper.data(e.merged));var actual=[UInt32](),rawActual=[UInt32]()
      for y in 0..<e.height {for x in 0..<e.width {let p=d.depth == .f32 ? surface.linearPixel(x:x,y:y):surface.pixel(x:x,y:y);actual += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern];let raw=d.depth == .f32 ? working.linearPixel(x:x,y:y):working.pixel(x:x,y:y);rawActual += [raw.r.bitPattern,raw.g.bitPattern,raw.b.bitPattern,raw.a.bitPattern]}}
      let rawChanged=zip(rawActual,rawExpected).filter{$0 != $1}.count
      XCTAssertEqual(rawChanged,0,"\(e.name)/\(e.depth): strict original working composite")
      let changed=zip(actual,expected).filter{$0 != $1}.count;XCTAssertEqual(changed,0,"\(e.name)/\(e.depth): strict original full composite")
      let first=actual.indices.filter{actual[$0] != expected[$0]}.prefix(6).map{["index":$0,"actual":actual[$0],"expected":expected[$0]] as [String:Any]}
      rows.append(["name":e.name,"depth":e.depth,"words":expected.count,"changedWords":changed,"rawChangedWords":rawChanged,"firstDifferences":first])
    };try helper.capture("source-adjustment-composite-words.json",rows)
  }
  func testUnknownFieldsInvalidShapeForeignToneAndOpaqueBytesAreNotDropped()throws {
    let e=try XCTUnwrap(helper.entries().first{$0.settings.kind == .vibrance}),data=try helper.data(e.project)
    for adjustment:[String:Any] in [["Vibrance":["vibrance":1,"saturation":2,"extra":3]],["ChannelMixer":["matrix":[[1,0]],"monochrome":false]],["Unknown":[:]]] {
      let p=try PcraftImportTests().source(data){d in var layers=d["layers"]as![[String:Any]];layers[1]["content"]=["kind":"adjustment","adjustment":adjustment];d["layers"]=layers};XCTAssertThrowsError(try PcraftImportTests().convert(p))
    }
    XCTAssertThrowsError(try PcraftImport.read(data,rasterByteLimit:1));XCTAssertEqual(try helper.data(e.project),data)
  }
  func testCancelledOriginalAdjustmentImportLeavesOriginalBytes()async throws {
    let e=try XCTUnwrap(helper.entries().first{$0.settings.kind == .colorLookup}),data=try helper.data(e.project)
    let task=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try PcraftImport.read(data)}
    do{_ = try await task.value;XCTFail("Cancelled import")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try helper.data(e.project),data)
  }
}
struct SourceAdjustmentFixture {
  struct Entry:Decodable {let name:String,depth:String,width:Int,height:Int,settings:SourceAdjustment,project:String,source:String,merged:String,mergedStored:String}
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/SourceAdjustments")
  func data(_ name:String)throws->Data {try Data(contentsOf:root.appendingPathComponent(name))}
  func entries()throws->[Entry]{try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func words(_ data:Data)->[UInt32]{data.withUnsafeBytes{p in (0..<(data.count/4)).map{UInt32(littleEndian:p.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}}
  func capture(_ name:String,_ rows:[[String:Any]])throws {if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let root=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(name))}}
}
