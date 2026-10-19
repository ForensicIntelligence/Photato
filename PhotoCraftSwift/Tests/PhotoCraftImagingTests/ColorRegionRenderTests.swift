import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class ColorRegionRenderTests: XCTestCase {
  func testAllLayersBucketNativeAndPSDAndIncrementalRenderingAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 96, height: 80, depth: depth)
      var s = try Surface(width: 96, height: 80, depth: depth, fill: .white)
      for y in 0..<80 { s.setPixel(x: 40, y: y, .black) }
      d.layers[0].content = .raster(s)
      let empty = Layer(
        name: "Fill", content: .raster(try Surface(width: 96, height: 80, depth: depth)))
      d.layers.append(empty)
      d.activeLayerID = empty.id
      let baseline = try Renderer.render(d)
      let sample = try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .all)
      var options = BucketOptions()
      options.sampleAllLayers = true
      let fill = BucketFill(
        source: sample, seed: .init(10, 10), color: Pixel(0.25, 0.5, 0.75), options: options)
      try Command.paintBucket(empty.id, fill).apply(to: &d)
      XCTAssertEqual(d.layers[0].content, .raster(s))
      let full = try Renderer.composite(d)
      let regional = try Renderer.render(d, reusing: baseline)
      if case .region = regional.update {} else { XCTFail("Expected regional update") }
      XCTAssertEqual(try full.rgbaData(depth: .f32), try regional.surface.rgbaData(depth: .f32))
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(d)), d)
      let restored = try Renderer.composite(PSDCodec.read(PSDCodec.writeRasterLayers(d)))
      for y in 0..<80 {
        for x in 0..<96 {
          let a = full.pixel(x: x, y: y)
          let b = restored.pixel(x: x, y: y)
          let tolerance: Float = depth == .u8 ? 1.0 / 255 : depth == .u16 ? 1.0 / 65535 : 0.000002
          XCTAssertEqual(a.r, b.r, accuracy: tolerance)
          XCTAssertEqual(a.g, b.g, accuracy: tolerance)
          XCTAssertEqual(a.b, b.b, accuracy: tolerance)
          XCTAssertEqual(a.a, b.a, accuracy: tolerance)
        }
      }
    }
  }
}
