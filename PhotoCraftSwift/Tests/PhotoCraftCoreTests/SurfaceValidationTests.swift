import Foundation
import XCTest
@testable import PhotoCraftCore

final class SurfaceValidationTests: XCTestCase {
  private final class HistoryTiles: RasterBlobDecoding {
    var pixels: [Pixel]
    init(_ pixels: [Pixel]) { self.pixels = pixels }
    func bytes(_ digest: String, maximumBytes: Int) throws -> Data { Data() }
    func tile(_ digest: String) throws -> [Pixel] { pixels }
  }
  private func data(_ value: [String: Any]) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
  }
  private func legacy(_ pixels: [[String: Any]]) -> [String: Any] {
    ["width": 1, "height": 1, "depth": PixelDepth.f32.rawValue,
     "defaultPixel": ["r": 0.0, "g": 0.0, "b": 0.0, "a": 0.0],
     "tiles": ["0": pixels], "tilesAreKnownFinite": true]
  }

  func testLegacyDecodeScansEveryComponentAndPaddingDespiteForgedProof() throws {
    let zero: [String: Any] = ["r": 0.0, "g": 0.0, "b": 0.0, "a": 0.0]
    let valid = Array(repeating: zero, count: 4096)
    try PropertyListDecoder().decode(Surface.self, from: data(legacy(valid))).validated()
    for component in ["r", "g", "b", "a"] {
      for invalid in [Double.infinity, -Double.infinity, Double.nan] {
        var pixels = valid
        pixels[4095][component] = invalid // Outside the logical 1x1 image.
        XCTAssertThrowsError(try PropertyListDecoder().decode(Surface.self, from: data(legacy(pixels))))
      }
    }
    XCTAssertThrowsError(try PropertyListDecoder().decode(Surface.self, from: data(legacy(Array(valid.dropLast())))))
  }

  func testHistoryDecodeDoesNotTrustCachedTileProviderOrSerializedProof() throws {
    let clear = Pixel.clear
    let provider = HistoryTiles(Array(repeating: clear, count: 4096))
    let value: [String: Any] = ["width": 1, "height": 1, "depth": PixelDepth.f32.rawValue,
      "defaultSample": TileArchive.encodeSample(clear), "packingVersion": 3,
      "tileData": ["0": "owned-fixture"], "tilesAreKnownFinite": true]
    let decoder = PropertyListDecoder(); decoder.userInfo[.historyTileDecoder] = provider
    let encoded = try data(value)
    let valid = try decoder.decode(Surface.self, from: encoded)
    for bad in [Pixel(.infinity, 0, 0), Pixel(0, .nan, 0), Pixel(0, 0, -.infinity), Pixel(0, 0, 0, .nan)] {
      provider.pixels[4095] = bad
      XCTAssertThrowsError(try decoder.decode(Surface.self, from: encoded))
      try valid.validated() // Provider mutation cannot corrupt the decoded value's COW tiles.
    }
    provider.pixels = [clear]
    XCTAssertThrowsError(try decoder.decode(Surface.self, from: encoded))
  }

  func testPackedDecodeRejectsNonfinitePaddingAndInvalidKeysDespiteForgedProof() throws {
    var original = try Surface(width: 1, height: 1, depth: .f32)
    original.setPixel(x: 0, y: 0, .white)
    var value = try XCTUnwrap(PropertyListSerialization.propertyList(
      from: PropertyListEncoder().encode(original), format: nil) as? [String: Any])
    value["tilesAreKnownFinite"] = true
    let originalTile = try XCTUnwrap(value["tileData"] as? [String: Any])["0"]!
    for key in ["-1", "1", "00"] {
      value["tileData"] = [key: originalTile]
      XCTAssertThrowsError(try PropertyListDecoder().decode(Surface.self, from: data(value)))
    }
    var raw = Data(repeating: 0, count: TileArchive.byteCount + 1)
    let offset = 1 + 4095 * 16 + 12
    raw[offset + 2] = 128; raw[offset + 3] = 127 // Infinity in padding alpha.
    value["tileData"] = ["0": raw]
    XCTAssertThrowsError(try PropertyListDecoder().decode(Surface.self, from: data(value)))
  }

  func testRawFillOverflowAndCopiedInvalidTilesStillReject() throws {
    let source = try Surface(width: 1, height: 1, depth: .f32, colorEncoding: .linearRGB)
    let bad = try source.expanded(to: .init(x: 0, y: 0, width: 2, height: 1),
      fill: Pixel(Float.greatestFiniteMagnitude, 0, 0), preservingFillBits: true)
    XCTAssertThrowsError(try bad.validated())
    let copied = try bad.expanded(to: .init(x: 0, y: 0, width: 3, height: 1), fill: .clear)
    XCTAssertThrowsError(try copied.validated())
    XCTAssertThrowsError(try PropertyListEncoder().encode(copied))
    let cropped = try copied.cropped(to: .init(x: 1, y: 0, width: 1, height: 1))
    XCTAssertThrowsError(try cropped.validated())
    let aligned = try copied.expanded(to: .init(x: -64, y: 0, width: 67, height: 1), fill: .clear)
    XCTAssertThrowsError(try aligned.validated())
    try source.validated()
  }

  func testProofIsNotPartOfEqualityArchivesOrCopyOnWrite() throws {
    let original = try Surface(width: 1, height: 1, depth: .f32, colorEncoding: .linearRGB)
    let invalid = try original.expanded(to: .init(x: 0, y: 0, width: 2, height: 1),
      fill: Pixel(Float.greatestFiniteMagnitude, 0, 0), preservingFillBits: true)
    let copied = try invalid.expanded(to: .init(x: 0, y: 0, width: 3, height: 1), fill: .clear)
    var repaired = copied
    for x in 0..<3 { repaired.setLinearPixel(x: x, y: 0, .clear) }
    try repaired.validated()
    XCTAssertThrowsError(try copied.validated())
    var fresh = try Surface(width: 3, height: 1, depth: .f32, colorEncoding: .linearRGB)
    fresh.setLinearPixel(x: 0, y: 0, .clear)
    XCTAssertEqual(repaired, fresh)
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    let archive = try encoder.encode(repaired)
    XCTAssertEqual(archive, try encoder.encode(fresh))
    XCTAssertFalse(String(decoding: archive, as: UTF8.self).contains("tilesAreKnownFinite"))
    XCTAssertEqual(try JSONDecoder().decode(Surface.self, from: archive), repaired)
  }

  func testCheckedWritesAndRawCopiesKeepExactFiniteSamples() throws {
    for depth in PixelDepth.allCases {
      for encoding in [SurfaceColorEncoding.sRGB, .linearRGB] where encoding == .sRGB || depth == .f32 {
        var surface = try Surface(width: 67, height: 65, depth: depth, colorEncoding: encoding)
        surface.setPixel(x: 0, y: 0, Pixel(.nan, .infinity, -.infinity, .nan))
        surface.setLinearPixel(x: 64, y: 64, Pixel(.infinity, .nan, -.infinity, .nan))
        try surface.mapPixels(in: .init(x: 2, y: 3, width: 2, height: 2)) { _, _, _ in Pixel(-0.0, 0.37, -0.25, 0) }
        try surface.mapStoredPixels { x, y, pixel in x == 1 && y == 1 ? Pixel(0.123, 0.456, 0.789, 0.3) : pixel }
        try surface.validated()
        let saved = try JSONEncoder().encode(surface)
        XCTAssertThrowsError(try surface.mapStoredPixels { _, _, _ in Pixel(.nan, 0, 0) })
        XCTAssertEqual(surface, try JSONDecoder().decode(Surface.self, from: saved))
        for shift in [0, 3, 64] {
          let expanded = try surface.expanded(to: .init(x: -shift, y: -shift, width: 80 + shift, height: 80 + shift),
            fill: Pixel(0.123, 0.456, 0.789, 0.3), preservingFillBits: true)
          try expanded.validated()
          let restored = try expanded.cropped(to: .init(x: shift, y: shift, width: 67, height: 65))
          try restored.validated()
          XCTAssertEqual(try restored.rgbaData(depth: .f32, colorEncoding: encoding),
            try surface.rgbaData(depth: .f32, colorEncoding: encoding))
        }
      }
    }
  }
}
