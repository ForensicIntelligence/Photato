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
