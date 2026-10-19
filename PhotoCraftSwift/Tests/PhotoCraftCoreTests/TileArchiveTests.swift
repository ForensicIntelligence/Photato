import Foundation
import XCTest

@testable import PhotoCraftCore

final class TileArchiveTests: XCTestCase {
  func assertBits(
    _ actual: Pixel, _ expected: Pixel, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertEqual(actual.r.bitPattern, expected.r.bitPattern, file: file, line: line)
    XCTAssertEqual(actual.g.bitPattern, expected.g.bitPattern, file: file, line: line)
    XCTAssertEqual(actual.b.bitPattern, expected.b.bitPattern, file: file, line: line)
    XCTAssertEqual(actual.a.bitPattern, expected.a.bitPattern, file: file, line: line)
  }
  func fixture(_ name: String) throws -> Data {
    let root = try XCTUnwrap(Bundle.module.resourceURL).appendingPathComponent("Fixtures")
    return try Data(contentsOf: root.appendingPathComponent(name))
  }
  func testIndependentPythonTileAndRawSamplesPreserveSubnormalsAndSignedZero() throws {
    let reference = Pixel(Float(bitPattern: 0x8000_0000), Float(bitPattern: 1), 2, 0.5)
    let pixels = try TileArchive.decode(fixture("tile-f32-zlib.bin"))
    XCTAssertEqual(pixels.count, 4096)
    for pixel in pixels { assertBits(pixel, reference) }
    let encoded = try TileArchive.encode(pixels)
    for pixel in try TileArchive.decode(encoded) { assertBits(pixel, reference) }
    var raw = Data([0])
    let sample: [UInt8] = [0, 0, 0, 128, 1, 0, 0, 0, 0, 0, 0, 64, 0, 0, 0, 63]
    for _ in 0..<4096 { raw.append(contentsOf: sample) }
    for pixel in try TileArchive.decode(raw) { assertBits(pixel, reference) }
  }
  func testCorruptTileLengthsCompressionChecksumsAndNonfiniteSamplesReject() throws {
    let data = try fixture("tile-f32-zlib.bin")
    for count in 0..<data.count { XCTAssertThrowsError(try TileArchive.decode(data.prefix(count))) }
    var appended = data
    appended.append(0)
    XCTAssertThrowsError(try TileArchive.decode(appended))
    var damaged = data
    damaged[damaged.count - 1] ^= 1
    XCTAssertThrowsError(try TileArchive.decode(damaged))
    XCTAssertThrowsError(try TileArchive.decode(Data([99])))
    XCTAssertThrowsError(
      try TileArchive.decode(Data(repeating: 0, count: TileArchive.byteCount + 2)))
    var nonfinite = Data(repeating: 0, count: TileArchive.byteCount + 1)
    nonfinite[3] = 128
    nonfinite[4] = 127  // little-endian +infinity in the first red sample.
    XCTAssertThrowsError(try TileArchive.decode(nonfinite))
  }
  func testRealVersionSixArchiveMigratesWithAllLayerAndMaskSamplesUnchanged() throws {
    let data = try fixture("native-v6-migration.pcswift")
    let oldHeader = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    XCTAssertEqual(oldHeader["version"] as? Int, 6)
    let original = try NativeArchive.decode(data)
    XCTAssertEqual(original.width, 3)
    XCTAssertEqual(original.height, 2)
    for (index, depth) in PixelDepth.allCases.enumerated() {
      let layer = original.layers[index]
      XCTAssertEqual(
        layer.id.uuidString, String(format: "00000000-0000-0000-0000-%012d", index + 1))
      XCTAssertEqual(layer.x, index - 1)
      XCTAssertEqual(layer.y, -index)
      guard case .raster(let surface) = layer.content else { return XCTFail("Lost pixels") }
      XCTAssertEqual(surface.depth, depth)
      assertBits(surface.pixel(x: 0, y: 0), Pixel(0.23, 0.57, 0.91, 0.37).quantized(depth))
      assertBits(surface.pixel(x: 1, y: 0), Pixel(-0.5, 2, 0.7, 0).quantized(depth))
      assertBits(surface.pixel(x: 2, y: 1), Pixel(0.17, 0.33, 0.61, 0.9).quantized(depth))
      assertBits(layer.mask!.pixel(x: 0, y: 0), Pixel(0.43, 0.43, 0.43).quantized(depth))
    }
    let migrated = try NativeArchive.encode(original)
    let header = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: migrated, format: nil) as? [String: Any])
    XCTAssertEqual(header["version"] as? Int, 9)
    XCTAssertEqual(try NativeArchive.decode(migrated), original)
  }
  func testNativeArchiveRetainsExactFloatBitsIncludingHiddenColorsAndSparseDefaults() throws {
    let reference = Pixel(Float(bitPattern: 0x8000_0000), Float(bitPattern: 1), -2, 0)
    var surface = try Surface(width: 65, height: 67, depth: .f32, fill: reference)
    surface.setPixel(x: 64, y: 66, Pixel(3, -0.5, Float(bitPattern: 0x3eaa_aaab), 0.3))
    var doc = try CraftDocument(width: 65, height: 67, depth: .f32)
    doc.layers[0].content = .raster(surface)
    let restored = try NativeArchive.decode(NativeArchive.encode(doc))
    guard case .raster(let pixels) = restored.layers[0].content else {
      return XCTFail("Lost raster")
    }
    assertBits(pixels.defaultPixel, surface.defaultPixel)
    assertBits(pixels.pixel(x: 0, y: 0), surface.pixel(x: 0, y: 0))
    assertBits(pixels.pixel(x: 64, y: 66), surface.pixel(x: 64, y: 66))
    XCTAssertEqual(pixels.tileCount, 1)
  }
  func testDecodeBudgetIsSharedAcrossLayersAndMasksBeforeExpansion() throws {
    var surface = try Surface(width: 2, height: 2)
    surface.setPixel(x: 0, y: 0, .white)
    var doc = try CraftDocument(width: 2, height: 2)
    doc.layers[0].content = .raster(surface)
    doc.layers[0].mask = surface
    let data = try NativeArchive.encode(doc)
    XCTAssertThrowsError(try NativeArchive.decode(data, rasterByteLimit: TileArchive.byteCount))
    XCTAssertEqual(try NativeArchive.decode(data, rasterByteLimit: TileArchive.byteCount * 2), doc)
    let legacy = try fixture("native-v6-migration.pcswift")
    XCTAssertThrowsError(try NativeArchive.decode(legacy, rasterByteLimit: TileArchive.byteCount))
  }
  func testPackedRGBAHasIndependentByteLayoutAtTileEdgesAndForSparsePixels() throws {
    for storageDepth in PixelDepth.allCases {
      var surface = try Surface(
        width: 65, height: 67, depth: storageDepth, fill: Pixel(0.2, 0.4, 0.8, 0.3))
      for (x, y) in [(0, 0), (63, 63), (64, 63), (0, 64), (64, 66)] {
        surface.setPixel(x: x, y: y, Pixel(Float(x) / 64, Float(y) / 66, 0.7, 0))
      }
      for depth in PixelDepth.allCases {
        let data = try surface.rgbaData(depth: depth)
        let bytes = depth == .u8 ? 1 : depth == .u16 ? 2 : 4
        XCTAssertEqual(data.count, 65 * 67 * 4 * bytes)
        for y in 0..<67 {
          for x in 0..<65 {
            let pixel = surface.pixel(x: x, y: y)
            let channels = [pixel.r, pixel.g, pixel.b, pixel.a]
            for c in 0..<4 {
              let offset = ((y * 65 + x) * 4 + c) * bytes
              var word: UInt32 = 0
              for b in 0..<bytes { word |= UInt32(data[offset + b]) << (8 * b) }
              let expected: UInt32 =
                depth == .f32
                ? channels[c].bitPattern
                : UInt32((unit(channels[c]) * (depth == .u8 ? 255 : 65535)).rounded())
              XCTAssertEqual(word, expected)
            }
          }
        }
      }
    }
  }
  func testUnknownPackingVersionAndAmbiguousOrInvalidTileKeysReject() throws {
    var surface = try Surface(width: 2, height: 2)
    surface.setPixel(x: 0, y: 0, .white)
    var value = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(surface)) as? [String: Any])
    let original = value
    value["packingVersion"] = 999
    XCTAssertThrowsError(
      try JSONDecoder().decode(Surface.self, from: JSONSerialization.data(withJSONObject: value)))
    value = original
    value["tiles"] = [:] as [String: Any]
    XCTAssertThrowsError(
      try JSONDecoder().decode(Surface.self, from: JSONSerialization.data(withJSONObject: value)))
    value = original
    let encoded = (value["tileData"] as! [String: Any])["0"]!
    for index in ["-1", "1", "00", String(Int.max)] {
      value["tileData"] = [index: encoded]
      XCTAssertThrowsError(
        try JSONDecoder().decode(Surface.self, from: JSONSerialization.data(withJSONObject: value)))
    }
  }
}
