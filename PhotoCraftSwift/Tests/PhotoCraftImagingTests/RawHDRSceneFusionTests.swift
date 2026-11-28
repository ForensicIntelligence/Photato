import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class RawHDRSceneFusionTests: XCTestCase {
  func testSceneFusionRecoversLinearColorAndHighlightsFromExposureRatios() throws {
    let size = SIMD2(64, 32)
    let factors = [2.0, 0.5, 1.0]
    func radiance(x: Int, y: Int) -> SIMD3<Float> {
      SIMD3(x < 32 ? 0.05 : 1.3, x < 16 ? 0.015625 : 0.375, y < 16 ? 0 : 0.625)
    }
    let inputs = try factors.map { exposure in
      try bracket(size: size, exposure: exposure, radiance: radiance)
    }
    var settings = RawHDRMergeSettings()
    settings.align = false
    let result = try RawHDRSceneFusion.merge(inputs, options: settings)
    XCTAssertEqual(result.exposureEV, [2, 0, 1])
    XCTAssertEqual(result.offsets, [.zero, .zero, .zero])
    XCTAssertNil(result.ghostMask)
    for y in 0..<size.y {
      for x in 0..<size.x {
        let pixel = result.pixels.linearPixel(x: x, y: y), expected = radiance(x: x, y: y)
        XCTAssertEqual(pixel.r, expected.x, accuracy: 0.000002)
        XCTAssertEqual(pixel.g, expected.y, accuracy: 0.000002)
        XCTAssertEqual(pixel.b, expected.z, accuracy: 0.000002)
        XCTAssertEqual(pixel.a, 1)
      }
    }
  }

  func testSceneAlignmentCorrectsShiftAndRetainsTheReferenceGeometry() throws {
    let size = SIMD2(128, 96)
    func radiance(x: Int, y: Int) -> SIMD3<Float> {
      let phaseX = Float(x) * 0.21, phaseY = Float(y) * 0.17
      let value = 0.23 + 0.12 * sin(phaseX) * cos(phaseY) + 0.0008 * Float(x)
      return SIMD3(repeating: value)
    }
    let short = try bracket(size: size, exposure: 0.5, translation: SIMD2(5, -3), radiance: radiance)
    let middle = try bracket(size: size, exposure: 1, radiance: radiance)
    let long = try bracket(size: size, exposure: 2, radiance: radiance)
    let result = try RawHDRSceneFusion.merge([short, middle, long], options: .init())
    XCTAssertEqual(result.offsets, [SIMD2(-5, 3), .zero, .zero])
    XCTAssertEqual(result.pixels.width, size.x)
    XCTAssertEqual(result.pixels.height, size.y)
    var worst: Float = 0
    for y in 4..<(size.y - 4) {
      for x in 6..<(size.x - 6) {
        let expected = radiance(x: x, y: y)
        let actual = result.pixels.linearPixel(x: x, y: y)
        worst = max(worst, abs(expected.x - actual.r))
      }
    }
    XCTAssertLessThan(worst, 0.000002)
    XCTAssertEqual(result.pixels.linearPixel(x: size.x - 1, y: 0).a, 1)
  }

  func testSceneDeghostLevelsPreserveTheAnchorAndExposeTheActualMask() throws {
    let size = SIMD2(64, 64)
    let short = try bracket(size: size, exposure: 0.5) { x, y in
      SIMD3(repeating: (20..<44).contains(x) && (20..<44).contains(y) ? 0.46 : 0.29)
    }
    let middle = try bracket(size: size, exposure: 1) { _, _ in SIMD3(repeating: 0.29) }
    let long = try bracket(size: size, exposure: 2) { _, _ in SIMD3(repeating: 0.29) }
    var settings = RawHDRMergeSettings()
    settings.align = false
    let off = try RawHDRSceneFusion.merge([short, middle, long], options: settings)
    settings.deghost = .low
    let low = try RawHDRSceneFusion.merge([short, middle, long], options: settings)
    settings.deghost = .high
    let high = try RawHDRSceneFusion.merge([short, middle, long], options: settings)
    XCTAssertGreaterThan(off.pixels.linearPixel(x: 30, y: 30).r, 0.33)
    XCTAssertEqual(low.pixels.linearPixel(x: 30, y: 30).r, off.pixels.linearPixel(x: 30, y: 30).r)
    XCTAssertEqual(high.pixels.linearPixel(x: 30, y: 30).r, 0.29, accuracy: 0.000002)
    XCTAssertEqual(high.pixels.linearPixel(x: 1, y: 1).r, off.pixels.linearPixel(x: 1, y: 1).r)
    XCTAssertEqual(try XCTUnwrap(low.ghostMask)[30 * size.x + 30], 0)
    XCTAssertEqual(try XCTUnwrap(high.ghostMask)[30 * size.x + 30], 1)
    XCTAssertEqual(try XCTUnwrap(high.ghostMask)[0], 0)
  }

  func testAutomaticToneRecoversDarkMidtonesAndProtectsTheBrightShoulder() throws {
    var dark = try Surface(width: 128, height: 64, depth: .f32, colorEncoding: .linearRGB)
    var bright = dark
    for y in 0..<dark.height {
      let gradient = Float(y) / Float(dark.height)
      for x in 0..<dark.width {
        let level: Float = x < 5 ? 1.021 + 0.3 * gradient : 0.022 + 0.055 * gradient
        dark.setLinearPixel(x: x, y: y, Pixel(level * 1.04, level, level * 0.9, 1))
        let high = 0.42 + 0.53 * gradient
        bright.setLinearPixel(x: x, y: y, Pixel(high, high, high, 1))
      }
    }
    let lowKey = try RawHDRMerge.automaticTone(dark)
    let highKey = try RawHDRMerge.automaticTone(bright)
    XCTAssertGreaterThan(lowKey.exposure, 0.2)
    XCTAssertLessThan(lowKey.exposure, 1.0)
    XCTAssertLessThan(highKey.exposure, -0.5)
    XCTAssertLessThan(lowKey.highlights, -30)
    XCTAssertLessThan(highKey.highlights, -30)
    XCTAssertGreaterThan(lowKey.shadows, 20)
    XCTAssertLessThan(lowKey.blacks, -10)
    XCTAssertGreaterThan(lowKey.vibrance, 0)
    XCTAssertEqual(highKey.vibrance, 0)
    XCTAssertEqual(highKey.saturation, 0)
    try lowKey.validate()
    try highKey.validate()
  }

  func testAutomaticToneProtectsASubstantialBrightRegionBesideShadows() throws {
    let width = 160, height = 64
    var pixels = try Surface(width: width, height: height, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<height {
      for x in 0..<width {
        let base: Float = x < 36 ? 0.96 : 0.22
        let light = base + 0.06 * Float(y) / Float(height)
        pixels.setLinearPixel(x: x, y: y, Pixel(light * 1.04, light, light * 0.91, 1))
      }
    }
    let settings = try RawHDRMerge.automaticTone(pixels)
    XCTAssertLessThan(settings.exposure, -0.3)
    XCTAssertGreaterThan(settings.shadows, 0)
    XCTAssertGreaterThan(settings.whites, 10)
  }

  func testAutomaticToneIgnoresSparseHotPixelsAndLeavesBlackUnchanged() throws {
    var strip = try Surface(width: 9_000, height: 1, depth: .f32, fill: Pixel(0, 0, 0, 1),
      colorEncoding: .linearRGB)
    XCTAssertTrue(try RawHDRMerge.automaticTone(strip).isIdentity)
    for x in 0..<strip.width {
      strip.setLinearPixel(x: x, y: 0, Pixel(0.12, 0.1, 0.08, 1))
    }
    let ordinary = try RawHDRMerge.automaticTone(strip)
    strip.setLinearPixel(x: 4_500, y: 0, Pixel(60, 60, 60, 1))
    XCTAssertEqual(try RawHDRMerge.automaticTone(strip), ordinary)
  }

  func testHDRPanoramaGroupingRequiresCompleteContiguousMatchingOffsetPatterns() throws {
    let first = [1.0, 0.5, 2.0], second = [1.2, 0.6, 2.4], third = [0.75, 0.375, 1.5]
    XCTAssertEqual(try RawPanorama.bracketRanges(exposureFactors: first + second + third), [0..<3, 3..<6, 6..<9])
    XCTAssertEqual(try RawPanorama.bracketRanges(exposureFactors: [1, 2, 0.8, 1.6]), [0..<2, 2..<4])
    XCTAssertThrowsError(try RawPanorama.bracketRanges(exposureFactors: first + second, bracketSize: 2))
    XCTAssertThrowsError(try RawPanorama.bracketRanges(exposureFactors: first + [1.2, 2.4, 0.6]))
    XCTAssertThrowsError(try RawPanorama.bracketRanges(exposureFactors: [1, 1, 2, 2]))
    XCTAssertThrowsError(try RawPanorama.bracketRanges(exposureFactors: first + [1.2, 0.6, 1.8]))
    XCTAssertThrowsError(try RawPanorama.bracketRanges(exposureFactors: first + [1.2, .nan, 2.4]))
    XCTAssertThrowsError(try RawPanorama.bracketRanges(exposureFactors: first + second + [0.8]))
  }

  func testHDRPanoramaReferenceGainKeepsHighlightsAndBracketsOnOneScale() throws {
    let size = SIMD2(64, 32)
    func radiance(x: Int, y: Int) -> SIMD3<Float> {
      x < 32 ? SIMD3(0.10, 0.21, 0.30) : SIMD3(1.2, 0.65, 0.36)
    }
    var options = RawHDRMergeSettings()
    options.align = false
    let groups = try [1.0, 1.2, 0.75].map { base in
      let set = try [0.5, 1.0, 2.0].map { try bracket(size: size, exposure: base * $0, radiance: radiance) }
      return try RawHDRSceneFusion.merge(set, options: options, referenceExposure: 1).pixels
    }
    for result in groups {
      let shadow = result.linearPixel(x: 16, y: 12), bright = result.linearPixel(x: 45, y: 12)
      XCTAssertEqual(shadow.r, 0.10, accuracy: 0.000_002)
      XCTAssertEqual(shadow.g, 0.21, accuracy: 0.000_002)
      XCTAssertEqual(bright.r, 1.2, accuracy: 0.000_002)
      XCTAssertEqual(bright.g, 0.65, accuracy: 0.000_002)
    }
  }

  private func bracket(size: SIMD2<Int>, exposure: Double, translation: SIMD2<Int> = .zero,
    radiance: (Int, Int) -> SIMD3<Float>) throws -> RawHDRSceneFusion.Bracket {
    var surface = try Surface(width: size.x, height: size.y, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<size.y {
      for x in 0..<size.x {
        let sx = max(0, min(size.x - 1, x - translation.x))
        let sy = max(0, min(size.y - 1, y - translation.y))
        let rgb = radiance(sx, sy) * Float(exposure)
        surface.setLinearPixel(x: x, y: y, Pixel(min(1, rgb.x), min(1, rgb.y), min(1, rgb.z), 1))
      }
    }
    return .init(pixels: surface, exposure: exposure)
  }
}
