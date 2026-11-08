import CoreGraphics
import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class UntaggedPSDTests: XCTestCase {
  func metadata() throws -> Data {
    try Data(contentsOf:URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PSDShapesInterop/untagged-OCIO.bin"))
  }
  func source(_ depth:PixelDepth = .u8) throws -> CraftDocument {
    var d=try CraftDocument(width:4,height:3,depth:depth)
    var pixels=try Surface(width:4,height:3,depth:depth,
      colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<3 {for x in 0..<4 {
      let p=Pixel(x%2==0 ? 0:1,y%2==0 ? 0.5:1,Float((x+y)%3)/2,Float((x+y)%3)/2)
      if depth == .f32 {pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}
    }}
    let layer=Layer(name:"Owned untagged samples",content:.raster(pixels))
    d.layers=[layer];d.activeLayerID=layer.id
    d.profileIsUntagged=true;d.workingICC=nil;d.sourceICC=nil
    return d
  }
  /// Independent container splice: preserve every native-written layer/sample
  /// and insert the real Photoshop global descriptor before merged image data.
  func adding(_ metadata:Data,to data:Data,format:PSDFileFormat)throws->Data {
    func integer(_ at:Int,_ count:Int)throws->Int {
      guard at>=0,count>0,at<=data.count-count else{throw CraftError.invalid("Invalid test envelope")}
      return data[at..<at+count].reduce(0){$0*256+Int($1)}
    }
    var at=26
    for _ in 0..<2 {at += 4 + (try integer(at,4))}
    let count=format == .psd ? 4:8,length=try integer(at,count),end=at+count+length
    var block=Data("8BIMOCIO".utf8)
    block.append(contentsOf:(0..<4).reversed().map{UInt8(truncatingIfNeeded:metadata.count >> ($0*8))})
    block.append(metadata);block.append(Data(repeating:0,count:(4-metadata.count%4)%4))
    var result=data;result.insert(contentsOf:block,at:end)
    let size=length+block.count
    result.replaceSubrange(at..<at+count,with:(0..<count).reversed().map{UInt8(truncatingIfNeeded:size >> ($0*8))})
    return result
  }
  func testUnmanagedPhotoshopMetadataOpensWithoutChangingSamplesAtEveryRGBDepthAndFormat() throws {
    for depth in PixelDepth.allCases {for format in [PSDFileFormat.psd,.psb] {
      let d=try source(depth),original=d
      let bytes=try adding(metadata(),to:PSDCodec.writeRasterLayers(d,format:format),format:format)
      let decoded=try PSDCodec.read(bytes)
      XCTAssertEqual(decoded.profileIsUntagged,true)
      XCTAssertNil(decoded.sourceICC)
      XCTAssertEqual(decoded.sourceMetadata?["psdGlobal_OCIO"],try metadata())
      guard case .raster(let a)=d.layers[0].content,case .raster(let b)=decoded.layers[0].content else{return XCTFail("Raster content changed")}
      XCTAssertEqual(try a.rgbaData(depth:depth),try b.rgbaData(depth:depth),"\(depth)/\(format)")
      XCTAssertEqual(d,original)
    }}
  }
  func testUnmanagedDescriptorSurvivesSaveAndIsOmittedAfterAssigningAProfile() throws {
    for format in [PSDFileFormat.psd,.psb] {
      var d=try source();d.sourceMetadata=["psdGlobal_OCIO":try metadata()]
      let bytes=try PSDCodec.writeRasterLayers(d,format:format)
      let reopened=try PSDCodec.read(bytes)
      XCTAssertEqual(reopened.profileIsUntagged,true)
      XCTAssertEqual(reopened.sourceMetadata?["psdGlobal_OCIO"],try metadata())
      d.profileIsUntagged=nil
      d.workingICC=try RasterIO.colorSpace().copyICCData() as Data?
      let tagged=try PSDCodec.read(PSDCodec.writeRasterLayers(d,format:format))
      XCTAssertNotEqual(tagged.profileIsUntagged,true)
      XCTAssertNotNil(tagged.sourceICC)
      XCTAssertNil(tagged.sourceMetadata?["psdGlobal_OCIO"])
    }
  }
  func testActiveOCIOViewsUnknownLayoutsAndConflictingProfileFlagsRemainRejected() throws {
    let d=try source(),base=try PSDCodec.writeRasterLayers(d)
    let actual=try PSDDescriptor.read(metadata())
    func edited(_ key:String,_ value:PSDValue)->PSDDescriptor {
      var result=actual
      result.items[result.items.firstIndex(where:{$0.key.text==key})!].value=value
      return result
    }
    let active=edited("Knd ",.text(Array("ocio".utf16)))
    XCTAssertThrowsError(try PSDCodec.read(adding(active.encoded(),to:base,format:.psd)))
    var view=PSDDescriptor("viewColorManagementInfo",items:[.init("display",.text(Array("ACES".utf16))),.init("view",.text([]))])
    XCTAssertThrowsError(try PSDCodec.read(adding(edited("ocio_display_view",.object(view)).encoded(),to:base,format:.psd)))
    view.items[0].value = .text([]);view.items[1].value = .text(Array("Filmic".utf16))
    XCTAssertThrowsError(try PSDCodec.read(adding(edited("ocio_display_view",.object(view)).encoded(),to:base,format:.psd)))
    var unknown=actual;unknown.items.append(.init("unrepresented",.boolean(true)))
    XCTAssertThrowsError(try PSDCodec.read(adding(unknown.encoded(),to:base,format:.psd)))
    var duplicate=actual;duplicate.items.append(duplicate.items[0])
    XCTAssertThrowsError(try PSDCodec.read(adding(duplicate.encoded(),to:base,format:.psd)))
    var tagged=d;tagged.profileIsUntagged=nil;tagged.workingICC=try RasterIO.colorSpace().copyICCData() as Data?
    XCTAssertThrowsError(try PSDCodec.read(adding(metadata(),to:PSDCodec.writeRasterLayers(tagged),format:.psd)))
    XCTAssertThrowsError(try PSDCodec.read(adding(Data(try metadata().dropLast()),to:base,format:.psd)))
  }
  func testUnrepresentedNeutralMetadataDoesNotReplaceExistingFilesOrMutateTheSource() throws {
    var d=try source(),unknown=try PSDDescriptor.read(metadata())
    unknown.items.append(.init("unrepresented",.boolean(true)))
    d.sourceMetadata=["psdGlobal_OCIO":try unknown.encoded()]
    let original=d,folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
    defer {try? FileManager.default.removeItem(at:folder)}
    let sentinel=Data("Owned previous file must survive".utf8)
    for format in [PSDFileFormat.psd,.psb] {
      let target=folder.appendingPathComponent(format == .psd ? "owned.psd":"owned.psb")
      try sentinel.write(to:target)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(d,to:target,format:format))
      XCTAssertEqual(try Data(contentsOf:target),sentinel)
      XCTAssertEqual(d,original)
    }
  }
  func testOwnedPhotoshopRasterKeepsAllChannelBytesThroughNativePSDPSBAndArchive() throws {
    let fixtures=URL(fileURLWithPath:#filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/PSDShapesInterop")
    let document=try PSDCodec.read(Data(contentsOf:fixtures.appendingPathComponent("photoshop-neutral-none-raster.psd")))
    let expected=try Data(contentsOf:fixtures.appendingPathComponent("photoshop-neutral-none-raster-layer.rgba"))
    XCTAssertEqual(expected.count,1764)
    func check(_ value:CraftDocument)throws {
      XCTAssertEqual(value.width,128);XCTAssertEqual(value.height,96)
      XCTAssertEqual(value.layers.count,1);XCTAssertEqual(value.profileIsUntagged,true)
      XCTAssertNil(value.sourceICC)
      XCTAssertEqual(value.sourceMetadata?["psdGlobal_OCIO"],try metadata())
      let layer=try XCTUnwrap(value.layers.first)
      XCTAssertEqual(layer.x,8);XCTAssertEqual(layer.y,9)
      guard case .raster(let surface)=layer.content else{return XCTFail("Owned raster became another content type")}
      XCTAssertEqual(surface.width,21);XCTAssertEqual(surface.height,21)
      XCTAssertEqual(try surface.rgbaData(depth:.u8),expected)
    }
    try check(document)
    let native=try NativeArchive.decode(NativeArchive.encode(document))
    try check(native);XCTAssertEqual(native,document)
    let original=document
    for format in [PSDFileFormat.psd,.psb] {
      let output=try PSDCodec.writeRasterLayers(document,format:format)
      try check(PSDCodec.read(output));XCTAssertEqual(document,original)
      if let capture=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        let suffix=format == .psd ? "psd":"psb"
        try output.write(to:URL(fileURLWithPath:capture).appendingPathComponent("unmanaged-owned."+suffix),options:.withoutOverwriting)
      }
    }
  }

}
