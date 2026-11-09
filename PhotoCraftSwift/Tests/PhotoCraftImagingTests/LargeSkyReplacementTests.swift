import CoreGraphics
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class LargeSkyReplacementTests: XCTestCase {
  func uniform(_ width: Int, _ height: Int, depth: PixelDepth = .u8, color: Pixel = Pixel(0.3, 0.6, 0.95)) throws -> CraftDocument {
    var document = try CraftDocument(width: width, height: height, depth: depth)
    document.layers[0].content = .raster(try Surface(width: width, height: height, depth: depth, fill: color,
      colorEncoding: depth == .f32 ? .linearRGB : .sRGB))
    return document
  }

  func testMaximumCanvasEditableOutputRetainsSmallKernelWordsAndArchive() throws {
    for depth in PixelDepth.allCases {
      let size = Surface.maxDimension
      let original = try uniform(size, size, depth: depth), sky = try uniform(size, size, depth: depth, color: Pixel(0.9, 0.4, 0.2))
      var settings = SkyReplacementSettings(); settings.edgeLighting = 70
      let input = try SkyReplacementInput.prepare(original)
      let result = try input.edit(sky: sky, name: "Owned sky", settings: settings)
      let actual = try Renderer.composite(result.edit.result)
      let small = try uniform(32, 32, depth: depth), smallSky = try uniform(32, 32, depth: depth, color: Pixel(0.9, 0.4, 0.2))
      let expected = try Renderer.composite(SkyReplacementInput.prepare(small).edit(sky: smallSky, name: "Owned sky", settings: settings).edit.result)
      XCTAssertEqual(result.edit.result.layers.count, original.layers.count + 7)
      XCTAssertTrue(try result.mask.isFullCoverage)
      for (x, y) in [(0, 0), (size / 2, size / 2), (size - 1, size - 1)] {
        let a = actual.linearPixel(x: x, y: y), b = expected.linearPixel(x: 0, y: 0)
        XCTAssertTrue(a.hasSameBits(as: b), "\(depth), (\(x),\(y))")
      }
      XCTAssertLessThan(actual.allocatedBytes, 4 * 1024 * 1024)
      XCTAssertTrue(try NativeArchive.decode(NativeArchive.encodeChunked(result.edit.result)) == result.edit.result)
      XCTAssertEqual(input.original, original)
      if depth == .u8 {
        let preview = try SkyReplacementInput.display(actual, in: result.edit.result)
        XCTAssertEqual(preview.width, 2048); XCTAssertEqual(preview.height, 2048)
      }
    }
  }

  func testMaximumManualRefinementDuplicateAndSelectionSources() throws {
    let size = Surface.maxDimension
    let original = try uniform(size, size), sky = try uniform(size, size, color: Pixel(0.9, 0.4, 0.2))
    let mask = try SelectionMask(coverage: Surface(width: size, height: size, depth: .u8, fill: .white))
    var settings = SkyReplacementSettings(); settings.fadeEdge = 0; settings.output = .duplicate
    // Isolate sky-mask coverage from the separately configurable foreground
    // adjustments, which correctly also affect manually restored foreground.
    settings.foregroundLighting = 0; settings.colorAdjustment = 0
    let result = try SkyReplacementInput.prepare(original).edit(sky: sky, name: "Owned sky", settings: settings,
      strokes: [.init(points: [.init(x: 129, y: 131)], size: 12, hardness: 1, add: false)], detected: mask)
    XCTAssertEqual(result.mask.coverage(x: 129, y: 131), 0)
    XCTAssertEqual(result.mask.coverage(x: size - 1, y: size - 1), 1)
    XCTAssertEqual(result.edit.result.layers.count, original.layers.count + 1)
    let composite = try Renderer.composite(result.edit.result)
    XCTAssertEqual(composite.pixel(x: 129, y: 131), try Renderer.composite(original).pixel(x: 129, y: 131))
    XCTAssertGreaterThan(composite.pixel(x: size - 1, y: size - 1).r, 0.8)
    for allLayers in [false, true] {
      var selected = original
      try SkyReplacementInput.selection(original, layerID: original.activeLayerID, allLayers: allLayers).apply(to: &selected)
      XCTAssertTrue(try XCTUnwrap(selected.coverageSelection()).isFullCoverage)
    }
    var changed = original; changed.name = "Changed"
    XCTAssertThrowsError(try result.edit.applied(to: changed))
    // The original small-image path confirms why the neutral setup above is
    // required: enabled foreground adjustments also color a brushed-out hole.
    let small = try uniform(32, 32), smallSky = try uniform(32, 32, color: Pixel(0.9, 0.4, 0.2))
    var active = SkyReplacementSettings(); active.fadeEdge = 0; active.output = .duplicate
    let restored = try SkyReplacementInput.prepare(small).edit(sky: smallSky, name: "Owned sky", settings: active,
      strokes: [.init(points: [.init(x: 13, y: 13)], size: 12, hardness: 1, add: false)])
    XCTAssertNotEqual(try Renderer.composite(restored.edit.result).pixel(x: 13, y: 13), try Renderer.composite(small).pixel(x: 13, y: 13))
  }

  func testSparseStatisticsUseEvenCoordinatesAndAnalyticImplicitCounts() throws {
    let size = Surface.maxDimension
    var old = try Surface(width: size, height: size, depth: .f32, fill: Pixel(0.25, 0.5, 0.75))
    var sky = try Surface(width: size, height: size, depth: .f32, fill: Pixel(0.5, 0.25, 0.125, 0.5))
    old.setPixel(x: 64, y: 64, Pixel(0.75, 0.5, 0.25))
    sky.setPixel(x: 65, y: 65, Pixel(1, 1, 1)) // Odd coordinates are outside the existing sample lattice.
    let mask = try SelectionMask(coverage: Surface(width: size, height: size, fill: .white))
    let result = try SkyRasterPreparation.statistics(original: old, replacement: sky, mask: mask)
    let count = Double(((size + 1) / 2) * ((size + 1) / 2))
    XCTAssertEqual(result.weight, count * 0.5)
    XCTAssertEqual(result.original, SIMD3(count * 0.125 + 0.25, count * 0.25, count * 0.375 - 0.25))
    XCTAssertEqual(result.replacement, SIMD3(count * 0.25, count * 0.125, count * 0.0625))
    XCTAssertThrowsError(try SkyRasterPreparation.statistics(original: old, replacement: Surface(width: 2, height: 2), mask: mask))
  }

  func testLargeColorConversionRetainsSparseDefaultsHiddenColorAndProfileWords() throws {
    let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData() as Data?)
    for depth in PixelDepth.allCases {
      let size = Surface.maxDimension
      var document = try uniform(size, size, depth: depth)
      document.workingICC = try ColorManagement.importedProfile(profile, depth: depth)
      var pixels = try Surface(width: size, height: size, depth: depth, fill: Pixel(0.25, 0.5, 0.75, 0),
        colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      pixels.setPixel(x: 65, y: 66, Pixel(0.75, 0.25, 0.5, 0.5))
      let copy = pixels, target = try CraftDocument(width: 1, height: 1)
      let result = try SkyRasterPreparation.converted(pixels, from: document, to: target)
      for (x, y) in [(0, 0), (65, 66), (size - 1, size - 1)] {
        let expected = try ColorManagement.converted(pixels.cropped(to: .init(x: x, y: y, width: 1, height: 1)), from: document, to: target)
        XCTAssertTrue(result.pixel(x: x, y: y).hasSameBits(as: expected.pixel(x: 0, y: 0)), "\(depth), \(x),\(y)")
      }
      XCTAssertLessThan(result.tileCount, 4); XCTAssertEqual(pixels, copy)
    }
  }

  func testActualNineMegapixelImageRetainsLocalRefinement() throws {
    // This is an actual larger-than-old-limit raster, with an allocated color
    // transition and local mask work; it is not only maximum-size metadata.
    let width = 3072, height = 3072
    var original = try uniform(width, height)
    guard case .raster(var pixels) = original.layers[0].content else { return XCTFail("Missing owned raster") }
    for y in 1500..<1510 { for x in 1530..<1540 { pixels.setPixel(x: x, y: y, Pixel(0.1, 0.2, 0.05)) } }
    original.layers[0].content = .raster(pixels)
    let sky = try uniform(width, height, color: Pixel(0.9, 0.4, 0.2))
    let selected = try SelectionMask.make(.rectangle(.init(x: 0, y: 0, width: width, height: 1490)), width: width, height: height, antiAlias: false)
    var settings = SkyReplacementSettings(); settings.shiftEdge = 5; settings.fadeEdge = 20
    let output = try SkyReplacementInput.prepare(original).edit(sky: sky, name: "Owned sky", settings: settings, detected: selected)
    XCTAssertGreaterThan(output.mask.coverage(x: 1535, y: 1400), 0.99)
    XCTAssertLessThan(output.mask.coverage(x: 1535, y: 1600), 0.01)
    XCTAssertEqual(output.edit.result.layers.count, 8)
  }

  func testCancelledPreparationLeavesOriginalAndSkyUntouched() async throws {
    let size = Surface.maxDimension, original = try uniform(size, size), sky = try uniform(size, size, color: Pixel(0.9, 0.4, 0.2))
    let copy = original
    let task = Task.detached { () throws -> SkyReplacementEdit in
      while !Task.isCancelled { await Task.yield() }
      return try SkyReplacementInput.prepare(original).edit(sky: sky, name: "Owned sky", settings: .init()).edit
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    XCTAssertEqual(original, copy)
  }
}
