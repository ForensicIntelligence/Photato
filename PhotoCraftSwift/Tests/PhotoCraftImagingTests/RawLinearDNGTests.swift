import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class RawLinearDNGTests: XCTestCase {
  func testLinearDNGStoresHalfFloatWordsAndNativeDecoderReadsTheFullImage() throws {
    let (folder, url) = try destination()
    defer { try? FileManager.default.removeItem(at: folder) }
    let width = 512, height = 384
    var pixels = try Surface(width: width, height: height, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<height {
      for x in 0..<width {
        pixels.setLinearPixel(x: x, y: y, Pixel(x < 256 ? 0.125 : 1.5, 0.375, 0.625, 1))
      }
    }
    let document = try image(pixels)
    try RawLinearDNG.write(document, to: url)
    let data = try Data(contentsOf: url)
    let file = try TIFFContainer(data, metadata: false, additionalTags: [254, 50_706, 50_717], inspectSubIFDs: true)
    XCTAssertEqual(try file.scalar(254), 1)
    XCTAssertEqual(try file.scalar(256), 160)
    XCTAssertEqual(file.root.fields[50_706]?.data, Data([1, 4, 0, 0]))
    let raw = try XCTUnwrap(file.root.fields[330]?.children.first)
    func words(_ tag: Int, bytes: Int) throws -> [Int] {
      let field = try XCTUnwrap(raw.fields[tag])
      return (0..<field.count).map { file.order.number(field.data, $0 * bytes, bytes) }
    }
    XCTAssertEqual(try words(262, bytes: 2), [34_892])
    XCTAssertEqual(try words(256, bytes: 4), [width])
    XCTAssertEqual(try words(257, bytes: 4), [height])
    XCTAssertEqual(try words(258, bytes: 2), [16, 16, 16])
    XCTAssertEqual(try words(339, bytes: 2), [3, 3, 3])
    XCTAssertEqual(try words(50_717, bytes: 4), [2, 2, 2])
    let offsets = try words(273, bytes: 4), lengths = try words(279, bytes: 4)
    let stripHeight = try XCTUnwrap(words(278, bytes: 4).first)
    XCTAssertGreaterThan(offsets.count, 1)
    XCTAssertEqual(lengths.reduce(0, +), width * height * 6)
    let dark = [0x3000, 0x3600, 0x3900]
    let light = [0x3E00, 0x3600, 0x3900]
    for (x, y, expected) in [(0, 0, dark), (255, 16, dark), (256, 16, light), (511, 383, light)] {
      let pixelOffset = offsets[y / stripHeight] + (y % stripHeight * width + x) * 6
      XCTAssertEqual((0..<3).map { file.order.number(data, pixelOffset + 2 * $0, 2) }, expected)
    }

    let info = try RawSourceIO.inspect(data)
    XCTAssertEqual(info.type, "com.adobe.raw-image")
    XCTAssertEqual(info.nativeWidth, width)
    XCTAssertEqual(info.nativeHeight, height)
    let reopened = try RawSourceIO.open(data, fileName: url.lastPathComponent, depth: .f32)
    XCTAssertEqual(reopened.width, width)
    XCTAssertEqual(reopened.height, height)
    XCTAssertEqual(reopened.layers.first?.smartObject?.data, data)
  }

  func testInvalidLinearSamplesLeaveExistingDestinationUntouched() throws {
    let (folder, url) = try destination()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = Data("Keep the existing file".utf8)
    try original.write(to: url)
    var pixels = try Surface(width: 64, height: 64, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<pixels.height {
      for x in 0..<pixels.width { pixels.setLinearPixel(x: x, y: y, Pixel(0.2, 0.3, 0.4, 1)) }
    }
    pixels.setLinearPixel(x: 1, y: 1, Pixel(-0.2, 0.3, 0.4, 1))
    let document = try image(pixels)
    XCTAssertThrowsError(try RawLinearDNG.write(document, to: url))
    XCTAssertEqual(try Data(contentsOf: url), original)
    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [url.lastPathComponent])
  }

  private func destination() throws -> (URL, URL) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    return (folder, folder.appendingPathComponent("Owned-HDR.dng"))
  }

  private func image(_ surface: Surface) throws -> CraftDocument {
    var document = try CraftDocument(width: surface.width, height: surface.height, depth: .f32)
    let layer = Layer(name: "HDR Merge", content: .raster(surface))
    document.layers = [layer]
    document.activeLayerID = layer.id
    return document
  }
}
