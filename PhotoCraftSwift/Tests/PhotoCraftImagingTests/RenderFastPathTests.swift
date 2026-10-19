import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class RenderFastPathTests: XCTestCase {
  func testDirectPatternPickingMatchesCanvasPixelsAtAllDepthsAndAffinePlacements() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 17, height: 13, depth: depth)
      var surface = try Surface(width: 3, height: 2, depth: .f32, fill: Pixel(0.2, 0.4, 0.6, 0.37))
      surface.setPixel(x: 1, y: 0, Pixel(-1, 2, 0.3, 0))
      let tile = try RasterPattern(name: "Picking", surface: surface)
      try doc.installPattern(tile)
      for transform in [
        Transform2D.identity, .translation(7.25, -3.5), .rotation(37), .scale(-0.7, 1.3),
      ] {
        var fill = PatternFill(patternID: tile.id)
        fill.placement.angle = -17
        fill.placement.scale = 137
        fill.geometry = transform
        let reference = try Renderer.layerSurface(
          Layer(name: "Fill", content: .patternFill(fill)), in: doc)
        for y in -1...doc.height {
          for x in -1...doc.width {
            XCTAssertTrue(
              try Renderer.patternPixel(fill, in: doc, x: x, y: y).hasSameBits(
                as: reference.pixel(x: x, y: y)))
          }
        }
      }
    }
  }
  func testIdentityElisionPreservesContinuousEdgeSamplingAndAllBlendRenderBits() throws {
    for depth in PixelDepth.allCases {
      var doc = try CraftDocument(width: 17, height: 13, depth: depth)
      doc.layers[0].content = .raster(
        try Surface(width: 17, height: 13, depth: depth, fill: Pixel(0.37, 0.72, 0.13, 0.6)))
      let pattern = try PatternPresets.make()[4]
      var layer = Layer(name: "Pattern", content: .patternFill(PatternFill(patternID: pattern.id)))
      layer.mask = try Surface(width: 17, height: 13, depth: depth, fill: .white)
      layer.opacity = 0.7
      try Command.addPatternFill(layer, pattern).apply(to: &doc)
      let region = IntRect(x: 0, y: 0, width: doc.width, height: doc.height)
      XCTAssertNil(try LayerMaskSampler.make(layer: layer, document: doc, pixelRegion: region))
      let continuous = try XCTUnwrap(LayerMaskSampler.make(layer: layer, document: doc))
      XCTAssertLessThan(continuous.coverage(x: 0.1, y: 0.5), 1)
      XCTAssertEqual(continuous.coverage(x: -3, y: 0.5), 0)
      for blend in BlendMode.allCases {
        doc.layers[1].blendMode = blend
        var reference = doc
        // An allocated, all-white tile forces the original per-pixel path.
        reference.layers[1].mask?.setPixel(x: 3, y: 2, .white)
        XCTAssertNotNil(
          try LayerMaskSampler.make(
            layer: reference.layers[1], document: reference, pixelRegion: region))
        XCTAssertEqual(
          try Renderer.composite(doc).rgbaData(depth: .f32),
          try Renderer.composite(reference).rgbaData(depth: .f32))
      }
    }
  }
}
