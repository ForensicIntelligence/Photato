import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LargeSmartObjectTests:XCTestCase {
  func testMaximumRGBConversionSourceReopenFilterAndNativePersistence()throws {
    let initial=try CraftDocument(width:300_000,height:300_000)
    let id=try XCTUnwrap(initial.activeLayerID);var session=EditorSession(document:initial)
    try session.execute(SmartObjectIO.convert(in:initial,selected:[id]))
    let converted=session.document,layer=converted.layers[0],source=try XCTUnwrap(layer.smartObject)
    let cached=try Renderer.render(converted)
    XCTAssertEqual(cached.surface.tileCount,0)
    XCTAssertEqual(cached.surface.pixel(x:150_000,y:150_000),.white)
    XCTAssertLessThan(source.data.count,SmartObject.maximumSourceBytes)
    let reopened=try SmartObjectIO.sourceDocument(source)
    XCTAssertEqual(reopened.width,300_000);XCTAssertEqual(reopened.height,300_000)
    XCTAssertEqual(reopened.layers[0].content,initial.layers[0].content)
    try session.execute(.applyFilter(layer.id,RasterFilter(.highPass)))
    XCTAssertEqual(session.document.layers[0].content,layer.content)
    XCTAssertEqual(session.document.layers[0].smartObject,source)
    let output=try Renderer.composite(session.document,region:IntRect(x:150_000,y:150_000,width:64,height:64))
    XCTAssertLessThan(output.pixel(x:150_001,y:150_001).r,1)
    let data=try NativeArchive.encodeChunked(session.document)
    XCTAssertEqual(try NativeArchive.decodePaged(data),session.document)
    try session.undo();XCTAssertEqual(session.document,converted)
    try session.undo();XCTAssertEqual(session.document,initial)
    try session.redo();XCTAssertEqual(session.document,converted)
  }
  func testLargeNativeSourceDecodeUsesMappedSamplesAndOriginalBytes()throws {
    var source=try CraftDocument(width:6000,height:1500)
    var pixels=try Surface(width:6000,height:1500,fill:.clear)
    pixels.setPixel(x:5999,y:1499,Pixel(0.2,0.4,0.8));source.layers[0].content = .raster(pixels)
    let bytes=try NativeArchive.encodeChunked(source)
    let decoded=try SmartObjectIO.decode(bytes,fileName:"Owned.photato")
    XCTAssertEqual(decoded,source)
    guard case .raster(let mapped)=decoded.layers[0].content else{return XCTFail("Missing pixels")}
    XCTAssertGreaterThan(mapped.mappedBytes,0)
    let object=try SmartObjectIO.placed(document:decoded,data:bytes,fileName:"Owned.photato",in:source,fit:false)
    XCTAssertEqual(object.smartObject?.data,bytes)
    XCTAssertEqual(object.smartObject?.width,6000)
    XCTAssertLessThan(try Renderer.layerSurface(object,in:source).allocatedBytes,256*1_024*1_024)
  }
  func testUnfilteredCachedCompositionMatchesBoundedRendererAtEveryDepth()throws {
    for depth in PixelDepth.allCases {
      let document=try SmartObjectTests().converted(depth)
      let expected=try Renderer.composite(document)
      let sparse=try XCTUnwrap(SparseCanvasRenderer.composite(document))
      XCTAssertEqual(try sparse.rgbaData(depth:.f32,colorEncoding:depth == .f32 ? .linearRGB:.sRGB),
        try expected.rgbaData(depth:.f32,colorEncoding:depth == .f32 ? .linearRGB:.sRGB))
    }
  }
}
