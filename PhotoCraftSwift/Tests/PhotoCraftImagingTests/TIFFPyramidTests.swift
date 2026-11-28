import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFPyramidTests: XCTestCase {
  func testTwoPixelImageRetainsThreeOnePixelPreviewLevels() throws {
    var source = try Surface(width: 2, height: 1, depth: .u8, fill: .black)
    source.setPixel(x: 0, y: 0, Pixel(20.0 / 255, 81.0 / 255, 144.0 / 255))
    source.setPixel(x: 1, y: 0, Pixel(41.0 / 255, 120.0 / 255, 41.0 / 255))
    let options = RasterEncodingOptions(tiffCompression: RasterEncodingOptions.TIFFCompression.none,
      tiffByteOrder: .bigEndian, tiffTransparency: false, tiffImagePyramid: true, tiffEmbedProfile: false)
    let data = try RasterIO.encoded(source, type: .tiff, options: options)
    let file = try TIFFContainer(data, metadata: true)
    let first = try XCTUnwrap(file.root.fields[330]?.children.first)
    let mid = try XCTUnwrap(first.next)
    let last = try XCTUnwrap(mid.next)
    XCTAssertNil(last.next)
    for page in [first, mid, last] {
      let width = try XCTUnwrap(page.fields[256])
      let height = try XCTUnwrap(page.fields[257])
      XCTAssertEqual(file.order.number(width.data, 0, 4), 1)
      XCTAssertEqual(file.order.number(height.data, 0, 4), 1)
      let start = try XCTUnwrap(page.fields[273])
      let at = file.order.number(start.data, 0, 4)
      XCTAssertEqual(try file.bytes(at: at, count: 3), Data([31, 101, 93]))
    }
  }

  func testPhotatoMatchesPhotoshopReducedRGBSampleWords() throws {
    let w = 257, h = 193
    var document = try CraftDocument(width: w, height: h, depth: .u8)
    document.resolution = 180
    var pixels = try Surface(width: w, height: h, depth: .u8, fill: .black)
    for y in 0..<h { for x in 0..<w {
      pixels.setPixel(x: x, y: y,
        Pixel(Float((x / 7) % 256) / 255, Float((y / 5) % 256) / 255, Float((x / 9 + y / 7) % 256) / 255))
    } }
    document.layers[0].content = .raster(pixels)
    let options = RasterEncodingOptions(tiffCompression: RasterEncodingOptions.TIFFCompression.none,
      tiffByteOrder: .bigEndian, tiffTransparency: false, tiffImagePyramid: true, tiffEmbedProfile: false)
    let output = try RasterIO.encoded(document, type: .tiff, options: options)
    let source = try TIFFContainer(output, metadata: true)
    let first = try XCTUnwrap(source.root.fields[330]?.children.first)
    let second = try XCTUnwrap(first.next)
    let third = try XCTUnwrap(second.next)
    XCTAssertNil(source.root.next)
    XCTAssertNil(third.next)
    let expected = [
      (257, 193, 180.0, "742dbe846a94917f4145a4484070b570217d5ddbf46950a54df6e8dbce1ab104"),
      (129, 97, 90.0, "87d1e3469950a8dcfc3fecf0bcc22e3c614f2c3af04e5971753186a5d3fa469d"),
      (65, 49, 45.0, "1c19b9f4f5ed01285ddd49854494fa78591a7b8563a48819cec44fefd44ba718"),
      (33, 25, 22.5, "5bda32c6627b0d337068d1849a32cfcbb86bf822eaec324de936e9e56de5cff7"),
    ]
    for (index, page) in [source.root, first, second, third].enumerated() {
      let (width, height, dpi, hash) = expected[index]
      func number(_ tag: Int) throws -> Int {
        let field = try XCTUnwrap(page.fields[tag])
        return source.order.number(field.data, 0, field.type == 3 ? 2 : 4)
      }
      XCTAssertEqual(try number(254), index == 0 ? 0 : 1)
      XCTAssertEqual(try number(256), width)
      XCTAssertEqual(try number(257), height)
      let density = try XCTUnwrap(page.fields[282])
      XCTAssertEqual(Double(source.order.number(density.data, 0, 4)) /
        Double(source.order.number(density.data, 4, 4)), dpi)
      let offsets = try XCTUnwrap(page.fields[273]), counts = try XCTUnwrap(page.fields[279])
      let bytes = try (0..<offsets.count).reduce(into: Data()) { result, index in
        let offset = source.order.number(offsets.data, index * (offsets.type == 3 ? 2 : 4), offsets.type == 3 ? 2 : 4)
        let length = source.order.number(counts.data, index * (counts.type == 3 ? 2 : 4), counts.type == 3 ? 2 : 4)
        result.append(try source.bytes(at: offset, count: length))
      }
      XCTAssertEqual(bytes.count, width * height * 3)
      XCTAssertEqual(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), hash)
    }
    var off = options; off.tiffImagePyramid = false
    XCTAssertNil(try TIFFContainer(RasterIO.encoded(document, type: .tiff, options: off), metadata: true).root.fields[330])
  }
}
