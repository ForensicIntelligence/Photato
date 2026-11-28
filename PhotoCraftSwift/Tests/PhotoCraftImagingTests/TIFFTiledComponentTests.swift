import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFTiledComponentTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/tiff-tiled-components")

  func testRectangularCMYKTilesKeepEverySeparationWord() throws {
    let file = fixtures.appendingPathComponent("planar-cmyk16-lzw-tiled.tiff")
    let document = try RasterIO.read(file)
    let resource = try XCTUnwrap(RasterIO.readPagedComponentTIFF(Data(contentsOf: file), name: "Ink test"))
    for restored in [document, resource] {
      XCTAssertEqual(restored.width, 259)
      XCTAssertEqual(restored.height, 137)
      XCTAssertEqual(restored.resolution, 225)
      let raster = try XCTUnwrap(restored.layers.first?.nativeMode)
      XCTAssertEqual(raster.mode, .cmyk)
      XCTAssertEqual(raster.depth, .u16)
      for c in 0..<4 {
        var expected: [UInt32] = []
        for y in 0..<137 { for x in 0..<259 {
          expected.append(UInt32(UInt16(truncatingIfNeeded: x * (37 + c * 18) + y * (109 + c * 12) + c * 13013)))
        } }
        XCTAssertEqual((0..<259 * 137).map { raster.rawWord(component: c, index: $0) }, expected)
      }
    }
  }

  func testTiledGray16WithOpacityKeepsNativeWords() throws {
    let file = fixtures.appendingPathComponent("gray16-planar-deflate-le.tiff")
    let document = try RasterIO.read(Data(contentsOf: file))
    XCTAssertEqual(document.width, 65)
    XCTAssertEqual(document.height, 73)
    let raster = try XCTUnwrap(document.layers.first?.nativeMode)
    XCTAssertEqual(raster.mode, .grayscale)
    XCTAssertEqual(raster.depth, .u16)
    for c in 0..<2 {
      var expected: [UInt32] = []
      for y in 0..<73 { for x in 0..<65 {
        expected.append(UInt32(UInt16(truncatingIfNeeded: x * 37 + y * 109 + c * 13013)))
      } }
      XCTAssertEqual((0..<65 * 73).map { raster.rawWord(component: c, index: $0) }, expected)
    }
  }

  func testRGBTilesKeepStraightOpacityAndFloatingSamples() throws {
    for (name, depth) in [("rgb8-contig-raw-be.tiff", PixelDepth.u8), ("rgb32-planar-deflate-be.tiff", .f32)] {
      let document = try RasterIO.read(fixtures.appendingPathComponent(name))
      XCTAssertEqual(document.width, 65)
      XCTAssertEqual(document.height, 73)
      XCTAssertEqual(document.depth, depth)
      guard case .raster(let raster) = document.layers.first?.content else {
        return XCTFail("Expected editable RGB pixels.")
      }
      var expected: [Pixel] = [], actual: [Pixel] = []
      for y in 0..<73 { for x in 0..<65 {
        let values: [Float] = (0..<4).map { c in
          if depth == .f32 {
            if c == 3 { return Float((x * 11 + y * 7) % 32) / 32 }
            return Float((x * 3 + y * 7 + c * 13) % 512) / 256 - 0.5
          }
          return Float(UInt8(truncatingIfNeeded: x * 37 + y * 109 + c * 13013)) / 255
        }
        expected.append(Pixel(values[0], values[1], values[2], values[3]))
        actual.append(depth == .f32 ? raster.linearPixel(x: x, y: y) : raster.pixel(x: x, y: y))
      } }
      XCTAssertEqual(actual, expected, name)
    }
  }
}
