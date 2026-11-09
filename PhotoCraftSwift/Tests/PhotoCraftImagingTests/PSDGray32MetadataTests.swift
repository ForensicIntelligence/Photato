import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDGray32MetadataTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .f32) throws -> CraftDocument {
    var document = try CraftDocument(width: 16, height: 12, depth: depth, name: "Owned Gray32 export")
    var gray = try NativeModeRaster(width: 16, height: 12, mode: .grayscale, depth: depth)
    let values: [Float] = depth == .f32 ? [-0.25, 0, 0.125, 0.25, 0.5, 1, 1.5, 2] : [0, 0.125, 0.25, 0.5, 1]
    for i in 0..<192 {
      try gray.set(values[(i % 16 + 3 * (i / 16)) % values.count], component: 0, index: i)
      try gray.set(1, component: 1, index: i)
    }
    document.modeDescriptor = try .init(mode: .grayscale, depth: depth, profile: gray.profile)
    document.profileIsUntagged = true
    document.layers[0].nativeMode = gray
    document.layers[0].content = .raster(try gray.surface())
    document.layers[0].background = true
    try document.validate()
    return document
  }
  func colorData(_ data: Data) throws -> Data {
    var reader = PSDReader(data: data)
    _ = try reader.bytes(26)
    let section = try reader.section()
    return try section.data
  }
  func assertWords(_ restored: CraftDocument, _ original: CraftDocument,
    file: StaticString = #filePath, line: UInt = #line) throws {
    let a = try XCTUnwrap(original.layers[0].nativeMode), b = try XCTUnwrap(restored.layers[0].nativeMode)
    XCTAssertEqual(try a.planes, try b.planes, file: file, line: line)
  }
  func testGray32ExportsIncludeHDRMetadataWithoutChangingAnyComponentWords() throws {
    let source = try fixture()
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    for format in PSDFileFormat.allCases { for compression in PSDCompression.allCases {
      let data = try PSDCodec.writeRasterLayers(source, compression: compression, format: format)
      let metadata = try colorData(data)
      XCTAssertEqual(metadata.count, 110)
      XCTAssertEqual(metadata.prefix(4), Data("hdrt".utf8))
      try assertWords(PSDCodec.read(data), source)
      let ext = format == .psd ? "psd" : "psb"
      let name = "native-gray32-\(compression.rawValue).\(ext)"
      let url = folder.appendingPathComponent(name)
      try PSDCodec.writeRasterLayers(source, to: url, compression: compression, format: format)
      XCTAssertEqual(try Data(contentsOf: url), data)
      try assertWords(PSDCodec.read(url), source)
      if let capture = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try data.write(to: URL(fileURLWithPath: capture).appendingPathComponent(name))
      }
    } }
  }
  func testReexportRetainsIndependentPhotoshopGray32ToningAndAllWords() throws {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "photoshop-owned-gray32", withExtension: "psd", subdirectory: "Fixtures/gray32"))
    let bytes = try Data(contentsOf: url), metadata = try colorData(bytes)
    XCTAssertEqual(metadata.count, 110)
    let source = try NativeArchive.decode(NativeArchive.encode(PSDCodec.read(bytes)))
    for format in PSDFileFormat.allCases {
      let output = try PSDCodec.writeRasterLayers(source, format: format)
      XCTAssertEqual(try colorData(output), metadata)
      try assertWords(PSDCodec.read(output), source)
    }
  }
  func testLowerDepthGrayRemainsWithoutToningAndRGB32KeepsItsExistingBlock() throws {
    for depth in [PixelDepth.u8, .u16] {
      let bytes = try PSDCodec.writeRasterLayers(fixture(depth))
      XCTAssertTrue(try colorData(bytes).isEmpty)
    }
    let rgb = try PSDModeTests().fixture(.rgb, .f32)
    let output = try PSDCodec.writeRasterLayers(rgb)
    XCTAssertEqual(try colorData(output), PSDColorMetadata.defaultHDRToning())
  }
}
