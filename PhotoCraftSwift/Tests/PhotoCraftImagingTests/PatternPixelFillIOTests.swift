import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class PatternPixelFillIOTests:XCTestCase{
  func pattern()throws->RasterPattern{var p=try Surface(width:2,height:2);p.setPixel(x:0,y:0,Pixel(1,0,0));p.setPixel(x:1,y:0,Pixel(0,1,0));p.setPixel(x:0,y:1,Pixel(0,0,1));return try RasterPattern(name:"Owned",surface:p,id:"owned")}
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument{var d=try CraftDocument(width:12,height:10,depth:depth);d.layers[0].content = .raster(try Surface(width:12,height:10,depth:depth));return d}
  func testBakedPatternColorAndTransparentWordsSurvivePSDPSBAtomicFilesAllDepths()throws{
    let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:directory)};for depth in PixelDepth.allCases{for format:PSDFileFormat in [.psd,.psb]{var d=try fixture(depth);try Command.pixelPaint(.init(.fill,target:.layer(d.layers[0].id),settings:.init(),pattern:pattern())).apply(to:&d);XCTAssertNil(d.patterns);let bytes=try PSDCodec.writeRasterLayers(d,format:format),url=directory.appendingPathComponent("pattern."+(format == .psd ? "psd":"psb"));try PSDCodec.writeRasterLayers(d,to:url,format:format);XCTAssertEqual(try Data(contentsOf:url),bytes);let read=try PSDCodec.read(bytes);XCTAssertEqual(read.layers.count,1);XCTAssertNil(read.layers[0].smartObject);guard case .raster(let out)=read.layers[0].content,case .raster(let expected)=d.layers[0].content else{return XCTFail()};for y in 0..<10{for x in 0..<12{XCTAssertTrue(out.pixel(x:x,y:y).hasSameBits(as:expected.pixel(x:x,y:y)))}}}}
  }
  func testNativeReopenWithoutPatternAssetsAndOwnedPNGForIndependentReader()throws{
    var d=try fixture();let asset=try pattern();d.patterns=[asset];try Command.pixelPaint(.init(.fill,target:.layer(d.layers[0].id),settings:.init(),pattern:asset)).apply(to:&d);let pixels=d.layers[0].content;d.patterns=nil;let read=try NativeArchive.decode(NativeArchive.encodeChunked(d));XCTAssertEqual(read,d);XCTAssertEqual(read.layers[0].content,pixels);let png=try RasterIO.encoded(read,type:.png);XCTAssertEqual(try RasterIO.read(png).width,12);if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try png.write(to:dir.appendingPathComponent("pattern-pixel-fill-owned.png"))}
  }
}
