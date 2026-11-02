import Foundation
import XCTest
@testable import PhotoCraftCore
@testable import PhotoCraftImaging

final class DocumentGuideImportTests:XCTestCase {
  func folder()throws->URL {try XCTUnwrap(Bundle.module.url(forResource:"Fixtures",withExtension:nil)).appendingPathComponent("SourceGuides")}
  func data(_ name:String)throws->Data {try Data(contentsOf:folder().appendingPathComponent(name))}
  func testEveryOriginalGuideFloatWordAndNativeIdentityAtAllDepths()throws {
    for label in ["u8","u16","f32"] {
      let bytes=try data("guides-\(label).pcraft"),d=try PcraftImport.read(bytes),lines=try XCTUnwrap(d.guides),expected=try data("guides-\(label).f32")
      XCTAssertEqual(lines.count,10);XCTAssertEqual(d.minimumArchiveVersion,78)
      expected.withUnsafeBytes {buffer in for i in lines.indices {XCTAssertEqual(Float(lines[i].position).bitPattern,UInt32(littleEndian:buffer.loadUnaligned(fromByteOffset:i*4,as:UInt32.self)))}}
      XCTAssertEqual(try PcraftImport.read(bytes),d)
      let restored=try NativeArchive.decode(NativeArchive.encodeChunked(d));XCTAssertEqual(restored,d)
      for (a,b)in zip(try XCTUnwrap(restored.guides),lines) {XCTAssertEqual(a.position.bitPattern,b.position.bitPattern)}
      var noGuides=d;noGuides.guides=nil;XCTAssertEqual(try Renderer.composite(d),try Renderer.composite(noGuides))
      let exported=try PSDCodec.writeRasterLayers(d);let reread=try PSDCodec.read(exported)
      XCTAssertEqual(try PSDGuides.applying(PSDImageResources.block(1032,data:try data("guides-u8.resource1032")),document:d),PSDImageResources.block(1032,data:try data("guides-u8.resource1032")))
      XCTAssertEqual(reread.guides?.count,10)
    }
  }
  func testIndependentPSDPSBProgramsAndAllWriterCodecsRetainRawGuideRecord()throws {
    let expected=try data("guides-u8.resource1032")
    for ext in ["psd","psb"] {
      let d=try PSDCodec.read(data("independent-guides.\(ext)")),lines=try XCTUnwrap(d.guides)
      XCTAssertEqual(lines.count,10);XCTAssertEqual(lines[0].position,-7.5);XCTAssertEqual(lines[6].position,0.34375)
      for compression in PSDCompression.allCases {
        let bytes=try PSDCodec.writeRasterLayers(d,compression:compression,format:ext=="psb" ? .psb:.psd,compositeCompression:compression),read=try PSDCodec.read(bytes)
        XCTAssertEqual(read.guides?.map(\.position),lines.map(\.position));XCTAssertEqual(try PSDImageResources.blocks(read.sourceMetadata!["psdResources"]!).first{$0.id==1032}?.data,expected)
        if let root=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {let folder=URL(fileURLWithPath:root).appendingPathComponent("guides");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try bytes.write(to:folder.appendingPathComponent("\(compression.rawValue).\(ext)"))}
      }
    }
  }
  func testEditedGuideQuantizationClearAndCustomGridRetention()throws {
    var d=try PSDCodec.read(data("independent-guides.psd"));var changed=try XCTUnwrap(d.guides?.first);changed.position=7.333
    try Command.guides(.update([changed])).apply(to:&d)
    let out=try PSDCodec.read(PSDCodec.writeRasterLayers(d));XCTAssertEqual(out.guides?.first?.position,7.34375)
    try Command.guides(.clearAll).apply(to:&d);let cleared=try PSDCodec.read(PSDCodec.writeRasterLayers(d));XCTAssertTrue((cleared.guides ?? []).isEmpty)
    var payload=try data("guides-u8.resource1032");payload.replaceSubrange(4..<12,with:Data([0,0,0,17,0,0,3,231]));let resource=PSDImageResources.block(1032,data:payload)
    d.sourceMetadata?["psdResources"]=resource;d.guides=try PSDGuides.decode(payload);d.guides?[0].position=20
    let saved=try PSDGuides.applying(resource,document:d),block=try XCTUnwrap(PSDImageResources.blocks(saved).first);XCTAssertEqual(block.data.subdata(in:4..<12),payload.subdata(in:4..<12))
  }
  func testMalformedSourceAndResourceRecordsRejectWholeImport()throws {
    let input=try data("guides-u8.pcraft"),helper=PcraftImportTests()
    for n in 0..<3 {
      let project=try helper.source(input){document in var guides=document["guides"]as![String:Any];if n==0 {guides["unknown"]=true};if n==1 {guides["horizontal"]=[1000001]};if n==2 {guides["vertical"]="bad"};document["guides"]=guides}
      XCTAssertThrowsError(try helper.convert(project))
    }
    let good=try data("guides-u8.resource1032")
    var bad=good;bad[20]=2;XCTAssertThrowsError(try PSDGuides.decode(bad))
    bad=good;bad[3]=2;XCTAssertThrowsError(try PSDGuides.decode(bad))
    XCTAssertThrowsError(try PSDGuides.decode(Data(good.dropLast())))
    var d=try CraftDocument(width:4,height:4);d.sourceMetadata=["psdResources":PSDImageResources.block(1032,data:good)+PSDImageResources.block(1032,data:good)];XCTAssertThrowsError(try PSDGuides.read(into:&d))
    XCTAssertEqual(try data("guides-u8.pcraft"),input)
  }
  func testGuidesSurviveEverySupportedOrdinaryRestrictedAndInkContainerPath()throws {
    let base=try CraftDocument(width:3,height:2)
    var documents=[base]
    for mode in [DocumentColorMode.grayscale,.cmyk,.lab] {documents.append(try base.convertingMode(.init(mode:mode,depth:.u8)))}
    documents.append(try base.replacingRestrictedMode(.indexed(IndexedRaster(width:3,height:2,palette:[.init(0,0,0),.init(255,255,255)],indices:Data([0,1,0,1,0,1])))))
    documents.append(try base.replacingRestrictedMode(.bitmap(BitmapRaster(width:3,height:2,bits:Data([0xa0,0x40])))))
    let plane=try InkPlane(width:3,height:2,depth:.u8,bytes:Data([0,1,127,128,254,255]))
    documents.append(try base.replacingInkMode(.multichannel(.init(plates:[.init(name:"Cyan",color:Pixel(0,1,1),samples:plane)]))))
    for var document in documents {
      document.guides=[.init(axis:.horizontal,position:1.125),.init(axis:.vertical,position:2.25)]
      for format in [PSDFileFormat.psd,.psb] {
        let output=try PSDCodec.read(PSDCodec.writeRasterLayers(document,format:format))
        XCTAssertEqual(output.colorMode,document.colorMode)
        XCTAssertEqual(output.guides?.map(\.position),[1.125,2.25]);XCTAssertEqual(output.guides?.map(\.axis),[.horizontal,.vertical])
        XCTAssertEqual(output.minimumArchiveVersion,78)
      }
    }
  }
  func testCustomGuideColorsNeverDisappearInPhotoshopExport()throws {
    var document=try CraftDocument(width:4,height:3);document.guides=[.init(axis:.vertical,position:2,color:Pixel(1,0,0))]
    XCTAssertNotNil(DocumentGuideInput.photoshopPersistenceIssue(document))
    for format in [PSDFileFormat.psd,.psb] {XCTAssertThrowsError(try PSDCodec.writeRasterLayers(document,format:format))}
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(document)),document)
    document.guides?[0].color=Pixel(0,1,1,1)
    XCTAssertNil(DocumentGuideInput.photoshopPersistenceIssue(document));XCTAssertNoThrow(try PSDCodec.writeRasterLayers(document))
  }
  func testCancelledSourceGuideImportPreservesInput()async throws {
    let input=try data("guides-f32.pcraft"),task=Task.detached {withUnsafeCurrentTask{$0?.cancel()};return try PcraftImport.read(input)}
    do{_ = try await task.value;XCTFail("Cancellation expected")}catch{XCTAssertTrue(error is CancellationError)}
    XCTAssertEqual(try data("guides-f32.pcraft"),input)
  }
}
