import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class SpotHealingRenderTests: XCTestCase {
  func testSampleAllLayersRepairPersistsAndMatchesRegionalComposition() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 96, height: 80, depth: depth)
      var pixels = try Surface(width: 96, height: 80, depth: depth, fill: Pixel(0.6, 0.5, 0.4))
      for y in 38...42 { for x in 46...50 { pixels.setPixel(x: x, y: y, Pixel(0.03, 0.03, 0.03)) } }
      d.layers[0].content = .raster(pixels)
      let empty = Layer(
        name: "Retouch", content: .raster(try Surface(width: 96, height: 80, depth: depth)))
      d.layers.append(empty)
      d.activeLayerID = empty.id
      let sample = try Renderer.cloneSample(in: d, layerID: empty.id, sampling: .all)
      let baseline = try Renderer.render(d)
      var brush = CloneBrush()
      brush.size = 12
      brush.hardness = 1
      brush.pressureSize = false
      let stroke = SpotHealingStroke(sample: sample, brush: brush, points: [.init(x: 48, y: 40)])
      try Command.spotHealing(empty.id, stroke).apply(to: &d)
      let full = try Renderer.composite(d)
      let regional = try Renderer.render(d, reusing: baseline)
      if case .region = regional.update {} else { XCTFail("Expected regional update") }
      XCTAssertEqual(try full.rgbaData(depth: .f32), try regional.surface.rgbaData(depth: .f32))
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      let restored = try Renderer.composite(reopened)
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
      XCTAssertEqual(d.layers[0].content, .raster(pixels))
    }
  }
}
