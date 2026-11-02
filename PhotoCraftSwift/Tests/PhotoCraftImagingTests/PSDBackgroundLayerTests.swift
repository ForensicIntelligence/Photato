import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PSDBackgroundLayerTests:XCTestCase {
  func testThreeDepthPSDPSBExplicitBackgroundIdentityPixelsAndStoredID()throws {
    for depth in PixelDepth.allCases {var source=try DocumentCreation.blank(width:9,height:7,depth:depth);var pixels=try Surface(width:9,height:7,depth:depth,fill:Pixel(0.25,0.5,0.75));pixels.setPixel(x:4,y:3,.black);source.layers[0].content = .raster(pixels)
      for format in [PSDFileFormat.psd,.psb] {let bytes=try PSDCodec.writeRasterLayers(source,format:format),read=try PSDCodec.read(bytes);XCTAssertTrue(read.layers[0].isBackground);XCTAssertEqual(read.layers[0].sourceTags?["lyid"],Data(repeating:0,count:4));XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:depth),try Renderer.composite(source).rgbaData(depth:depth));try read.validate()
        if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try bytes.write(to:dir.appendingPathComponent("background-\(depth.rawValue).\(format == .psd ? "psd":"psb")"))}
      }
    }
  }
  func testOrdinaryNamedBackgroundKeepsAlphaAndNeverGainsIdentity()throws {
    var d=try CraftDocument(width:9,height:7);d.layers[0].content = .raster(try Surface(width:9,height:7,fill:.white));d.layers[0].protection = [.position,.transparency]
    for format in [PSDFileFormat.psd,.psb] {let read=try PSDCodec.read(PSDCodec.writeRasterLayers(d,format:format));XCTAssertEqual(read.layers[0].name,"Background");XCTAssertFalse(read.layers[0].isBackground);XCTAssertEqual(read.layers[0].protection,[.position,.transparency])}
  }
}
