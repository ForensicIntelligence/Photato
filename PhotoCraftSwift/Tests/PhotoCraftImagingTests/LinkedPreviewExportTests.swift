import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LinkedPreviewExportTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8,explicit:Bool=false,outside:Float=0)throws->CraftDocument {
    let bytes=try RasterIO.encoded(Surface(width:4,height:3,fill:Pixel(1,0,0)),type:.png)
    var d=try CraftDocument(width:12,height:12,depth:depth)
    let reference=try LinkedSmartObjectSource(reference:"file:///does-not-exist/Owned.png",contentHash:LinkedSmartObjectSource.fingerprint(bytes),byteLength:UInt64(bytes.count))
    var layer=try LinkedSmartObjectIO.place(bytes,fileName:"Owned.png",reference:reference,in:d,fit:false)
    layer.x=3;layer.y=4;layer.affine = .scale(2,2);layer.mask=try Surface(width:4,height:3,depth:depth,fill:.white)
    if explicit || outside != 0 {var p=MaskProperties();p.outside=outside;p.linked = !explicit;layer.maskProperties=p}
    d.layers=[layer];d.activeLayerID=layer.id;return d
  }
  func capture(_ data:Data,_ name:String)throws {
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try data.write(to:dir.appendingPathComponent(name))
    }
  }
  func testSourceAlphaAndNumericalMaskUseIndependentAnalyticalCoverageAtEveryDepth()throws {
    var records:[[String:Any]]=[]
    for depth in PixelDepth.allCases {
      let source=try fixture(depth),preview=try PSDSmartObjects.bakedPreview(source.layers[0],in:source)
      guard case .raster(let p)=preview.content,let mask=preview.mask else{return XCTFail("Raster and mask")}
      XCTAssertEqual(p.width,8);XCTAssertEqual(p.height,6);XCTAssertEqual(p.pixel(x:0,y:0).a,depth.quantize(0.5625));XCTAssertEqual(p.pixel(x:1,y:0).a,depth.quantize(0.75))
      let sampler=try MaskSampler(layer:preview);XCTAssertEqual(sampler.coverage(x:3.5,y:4.5),depth.quantize(0.5625));XCTAssertEqual(sampler.coverage(x:4.5,y:4.5),depth.quantize(0.75))
      XCTAssertEqual(mask.colorEncoding,.sRGB);XCTAssertEqual(preview.maskProperties?.outside,0)
      records.append(["depth":depth.rawValue,"sourceAlpha":p.pixel(x:0,y:0).a,"maskGray":sampler.coverage(x:3.5,y:4.5),"maskOrigin":[preview.maskCoordinateTransform.tx,preview.maskCoordinateTransform.ty]])
      for format:PSDFileFormat in [.psd,.psb] {
        let bytes=try PSDCodec.writeRasterLayers(source,compression:.raw,format:format),read=try PSDCodec.read(bytes)
        try capture(bytes,"linked-preview-\(depth.rawValue).\(format == .psd ? "psd":"psb")")
        try capture(Renderer.composite(source).rgbaData(depth:.u8),"linked-before-\(depth.rawValue).rgba")
        try capture(Renderer.composite(read).rgbaData(depth:.u8),"linked-reopened-\(depth.rawValue)-\(format == .psd ? "psd":"psb").rgba")
      }
    }
    try capture(JSONSerialization.data(withJSONObject:records,options:[.sortedKeys]),"linked-preview-analytical.json")
  }
  func testFloat32PSDPSBMaskAppearanceRetainsExactSamplesAcrossMaskStates()throws {
    for explicit in [false,true] {for outside:Float in [0,1] {for disabled in [false,true] {
      var source=try fixture(.f32,explicit:explicit,outside:outside)
      if disabled {var p=source.layers[0].effectiveMaskProperties;p.enabled=false;source.layers[0].maskProperties=p}
      let expected=try Renderer.composite(source).rgbaData(depth:.f32,colorEncoding:.linearRGB)
      for format:PSDFileFormat in [.psd,.psb] {
        let read=try PSDCodec.read(PSDCodec.writeRasterLayers(source,format:format))
        XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.f32,colorEncoding:.linearRGB),expected,"explicit=\(explicit), outside=\(outside), disabled=\(disabled)")
      }
    }}}
  }
  func testExportPreservesOriginalSourceBytesNativeMaskGeometryAndUndoHistory()throws {
    for explicit in [false,true] {
      let source=try fixture(.u16,explicit:explicit),original=source
      let session=EditorSession(document:source)
      for format:PSDFileFormat in [.psd,.psb] {_=try PSDCodec.writeRasterLayers(source,format:format)}
      XCTAssertEqual(source,original);XCTAssertEqual(source.layers[0].smartObject?.data,original.layers[0].smartObject?.data);XCTAssertEqual(session.document,source);XCTAssertTrue(session.undoStack.isEmpty)
      let preview=try PSDSmartObjects.bakedPreview(source.layers[0],in:source)
      XCTAssertEqual(preview.smartObject,source.layers[0].smartObject);XCTAssertEqual(preview.maskProperties?.linked,!explicit)
    }
  }
  func testMissingOriginalCacheReexportIsStableAndNeverGrantsFileAuthorization()throws {
    for depth in PixelDepth.allCases {
      let source=try fixture(depth)
      for format:PSDFileFormat in [.psd,.psb] {
        var read=try PSDCodec.read(PSDCodec.writeRasterLayers(source,format:format))
        let expected=try Renderer.composite(read).rgbaData(depth:depth)
        for _ in 0..<2 {
          let object=try XCTUnwrap(read.layers[0].smartObject);XCTAssertTrue(object.data.isEmpty);XCTAssertNil(object.linkedSource?.authorizationID)
          XCTAssertNotNil(try read.layers[0].linkedSmartObjectPreview())
          read=try PSDCodec.read(PSDCodec.writeRasterLayers(read,format:format))
          XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:depth),expected)
        }
        XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(read)),read)
      }
    }
  }
  func testCancellationAndUnqualifiedTransformedFeatherLeaveOriginalUntouched()async throws {
    let source=try fixture(.f32),original=source
    let task=Task {withUnsafeCurrentTask{$0?.cancel()};return try PSDCodec.writeRasterLayers(source)}
    do{_=try await task.value;XCTFail("Cancelled PSD returned output")}catch is CancellationError{}
    XCTAssertEqual(source,original)
    var feathered=source;var p=MaskProperties();p.feather=1;feathered.layers[0].maskProperties=p
    XCTAssertThrowsError(try PSDCodec.writeRasterLayers(feathered));XCTAssertEqual(source,original)
  }
}
