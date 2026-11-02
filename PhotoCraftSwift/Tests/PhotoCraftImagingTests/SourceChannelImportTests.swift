import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class SourceChannelImportTests:XCTestCase {
  func folder()throws->URL {try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("SourceChannels")}
  func rows()throws->[[String:Any]] {try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:folder().appendingPathComponent("cases.json")))as?[[String:Any]])}
  func data(_ file:String)throws->Data {try Data(contentsOf:folder().appendingPathComponent(file))}
  func words(_ file:String)throws->[UInt32] {let input=try data(file);return input.withUnsafeBytes{b in stride(from:0,to:b.count,by:4).map{UInt32(littleEndian:b.loadUnaligned(fromByteOffset:$0,as:UInt32.self))}}}
  func testOriginalAlphaSpotsAndQuickMaskRetainEveryCanvasWordAtAllDepths()throws {
    let entries=try rows();XCTAssertEqual(entries.count,3)
    for row in entries {
      let bytes=try data(row["project"]as!String),d=try PcraftImport.read(bytes),channels=try XCTUnwrap(d.alphaChannels)
      XCTAssertEqual(channels.count,3);XCTAssertEqual(d.minimumArchiveVersion,76)
      let all=channels+[try XCTUnwrap(d.quickMask)],refs=row["channels"]as![String]
      for (channel,file)in zip(all,refs) {
        let expected=try words(file);XCTAssertEqual(expected.count,d.width*d.height)
        for y in 0..<d.height {for x in 0..<d.width {XCTAssertEqual(channel.pixels.pixel(x:x,y:y).r.bitPattern,expected[y*d.width+x],"\(file) \(x),\(y)")}}
        XCTAssertEqual(channel.options.opacity,0.375);XCTAssertEqual(channel.options.indicates,.selectedAreas)
      }
      XCTAssertNil(channels[0].spot);XCTAssertEqual(channels[1].spot?.solidity,0);XCTAssertEqual(channels[2].spot?.solidity,0.625)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      let again=try PcraftImport.read(bytes);XCTAssertEqual(again,d)
      var session=EditorSession(document:d);try session.execute(.channel(.fill(.alpha(channels[1].id),0,1)));try session.undo();XCTAssertEqual(session.document,d)
      let psd=try PSDCodec.read(PSDCodec.writeRasterLayers(d));XCTAssertEqual(psd.alphaChannels?.count,3);XCTAssertNotNil(psd.quickMask);XCTAssertEqual(try data(row["project"]as!String),bytes)
    }
  }
  func testOverprintPreviewMatchesIndependentOriginalFloatWords()throws {
    for row in try rows() {
      let d=try PcraftImport.read(data(row["project"]as!String)),expected=try words(row["overprint"]as!String)
      var actual:[UInt32]=[]
      for y in 0..<d.height {for x in 0..<d.width {
        var p=Pixel.white
        for channel in d.alphaChannels ?? [] {if let ink=channel.spot {p=ink.preview(density:channel.pixels.pixel(x:x,y:y).r,over:p)}}
        actual += [p.r.bitPattern,p.g.bitPattern,p.b.bitPattern,p.a.bitPattern]
      }}
      XCTAssertEqual(actual,expected,"Original overprint \(row["depth"]!)")
    }
  }
  func testMalformedChannelsUnknownFieldsLimitsAndSpotQuickMaskRejectWholeImport()throws {
    let bytes=try data("channels-u8.pcraft"),helper=PcraftImportTests()
    for change in 0..<4 {
      let source=try helper.source(bytes){document in
        var channels=document["channels"]as![[String:Any]]
        if change==0 {channels[0]["surprise"]=true}
        if change==1 {channels[1]["spot"]=[channels[1]["color"]!,2.0]}
        if change==2 {document["quick_mask"]=channels[1]}
        if change==3 {channels=Array(repeating:channels[0],count:53)}
        document["channels"]=channels
      }
      XCTAssertThrowsError(try helper.convert(source))
    }
    XCTAssertThrowsError(try PcraftImport.read(bytes,rasterByteLimit:1));XCTAssertEqual(try data("channels-u8.pcraft"),bytes)
  }
  func testCancelledChannelImportLeavesOriginalUnchanged()async throws {
    let input=try data("channels-f32.pcraft")
    let task=Task.detached {withUnsafeCurrentTask{$0?.cancel()};return try PcraftImport.read(input)}
    do{_ = try await task.value;XCTFail("Cancellation expected")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try data("channels-f32.pcraft"),input)
  }
}
