import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class CanvasEdgeIOTests:XCTestCase {
  func fixture(_ depth:PixelDepth = .u8)throws->CraftDocument {
    var source=try CraftDocument(width:16,height:12,depth:depth)
    var pixels=try Surface(width:16,height:12,depth:depth)
    for y in 5..<8{for x in 4..<8{pixels.setPixel(x:x,y:y,Pixel(1,0,0))}}
    source.layers[0].content = .raster(pixels);return source
  }
  func capture(_ data:Data,_ name:String)throws {
    if let path=ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"]{let dir=URL(fileURLWithPath:path);try FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true);try data.write(to:dir.appendingPathComponent(name))}
  }
  func testTrimVisibleCompositeAtEveryDepthAndIndependentVectors()throws {
    var vectors:[[String:Any]]=[]
    for depth in PixelDepth.allCases {
      var source=try fixture(depth);source.selection=IntRect(x:0,y:0,width:1,height:1)
      var hidden=Layer(name:"Hidden border",content:.raster(try Surface(width:16,height:12,depth:depth,fill:.white)));hidden.visible=false;source.layers.append(hidden)
      let result=try CanvasEdgePreparation.prepare(source,operation:.trim(.init(basis:.transparent))).result
      XCTAssertEqual(result.width,4);XCTAssertEqual(result.height,3);XCTAssertNil(result.selection);XCTAssertEqual(result.layers.map(\.id),source.layers.map(\.id))
      let pixels=try Renderer.composite(result);vectors.append(["depth":depth.rawValue,"rgba8":Array(try pixels.rgbaData(depth:.u8))])
      try capture(RasterIO.encoded(result,type:.png),"trim-owned-\(depth.rawValue).png")
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)),result)
    }
    try capture(JSONSerialization.data(withJSONObject:vectors,options:[.sortedKeys]),"trim-analytical.json")
  }
  func testRevealAllRestoresRetainedCropContentWithoutTransparentStoragePadding()throws {
    let source=try fixture();var crop=CropRequest(x:6,y:6,width:2,height:1);crop.deleteCroppedPixels=false
    let cropped=try CropGeometry.applying(crop,to:source)
    let result=try CanvasEdgePreparation.prepare(cropped,operation:.revealAll).result
    XCTAssertEqual(result.width,4);XCTAssertEqual(result.height,3);XCTAssertEqual(result.layers[0].content,source.layers[0].content)
    XCTAssertEqual(result.layers[0].x,-4);XCTAssertEqual(result.layers[0].y,-5)
    XCTAssertEqual(try Renderer.composite(result).rgbaData(depth:.u8),Data(Array(repeating:[UInt8(255),0,0,255],count:12).flatMap{$0}))
    try capture(RasterIO.encoded(result,type:.png),"reveal-owned.png")
  }
  func testHiddenAndZeroOpacityLeavesRevealWhileCurrentCanvasDoesNotShrink()throws {
    var source=try CraftDocument(width:4,height:3)
    source.layers[0].content = .raster(try Surface(width:1,height:1,fill:.white))
    var hidden=Layer(name:"Hidden",content:.raster(try Surface(width:2,height:2,fill:Pixel(0,0,1))));hidden.x = -3;hidden.y = -2;hidden.visible=false
    var zero=Layer(name:"Zero opacity",content:.raster(try Surface(width:1,height:1,fill:.white)));zero.x=8;zero.y=5;zero.opacity=0
    source.layers += [hidden,zero]
    let result=try CanvasEdgePreparation.prepare(source,operation:.revealAll).result
    XCTAssertEqual(result.width,12);XCTAssertEqual(result.height,8);XCTAssertEqual(result.layers[0].x,3);XCTAssertEqual(result.layers[0].y,2);XCTAssertFalse(result.layers[1].visible);XCTAssertEqual(result.layers[2].opacity,0)
  }
  func testMaximumSparseTrimAndRevealAllDoNotAllocateLogicalCanvas()throws {
    var source=try CraftDocument(width:299998,height:299998,depth:.f32)
    var pixels=try Surface(width:300000,height:300000,depth:.f32);pixels.setLinearPixel(x:299999,y:299999,Pixel(8,0,0,1));source.layers[0].content = .raster(pixels)
    let revealed=try CanvasEdgePreparation.prepare(source,operation:.revealAll).result
    XCTAssertEqual(revealed.width,300000);XCTAssertEqual(revealed.height,300000);XCTAssertLessThan(revealed.estimatedBytes,2*1024*1024)
    let trimmed=try CanvasEdgePreparation.prepare(revealed,operation:.trim(.init(basis:.transparent))).result
    XCTAssertEqual(trimmed.width,1);XCTAssertEqual(trimmed.height,1);XCTAssertLessThan(trimmed.estimatedBytes,2*1024*1024)
    guard case .raster(let retained)=trimmed.layers[0].content else{return XCTFail("Raster")};XCTAssertEqual(retained.linearPixel(x:0,y:0),Pixel(8,0,0,1))
  }
  func testNativeComponentTrimKeepsNumericalDistinctionsAndRawWords()throws {
    for mode in [DocumentColorMode.grayscale,.cmyk,.lab] {
      var source=try CraftDocument(width:4,height:3).convertingMode(.init(mode:mode,depth:.u16))
      var native=try XCTUnwrap(source.layers[0].nativeMode)
      for i in 0..<12 {for c in 0..<mode.componentCount{try native.set(0.5,component:c,index:i)};try native.set(1,component:mode.componentCount,index:i)}
      try native.set(0.25,component:0,index:5);source.layers[0].nativeMode=native;source.layers[0].content = .raster(try native.surface())
      let result=try CanvasEdgePreparation.prepare(source,operation:.trim(.init())).result
      XCTAssertEqual(result.width,1);XCTAssertEqual(result.height,1)
      let retained=try XCTUnwrap(result.layers[0].nativeMode)
      for c in native.planes.indices {XCTAssertEqual(retained.planes[c],Data(native.planes[c][10..<12]))}
      XCTAssertEqual(retained.profile,native.profile)
    }
  }
  func testBackgroundExpansionKeepsOpaqueSamplesAndNativePlanes()throws {
    for nativeMode in [false,true] {
      var source=try DocumentCreation.blank(width:3,height:2,depth:.u16,background:Pixel(1,0,0),name:"Owned")
      if nativeMode {source=try source.convertingMode(.init(mode:.cmyk,depth:.u16))}
      let background=source.layers[0]
      var outside=Layer(name:"Outside",content:.raster(try Surface(width:1,height:1,depth:.u16,fill:.white)));outside.x = -1;outside.y = -1
      if source.modeDescriptor == nil {source.layers.append(outside)} else {
        let result=try CanvasFrameGeometry.reframed(source,bounds:.init(x:-1,y:-1,width:5,height:4),background:.white)
        let retained=try XCTUnwrap(result.layers[0].nativeMode),old=try XCTUnwrap(background.nativeMode)
        for c in old.planes.indices {XCTAssertEqual(Data(retained.planes[c][12..<18]),Data(old.planes[c][0..<6]))}
        XCTAssertTrue(try Renderer.composite(result).isOpaque());continue
      }
      let result=try CanvasEdgePreparation.prepare(source,operation:.revealAll).result
      XCTAssertTrue(result.layers[0].isBackground);XCTAssertEqual(result.width,4);XCTAssertEqual(result.height,3)
      guard case .raster(let pixels)=result.layers[0].content else{return XCTFail("Raster")}
      XCTAssertEqual(pixels.pixel(x:0,y:0),.white);XCTAssertEqual(pixels.pixel(x:1,y:1),Pixel(1,0,0));XCTAssertTrue(try pixels.isOpaque())
    }
  }
  func testTrimAndRevealSaveOpenAsPSDAndPSBAcrossDepths()throws {
    for depth in PixelDepth.allCases {
      let original=try fixture(depth)
      var crop=CropRequest(x:6,y:6,width:2,height:1);crop.deleteCroppedPixels=false
      let retained=try CropGeometry.applying(crop,to:original)
      let documents=[("trim",try CanvasEdgePreparation.prepare(original,operation:.trim(.init(basis:.transparent))).result),("reveal",try CanvasEdgePreparation.prepare(retained,operation:.revealAll).result)]
      for (kind,result) in documents {for format:PSDFileFormat in [.psd,.psb] {
        let data=try PSDCodec.writeRasterLayers(result,format:format),read=try PSDCodec.read(data)
        XCTAssertEqual(read.width,4);XCTAssertEqual(read.height,3);XCTAssertEqual(read.depth,depth)
        XCTAssertEqual(try Renderer.composite(read).rgbaData(depth:.u8),Data(Array(repeating:[UInt8(255),0,0,255],count:12).flatMap{$0}))
        XCTAssertEqual(read.layers[0].x,result.layers[0].x);XCTAssertEqual(read.layers[0].y,result.layers[0].y)
        try capture(data,"edges-\(kind)-\(depth.rawValue).\(format == .psd ? "psd":"psb")")
      }}
    }
  }
  func testNoOpAndOversizeDoNotChangeHistoryOrSource()throws {
    let source=try fixture();var session=EditorSession(document:source)
    try session.execute(CanvasEdgePreparation.command(source,operation:.revealAll));XCTAssertEqual(session.document,source);XCTAssertTrue(session.undoStack.isEmpty)
    var outside=source;outside.layers[0].x = -300000
    XCTAssertThrowsError(try CanvasEdgePreparation.command(outside,operation:.revealAll));XCTAssertEqual(source.layers[0].x,0)
  }
}
