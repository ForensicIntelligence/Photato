import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class ToningRenderTests: XCTestCase {
  func testAllToolsAtEveryDepthMatchRegionalCompositionAndPersistThroughPSD() throws {
    for depth in PixelDepth.allCases {
      for kind in ToningTool.allCases {
        var d = try CraftDocument(width: 96, height: 80, depth: depth)
        d.layers[0].content = .raster(
          try Surface(width: 96, height: 80, depth: depth, fill: Pixel(0.7, 0.4, 0.3, 0.8)))
        let baseline = try Renderer.render(d)
        var brush = CloneBrush()
        brush.size = 12
        brush.hardness = 1
        brush.pressureSize = false
        try Command.toning(
          d.layers[0].id,
          ToningStroke(
            tool: kind, brush: brush, points: [.init(x: 48, y: 40), .init(x: 55, y: 40)])
        ).apply(to: &d)
        let full = try Renderer.composite(d)
        let regional = try Renderer.render(d, reusing: baseline)
        if case .region = regional.update {} else { XCTFail("Expected a regional edit") }
        XCTAssertEqual(try full.rgbaData(depth: .f32), try regional.surface.rgbaData(depth: .f32))
        let reopened = try Renderer.composite(PSDCodec.read(PSDCodec.writeRasterLayers(d)))
        for y in 0..<80 {
          for x in 0..<96 {
            let a = full.pixel(x: x, y: y)
            let b = reopened.pixel(x: x, y: y)
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
}
