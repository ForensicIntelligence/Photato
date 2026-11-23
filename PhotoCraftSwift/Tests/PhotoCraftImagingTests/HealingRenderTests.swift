import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class HealingRenderTests: XCTestCase {

  func testCroppedCorrectionLayerGrowthKeepsAnExactRegionalPreviewAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      var document = try CraftDocument(width: 384, height: 256, depth: depth)
      var background = try Surface(width: 384, height: 256, depth: depth, fill: Pixel(0.28, 0.43, 0.55))
      for y in 40..<110 {
        for x in 40..<110 {
          background.setPixel(x: x, y: y, Pixel(Float(x % 13) / 20, Float(y % 17) / 25, 0.45))
        }
      }
      document.layers[0].content = .raster(background)
      var small = try Surface(width: 15, height: 17, depth: depth)
      small.setPixel(x: 0, y: 0, Pixel(0.8, 0.3, 0.1, 0.5))
      small.setPixel(x: 14, y: 16, Pixel(0.4, 0.1, 0.8, 0))
      var correction = Layer(name: "Cropped correction", content: .raster(small))
      correction.x = 175
      correction.y = 115
      try Command.addLayer(correction).apply(to: &document)
      let initial = try Renderer.render(document)
      let sample = try Renderer.cloneSample(in: document, layerID: correction.id, sampling: .currentAndBelow)
      var brush = CloneBrush()
      brush.size = 36
      brush.hardness = 0.7
      brush.pressureSize = false
      let stroke = CloneStroke(source: sample, mapping: .init(source: .init(72, 72), anchor: .init(163, 106)),
        brush: brush, points: [.init(x: 163, y: 106), .init(x: 154, y: 93)], mask: false)
      for edit in [Command.cloneStamp(correction.id, stroke), .healingBrush(correction.id, .init(stroke: stroke, destination: sample))] {
        var result = document
        try edit.apply(to: &result)
        let grown = try XCTUnwrap(result.layers.last)
        XCTAssertLessThan(grown.x, correction.x)
        XCTAssertLessThan(grown.y, correction.y)
        let regional = try Renderer.render(result, reusing: initial)
        guard case .region(let damage) = regional.update else { return XCTFail("Expected a regional preview") }
        XCTAssertLessThan(damage.width * damage.height, 12_000)
        XCTAssertEqual(regional.surface, try Renderer.composite(result))
        XCTAssertNotEqual(initial.surface, regional.surface)
        let reversed = try Renderer.render(document, reusing: regional)
        XCTAssertEqual(reversed.surface, initial.surface)
        XCTAssertEqual(reversed.update, regional.update)
      }
    }
  }

  func testCroppedRasterWithAnOpaqueDefaultOrMaskKeepsFullInvalidation() throws {
    for masked in [false, true] {
      var document = try CraftDocument(width: 192, height: 128)
      let fill: Pixel = masked ? .clear : .white
      var layer = Layer(name: "Cropped", content: .raster(try Surface(width: 20, height: 20, fill: fill)))
      if masked { layer.mask = try Surface(width: 20, height: 20, fill: .white) }
      try Command.addLayer(layer).apply(to: &document)
      let initial = try Renderer.render(document)
      let index = try XCTUnwrap(document.layers.firstIndex(where: { $0.id == layer.id }))
      document.layers[index].content = .raster(try Surface(width: 40, height: 32, fill: fill))
      let updated = try Renderer.render(document, reusing: initial)
      XCTAssertEqual(updated.update, .full)
      XCTAssertEqual(updated.surface, try Renderer.composite(document))
    }
  }

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
