import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFBigInputTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

  func testGrayBigTIFFMatchesPhotoshopsDecodedSamples() throws {
    let url = fixtures.appendingPathComponent("bigtiff/gray8-stripped-le.tif")
    let bytes = try Data(contentsOf: url)
    let pathDocument = try RasterIO.read(url)
    let dataDocument = try RasterIO.read(bytes)
    for document in [pathDocument, dataDocument] { try checkGrayscale(document) }
  }

  func testFileBackedBigTIFFReadsARealStripAboveFourGiB() throws {
    let source = fixtures.appendingPathComponent("bigtiff/gray8-stripped-le.tif")
    var container = try Data(contentsOf: source)
    let header = try stripOffsetField(container)
    let originalOffset = try XCTUnwrap(Int(exactly: word(container, at: header, width: 8)))
    let samples = container.subdata(in: originalOffset..<originalOffset + 179 * 129)
    let largeOffset: UInt64 = (1 << 32) + 65_536
    store(largeOffset, in: &container, at: header, width: 8)

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tif")
    defer { try? FileManager.default.removeItem(at: url) }
    try container.write(to: url)
    let output = try FileHandle(forWritingTo: url)
    do {
      try output.seek(toOffset: largeOffset)
      try output.write(contentsOf: samples)
      try output.close()
    } catch {
      try? output.close()
      throw error
    }
    XCTAssertEqual(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
      Int(largeOffset) + samples.count)
    try checkGrayscale(RasterIO.read(url))
  }

  func testBigTIFFKeepsTiledCMYKRestrictedModesAndEditableLayers() throws {
    let tiles = try RasterIO.read(fixtures.appendingPathComponent("bigtiff/cmyk16-tiled-be.tif"))
    let original = try RasterIO.read(fixtures.appendingPathComponent("tiff-tiled-components/planar-cmyk16-lzw-tiled.tiff"))
    XCTAssertEqual(tiles.colorMode, .cmyk)
    XCTAssertEqual(tiles.depth, .u16)
    XCTAssertEqual(tiles.width, 259)
    XCTAssertEqual(tiles.height, 137)
    XCTAssertEqual(tiles.resolution, 225)
    let plane = try XCTUnwrap(tiles.layers.first?.nativeMode)
    let control = try XCTUnwrap(original.layers.first?.nativeMode)
    for channel in 0..<5 {
      let indices = 0..<(259 * 137)
      XCTAssertEqual(indices.map { plane.rawWord(component: channel, index: $0) },
        indices.map { control.rawWord(component: channel, index: $0) })
    }

    let palette = try RasterIO.read(fixtures.appendingPathComponent("bigtiff/indexed-be.tif"))
    let paletteControl = try RasterIO.read(fixtures.appendingPathComponent("RestrictedFormats/palette-be-raw-False.tiff"))
    guard case .indexed(let restoredPalette) = palette.restrictedMode,
      case .indexed(let knownPalette) = paletteControl.restrictedMode else { return XCTFail("Missing palette") }
    XCTAssertEqual(restoredPalette.indices, knownPalette.indices)
    for i in Set(restoredPalette.indices) {
      XCTAssertEqual(restoredPalette.palette[Int(i)], knownPalette.palette[Int(i)])
    }
    XCTAssertEqual(palette.resolution, 144)
    let bitmap = try RasterIO.read(fixtures.appendingPathComponent("bigtiff/bitmap-le.tif"))
    let bitmapControl = try RasterIO.read(fixtures.appendingPathComponent("RestrictedFormats/bitmap-le-raw-False.tiff"))
    XCTAssertEqual(bitmap.restrictedMode, bitmapControl.restrictedMode)

    let layered = try RasterIO.read(fixtures.appendingPathComponent("bigtiff/layered-rgb8-be.tif"))
    let layeredControl = try RasterIO.read(fixtures.appendingPathComponent("tiff-layers/8-big-0.tiff"))
    XCTAssertEqual(layered.layers.map(\.name), ["Base Ω", "Crème 层", "Layers"])
    XCTAssertEqual(layered.resolution, 144)
    for (a, b) in zip(layered.layers.prefix(2), layeredControl.layers.prefix(2)) {
      guard case .raster(let pixels) = a.content, case .raster(let expected) = b.content else {
        return XCTFail("Missing editable raster")
      }
      XCTAssertEqual(try pixels.rgbaData(depth: .u8), try expected.rgbaData(depth: .u8))
      XCTAssertEqual(try a.mask?.rgbaData(depth: .u8), try b.mask?.rgbaData(depth: .u8))
      XCTAssertEqual(a.x, b.x)
      XCTAssertEqual(a.y, b.y)
    }
    XCTAssertEqual(layered.layers[1].parentID, layered.layers[2].id)
  }

  func testBigTIFFRejectsUnaddressablePointersAndUnboundedDirectoryCounts() throws {
    let original = try Data(contentsOf: fixtures.appendingPathComponent("bigtiff/gray8-stripped-le.tif"))
    let strip = try stripOffsetField(original)
    var invalid = original
    store(.max, in: &invalid, at: strip, width: 8)
    XCTAssertThrowsError(try RasterIO.read(invalid))
    invalid = original
    store(.max, in: &invalid, at: 8, width: 8)
    XCTAssertThrowsError(try RasterIO.read(invalid))
    invalid = original
    let directory = try XCTUnwrap(Int(exactly: word(original, at: 8, width: 8)))
    store(UInt64.max >> 1, in: &invalid, at: directory, width: 8)
    XCTAssertThrowsError(try RasterIO.read(invalid))
    invalid = original
    store(4, in: &invalid, at: 4, width: 2)
    XCTAssertThrowsError(try RasterIO.read(invalid))
  }

  private func checkGrayscale(_ document: CraftDocument) throws {
    XCTAssertEqual(document.width, 179)
    XCTAssertEqual(document.height, 129)
    XCTAssertEqual(document.resolution, 225)
    XCTAssertEqual(document.depth, .u8)
    XCTAssertEqual(document.colorMode, .grayscale)
    XCTAssertEqual(document.profileIsUntagged, true)
    let raster = try XCTUnwrap(document.layers.first?.nativeMode)
    let range = 0..<(179 * 129)
    let values = Data(range.map { UInt8(raster.rawWord(component: 0, index: $0)) })
    let digest = SHA256.hash(data: values).map { String(format: "%02x", $0) }.joined()
    XCTAssertEqual(digest, "3eed76b7fda2b7ac4c4c1358a0e50471238bf6105a8a0ef8d24e0f0febba2934")
    XCTAssertTrue(range.allSatisfy { raster.rawWord(component: 1, index: $0) == 255 })
  }

  private func stripOffsetField(_ container: Data) throws -> Int {
    let directory = try XCTUnwrap(Int(exactly: word(container, at: 8, width: 8)))
    let fields = Int(word(container, at: directory, width: 8))
    for index in 0..<fields {
      let start = directory + 8 + index * 20
      if word(container, at: start, width: 2) == 273 {
        XCTAssertEqual(word(container, at: start + 2, width: 2), 16)
        XCTAssertEqual(word(container, at: start + 4, width: 8), 1)
        return start + 12
      }
    }
    throw CraftError.invalid("Missing BigTIFF strip location.")
  }

  private func word(_ data: Data, at offset: Int, width: Int) -> UInt64 {
    (0..<width).reduce(0) { $0 | (UInt64(data[offset + $1]) << ($1 * 8)) }
  }
  private func store(_ value: UInt64, in data: inout Data, at offset: Int, width: Int) {
    for byte in 0..<width { data[offset + byte] = UInt8(truncatingIfNeeded: value >> (8 * byte)) }
  }
}
