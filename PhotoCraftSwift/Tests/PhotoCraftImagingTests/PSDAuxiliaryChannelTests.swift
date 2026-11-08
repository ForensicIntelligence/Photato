import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDAuxiliaryChannelTests:XCTestCase {
  func folder()throws->URL {try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("PSDAuxiliary")}
  func data(_ name:String)throws->Data {try Data(contentsOf:folder().appendingPathComponent(name))}
  func rows()throws->[[String:Any]] {try XCTUnwrap(JSONSerialization.jsonObject(with:data("cases.json"))as?[[String:Any]])}
  func compare(_ document:CraftDocument,row:[String:Any],file:StaticString = #filePath,line:UInt = #line)throws {
    let channels=PSDAuxiliaryChannels.all(document),expected=row["planes"]as![String]
    XCTAssertEqual(channels.count,3,file:file,line:line);XCTAssertEqual(channels.map(\.name),row["names"]as![String],file:file,line:line)
    for(index,channel)in channels.enumerated(){
      var actual=Data();for y in 0..<document.height{actual.append(contentsOf:try PSDAuxiliaryChannels.row(channel,y:y,depth:document.bitsPerChannel))}
      XCTAssertEqual(actual,try data(expected[index]),"Unchanged gray words \(row["file"]!) channel\(index)",file:file,line:line)
    }
  }
  func testAllIndependentCompressedPlanesAndNative77PreserveEveryWord()throws {
    let cases=try rows();XCTAssertEqual(cases.count,81)
    for row in cases {
      let input=try data(row["file"]as!String),d=try PSDCodec.read(input)
      // These synthetic Float32 fixtures include selected-area gray; native91 retains its exact source words.
      let expectedArchive = (row["depth"]as!Int)==32 && row["independentCorpus"]as?Bool != true ? 91:77
      try compare(d,row:row);XCTAssertEqual(d.minimumArchiveVersion,expectedArchive)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
      if row["independentCorpus"]as?Bool != true {
        XCTAssertEqual(d.alphaChannels?.map(\.psdIdentifier),[41,73]);XCTAssertEqual(d.quickMask?.psdIdentifier,99)
        XCTAssertEqual(d.quickMask?.psdQuickMaskInitiallyEmpty,true)
      }else{XCTAssertNil(d.quickMask);XCTAssertTrue(d.alphaChannels?.allSatisfy{$0.spot != nil}==true)}
      XCTAssertEqual(try data(row["file"]as!String),input)
    }
  }
  func testLayeredPSDPSBOutputsKeepPlanesAndAreCapturedForIndependentReader()throws {
    for row in try rows() {
      let d=try PSDCodec.read(data(row["file"]as!String)),format:PSDFileFormat=(row["version"]as!Int)==2 ? .psb:.psd
      let compression=try XCTUnwrap(PSDCompression(rawValue:row["compression"]as!Int))
      let bytes=try PSDCodec.writeRasterLayers(d,compression:compression,format:format,compositeCompression:compression)
      let restored=try PSDCodec.read(bytes);try compare(restored,row:row)
      if let base=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let folder=URL(fileURLWithPath:base).appendingPathComponent("psd-auxiliary");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try bytes.write(to:folder.appendingPathComponent(row["file"]as!String),options:.atomic)
      }
    }
  }
  func testFloatSpotGrayUsesOriginalOnlyUntilTheSampleChanges()throws {
    var d=try PSDCodec.read(data("m3-d32-v1-c0.psd"));let channel=try XCTUnwrap(d.alphaChannels?.last),original=try XCTUnwrap(channel.psdSpotGray)
    var before=Data();for y in 0..<d.height{before.append(contentsOf:try PSDAuxiliaryChannels.row(channel,y:y,depth:32))}
    XCTAssertEqual(before,try data("m3-d32-channel1.bin"))
    d.selection = .init(x:1,y:1,width:1,height:1)
    try Command.channel(.fill(.alpha(channel.id),0.25,1)).apply(to:&d)
    let edited=try d.channel(.alpha(channel.id));XCTAssertEqual(edited.psdSpotGray,original)
    let row=try PSDAuxiliaryChannels.row(edited,y:1,depth:32);XCTAssertEqual(try PSDChannelCodec.sample(row,1,depth:32),0.25)
    for y in 0..<d.height {for x in 0..<d.width where x != 1 || y != 1 {
      let actual=try PSDAuxiliaryChannels.row(edited,y:y,depth:32);XCTAssertEqual(try PSDChannelCodec.sample(actual,x,depth:32).bitPattern,original.pixel(x:x,y:y).r.bitPattern)
    }}
  }
  func testMetadataValidationNamesAndUnknownBookColorsAreExplicit()throws {
    let d=try PSDCodec.read(data("m3-d8-v1-c0.psd")),channels=PSDAuxiliaryChannels.all(d)
    XCTAssertEqual(channels.map(\.name),["Mask α","Ink Ω","Quick Mask"])
    var raw=Data(repeating:0,count:13);raw[0]=0x23;raw[1]=0x31
    XCTAssertThrowsError(try PSDInkChannels.display(raw))
    let duplicated=[PSDImageResources.Block(id:1053,data:Data(),raw:Data()),PSDImageResources.Block(id:1053,data:Data(),raw:Data())]
    var document=try CraftDocument(width:1,height:1)
    let stream=try PSDChannelReader(PSDReader(data:Data([0,0,0])),width:1,height:1,depth:8)
    XCTAssertThrowsError(try PSDAuxiliaryChannels.read(stream,first:3,count:1,blocks:duplicated,document:&document,paging:nil))
    var invalid=PSDWriter();invalid.n(2,2);invalid.n(0,1)
    XCTAssertThrowsError(try PSDAuxiliaryChannels.read(stream,first:3,count:1,blocks:[.init(id:1022,data:invalid.data,raw:Data())],document:&document,paging:nil))
    let long=String(repeating:"A",count:1024);var channel=channels[0];channel.name=long;document.alphaChannels=[channel]
    document.width=d.width;document.height=d.height
    let blocks=try PSDImageResources.blocks(PSDAuxiliaryChannels.resources(document,first:4));XCTAssertEqual(try PSDAuxiliaryChannels.names(blocks,count:1),[long])
  }
  func testFiftySixChannelBoundaryNeverDropsPlanesAndCancellationIsAtomic()async throws {
    var d=try CraftDocument(width:2,height:1);d.layers[0].content = .fill(.white)
    d.alphaChannels=try (0..<52).map{AlphaChannel(name:"A\($0)",pixels:try Surface(width:2,height:1,fill:.white))}
    d.quickMask=AlphaChannel(name:"Quick Mask",pixels:try Surface(width:2,height:1,fill:.black))
    let bytes=try PSDCodec.writeRasterLayers(d),restored=try PSDCodec.read(bytes)
    XCTAssertEqual(Int(bytes[12])<<8|Int(bytes[13]),56);XCTAssertEqual(restored.alphaChannels?.count,52);XCTAssertNotNil(restored.quickMask)
    d.layers[0].content = .fill(Pixel(1,1,1,0.5));XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
    let input=try data("m3-d32-v2-c3.psb")
    let task=Task.detached{withUnsafeCurrentTask{$0?.cancel()};return try PSDCodec.read(input)}
    do{_ = try await task.value;XCTFail("Cancellation expected")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try data("m3-d32-v2-c3.psb"),input)
  }
}
