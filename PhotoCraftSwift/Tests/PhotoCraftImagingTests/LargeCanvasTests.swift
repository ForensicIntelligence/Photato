import CoreGraphics
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class LargeCanvasTests: XCTestCase {
  func testSparseCompositorMatchesExistingNativePixelsAcrossDepthAndBlend() throws {
    for depth in PixelDepth.allCases { for opaque in [false,true] { for blend in [BlendMode.normal,.multiply,.screen] {
      var d = try CraftDocument(width: 67, height: 65, depth: depth)
      var a = try Surface(width: 67, height: 65, depth: depth, fill: Pixel(0.2,0.5,0.8,opaque ? 1:0.4), colorEncoding: depth == .f32 ? .linearRGB:.sRGB)
      a.setPixel(x: 66, y: 64, Pixel(0.4,0.1,0.7,opaque ? 1:0.2))
      var b = try Surface(width: 67, height: 65, depth: depth, fill: Pixel(0.7,0.4,0.2,0.6), colorEncoding: depth == .f32 ? .linearRGB:.sRGB)
      b.setPixel(x: 2, y: 3, .clear)
      d.layers[0].content = .raster(a)
      var top = Layer(name: "Top", content: .raster(b)); top.opacity = 0.37; top.blendMode = blend; d.layers.append(top)
      let expected = try Renderer.composite(d), actual = try XCTUnwrap(SparseCanvasRenderer.composite(d))
      for (x,y) in [(0,0),(2,3),(66,64),(64,63)] {
        let e = depth == .f32 ? expected.linearPixel(x:x,y:y):expected.pixel(x:x,y:y)
        let p = depth == .f32 ? actual.linearPixel(x:x,y:y):actual.pixel(x:x,y:y)
        XCTAssertTrue(e.hasSameBits(as:p), "\(depth),\(opaque),\(blend),\(x),\(y):\(e),\(p)")
      }
    } } }
  }
  func testMaximumCanvasCompositionIncrementalPaintAndThumbnailAreBounded() throws {
    var d = try CraftDocument(width: 300_000, height: 300_000)
    let initial = try Renderer.render(d); XCTAssertEqual(initial.surface.allocatedBytes, 0)
    var source = try Surface(width: d.width, height: d.height)
    source.setPixel(x:299_999,y:299_999,Pixel(1,0,0))
    let layer = Layer(name:"Far edge",content:.raster(source));d.layers.append(layer)
    let first = try Renderer.render(d,reusing:initial)
    XCTAssertEqual(first.surface.pixel(x:299_999,y:299_999),Pixel(1,0,0))
    XCTAssertLessThanOrEqual(first.surface.tileCount,1)
    source.setPixel(x:10,y:10,.black);d.layers[1].content = .raster(source)
    let second = try Renderer.render(d,reusing:first)
    XCTAssertEqual(second.surface.pixel(x:10,y:10),.black)
    XCTAssertEqual(second.surface.pixel(x:299_999,y:299_999),Pixel(1,0,0))
    let thumbnail = try XCTUnwrap(Renderer.layerThumbnail(d.layers[0],in:d,framing:.entireDocument,maximumSize:32))
    XCTAssertEqual(thumbnail.width,32);XCTAssertEqual(thumbnail.pixel(x:0,y:0),.white)
    let paintedThumbnail = try XCTUnwrap(Renderer.layerThumbnail(d.layers[1],in:d,framing:.entireDocument,maximumSize:32))
    // One source pixel is below an8-bit thumbnail alpha code; verify coverage
    // before that intentional quantization as well as the resulting thumbnail.
    let area = try source.sparseAreaSample(left:290_625,top:290_625,right:300_000,bottom:300_000,maximumSamples:4096)
    XCTAssertEqual(Double(area.pixel.a),1 / (9375.0 * 9375.0),accuracy:1e-15)
    XCTAssertEqual(paintedThumbnail.pixel(x:31,y:31).a,0)
    let bounded = try second.surface.reducedPreview(in:.init(x:299_990,y:299_990,width:10,height:10),width:10,height:10)
    let image = try ColorManagement.displayImage(bounded,in:d)
    let preview = CanvasRasterPreview(base:image,documentRegion:.init(x:299_990,y:299_990,width:10,height:10))
    XCTAssertEqual(preview.documentRegion.x,299_990);XCTAssertLessThan(preview.allocatedBytes,1000)
    XCTAssertThrowsError(try RasterIO.displayImage(second.surface))
  }
}
