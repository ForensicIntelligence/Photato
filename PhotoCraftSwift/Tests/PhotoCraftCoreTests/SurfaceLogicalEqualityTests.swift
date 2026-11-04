import Foundation
import XCTest
@testable import PhotoCraftCore

final class SurfaceLogicalEqualityTests: XCTestCase {
  func testImplicitAndExplicitPixelsCompareSymmetricallyAcrossDepths() throws {
    for depth in PixelDepth.allCases {
      let a = try Surface(width: 67, height: 3, depth: depth, fill: Pixel(0.25, 0.5, 0.75, 0))
      var b = try Surface(width: 67, height: 3, depth: depth)
      for y in 0..<3 { for x in 0..<67 { b.setPixel(x: x, y: y, a.pixel(x: x, y: y)) } }
      XCTAssertEqual(a, b); XCTAssertEqual(b, a)
      let c = try b.cropped(to: .init(x: 0, y: 0, width: 67, height: 3))
      XCTAssertEqual(b, c); XCTAssertEqual(a, c)
      b.setPixel(x: 66, y: 2, .white); XCTAssertNotEqual(a, b)
    }
  }
  func testFloatEqualityKeepsSignedZeroHiddenColorAndEncoding() throws {
    let positive = try Surface(width: 1, height: 1, depth: .f32, fill: Pixel(0, 0.5, 0.75, 0))
    let negative = try Surface(width: 1, height: 1, depth: .f32, fill: Pixel(-0.0, 0.5, 0.75, 0))
    var explicit = try Surface(width: 1, height: 1, depth: .f32)
    explicit.setPixel(x: 0, y: 0, negative.pixel(x: 0, y: 0))
    XCTAssertNotEqual(positive, negative); XCTAssertNotEqual(positive, explicit); XCTAssertEqual(negative, explicit)
    XCTAssertNotEqual(negative, try negative.interpretingSamples(as: .linearRGB))
    XCTAssertNotEqual(positive, try Surface(width: 1, height: 1, depth: .f32, fill: Pixel(0, 0.5, 0.8, 0)))
  }
  func testMaximumSparsePlanesDoNotEnumerateImplicitCanvas() throws {
    let a = try Surface(width: 300000, height: 300000, depth: .u16, fill: .white)
    var b = a; b.setPixel(x: 299999, y: 299999, .white)
    XCTAssertEqual(a, b); XCTAssertEqual(b, a)
    var c = b; c.setPixel(x: 299999, y: 299999, .black)
    XCTAssertNotEqual(a, c); XCTAssertEqual(a.pixel(x: 299999, y: 299999), .white)
    XCTAssertNotEqual(a, try Surface(width: 300000, height: 300000, depth: .u16))
  }
  func testMappedAndOwnedSnapshotsIgnoreBackingAndRetainEdits() throws {
    var a = try Surface(width: 129, height: 65, depth: .f32, fill: Pixel(0.25, 0.5, 0.75))
    a.setPixel(x: 128, y: 64, Pixel(2, -1, 0.5))
    let mapped = try a.spillingTiles(to: RasterTileStore())
    XCTAssertEqual(a, mapped); XCTAssertEqual(mapped, a)
    var edited = mapped; edited.setPixel(x: 128, y: 64, Pixel(3, -1, 0.5))
    XCTAssertNotEqual(mapped, edited); XCTAssertEqual(a, mapped)
  }
  func testPartialCoverageAndEdgePaddingDoNotHideDefaultDifferences() throws {
    let a = try Surface(width: 65, height: 1, depth: .u8, fill: .white)
    var b = try Surface(width: 65, height: 1, depth: .u8)
    for x in 0..<64 { b.setPixel(x: x, y: 0, .white) }
    XCTAssertNotEqual(a, b)
    b.setPixel(x: 64, y: 0, .white); XCTAssertEqual(a, b)
    XCTAssertNotEqual(a, try Surface(width: 64, height: 1, depth: .u8, fill: .white))
  }
  func testNativeCacheLayoutRoundTripKeepsDocumentIdentityAndStaleGuard() throws {
    let source = try DocumentCreation.blank(width: 7, height: 3, depth: .u16, background: Pixel(0.2, 0.4, 0.8), mode: .cmyk)
    let copy = try NativeArchive.decode(NativeArchive.encode(source))
    XCTAssertEqual(source, copy)
    var changed = copy; changed.name = "Changed"
    let request = DocumentModeEdit(source: source, result: source)
    XCTAssertThrowsError(try request.applied(to: changed))
    XCTAssertEqual(try request.applied(to: copy), source)
  }
}
