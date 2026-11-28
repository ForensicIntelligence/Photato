import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFJPEGOutputTests: XCTestCase {
  func testJPEGQualityChangesBoundedRGBStripsAndPyramids() throws {
    let document = try rgb()
    let settings = RasterEncodingOptions(tiffCompression: .jpeg, tiffByteOrder: .littleEndian,
      tiffImagePyramid: true, tiffJPEGQuality: 3)
    let encoded = try RasterIO.encoded(document, type: .tiff, options: settings)
    let tiff = try TIFFContainer(encoded, metadata: true)
    XCTAssertEqual(tiff.order, .little)
    XCTAssertEqual(try tiff.scalar(259), 7)
    XCTAssertEqual(try tiff.scalar(262), 6)
    XCTAssertEqual(try tiff.scalar(277), 3)
    XCTAssertNil(tiff.root.fields[338])
    XCTAssertGreaterThan(try tiff.numbers(273).count, 1)
    XCTAssertEqual(try tiff.scalar(278) % 16, 0)
    var child = try XCTUnwrap(tiff.root.fields[330]?.children.first)
    var width = document.width, height = document.height
    for index in 0..<3 {
      XCTAssertEqual(try field(256, of: child, in: tiff), (width + 1) / 2)
      XCTAssertEqual(try field(257, of: child, in: tiff), (height + 1) / 2)
      XCTAssertEqual(try field(259, of: child, in: tiff), 7)
      XCTAssertNotNil(child.fields[530])
      width = (width + 1) / 2; height = (height + 1) / 2
      if index == 2 { XCTAssertNil(child.next) }
      else { child = try XCTUnwrap(child.next) }
    }

    var high = settings; high.tiffJPEGQuality = 12
    let highBytes = try RasterIO.encoded(document, type: .tiff, options: high)
    XCTAssertGreaterThan(highBytes.count, encoded.count)
    let highTIFF = try TIFFContainer(highBytes, metadata: false, additionalTags: [530])
    XCTAssertEqual(try highTIFF.numbers(530), [1, 1])
    let reopened = try RasterIO.read(highBytes)
    XCTAssertEqual(reopened.width, document.width)
    XCTAssertEqual(reopened.height, document.height)
    XCTAssertEqual(reopened.resolution, 225)
    XCTAssertEqual(reopened.colorMode, .rgb)

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tif")
    defer { try? FileManager.default.removeItem(at: url) }
    try RasterIO.write(document, to: url, type: .tiff, options: settings)
    XCTAssertEqual(try Data(contentsOf: url), encoded)
    let preview = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
    XCTAssertEqual(CGImageSourceCreateImageAtIndex(preview, 0, nil)?.width, document.width)
  }

  func testGrayAndSeparateRGBKeepModeAndEditableLayers() throws {
    let grayURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/tiff-jpeg/gray-tile.tif")
    let gray = try RasterIO.read(grayURL)
    let options = RasterEncodingOptions(tiffCompression: .jpeg, tiffByteOrder: .bigEndian, tiffJPEGQuality: 9)
    let grayBytes = try RasterIO.encoded(gray, type: .tiff, options: options)
    let grayTIFF = try TIFFContainer(grayBytes, metadata: true)
    XCTAssertEqual(try grayTIFF.scalar(259), 7)
    XCTAssertEqual(try grayTIFF.scalar(262), 1)
    XCTAssertEqual(try grayTIFF.scalar(277), 1)
    XCTAssertNil(grayTIFF.root.fields[34675])
    for tag in 322...325 { XCTAssertNil(grayTIFF.root.fields[tag]) }
    let lossless = try RasterIO.encoded(gray, type: .tiff, options: .init(tiffCompression: .lzw, tiffImagePyramid: true))
    XCTAssertEqual(try RasterIO.read(lossless).colorMode, .grayscale)
    let grayCopy = try RasterIO.read(grayBytes)
    XCTAssertEqual(grayCopy.colorMode, .grayscale)
    XCTAssertEqual(grayCopy.resolution, 225)
    XCTAssertEqual(try XCTUnwrap(grayCopy.layers[0].nativeMode).rawWord(component: 1, index: 227), 255)

    var document = try rgb()
    document.layers[0].name = "Background detail"
    let detail = try Surface(width: 5, height: 3, depth: .u8, fill: Pixel(0.25, 0.5, 0.75, 0.5))
    var layer = Layer(name: "Editable overlay", content: .raster(detail))
    layer.x = 43; layer.y = 57
    document.layers.append(layer)
    var layered = options; layered.tiffPixelOrder = .perChannel; layered.tiffLayers = true
    let bytes = try RasterIO.encoded(document, type: .tiff, options: layered)
    let tiff = try TIFFContainer(bytes, metadata: true)
    XCTAssertEqual(try tiff.scalar(259), 7)
    XCTAssertEqual(try tiff.scalar(262), 2)
    XCTAssertEqual(try tiff.scalar(284), 2)
    XCTAssertNotNil(tiff.root.fields[34675])
    XCTAssertNotNil(tiff.root.fields[37724])
    let reopened = try RasterIO.read(bytes)
    XCTAssertEqual(reopened.layers.map(\.name), ["Background detail", "Editable overlay"])
    let overlay = try XCTUnwrap(reopened.layers.last)
    XCTAssertEqual(overlay.x, 43)
    XCTAssertEqual(overlay.y, 57)
    guard case .raster(let pixels) = overlay.content else { return XCTFail("Expected editable overlay") }
    XCTAssertEqual(try pixels.rgbaData(depth: .u8), try detail.rgbaData(depth: .u8))
  }

  func testInvalidJPEGOutputLeavesFileIntactAndExplicitWhiteMatteWorks() throws {
    let options = RasterEncodingOptions(tiffCompression: .jpeg, tiffJPEGQuality: 9)
    var transparent = try CraftDocument(width: 31, height: 19, depth: .u8)
    transparent.layers[0].content = .raster(try Surface(width: 31, height: 19, depth: .u8))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tif")
    defer { try? FileManager.default.removeItem(at: url) }
    let original = Data("Existing document".utf8)
    try original.write(to: url)
    XCTAssertThrowsError(try RasterIO.write(transparent, to: url, type: .tiff, options: options))
    XCTAssertEqual(try Data(contentsOf: url), original)
    var white = options; white.tiffTransparency = false
    try RasterIO.write(transparent, to: url, type: .tiff, options: white)
    let result = try RasterIO.read(url)
    guard case .raster(let pixels) = result.layers[0].content else { return XCTFail("Expected matte raster") }
    XCTAssertEqual(pixels.pixel(x: 12, y: 14), .white)

    let large = try CraftDocument(width: 30_001, height: 1, depth: .u8)
    XCTAssertThrowsError(try RasterIO.encoded(large, type: .tiff, options: options))
    let deep = try CraftDocument(width: 8, height: 3, depth: .u16)
    XCTAssertThrowsError(try RasterIO.encoded(deep, type: .tiff, options: options))
    XCTAssertThrowsError(try RasterIO.encoded(transparent, type: .tiff, options: .init(tiffJPEGQuality: 5)))
    XCTAssertThrowsError(try RasterIO.encoded(transparent, type: .tiff,
      options: .init(tiffCompression: .jpeg, tiffTransparency: true)))
  }

  private func field(_ tag: Int, of node: TIFFContainer.Directory, in file: TIFFContainer) throws -> Int {
    let field = try XCTUnwrap(node.fields[tag])
    return file.order.number(field.data, 0, field.type == 3 ? 2 : 4)
  }

  private func rgb() throws -> CraftDocument {
    let width = 641, height = 103
    var result = try CraftDocument(width: width, height: height, depth: .u8)
    var image = try Surface(width: width, height: height, depth: .u8)
    for y in 0..<height {
      for x in 0..<width {
        image.setPixel(x: x, y: y, Pixel(Float((x * 19 + y * 7) % 256) / 255,
          Float((x * 11 + y * 23) % 256) / 255, Float((x ^ y) % 256) / 255, 1))
      }
    }
    result.layers[0].content = .raster(image)
    result.resolution = 225
    return result
  }
}
