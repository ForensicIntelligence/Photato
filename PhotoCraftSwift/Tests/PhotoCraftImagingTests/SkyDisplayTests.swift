import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class SkyDisplayTests: XCTestCase {
  func fixture(_ depth: PixelDepth, profile: Bool) throws -> (CraftDocument, Surface) {
    var document = try CraftDocument(width: 3001, height: 7, depth: depth)
    document.workingICC = profile ? CGColorSpace(name: depth == .f32 ? CGColorSpace.linearDisplayP3 : CGColorSpace.displayP3)!.copyICCData() as Data? : nil
    var source = try Surface(width: document.width, height: document.height, depth: depth, fill: Pixel(0.2, 0.6, 0.8, 0.75))
    for x in 2039..<2065 { for y in 0..<7 {
      source.setPixel(x: x, y: y, Pixel(Float(x % 5) / 4, Float(y) / 6, 0.4, x.isMultiple(of: 3) ? 0 : 1))
    } }
    document.layers[0].content = .raster(source)
    return (document, source)
  }
  func bytes(_ image: CGImage) throws -> Data { try XCTUnwrap(image.dataProvider?.data) as Data }

  func testLegacyPreviewBeyond2048RetainsAllExistingDisplayBytes() throws {
    for depth in PixelDepth.allCases { for profile in [false, true] {
      let (document, source) = try fixture(depth, profile: profile), original = source
      if depth == .f32 && profile {
        var unsupported = document; unsupported.workingICC = NSColorSpace.displayP3.iccProfileData
        XCTAssertThrowsError(try SkyReplacementInput.display(source, in: unsupported))
      }
      let actual = try SkyReplacementInput.display(source, in: document)
      let expected = try ColorManagement.displayImage(source, in: document)
      XCTAssertEqual(actual.width, 3001); XCTAssertEqual(actual.height, 7)
      XCTAssertEqual(try bytes(actual), try bytes(expected))
      XCTAssertEqual(source, original)
    } }
  }

  func testVisibleTileUsesFullResolutionProfileAndAlphaBytesAndRejectsInvalidRegion() async throws {
    for depth in PixelDepth.allCases { for profile in [false, true] {
      let (document, source) = try fixture(depth, profile: profile), original = source
      let request = try RasterPreviewRequest(region: .init(x: 2041, y: 1, width: 24, height: 5), width: 24, height: 5)
      let actual = try SkyReplacementInput.display(source, in: document, request: request)
      let expected = try ColorManagement.displayImage(source.cropped(to: request.region), in: document)
      XCTAssertEqual(actual.width, 24); XCTAssertEqual(actual.height, 5)
      XCTAssertEqual(try bytes(actual), try bytes(expected))
      let outside = try RasterPreviewRequest(region: .init(x: 3000, y: 0, width: 2, height: 1), width: 2, height: 1)
      XCTAssertThrowsError(try SkyReplacementInput.display(source, in: document, request: outside))
      let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try SkyReplacementInput.display(source, in: document, request: request) }
      do { _ = try await cancelled.value; XCTFail("Cancelled tile must not publish an image") } catch is CancellationError {} catch { XCTFail("Unexpected cancellation error: \(error)") }
      XCTAssertEqual(source, original)
    } }
  }
}
