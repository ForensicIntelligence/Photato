import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class HealingRenderTests: XCTestCase {
  func testRepairPersistsAndRegionalRenderMatchesFullAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var d = try CraftDocument(width: 128, height: 64, depth: depth)
      var pixels = try Surface(width: 128, height: 64, depth: depth, fill: Pixel(0.7, 0.5, 0.3))
      for y in 0..<64 {
        for x in 0..<64 {
          let t: Float = x % 8 < 4 ? 0.07 : -0.07
          pixels.setPixel(x: x, y: y, Pixel(0.2 + t, 0.3 + t, 0.6 + t))
        }
      }
      d.layers[0].content = .raster(pixels)
      let id = d.layers[0].id
      let snapshot = try Renderer.render(d)
      var brush = CloneBrush()
      brush.size = 24
      brush.hardness = 1
      let sample = try Renderer.cloneSample(in: d, layerID: id, sampling: .current)
      let stroke = CloneStroke(
        source: sample, mapping: .init(source: .init(32, 32), anchor: .init(96, 32)), brush: brush,
        points: [.init(x: 96, y: 32)])
      try Command.healingBrush(id, .init(stroke: stroke)).apply(to: &d)
      let full = try Renderer.composite(d)
      let regional = try Renderer.render(d, reusing: snapshot)
      XCTAssertEqual(regional.update, .region(IntRect(x: 64, y: 0, width: 64, height: 64)))
      XCTAssertEqual(try full.rgbaData(depth: .f32), try regional.surface.rgbaData(depth: .f32))
      let reopened = try PSDCodec.read(PSDCodec.writeRasterLayers(d))
      let restored = try Renderer.composite(reopened)
      for y in 0..<64 {
        for x in 0..<128 {
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
