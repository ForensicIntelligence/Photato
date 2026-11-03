import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class SelectionChannelDocumentIOTests:XCTestCase {
  func file(_ name:String)throws->Data {try Data(contentsOf:Bundle.module.resourceURL!.appendingPathComponent("Fixtures/quick-mask-selection/"+name))}
  func capture(_ data:Data,_ name:String)throws {
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try data.write(to:dir.appendingPathComponent(name))
    }
  }
  func testActualPhotoshopStandaloneFilesReadAsAuxiliaryOnlyDocuments()throws {
    for depth in [8,16] {
      let source=try PSDCodec.read(file("standalone-selection-\(depth).psd"))
      XCTAssertTrue(source.isChannelOnly);XCTAssertTrue(source.layers.isEmpty);XCTAssertNil(source.activeLayerID);XCTAssertNil(source.inkMode)
      XCTAssertEqual(source.colorMode,.multichannel);XCTAssertEqual(source.alphaChannels?.count,1);XCTAssertEqual(source.minimumArchiveVersion,85)
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(source)),source)
    }
  }
  func testAllStandalonePSDPSBCompressionModesRetainExactChannelSamples()throws {
    for depth in [8,16] {
      let original=try PSDCodec.read(file("standalone-selection-\(depth).psd")),channel=try XCTUnwrap(original.alphaChannels?.first)
      for format:PSDFileFormat in [.psd,.psb] {for compression:PSDCompression in [.raw,.rle,.zip,.zipPrediction] {
        let bytes=try PSDCodec.writeRasterLayers(original,format:format,compositeCompression:compression),restored=try PSDCodec.read(bytes)
        XCTAssertTrue(restored.isChannelOnly);XCTAssertEqual(restored.alphaChannels?.first?.name,channel.name)
        for key in ["CAI ","OCIO","GenI","FMsk","cinf"] {XCTAssertEqual(restored.sourceMetadata?["psdGlobal_"+key],original.sourceMetadata?["psdGlobal_"+key])}
        XCTAssertEqual(try restored.alphaChannels?.first?.pixels.rgbaData(depth:original.depth),try channel.pixels.rgbaData(depth:original.depth))
        try capture(bytes,"standalone-\(depth)-\(format)-\(compression).psddata")
      }}
    }
  }
  func testFloat32StandaloneNativeRemainsExactAndPhotoshopOutputFailsExplicitly()throws {
    var source=try CraftDocument(width:4,height:1,depth:.f32);source.setCoverageSelection(try SelectionMask(width:4,height:1,bytes:[0,64,128,255]))
    let document=try source.selectionDocument();XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(document)),document)
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(document))
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(document,format:.psb))
    let rendered=try Renderer.composite(document);XCTAssertEqual(rendered.width,4)
    XCTAssertEqual(try document.alphaChannels?.first?.selection().denseBytes(),[0,64,128,255])
  }
  func testComponentTransparencyAndMaskSourcesKeepNumericCoverage()throws {
    var d=try CraftDocument(width:4,height:2);d.layers[0].background=nil
    var pixels=try Surface(width:4,height:2,fill:Pixel(64/255,128/255,192/255,0.5));pixels.setPixel(x:3,y:1,Pixel(1,0,0,0))
    d.layers[0].content = .raster(pixels);d.layers[0].opacity=0.2
    d.layers[0].mask=try Surface(width:4,height:2,fill:Pixel(0.25,0,0,0))
    let id=d.layers[0].id,original=d
    XCTAssertEqual(try SelectionChannelSource.component(0).selection(in:d).byte(at:0),64)
    XCTAssertEqual(try SelectionChannelSource.component(1).selection(in:d).byte(at:0),128)
    XCTAssertEqual(try SelectionChannelSource.transparency(id).selection(in:d).byte(at:0),128)
    XCTAssertEqual(try SelectionChannelSource.transparency(id).selection(in:d).byte(at:7),0)
    XCTAssertEqual(try SelectionChannelSource.layerMask(id).selection(in:d).byte(at:0),64)
    XCTAssertEqual(d,original)
    XCTAssertTrue(SelectionChannelSource.choices(in:d).contains(.transparency(id)));XCTAssertTrue(SelectionChannelSource.choices(in:d).contains(.layerMask(id)))
  }
  func testSpotSelectionUsesEditingGrayAndAlphaDisplayOptionsDoNotChangeCoverage()throws {
    var d=try CraftDocument(width:2,height:1)
    var plane=try Surface(width:2,height:1,fill:.black);plane.setPixel(x:1,y:0,.white)
    let spot=AlphaChannel(name:"Spot",pixels:plane,spot:SpotInk(color:.black,solidity:0))
    var options=ChannelDisplayOptions();options.indicates = .selectedAreas
    let alpha=AlphaChannel(name:"Mask",pixels:plane,options:options);d.alphaChannels=[spot,alpha]
    XCTAssertEqual(try SelectionChannelSource.alpha(spot.id).selection(in:d).denseBytes(),[255,0])
    XCTAssertEqual(try SelectionChannelSource.alpha(alpha.id).selection(in:d).denseBytes(),[0,255])
    try Command.channel(.load(.alpha(spot.id),.replace,false)).apply(to:&d);XCTAssertEqual(try d.coverageSelection()?.denseBytes(),[255,0])
    XCTAssertThrowsError(try Command.channel(.saveSelection(spot.id,nil,.replace)).apply(to:&d))
  }
}
