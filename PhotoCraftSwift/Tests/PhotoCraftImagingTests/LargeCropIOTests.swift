import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LargeCropIOTests:XCTestCase {
  func testLargeBackgroundStripKeepsInteriorTransparencyAndStreamsOutput()throws {
    var source=try CraftDocument(width:90000,height:449),pixels=try Surface(width:90000,height:449);pixels.setPixel(x:70,y:80,Pixel(0,0,1));source.layers[0].content = .raster(pixels)
    var request=CropRequest(x:0,y:0,width:90000,height:450);request.deleteCroppedPixels=false;request.fill = .background;request.backgroundColor=Pixel(1,0,0)
    let result=try CropPreparation.prepare(request,document:source).result;XCTAssertEqual(result.layers.count,2);XCTAssertEqual(result.layers[0].content,source.layers[0].content);guard case .raster(let patch)=result.layers.last?.content else{return XCTFail("Fill")};XCTAssertLessThan(patch.allocatedBytes,4*1024*1024);XCTAssertGreaterThan(patch.mappedBytes,0);XCTAssertEqual(patch.pixel(x:89999,y:449),Pixel(1,0,0));XCTAssertEqual(patch.pixel(x:70,y:80),.clear);XCTAssertEqual(patch.pixel(x:80,y:80),.clear);let preview=try CropPreparation.preview(result);XCTAssertLessThanOrEqual(preview.width,1024);XCTAssertLessThanOrEqual(preview.height,1024)
  }
  func testLargePSBCropRetainsEditedWordsAllDepthsAndPSDRejectsOversize()throws {
    for depth in PixelDepth.allCases {
      var source=try CraftDocument(width:100000,height:2,depth:depth),s=try Surface(width:100000,height:2,depth:depth)
      s.setPixel(x:10001,y:0,Pixel(0.2,0.4,0.8,0.5));source.layers[0].content = .raster(s)
      let result=try CropPreparation.prepare(.init(x:10000,y:0,width:80000,height:1),document:source).result
      let data=try PSDCodec.writeRasterLayers(result,format:.psb),read=try PSDCodec.read(data);XCTAssertEqual(read.width,80000)
      guard case .raster(let actual)=read.layers[0].content,case .raster(let expected)=result.layers[0].content else{return XCTFail("Raster")}
      let actualBytes=try actual.rgbaData(depth:depth),expectedBytes=try expected.rgbaData(depth:depth)
      if depth == .f32 {
        let actualLinear=try actual.rgbaData(depth:.f32,colorEncoding:.linearRGB),expectedLinear=try expected.rgbaData(depth:.f32,colorEncoding:.linearRGB)
        XCTAssertEqual(actualLinear,expectedLinear,"Linear PSB working samples must be exact even when encoded-sRGB round-trip precision differs.")
        if let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
          let url=URL(fileURLWithPath:folder);try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
          for (name,bytes) in [("crop-f32-encoded-expected.rgba",expectedBytes),("crop-f32-encoded-actual.rgba",actualBytes),("crop-f32-linear-expected.rgba",expectedLinear),("crop-f32-linear-actual.rgba",actualLinear)] {try bytes.write(to:url.appendingPathComponent(name))}
          try PSDCodec.writeRasterLayers(result,compression:.raw,format:.psb).write(to:url.appendingPathComponent("crop-f32-raw.psb"))
          var control=try CraftDocument(width:2,height:1,depth:.f32),controlPixels=try Surface(width:2,height:1,depth:.f32)
          controlPixels.setPixel(x:0,y:0,Pixel(0.2,0.4,0.8,0.5));control.layers[0].content = .raster(controlPixels)
          let raw=try PSDCodec.writeRasterLayers(control,compression:.raw,format:.psb),decoded=try PSDCodec.read(raw)
          guard case .raster(let controlActual)=decoded.layers[0].content else{throw CraftError.invalid("Control raster")}
          try raw.write(to:url.appendingPathComponent("control-f32-raw.psb"))
          try controlPixels.rgbaData(depth:.f32).write(to:url.appendingPathComponent("control-f32-encoded-expected.rgba"))
          try controlActual.rgbaData(depth:.f32).write(to:url.appendingPathComponent("control-f32-encoded-actual.rgba"))
          try controlPixels.rgbaData(depth:.f32,colorEncoding:.linearRGB).write(to:url.appendingPathComponent("control-f32-linear-expected.rgba"))
          try JSONSerialization.data(withJSONObject:["cropExpectedEncoding":expected.colorEncoding.rawValue,"cropActualEncoding":actual.colorEncoding.rawValue,"controlExpectedEncoding":controlPixels.colorEncoding.rawValue,"controlActualEncoding":controlActual.colorEncoding.rawValue],options:[.sortedKeys]).write(to:url.appendingPathComponent("crop-f32-encoding.json"))
        }
      }
      // Preserve the original strict all-word assertion and all-depth coverage.
      XCTAssertEqual(actualBytes,expectedBytes)
      XCTAssertThrowsError(try PSDCodec.writeRasterLayers(result,format:.psd))
    }
  }
  func testContentAwareBudgetIsSpecificAndSmallBackgroundPNGCapturesIndependentPixels()throws {
    var d=try CraftDocument(width:300000,height:300000);d.layers[0].content = .raster(try Surface(width:300000,height:300000));var enclosed=CropRequest(x:1,y:1,width:299999,height:299999);enclosed.fill = .contentAware;enclosed.deleteCroppedPixels=false;XCTAssertNoThrow(try CropPreparation.prepare(enclosed,document:d));enclosed.x = -1;XCTAssertThrowsError(try CropPreparation.prepare(enclosed,document:d))
    guard let folder=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] else{return};var source=try CraftDocument(width:2,height:2);source.layers[0].content = .raster(try Surface(width:2,height:2,fill:Pixel(0,0,1)));var request=CropRequest(x:-1,y:0,width:4,height:3);request.deleteCroppedPixels=false;request.fill = .background;request.backgroundColor=Pixel(1,0,0);let output=try CropPreparation.prepare(request,document:source).result;try FileManager.default.createDirectory(atPath:folder,withIntermediateDirectories:true);try RasterIO.encoded(output,type:.png).write(to:URL(fileURLWithPath:folder).appendingPathComponent("large-crop-background-owned.png"))
  }
  func testSoleBackgroundContentAwareExpansionUsesUnfilledOutsideRegion()throws {
    var source=try CraftDocument(width:12,height:8);source.layers[0].content = .raster(try Surface(width:12,height:8,fill:Pixel(0,0,1)));source.layers[0].background=true;var request=CropRequest(x:-2,y:-2,width:16,height:12);request.fill = .contentAware;let result=try CropPreparation.prepare(request,document:source).result;XCTAssertTrue(result.layers[0].isBackground);XCTAssertEqual(result.layers.count,2);let output=try Renderer.composite(result);XCTAssertEqual(output.pixel(x:0,y:0),Pixel(0,0,1));XCTAssertEqual(output.pixel(x:5,y:5),Pixel(0,0,1));XCTAssertFalse(try PSDCodec.writeRasterLayers(result,format:.psb).isEmpty)
  }

}
