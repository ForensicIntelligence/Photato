import Foundation
import PhotoCraftCore
import XCTest

final class SurfaceExpansionTests: XCTestCase {
  func testExpansionAcrossTileBoundariesPreservesPixelsAndHidesOldPadding() throws {
    for depth in PixelDepth.allCases {
      for outside in [Pixel.clear, Pixel(0.25, 0.25, 0.25)] {
        var source = try Surface(width: 67, height: 65, depth: depth, fill: Pixel(0.5, 0.3, 0.2))
        source.setPixel(x: 64, y: 64, Pixel(0.8, 0.9, 0.1, 0))
        source.setPixel(x: 2, y: 3, .black)
        for shift in [0, 3, 64] {
          let rect = IntRect(x: -shift, y: -shift, width: 80 + shift, height: 77 + shift)
          var result = try source.expanded(to: rect, fill: outside)
          for y in 0..<result.height {
            for x in 0..<result.width {
              let sx = x - shift
              let sy = y - shift
              let expected =
                sx >= 0 && sy >= 0 && sx < source.width && sy < source.height
                ? source.pixel(x: sx, y: sy) : outside.quantized(depth)
              XCTAssertTrue(result.pixel(x: x, y: y).hasSameBits(as: expected))
            }
          }
          result.setPixel(x: 2 + shift, y: 3 + shift, .white)
          XCTAssertEqual(source.pixel(x: 2, y: 3), .black)
        }
      }
    }
    let largeSparse = try Surface(width: 6000, height: 4000)
    let expanded = try largeSparse.expanded(
      to: .init(x: -64, y: -64, width: 6064, height: 4064), fill: .clear)
    XCTAssertEqual(expanded.tileCount, 0)
  }

  func testDecodedSamplesRemainBitExactAndMalformedBoundsReject() throws {
    var source = try Surface(width: 3, height: 2, depth: .f32, fill: Pixel(-0.0, 0.37, -0.25))
    source.setPixel(x: 2, y: 1, Pixel(1.3, -0.4, -0.0, 0))
    var plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: PropertyListEncoder().encode(source), format: nil) as? [String: Any])
    plist["depth"] = PixelDepth.u8.rawValue
    let decoded = try PropertyListDecoder().decode(
      Surface.self,
      from: PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0))
    let moved = try decoded.expanded(to: .init(x: -1, y: -2, width: 6, height: 6), fill: .clear)
    for y in 0..<2 {
      for x in 0..<3 {
        XCTAssertTrue(moved.pixel(x: x + 1, y: y + 2).hasSameBits(as: decoded.pixel(x: x, y: y)))
      }
    }
    for bounds in [
      IntRect(x: 1, y: 0, width: 2, height: 2),
      IntRect(x: Int.min, y: 0, width: Int.max, height: 2),
      IntRect(x: -1, y: -1, width: Int.max, height: Int.max),
      IntRect(x: 0, y: 0, width: 300001, height: 300000),
    ] {
      XCTAssertThrowsError(try decoded.expanded(to: bounds, fill: .clear))
    }
  }
}
