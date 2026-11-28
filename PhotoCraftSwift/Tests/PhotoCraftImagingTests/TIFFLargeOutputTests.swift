import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class TIFFLargeOutputTests: XCTestCase {
  private func fixture(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent()
      .appendingPathComponent("Fixtures/tiff-large-components/\(name).tif")
  }

  func testLargeGray16WrittenToFileMatchesDataAndOriginalNativeSamples() throws {
    let original = try RasterIO.read(fixture("gray16-36mp-zip"))
    let expected = try XCTUnwrap(original.layers.first?.nativeMode)
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let output = temporary.appendingPathComponent("gray16.tif")
    let options = RasterEncodingOptions(tiffCompression: .zip, tiffByteOrder: .bigEndian,
      tiffPixelOrder: .perChannel, tiffTransparency: false, tiffEmbedProfile: true)
    try RasterIO.write(original, to: output, type: .tiff, options: options)
    let bytes = try Data(contentsOf: output)
    XCTAssertEqual(bytes, try RasterIO.encoded(original, type: .tiff, options: options))
    let result = try RasterIO.read(output)
    XCTAssertEqual(result.layers.first?.nativeMode, expected)
    XCTAssertEqual(result.sourceICC, expected.profile)
    let tiff = try TIFFContainer(bytes, metadata: false)
    XCTAssertEqual(try tiff.scalar(259), 8)
    XCTAssertEqual(try tiff.scalar(277), 1)
    XCTAssertLessThan(try tiff.scalar(278), original.height)
  }

  func testLargeLayeredCMYKTiffKeepsEditableComponents() throws {
    var original = try RasterIO.read(fixture("cmyk16-9mp-zip-planar"))
    original.layers[0].name = "Proof CMYK"
    let originalMode = try XCTUnwrap(original.layers.first?.nativeMode)
    let options = RasterEncodingOptions(tiffCompression: .zip, tiffPixelOrder: .perChannel,
      tiffLayers: true, tiffEmbedProfile: false, tiffLayerCompression: .zip)
    let bytes = try RasterIO.encoded(original, type: .tiff, options: options)
    let document = try RasterIO.read(bytes)
    XCTAssertEqual(document.layers.count, 1)
    XCTAssertEqual(document.layers.first?.name, "Proof CMYK")
    XCTAssertEqual(document.layers.first?.nativeMode, originalMode)
    XCTAssertNil(document.sourceICC)
  }

  func testClassicTIFFFileReaderOpensSparseSourceAbove512MiB() throws {
    let width = 16_384, height = 16_385, bytesPerRow = width * 2
    let stripLength = height * bytesPerRow
    let ifdOffset = 8 + stripLength
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let output = temporary.appendingPathComponent("gray16.tif")
    func bytes(_ value: Int, count: Int) -> Data {
      Data((0..<count).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    let directory: [(Int, Int, Int)] = [(256, 4, width), (257, 4, height), (258, 3, 16), (259, 3, 1),
      (262, 3, 1), (273, 4, 8), (277, 3, 1), (278, 4, height), (279, 4, stripLength), (284, 3, 1)]
    var table = bytes(directory.count, count: 2)
    for (tag, type, value) in directory {
      table.append(bytes(tag, count: 2)); table.append(bytes(type, count: 2)); table.append(bytes(1, count: 4))
      if type == 3 { table.append(bytes(value, count: 2)); table.append(bytes(0, count: 2)) }
      else { table.append(bytes(value, count: 4)) }
    }
    table.append(bytes(0, count: 4))
    let header = Data([77, 77, 0, 42]) + bytes(ifdOffset, count: 4)
    try header.write(to: output)
    let file = try FileHandle(forWritingTo: output)
    try file.seek(toOffset: 8)
    try file.write(contentsOf: bytes(14911, count: 2))
    try file.seek(toOffset: UInt64(ifdOffset - 2))
    try file.write(contentsOf: bytes(50031, count: 2))
    try file.write(contentsOf: table)
    try file.close()
    let read = try RasterIO.read(output)
    XCTAssertEqual(read.width, width)
    XCTAssertEqual(read.height, height)
    let samples = try XCTUnwrap(read.layers.first?.nativeMode)
    XCTAssertEqual(samples.rawWord(component: 0, index: 0), 14911)
    XCTAssertEqual(samples.rawWord(component: 0, index: 1), 0)
    XCTAssertEqual(samples.rawWord(component: 0, index: width * height - 1), 50031)
    XCTAssertTrue(samples.isOpaque)
    XCTAssertEqual(samples.residentComponentEditBytes, 0)
  }
}
