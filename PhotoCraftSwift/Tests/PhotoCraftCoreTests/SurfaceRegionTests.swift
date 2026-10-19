import PhotoCraftCore
import XCTest

final class SurfaceRegionTests: XCTestCase {
  func testTileDifferenceSharedCopiesSparseDefaultsAndSignedZero() throws {
    let original = try Surface(width: 130, height: 129, depth: .f32)
    var copy = original
    XCTAssertNil(try copy.changedTileBounds(comparedTo: original))
    copy.setPixel(x: 129, y: 128, .clear)
    XCTAssertNil(try copy.changedTileBounds(comparedTo: original))
    copy.setPixel(x: 129, y: 128, Pixel(-0.0, 0, 0, 0))
    XCTAssertEqual(
      try copy.changedTileBounds(comparedTo: original),
      IntRect(x: 128, y: 128, width: 2, height: 1))
    let shared = copy
    XCTAssertNil(try copy.changedTileBounds(comparedTo: shared))
    copy.setPixel(x: 63, y: 64, .white)
    XCTAssertEqual(
      try copy.changedTileBounds(comparedTo: shared),
      IntRect(x: 0, y: 64, width: 64, height: 64))
    let archive = try PropertyListEncoder().encode(shared)
    let decoded = try PropertyListDecoder().decode(Surface.self, from: archive)
    XCTAssertNil(try decoded.changedTileBounds(comparedTo: shared))
    let filled = try Surface(width: 130, height: 129, depth: .f32, fill: .white)
    XCTAssertEqual(
      try filled.changedTileBounds(comparedTo: original),
      IntRect(x: 0, y: 0, width: 130, height: 129))
  }

  func testRegionMappingClipsExtremeBoundsAndPreservesOutsideBits() throws {
    var surface = try Surface(width: 130, height: 130, depth: .f32, fill: Pixel(-0.0, 2, -1))
    try surface.mapPixels(in: IntRect(x: 63, y: 63, width: 2, height: 2)) { _, _, _ in .clear }
    XCTAssertEqual(surface.tileCount, 4)
    XCTAssertEqual(surface.pixel(x: 63, y: 63), .clear)
    XCTAssertEqual(surface.pixel(x: 62, y: 63).r.bitPattern, Float(-0.0).bitPattern)
    try surface.mapPixels(in: IntRect(x: Int.max - 1, y: 0, width: 100, height: 100)) {
      _, _, _ in
      XCTFail("Off-canvas map must be empty")
      return .white
    }
    try surface.mapPixels(in: IntRect(x: Int.min, y: Int.min, width: Int.max, height: Int.max)) {
      _, _, _ in
      XCTFail("Off-canvas map must be empty")
      return .white
    }
    try surface.mapPixels(in: IntRect(x: -2, y: -2, width: 3, height: 3)) { _, _, _ in .black }
    XCTAssertEqual(surface.pixel(x: 0, y: 0), .black)
    XCTAssertEqual(surface.pixel(x: 1, y: 0).b, -1)
  }

  func testCancelledMappingIsAtomic() async throws {
    let task = Task.detached {
      var surface = try Surface(width: 64, height: 64)
      let before = surface
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        try surface.mapPixels(in: IntRect(x: 0, y: 0, width: 64, height: 64)) { _, _, _ in .white }
        XCTFail("Cancelled map must throw")
      } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
      XCTAssertEqual(surface, before)
    }
    try await task.value
  }
}
