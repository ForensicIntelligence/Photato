import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFBigOutputTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

  func testBigTIFFFileAndDataKeepEditableLayersSelectionsAndPyramids() throws {
    let original = try RasterIO.read(fixtures.appendingPathComponent("tiff-layers/photoshop-transparent-be-fixture.tiff"))
    let expected = try XCTUnwrap(original.alphaChannels?.first)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tif")
    defer { try? FileManager.default.removeItem(at: url) }
    for order in RasterEncodingOptions.TIFFByteOrder.allCases {
      let options = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: order, tiffPixelOrder: .perChannel,
        tiffLayers: true, tiffTransparency: true, tiffImagePyramid: true, tiffBigTIFF: true, tiffLayerCompression: .rle)
      let data = try RasterIO.encoded(original, type: .tiff, options: options)
      try RasterIO.write(original, to: url, type: .tiff, options: options)
      XCTAssertEqual(try Data(contentsOf: url), data)
      let file = try TIFFContainer(data, metadata: true)
      XCTAssertTrue(file.isBigTIFF)
      XCTAssertEqual(file.order, order == .bigEndian ? .big : .little)
      XCTAssertEqual(file.root.fields[273]?.type, 16)
      XCTAssertEqual(file.root.fields[279]?.type, 16)
      let pyramid = try XCTUnwrap(file.root.fields[330])
      XCTAssertEqual(pyramid.type, 18)
      var next = pyramid.children.first
      for _ in 0..<3 {
        let level = try XCTUnwrap(next)
        XCTAssertEqual(level.fields[273]?.type, 16)
        XCTAssertEqual(level.fields[279]?.type, 16)
        next = level.next
      }
      XCTAssertNil(next)
      let reopened = try RasterIO.read(url)
      XCTAssertEqual(reopened.layers.map(\.name), original.layers.map(\.name))
      XCTAssertEqual(reopened.layers.map(\.mask), original.layers.map(\.mask))
      XCTAssertEqual(reopened.alphaChannels?.first?.pixels, expected.pixels)
      XCTAssertEqual(reopened.resolution, original.resolution)
      XCTAssertEqual(reopened.profileIsUntagged, original.profileIsUntagged)
      XCTAssertNil(file.root.fields[34675])
    }
    let tagged = try RasterIO.encoded(original, type: .tiff, options: .init(tiffBigTIFF: true, tiffEmbedProfile: true))
    let taggedFile = try TIFFContainer(tagged, metadata: true)
    let embedded = try XCTUnwrap(taggedFile.root.fields[34675]?.data)
    XCTAssertEqual(embedded, try original.workingICC ?? NativeModeProfile.standard(.rgb, depth: original.depth))
    XCTAssertEqual(try RasterIO.read(tagged).sourceICC, embedded)
  }

  func testBigTIFFWorksForFlatSurfaceAndRestrictedStorage() throws {
    let shape = try Surface(width: 19, height: 13, depth: .u8, fill: Pixel(0.25, 0.5, 0.75, 1))
    let size = RasterEncodingOptions(tiffCompression: .lzw, tiffByteOrder: .littleEndian, tiffBigTIFF: true)
    let raw = try RasterIO.encoded(shape, type: .tiff, options: size)
    let tiff = try TIFFContainer(raw, metadata: false)
    XCTAssertTrue(tiff.isBigTIFF)
    XCTAssertEqual(try tiff.scalar(259), 5)
    let opened = try RasterIO.read(raw)
    guard case .raster(let pixels) = opened.layers[0].content else { return XCTFail("Expected RGB pixels") }
    XCTAssertEqual(try pixels.rgbaData(depth: .u8), try shape.rgbaData(depth: .u8))

    for name in ["bitmap-le.tif", "indexed-be.tif"] {
      let original = try RasterIO.read(fixtures.appendingPathComponent("bigtiff/" + name))
      let bytes = try RasterIO.encoded(original, type: .tiff, options: size)
      XCTAssertTrue(TIFFContainer.isBigTIFF(bytes))
      let reopened = try RasterIO.read(bytes)
      XCTAssertEqual(reopened.restrictedMode, original.restrictedMode)
      XCTAssertEqual(reopened.resolution, original.resolution)
    }

    let classic = try RasterIO.encoded(shape, type: .tiff, options: .init(tiffBigTIFF: false))
    XCTAssertTrue(TIFFContainer.isClassic(classic))
    XCTAssertThrowsError(try RasterIO.encoded(shape, type: .png, options: size))
  }

  func testBigTIFFWritesAFirstIFDAndStripAboveFourGiB() throws {
    let document = try RasterIO.read(fixtures.appendingPathComponent("bigtiff/gray8-stripped-le.tif"))
    let data = try RasterIO.encoded(document, type: .tiff,
      options: .init(tiffCompression: RasterEncodingOptions.TIFFCompression.none, tiffTransparency: false))
    let container = try TIFFContainer(data, metadata: true)
    let length = try XCTUnwrap(container.numbers(279).first)
    let strip = try container.bytes(at: XCTUnwrap(container.numbers(273).first), count: length)
    let layout = TIFFContainer.Layout(bigTIFF: true)
    let order = container.order
    let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tif")
    defer { try? FileManager.default.removeItem(at: destination) }
    try layout.header(order: order).write(to: destination)
    let file = try FileHandle(forWritingTo: destination)
    let highStrip = 4_295_032_832
    var extent = highStrip
    func append(_ bytes: Data) throws {
      try file.seek(toOffset: UInt64(extent))
      try file.write(contentsOf: bytes)
      extent += bytes.count
    }
    func patch(_ bytes: Data, _ offset: Int) throws {
      try file.seek(toOffset: UInt64(offset))
      try file.write(contentsOf: bytes)
    }
    do {
      try append(strip)
      container.set(273, [highStrip], type: layout.offsetFieldType)
      container.set(279, [length], type: layout.offsetFieldType)
      let pointer = try container.writeDirectories(order: order, maximumOutput: layout.maximumFileBytes, layout: layout,
        extent: { extent }, emit: append, patch: patch)
      XCTAssertGreaterThan(order.number(pointer, 0, 8), Int(UInt32.max))
      try patch(pointer, layout.headerPointerOffset)
      try file.close()
    } catch {
      try? file.close()
      throw error
    }
    let reopened = try RasterIO.read(destination)
    XCTAssertEqual(reopened.colorMode, .grayscale)
    XCTAssertEqual(reopened.resolution, 225)
    let exported = try XCTUnwrap(reopened.layers.first?.nativeMode)
    let control = try XCTUnwrap(document.layers.first?.nativeMode)
    let range = 0..<(document.width * document.height)
    XCTAssertEqual(range.map { exported.rawWord(component: 0, index: $0) },
      range.map { control.rawWord(component: 0, index: $0) })
  }
}
