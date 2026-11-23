import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class HealingRenderTests: XCTestCase {

  func testCompositeSampleReuseMatchesFreshAndRejectsStaleOrDifferentLayerCoverage() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 24, height: 16, depth: depth)
      document.layers[0].content = .raster(try Surface(width: 24, height: 16, depth: depth, fill: Pixel(0.31, 0.22, 0.19)))
      let correction = Layer(name: "Retouch", content: .raster(try Surface(width: 2, height: 2, depth: depth)))
      try Command.addLayer(correction).apply(to: &document)
      let before = try Renderer.render(document)
      let sample = try Renderer.cloneSample(in: document, layerID: correction.id, sampling: .currentAndBelow, reusing: before)
      let fresh = try Renderer.cloneSample(in: document, layerID: correction.id, sampling: .currentAndBelow)
      XCTAssertEqual(sample, fresh)
      XCTAssertEqual(sample.surface, before.surface)

      let overlay = Layer(name: "Above", content: .raster(try Surface(width: 24, height: 16, depth: depth, fill: Pixel(0.78, 0.74, 0.45))))
      try Command.addLayer(overlay).apply(to: &document)
      let withOverlay = try Renderer.render(document)
      let below = try Renderer.cloneSample(in: document, layerID: correction.id, sampling: .currentAndBelow, reusing: withOverlay)
      let all = try Renderer.cloneSample(in: document, layerID: correction.id, sampling: .all, reusing: withOverlay)
      XCTAssertEqual(below.surface, before.surface)
      XCTAssertEqual(all.surface, withOverlay.surface)
      XCTAssertNotEqual(all.surface, below.surface)

      document.layers[0].content = .raster(try Surface(width: 24, height: 16, depth: depth, fill: Pixel(0.58, 0.37, 0.3)))
      let after = try Renderer.cloneSample(in: document, layerID: correction.id, sampling: .currentAndBelow, reusing: before)
      let current = try Renderer.cloneSample(in: document, layerID: correction.id, sampling: .currentAndBelow)
      XCTAssertEqual(after, current)
      XCTAssertNotEqual(after.surface, before.surface)
    }
  }

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
