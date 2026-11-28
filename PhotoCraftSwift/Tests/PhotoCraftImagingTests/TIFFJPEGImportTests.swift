import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFJPEGImportTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/tiff-jpeg")

  func testGrayPolarityAndSeparateRGBMatchIndependentLibTIFFSamples() throws {
    let cases: [(String, DocumentColorMode, String)] = [
      ("gray-strip", .grayscale, "a979d42a72cd21e3cd560374e768de9167e1c76144ffd1ecbcc0caa35ca150d9"),
      ("gray-tile", .grayscale, "dcd9c66fa494ba4849b7f043acf6d8e9cd8547347224593c99824038df2dc240"),
      ("min-white", .grayscale, "3e481a001d8c48f3ff9a4cf08d8cbdd132e28b8463b36b49395f82341ae1143d"),
      ("rgb-strip", .rgb, "fcef610fa3afa42bed3aa5c7dcca09de7fc69483b016c429987cb5808a5ca374"),
      ("rgb-planar", .rgb, "fcef610fa3afa42bed3aa5c7dcca09de7fc69483b016c429987cb5808a5ca374"),
    ]
    for (name, mode, expected) in cases {
      let url = fixtures.appendingPathComponent(name + ".tif")
      let document = try RasterIO.read(url)
      checkGeometry(document, mode: mode)
      let bytes = try samples(document)
      XCTAssertEqual(bytes.count, 179 * 129 * mode.componentCount, name)
      let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
      XCTAssertEqual(digest, expected, name)
    }
  }

  func testYCbCrStripsAndTilesMatchFullFileImageIODecoding() throws {
    for name in ["ycc-strip", "ycc-tile"] {
      let url = fixtures.appendingPathComponent(name + ".tif")
      let bytes = try Data(contentsOf: url)
      let document = try RasterIO.read(bytes)
      checkGeometry(document, mode: .rgb)
      let actual = try samples(document)
      let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
      let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
      XCTAssertEqual(image.colorSpace?.model, .rgb)
      XCTAssertEqual(image.alphaInfo, .noneSkipLast)
      let decoded = try XCTUnwrap(image.dataProvider?.data) as Data
      var expected = Data()
      for y in 0..<image.height {
        for x in 0..<image.width {
          let start = y * image.bytesPerRow + x * 4
          expected.append(decoded[start..<start + 3])
        }
      }
      XCTAssertEqual(actual, expected, name)
    }
  }

  func testEditableLayersSurviveACompressedCompositeAndTruncatedBlocksFail() throws {
    let url = fixtures.appendingPathComponent("ycc-strip.tif")
    let input = try Data(contentsOf: url)
    let tiff = try TIFFContainer(input, metadata: true)
    var document = try CraftDocument(width: 179, height: 129, depth: .u8)
    document.layers[0].name = "Imported base"
    let content = try Surface(width: 3, height: 5, depth: .u8, fill: Pixel(0.25, 0.5, 0.75, 1))
    var mark = Layer(name: "Editable mark", content: .raster(content))
    mark.x = 79
    mark.y = 43
    document.layers.append(mark)
    let encoded = try RasterIO.encoded(document, type: .tiff,
      options: .init(tiffByteOrder: .littleEndian, tiffLayers: true))
    let layerSource = try TIFFContainer(encoded, metadata: true, additionalTags: [37724])
    tiff.root.fields[37724] = try XCTUnwrap(layerSource.root.fields[37724])
    var layered = input
    try tiff.appendDirectories(to: &layered, order: tiff.order)
    let reopened = try RasterIO.read(layered)
    XCTAssertEqual(reopened.layers.map(\.name), ["Imported base", "Editable mark"])
    let layer = try XCTUnwrap(reopened.layers.last)
    XCTAssertEqual(layer.x, 79)
    XCTAssertEqual(layer.y, 43)
    guard case .raster(let stored) = layer.content else { return XCTFail("Missing editable raster") }
    XCTAssertEqual(try stored.rgbaData(depth: .u8), try content.rgbaData(depth: .u8))

    let lengths = try tiff.numbers(279)
    let offsets = try tiff.numbers(273)
    let endOfFirstJPEG = offsets[0] + lengths[0]
    layered[endOfFirstJPEG - 1] = 0
    XCTAssertThrowsError(try RasterIO.read(layered))
  }

  private func checkGeometry(_ document: CraftDocument, mode: DocumentColorMode) {
    XCTAssertEqual(document.colorMode, mode)
    XCTAssertEqual(document.depth, .u8)
    XCTAssertEqual(document.width, 179)
    XCTAssertEqual(document.height, 129)
    XCTAssertEqual(document.resolution, 225)
    XCTAssertEqual(document.profileIsUntagged, true)
    XCTAssertEqual(document.layers.count, 1)
  }

  private func samples(_ document: CraftDocument) throws -> Data {
    let layer = try XCTUnwrap(document.layers.first)
    var result = Data()
    if let native = layer.nativeMode {
      for index in 0..<document.width * document.height {
        result.append(UInt8(native.rawWord(component: 0, index: index)))
        XCTAssertEqual(native.rawWord(component: 1, index: index), 255)
      }
      return result
    }
    guard case .raster(let surface) = layer.content else { throw CraftError.invalid("Missing TIFF raster") }
    let rgba = try surface.rgbaData(depth: .u8)
    for index in stride(from: 0, to: rgba.count, by: 4) {
      result.append(rgba[index..<index + 3])
      XCTAssertEqual(rgba[index + 3], 255)
    }
    return result
  }
}
