import XCTest
@testable import PhotoCraftCore

final class PagedSkySelectionTests: XCTestCase {
  func testPagedBoxRetainsExactDenseFloatWordsAcrossPatchBoundaries() throws {
    let width = 333, height = 139
    var source = try Surface(width: width, height: height, depth: .f32, fill: Pixel(0.25, 0.25, 0.25))
    for y in 59..<133 { for x in 57..<329 {
      let v = Float((x * 173 + y * 71) % 256) / 255
      source.setPixel(x: x, y: y, Pixel(v, v, v))
    } }
    let values = (0..<width * height).map { source.pixel(x: $0 % width, y: $0 / width).r }
    for radius in [1, 7, 31, 180] {
      let expected = try MattingFilters.box(values, width, height, radius)
      let output = try PagedSkySelection.box(source, radius: radius)
      let actual = (0..<width * height).map { output.pixel(x: $0 % width, y: $0 / width).r.bitPattern }
      XCTAssertEqual(actual, expected.map(\.bitPattern), "radius=\(radius)")
    }
  }

  func testPagedGuidanceRetainsQuantizedDenseResults() throws {
    let width = 149, height = 83
    var guide = try Surface(width: width, height: height, depth: .f32)
    var input = guide
    for y in 0..<height { for x in 0..<width {
      let g = Float((x * 173 + y * 71) % 256) / 255
      let v: Float = y < 31 + x / 13 ? 1 : 0
      guide.setPixel(x: x, y: y, Pixel(g, g, g)); input.setPixel(x: x, y: y, Pixel(v, v, v))
    } }
    let original = guide
    let gs = (0..<width * height).map { guide.pixel(x: $0 % width, y: $0 / width).r }
    let vs = (0..<width * height).map { input.pixel(x: $0 % width, y: $0 / width).r }
    for radius in [3, 9] {
      let expected = try SkySelection.guided(gs, vs, width, height, radius, 0.0021)
      let actual = try PagedSkySelection.guided(guide: guide, input: input, radius: radius, epsilon: 0.0021)
      func byte(_ value: Float) -> UInt8 { UInt8((SkySelection.smooth(0.21, 0.79, value) * 255).rounded()) }
      XCTAssertEqual((0..<width * height).map { byte(actual.pixel(x: $0 % width, y: $0 / width).r) }, expected.map(byte))
    }
    XCTAssertEqual(guide, original)
  }

  func testMaximumDimensionAutomaticSkyAndNoSkyUseBoundedAnalysis() throws {
    for depth in PixelDepth.allCases {
      let size = Surface.maxDimension
      let source = try Surface(width: size, height: size, depth: depth, fill: Pixel(0.3, 0.6, 0.95))
      let copy = source
      let mask = try XCTUnwrap(PagedSkySelection.mask(source, settings: .init(), workingPixels: 4000))
      XCTAssertTrue(try mask.isFullCoverage); XCTAssertEqual(try mask.coverageSurface().tileCount, 0)
      XCTAssertEqual(mask.width, size); XCTAssertEqual(mask.height, size); XCTAssertEqual(source, copy)
      let ground = try Surface(width: size, height: size, depth: depth, fill: Pixel(0.1, 0.2, 0.05))
      XCTAssertNil(try PagedSkySelection.mask(ground, settings: .init(), workingPixels: 4000))
    }
  }

  func testAutomaticDetectionKeepsOriginalGridAndTreeBoundary() throws {
    let source = try SkySelectionTests().landscape(333, 211)
    let copy = source
    let mask = try XCTUnwrap(PagedSkySelection.mask(source, settings: .init(), workingPixels: 4000))
    XCTAssertEqual(mask.width, source.width); XCTAssertEqual(mask.height, source.height)
    XCTAssertGreaterThan(mask.coverage(x: 10, y: 10), 0.99)
    XCTAssertLessThan(mask.coverage(x: 10, y: 190), 0.01)
    XCTAssertLessThan(mask.coverage(x: 233, y: 74), 0.1)
    XCTAssertTrue(try mask.bytes.contains { $0 > 0 && $0 < 255 })
    XCTAssertEqual(source, copy)
  }

  func testCancelledLargeAnalysisAndInvalidWorkingResolution() async throws {
    let source = try Surface(width: Surface.maxDimension, height: Surface.maxDimension, fill: Pixel(0.3, 0.6, 0.95))
    XCTAssertThrowsError(try PagedSkySelection.mask(source, settings: .init(), workingPixels: 15))
    XCTAssertThrowsError(try PagedSkySelection.box(source, radius: -1))
    let task = Task.detached { () throws -> SelectionMask? in
      while !Task.isCancelled { await Task.yield() }
      return try PagedSkySelection.mask(source, settings: .init(), workingPixels: 160_000)
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
  }

  func testActualTwentyMegapixelAutomaticSelectionKeepsGroundAndFullGrid() throws {
    let width = 5000, height = 4000
    var source = try Surface(width: width, height: height, fill: Pixel(0.3, 0.6, 0.95))
    for y in 3900..<height { for x in 0..<width { source.setPixel(x: x, y: y, Pixel(0.1, 0.2, 0.05)) } }
    let copy = source
    let mask = try XCTUnwrap(SkySelection.mask(source, workingPixels: 4000))
    XCTAssertEqual(mask.width, width); XCTAssertEqual(mask.height, height)
    XCTAssertGreaterThan(mask.coverage(x: 2499, y: 1000), 0.99)
    XCTAssertLessThan(mask.coverage(x: 2499, y: 3999), 0.1)
    XCTAssertEqual(source, copy)
  }
}
