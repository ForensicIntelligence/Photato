import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class MultichannelQuickMaskTests:XCTestCase {
  func input()throws->Data {try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/multichannel-quick-mask/selection8.psd"))}
  func capture(_ data:Data,_ name:String)throws {
    guard let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else{return}
    let folder=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try data.write(to:folder.appendingPathComponent(name))
  }
  func fixture(_ depth:PixelDepth,plates:Bool=false)throws->CraftDocument {
    var source:CraftDocument
    if plates {source=try PSDMultichannelTests().fixture(depth)}
    else {var d=try CraftDocument(width:4,height:3,depth:depth);d.selection = .init(x:1,y:0,width:2,height:3);source=try d.selectionDocument(channelName:"Stored")}
    var plane=try Surface(width:4,height:3,depth:depth,fill:.white)
    let maximum=depth == .u8 ? 255:65535
    for y in 0..<3 {for x in 0..<4 {let v=Float((y*4+x)*maximum/11)/Float(maximum);plane.setPixel(x:x,y:y,Pixel(v,v,v))}}
    var options=ChannelDisplayOptions();options.color=Pixel(0,1,0);options.opacity=0.37;options.indicates = .selectedAreas
    source.quickMask=AlphaChannel(name:"Quick Mask",pixels:plane,options:options);source.quickMask?.psdIdentifier=987;source.quickMask?.psdQuickMaskInitiallyEmpty=false
    try source.validate();return source
  }
  func assertChannels(_ restored:CraftDocument,_ original:CraftDocument,file:StaticString=#filePath,line:UInt=#line)throws {
    XCTAssertEqual(restored.isChannelOnly,original.isChannelOnly,file:file,line:line)
    XCTAssertEqual(restored.alphaChannels?.map(\.name),original.alphaChannels?.map(\.name),file:file,line:line)
    func pixels(_ actual:Surface?,_ expected:Surface?)throws {
      let a=try XCTUnwrap(actual,file:file,line:line),b=try XCTUnwrap(expected,file:file,line:line)
      XCTAssertEqual(a.width,b.width,file:file,line:line);XCTAssertEqual(a.height,b.height,file:file,line:line);XCTAssertEqual(a.depth,b.depth,file:file,line:line)
      for y in 0..<b.height {for x in 0..<b.width {XCTAssertEqual(a.pixel(x:x,y:y),b.pixel(x:x,y:y),"Document pixel(\(x),\(y))",file:file,line:line)}}
    }
    XCTAssertEqual(restored.alphaChannels?.count,original.alphaChannels?.count,file:file,line:line)
    for (a,b) in zip(restored.alphaChannels ?? [],original.alphaChannels ?? []) {try pixels(a.pixels,b.pixels)}
    try pixels(restored.quickMask?.pixels,original.quickMask?.pixels)
    XCTAssertEqual(restored.quickMask?.options,original.quickMask?.options,file:file,line:line)
    XCTAssertEqual(restored.quickMask?.psdIdentifier,original.quickMask?.psdIdentifier,file:file,line:line)
    XCTAssertEqual(restored.quickMask?.psdQuickMaskInitiallyEmpty,original.quickMask?.psdQuickMaskInitiallyEmpty,file:file,line:line)
    if !original.isChannelOnly {XCTAssertEqual(try restored.multichannelRaster().plates.map(\.samples),try original.multichannelRaster().plates.map(\.samples),file:file,line:line)}
  }
  func testActualPhotoshopFileSeparatesTemporaryPlaneFromSavedSelection()throws {
    let d=try PSDCodec.read(input());XCTAssertTrue(d.isChannelOnly);XCTAssertEqual(d.alphaChannels?.count,1)
    XCTAssertEqual(d.alphaChannels?.first?.name,"Standalone selection");XCTAssertEqual(d.alphaChannels?.first?.psdIdentifier,2)
    XCTAssertEqual(d.quickMask?.name,"Quick Mask");XCTAssertEqual(d.quickMask?.psdIdentifier,3);XCTAssertEqual(d.quickMask?.psdQuickMaskInitiallyEmpty,true)
    let expected:[UInt8]=[0,32,64,96,128,160,192,224,255,255,128,64,0,192,255,128]
    for y in 0..<4 {for x in 0..<16 {XCTAssertEqual(try d.alphaChannels?.first?.selection().byte(at:y*16+x),expected[x]);XCTAssertEqual(d.quickMask?.pixels.pixel(x:x,y:y).r,0)}}
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(d)),d)
    for format in PSDFileFormat.allCases {let data=try PSDCodec.writeRasterLayers(d,format:format,compositeCompression:.rle);try assertChannels(PSDCodec.read(data),d);try capture(data,"actual-quick8-\(format).psddata")}
  }
  func testStandaloneAndPrintingPlanesRetainQuickMaskAcrossBothDepthsContainersAndCompressions()throws {
    for depth in [PixelDepth.u8,.u16] {for plates in [false,true] {let d=try fixture(depth,plates:plates)
      for format in PSDFileFormat.allCases {for compression in PSDCompression.allCases {
        let data=try PSDCodec.writeRasterLayers(d,format:format,compositeCompression:compression)
        let restored=try PSDCodec.read(data);try assertChannels(restored,d)
        let again=try PSDCodec.read(PSDCodec.writeRasterLayers(restored,format:format,compositeCompression:compression));try assertChannels(again,restored)
        try capture(data,"quick-\(d.bitsPerChannel)-\(plates ? "ink":"selection")-\(format)-\(compression).psddata")
      }}
    }}
  }
  func replacingResources(_ data:Data,_ change:([PSDImageResources.Block])throws->Data)throws->Data {
    var r=PSDReader(data:data);let header=try r.bytes(26),color=try r.section().data,blocks=try PSDImageResources.blocks(r.section().data),tail=try r.bytes(r.remaining)
    var w=PSDWriter();w.data=header;w.section(color);w.section(try change(blocks));w.data+=tail;return w.data
  }
  func testMalformedMissingPrintingAndDuplicateQuickMaskResourcesReject()throws {
    let data=try PSDCodec.writeRasterLayers(fixture(.u8))
    for info in [Data(),Data([0,0]),Data([0,1,2]),Data([0,2,0]),Data([255,255,0])] {
      let bad=try replacingResources(data) {blocks in blocks.filter{$0.id != 1022}.reduce(into:Data()){$0 += $1.raw}+PSDImageResources.block(1022,data:info)}
      XCTAssertThrowsError(try PSDCodec.read(bad))
    }
    let duplicate=try replacingResources(data) {$0.reduce(into:Data()){$0 += $1.raw}+PSDImageResources.block(1022,data:Data([0,1,0]))}
    XCTAssertThrowsError(try PSDCodec.read(duplicate))
    let printing=try PSDCodec.writeRasterLayers(fixture(.u8,plates:true))
    let bad=try replacingResources(printing) {$0.filter{$0.id != 1022}.reduce(into:Data()){$0 += $1.raw}+PSDImageResources.block(1022,data:Data([0,0,0]))}
    XCTAssertThrowsError(try PSDCodec.read(bad))
  }
  func testQuickMaskResourceMaySelectAnEarlierPlaneAndReorderingKeepsIdentities()throws {
    let data=try PSDCodec.writeRasterLayers(fixture(.u16))
    let swapped=try replacingResources(data) {$0.filter{$0.id != 1022}.reduce(into:Data()){$0 += $1.raw}+PSDImageResources.block(1022,data:Data([0,0,1]))}
    let read=try PSDCodec.read(swapped);XCTAssertEqual(read.quickMask?.name,"Stored");XCTAssertEqual(read.alphaChannels?.first?.name,"Quick Mask")
    XCTAssertEqual(read.quickMask?.psdQuickMaskInitiallyEmpty,true)
    let saved=try PSDCodec.read(PSDCodec.writeRasterLayers(read));try assertChannels(saved,read)
  }
  func testTotalChannelLimitIncludesTemporaryPlaneAndInvalidReadIsNotTruncated()throws {
    var d=try fixture(.u8,plates:true);let plane=try Surface(width:4,height:3,fill:.white)
    d.alphaChannels=(0..<52).map{AlphaChannel(name:"Saved \($0)",pixels:plane)}
    let data=try PSDCodec.writeRasterLayers(d);XCTAssertEqual(try PSDCodec.read(data).alphaChannels?.count,52)
    for n in 0..<data.count {XCTAssertThrowsError(try PSDCodec.read(data.prefix(n)),"Truncated \(n)")}
    guard case .multichannel(var ink)=d.inkMode else{return XCTFail()}
    ink.plates.append(InkPlate(name:"Fourth",color:.black,samples:try InkPlane(width:4,height:3,bytes:Data(repeating:0,count:12))));d.inkMode = .multichannel(ink)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d))
  }
}
