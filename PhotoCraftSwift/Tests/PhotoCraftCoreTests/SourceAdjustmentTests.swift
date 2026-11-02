import Foundation
import XCTest
@testable import PhotoCraftCore

final class SourceAdjustmentTests:XCTestCase {
  struct Entry:Decodable {let name:String,depth:String,width:Int,height:Int,x:Int,y:Int,settings:SourceAdjustment,input:String,expected:String,source:String,project:String,merged:String}
  let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("PhotoCraftImagingTests/Fixtures/SourceAdjustments")
  func data(_ name:String)throws->Data {try Data(contentsOf:root.appendingPathComponent(name))}
  func entries()throws->[Entry] {try JSONDecoder().decode([Entry].self,from:data("cases.json"))}
  func words(_ bytes:Data)->[UInt32] {bytes.withUnsafeBytes{p in (0..<(bytes.count/4)).map{UInt32(littleEndian:p.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))}}}
  func depth(_ name:String)->PixelDepth {name=="u8" ? .u8:name=="u16" ? .u16:.f32}
  func capture(_ name:String,_ rows:[[String:Any]])throws {
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {let root=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(name))}
  }
  func testAllIndependentOriginalSourceAdjustmentWordsExactly()throws {
    var rows=[[String:Any]]()
    for e in try entries() {
      let transfer=try SourceAdjustmentTransfer(e.settings,depth:depth(e.depth)),input=words(try data(e.input)),expected=words(try data(e.expected));var actual=[UInt32]()
      for y in 0..<e.height {for x in 0..<e.width {let i=(y*e.width+x)*4,p=Pixel(Float(bitPattern:input[i]),Float(bitPattern:input[i+1]),Float(bitPattern:input[i+2]),Float(bitPattern:input[i+3])),out=transfer.applySourceSample(p,x:x+e.x,y:y+e.y);actual += [out.r.bitPattern,out.g.bitPattern,out.b.bitPattern,out.a.bitPattern]}}
      let changed=zip(actual,expected).filter{$0 != $1}.count
      XCTAssertEqual(actual.count,expected.count);XCTAssertEqual(changed,0,"\(e.name)/\(e.depth): strict original working samples")
      rows.append(["name":e.name,"depth":e.depth,"words":expected.count,"changedWords":changed])
    };try capture("source-adjustment-core-words.json",rows)
  }
  func testFractionalControlsRoundTripAndAllKindsRemainTyped()throws {
    let es=try entries();XCTAssertEqual(Set(es.map{$0.settings.kind}),Set(SourceAdjustment.Kind.allCases))
    for e in es {try e.settings.validate();XCTAssertEqual(try JSONDecoder().decode(SourceAdjustment.self,from:JSONEncoder().encode(e.settings)),e.settings)}
    let e=try XCTUnwrap(es.first{$0.name=="levels-fractional"});XCTAssertEqual(e.settings.records["channels"]?[0][0].bitPattern,Float(0.0713).bitPattern)
    let l=try XCTUnwrap(es.first{$0.name=="lookup-icc-identity"});XCTAssertTrue(l.settings.isOpaque);XCTAssertNil(l.settings.records["lut"])
    let u=try XCTUnwrap(es.first{$0.settings.kind == .unsupported});XCTAssertEqual(u.settings.opaqueData,Data([1,7,33,255]));XCTAssertEqual(u.settings.opaqueKey,"test")
  }
  func testMalformedUnknownOversizedAndForeignToneSpaceReject()throws {
    let es=try entries(),base=try XCTUnwrap(es.first).settings
    var bad=base;bad.parameters["unknown"]=1;XCTAssertThrowsError(try bad.validate());bad=base;bad.parameters["brightness"] = .infinity;XCTAssertThrowsError(try bad.validate())
    bad=base;bad.options["unexpected"]=true;XCTAssertThrowsError(try bad.validate())
    bad=try XCTUnwrap(es.first{$0.settings.kind == .levels}).settings;bad.records["channels"]?[0][1]=0;XCTAssertThrowsError(try bad.validate())
    bad=try XCTUnwrap(es.first{$0.settings.kind == .channelMixer}).settings;bad.records["matrix"]=[[1,0]];XCTAssertThrowsError(try bad.validate())
    bad=try XCTUnwrap(es.first{$0.settings.kind == .colorLookup}).settings;bad.records["lut"]=[[0,1,2]];XCTAssertThrowsError(try bad.validate())
    bad=try XCTUnwrap(es.first{$0.settings.kind == .levels}).settings;bad.space = .cmyk;try bad.validate();XCTAssertThrowsError(try SourceAdjustmentTransfer(bad,depth:.u8))
    bad=base;bad.opaqueData=Data([0]);XCTAssertThrowsError(try bad.validate())
  }
  func testAlphaOpaqueBitsHistorySelectionAndNative74Admission()throws {
    for e in try entries() where e.depth=="u8" {
      let value=e.settings,transfer=try SourceAdjustmentTransfer(value,depth:.u8),hidden=Pixel(0.375,0.8125,0.125,0)
      for depth in PixelDepth.allCases {XCTAssertTrue(try SourceAdjustmentTransfer(value,depth:depth).apply(hidden).hasSameBits(as:hidden),"Hidden source colors at every depth")}
      XCTAssertTrue(transfer.apply(hidden).hasSameBits(as:hidden));XCTAssertEqual(transfer.apply(Pixel(0.25,0.5,0.75,0.375)).a.bitPattern,Float(0.375).bitPattern)
      var d=try CraftDocument(width:5,height:3,depth:.u8);d.selection = .init(x:1,y:1,width:2,height:1);var session=EditorSession(document:d)
      let layer=try value.layer(in:d);try session.execute(.addLayer(layer));XCTAssertEqual(session.document.minimumArchiveVersion,74);XCTAssertEqual(session.document.selection,d.selection)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(session.document)),session.document);try session.undo();XCTAssertEqual(session.document,d);try session.redo();XCTAssertEqual(session.undoStack.count,1)
    }
  }
}
