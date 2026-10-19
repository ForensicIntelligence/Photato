import Foundation
import PhotoCraftCore
import XCTest

@testable import PhotoCraftImaging

final class ThumbnailCoverageTests: XCTestCase {
  func testNonconstantAffineFootprintAndReflectionPreserveCoveredArea() throws {
    let document = try CraftDocument(width: 4, height: 4, depth: .f32)
    var source = try Surface(width: 2, height: 2, depth: .f32)
    source.setPixel(x: 0, y: 0, .white)
    for reflection in [1.0, -1.0] {
      var layer = Layer(name: "Sparse diamond", content: .raster(source))
      layer.affine =
        .translation(2, reflection < 0 ? 1.4142135623730951 : 0)
        * .scale(1, reflection) * .rotation(45)
      let output = try XCTUnwrap(
        Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 2))
      XCTAssertEqual(output.pixel(x: 0, y: 0).a, 0.125, accuracy: 0.000001)
      XCTAssertEqual(output.pixel(x: 1, y: 0).a, 0.125, accuracy: 0.000001)
      XCTAssertEqual(output.pixel(x: 0, y: 1), .clear)
      XCTAssertEqual(output.pixel(x: 1, y: 1), .clear)
    }
  }

  func testColorAverageUsesAlphaWeightsAndFractionalClipping() throws {
    let document = try CraftDocument(width: 2, height: 2, depth: .f32)
    var source = try Surface(width: 2, height: 2, depth: .f32)
    source.setPixel(x: 0, y: 0, Pixel(1, 0, 0))
    source.setPixel(x: 1, y: 0, Pixel(0, 0, 1, 0.5))
    var layer = Layer(name: "Alpha", content: .raster(source))
    let output = try XCTUnwrap(
      Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 1))
    XCTAssertEqual(output.pixel(x: 0, y: 0), Pixel(2.0 / 3.0, 0, 1.0 / 3.0, 0.375))
    layer.content = .raster(try Surface(width: 2, height: 2, depth: .f32, fill: .white))
    layer.affine = .translation(-0.5, 0)
    XCTAssertEqual(
      try Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 1)?
        .pixel(x: 0, y: 0), Pixel(1, 1, 1, 0.75))
  }

  func testMixedAxisMinificationDoesNotLoseThinLine() throws {
    let document = try CraftDocument(width: 4, height: 4, depth: .f32)
    var source = try Surface(width: 4, height: 1, depth: .f32)
    source.setPixel(x: 0, y: 0, .white)
    var layer = Layer(name: "Anisotropic", content: .raster(source))
    layer.affine = .scale(0.5, 4)
    let output = try XCTUnwrap(
      Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 4))
    for y in 0..<4 {
      XCTAssertEqual(output.pixel(x: 0, y: y), Pixel(1, 1, 1, 0.5))
      for x in 1..<4 { XCTAssertEqual(output.pixel(x: x, y: y), .clear) }
    }
  }

  func testSampleBudgetRejectsExcessWorkAndConstantSurfacesAvoidScan() throws {
    var sampler = ThumbnailCoverage(mapping: .scale(4, 4), maximumSamples: 1)
    var sparse = try Surface(width: 4, height: 4)
    sparse.setPixel(x: 0, y: 0, .white)
    XCTAssertThrowsError(try sampler.sample(sparse, x: 0, y: 0))
    var constant = ThumbnailCoverage(mapping: .scale(32768, 1), maximumSamples: 0)
    XCTAssertEqual(
      try constant.sample(Surface(width: 32768, height: 1, fill: .white), x: 0, y: 0), .white)
  }

  func testMagnificationRetainsExistingBilinearEdgeBehavior() throws {
    let document = try CraftDocument(width: 2, height: 1, depth: .f32)
    let layer = Layer(
      name: "Enlarged",
      content: .raster(try Surface(width: 2, height: 1, depth: .f32, fill: .white)))
    let result = try XCTUnwrap(
      Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 4))
    XCTAssertEqual(result.pixel(x: 0, y: 0), Pixel(1, 1, 1, 0.5625))
    XCTAssertEqual(result.pixel(x: 1, y: 0), Pixel(1, 1, 1, 0.75))
  }

  func testLargeSparsePreviewProducesFiniteCoverageWithinBudget() throws {
    let document = try CraftDocument(width: 1060, height: 470, depth: .f32)
    var source = try Surface(width: 1060, height: 470, depth: .f32)
    for x in 0..<1060 { source.setPixel(x: x, y: 3, .white) }
    let layer = Layer(name: "Wide line", content: .raster(source))
    let start = Date()
    let output = try XCTUnwrap(
      Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 64))
    var alpha = 0.0
    for y in 0..<output.height {
      for x in 0..<output.width { alpha += Double(output.pixel(x: x, y: y).a) }
    }
    // Unit-height line covers1060 square document pixels.
    XCTAssertEqual(
      alpha * Double(document.width * document.height) / Double(output.width * output.height), 1060,
      accuracy: 0.001)
    print(
      "Thumbnail area1060x470 to64: \(Date().timeIntervalSince(start)) seconds; output \(output.width)x\(output.height)"
    )
  }
  func testThinLineContributesCoverageBetweenSampleCentersAtEveryDepth() throws {
    for depth in PixelDepth.allCases {
      let document = try CraftDocument(width: 32, height: 8, depth: depth)
      var pixels = try Surface(width: 32, height: 8, depth: depth)
      for x in 0..<32 { pixels.setPixel(x: x, y: 0, .white) }
      let layer = Layer(name: "One pixel line", content: .raster(pixels))
      let result = try XCTUnwrap(
        Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 4))
      XCTAssertEqual(result.width, 4)
      XCTAssertEqual(result.height, 1)
      for x in 0..<4 {
        XCTAssertEqual(result.pixel(x: x, y: 0), Pixel(1, 1, 1, 0.125).quantized(depth))
      }
    }
  }

  func testOffCenterSinglePixelAndHiddenRGBUsePremultipliedCoverage() throws {
    let document = try CraftDocument(width: 4, height: 4, depth: .f32)
    var pixels = try Surface(width: 4, height: 4, depth: .f32, fill: Pixel(1, 0, 0, 0))
    pixels.setPixel(x: 0, y: 0, Pixel(0, 0, 1, 0.5))
    let result = try XCTUnwrap(
      Renderer.layerThumbnail(
        Layer(name: "Blue", content: .raster(pixels)), in: document, framing: .entireDocument,
        maximumSize: 1))
    XCTAssertEqual(result.pixel(x: 0, y: 0), Pixel(0, 0, 1, 1.0 / 32.0))
  }

  func testRotatedPixelAreaIsSharedAcrossOutputCells() throws {
    let document = try CraftDocument(width: 4, height: 4, depth: .f32)
    var layer = Layer(
      name: "Diamond", content: .raster(try Surface(width: 1, height: 1, depth: .f32, fill: .white))
    )
    layer.affine = .translation(2, 0) * .rotation(45)
    let result = try XCTUnwrap(
      Renderer.layerThumbnail(layer, in: document, framing: .entireDocument, maximumSize: 2))
    // Unit-area diamond, split in half at x=2. Each output pixel covers4 source-document units.
    XCTAssertEqual(result.pixel(x: 0, y: 0).a, 0.125, accuracy: 0.000001)
    XCTAssertEqual(result.pixel(x: 1, y: 0).a, 0.125, accuracy: 0.000001)
    XCTAssertEqual(result.pixel(x: 0, y: 1), .clear)
    XCTAssertEqual(result.pixel(x: 1, y: 1), .clear)
  }
}
