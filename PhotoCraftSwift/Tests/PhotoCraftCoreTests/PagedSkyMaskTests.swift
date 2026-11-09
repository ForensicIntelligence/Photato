import XCTest
@testable import PhotoCraftCore

final class PagedSkyMaskTests: XCTestCase {
  private func fixture(_ width: Int = 333, _ height: Int = 139, inverted: Bool = false) throws -> SelectionMask {
    let bytes = (0..<width * height).map { i -> UInt8 in
      let x = i % width, y = i / width
      let value = (x * 173 + y * 71 + (x / 61) * 29) % 256
      return UInt8(inverted ? 255 - value : value)
    }
    return try SelectionMask(width: width, height: height, bytes: bytes)
  }

  func testPagedRefinementMatchesExistingDenseKernelsAtSeamsAndCanvasEdges() throws {
    let mask = try fixture()
    for (shift, fade) in [(-100.0, 0.0), (100, 0), (-25, 38), (40, 100), (0, 2), (0, 50)] {
      var settings = SkyReplacementSettings(); settings.shiftEdge = shift; settings.fadeEdge = fade
      let expected = try SkyReplacement.refined(mask, settings: settings, strokes: [])
      let actual = try PagedSkyMask.refined(mask, settings: settings, strokes: [])
      XCTAssertEqual(try actual.bytes, try expected.bytes, "shift=\(shift), fade=\(fade)")
    }
  }

  func testPagedBrushAndEdgeMatchExistingFractionalCoverage() throws {
    let mask = try fixture(inverted: true)
    var settings = SkyReplacementSettings(); settings.fadeEdge = 38; settings.shiftEdge = -20
    let strokes: [SkyMaskStroke] = [
      .init(points: [.init(x: 61, y: 62), .init(x: 133, y: 66)], size: 23, hardness: 0.37, opacity: 0.6, add: false),
      .init(points: [.init(x: 185, y: 126), .init(x: 333, y: 138)], size: 35, hardness: 0.5, opacity: 0.8)
    ]
    let expected = try SkyReplacement.refined(mask, settings: settings, strokes: strokes)
    let actual = try PagedSkyMask.refined(mask, settings: settings, strokes: strokes)
    XCTAssertEqual(try actual.bytes, try expected.bytes)
    XCTAssertEqual(try PagedSkyMask.edge(actual).bytes, try SkyReplacement.edgeMask(expected).bytes)
    XCTAssertEqual(try PagedSkyMask.edge(mask).bytes, try SkyReplacement.edgeMask(mask).bytes)
  }

  func testMaximumDimensionUniformAndLocalRefinementStaySparse() throws {
    let size = Surface.maxDimension
    let full = try SelectionMask(coverage: Surface(width: size, height: size, depth: .u8, fill: .white))
    var settings = SkyReplacementSettings(); settings.shiftEdge = 100; settings.fadeEdge = 100
    let unchanged = try PagedSkyMask.refined(full, settings: settings, strokes: [])
    XCTAssertTrue(try unchanged.isFullCoverage)
    XCTAssertEqual(try unchanged.coverageSurface().tileCount, 0)
    XCTAssertNil(try PagedSkyMask.edge(unchanged).bounds)
    let point = StrokePoint(x: Double(size - 70), y: Double(size - 70))
    let cut = try PagedSkyMask.refined(full, settings: settings,
      strokes: [.init(points: [point], size: 20, hardness: 1, add: false)])
    XCTAssertEqual(cut.coverage(x: size - 70, y: size - 70), 0)
    XCTAssertEqual(cut.coverage(x: 0, y: 0), 1)
    XCTAssertLessThan(try cut.coverageSurface().tileCount, 16)
    let repaired = try PagedSkyMask.refined(cut, settings: settings, strokes: [])
    XCTAssertGreaterThan(repaired.coverage(x: size - 70, y: size - 70), 0.99)
    XCTAssertLessThan(repaired.allocatedBytes, 2 * 1024 * 1024)
    XCTAssertLessThan(try PagedSkyMask.edge(cut).coverageSurface().tileCount, 25)
  }

  func testSparseIslandsAndHolesRetainFullResolutionAndUntouchedInput() throws {
    let size = Surface.maxDimension
    for background in [Float(0), 1] {
      var surface = try Surface(width: size, height: size, depth: .u8, fill: Pixel(background, background, background))
      for y in 125..<132 { for x in 127..<136 { let v: Float = background == 0 ? 1 : 0; surface.setPixel(x: x, y: y, Pixel(v, v, v)) } }
      let mask = try SelectionMask(coverage: surface), copy = mask
      var settings = SkyReplacementSettings(); settings.fadeEdge = 50; settings.shiftEdge = 0
      let output = try PagedSkyMask.refined(mask, settings: settings, strokes: [])
      XCTAssertEqual(mask, copy)
      XCTAssertEqual(output.width, size); XCTAssertEqual(output.height, size)
      XCTAssertEqual(output.coverage(x: size - 1, y: size - 1), background)
      let center = output.coverage(x: 130, y: 128)
      XCTAssertGreaterThan(center, 0); XCTAssertLessThan(center, 1)
      XCTAssertLessThan(try output.coverageSurface().tileCount, 25)
    }
  }

  func testCancellationAndInvalidStrokesLeaveSourceUnchanged() async throws {
    let mask = try fixture(), copy = mask
    var settings = SkyReplacementSettings(); settings.fadeEdge = .nan
    XCTAssertThrowsError(try PagedSkyMask.refined(mask, settings: settings, strokes: []))
    let invalid = SkyMaskStroke(points: [], size: 20)
    XCTAssertThrowsError(try PagedSkyMask.refined(mask, settings: .init(), strokes: [invalid]))
    XCTAssertThrowsError(try PagedSkyMask.refined(mask, settings: .init(), strokes: Array(repeating: invalid, count: 129)))
    let task = Task.detached { () throws -> SelectionMask in
      while !Task.isCancelled { await Task.yield() }
      return try PagedSkyMask.refined(mask, settings: .init(), strokes: [])
    }
    task.cancel()
    do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("Unexpected: \(error)") }
    XCTAssertEqual(mask, copy)
  }
}
