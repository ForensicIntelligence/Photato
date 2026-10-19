import Foundation
import XCTest

@testable import PhotoCraftCore

final class LinearSurfaceTests: XCTestCase {
  let words: [UInt32] = [
    0, 0x8000_0000, 1, 0x8000_0001, 0x007f_ffff, 0x0080_0000,
    0x3dcc_cccd, 0x3eaa_aaab, 0x3f80_0001, 0xc050_0000, 0x7f7f_ffff,
  ]
  func fixture() throws -> Surface {
    var surface = try Surface(width: words.count, height: 2, depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<2 {
      for x in words.indices {
        let v = Float(bitPattern: words[x])
        surface.setLinearPixel(x: x, y: y, Pixel(v, -v, 0.25, y == 0 ? 0 : 1))
      }
    }
    return surface
  }
  func testLinearStorageEncodedViewsAndIdentityAlphaEditsKeepAllRGBBits() throws {
    var surface = try fixture()
    let before = try surface.rgbaData(depth: .f32, colorEncoding: .linearRGB)
    for y in 0..<2 {
      for x in words.indices {
        let pixel = surface.linearPixel(x: x, y: y)
        XCTAssertEqual(pixel.r.bitPattern, words[x])
        XCTAssertEqual(
          surface.pixel(x: x, y: y).r.bitPattern, SRGBTransfer.encoded(pixel.r).bitPattern)
        let offset = (y * words.count + x) * 16
        let actual = before.withUnsafeBytes {
          UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
        XCTAssertEqual(actual, words[x])
      }
    }
    surface.mapPixels { _, _, pixel in pixel }
    XCTAssertEqual(try surface.rgbaData(depth: .f32, colorEncoding: .linearRGB), before)
    surface.mapPixels { _, _, p in Pixel(p.r, p.g, p.b, 0.5) }
    for x in words.indices {
      XCTAssertEqual(surface.linearPixel(x: x, y: 0).r.bitPattern, words[x])
      XCTAssertEqual(surface.linearPixel(x: x, y: 0).a, 0.5)
    }
  }
  func testCropExpansionNativeArchiveAndHistoryRetainLinearStorage() throws {
    var source = try Surface(width: 65, height: 67, depth: .f32, colorEncoding: .linearRGB)
    let sample = Pixel(Float(bitPattern: 0x3dcc_cccd), Float(bitPattern: 1), -0.0, 0)
    source.setLinearPixel(x: 64, y: 66, sample)
    let cropped = try source.cropped(to: IntRect(x: 63, y: 65, width: 2, height: 2))
    XCTAssertEqual(cropped.colorEncoding, .linearRGB)
    XCTAssertTrue(cropped.linearPixel(x: 1, y: 1).hasSameBits(as: sample))
    let expanded = try cropped.expanded(
      to: IntRect(x: -3, y: -2, width: 7, height: 6), fill: .clear)
    XCTAssertEqual(expanded.colorEncoding, .linearRGB)
    XCTAssertTrue(expanded.linearPixel(x: 4, y: 3).hasSameBits(as: sample))
    var doc = try CraftDocument(width: 65, height: 67, depth: .f32)
    doc.layers[0].content = .raster(source)
    let restored = try NativeArchive.decode(NativeArchive.encode(doc))
    XCTAssertEqual(restored, doc)
    var session = EditorSession(document: doc)
    try session.execute(.opacity(doc.layers[0].id, 0.5))
    session.undo()
    XCTAssertEqual(session.document, doc)
    session.redo()
    guard case .raster(let pixels) = session.document.layers[0].content else { return XCTFail() }
    XCTAssertEqual(
      try pixels.rgbaData(depth: .f32, colorEncoding: .linearRGB),
      try source.rgbaData(depth: .f32, colorEncoding: .linearRGB))
  }
  func testLinearArchiveDeclarationAndInvalidCombinations() throws {
    let source = try fixture()
    let encoded = try PropertyListEncoder().encode(source)
    var fields = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: encoded, format: nil) as? [String: Any])
    XCTAssertEqual(fields["packingVersion"] as? Int, 2)
    XCTAssertEqual(fields["colorEncoding"] as? String, "linearRGB")
    XCTAssertEqual(try PropertyListDecoder().decode(Surface.self, from: encoded), source)
    for (key, value) in [
      ("packingVersion", 1 as Any), ("colorEncoding", "sRGB"), ("depth", "8 bit"),
    ] {
      var invalid = fields
      invalid[key] = value
      let bytes = try PropertyListSerialization.data(
        fromPropertyList: invalid, format: .binary, options: 0)
      XCTAssertThrowsError(try PropertyListDecoder().decode(Surface.self, from: bytes))
    }
    fields.removeValue(forKey: "colorEncoding")
    let missing = try PropertyListSerialization.data(
      fromPropertyList: fields, format: .binary, options: 0)
    XCTAssertThrowsError(try PropertyListDecoder().decode(Surface.self, from: missing))
    XCTAssertThrowsError(try Surface(width: 1, height: 1, colorEncoding: .linearRGB))
    XCTAssertThrowsError(try Surface(width: 1, height: 1).interpretingSamples(as: .linearRGB))
  }
}
