import CryptoKit
import Foundation
import PhotoCraftCore
import XCTest
@testable import PhotoCraftImaging

final class PSDLayerProtectionTests: XCTestCase {
  private struct Manifest: Decodable {
    struct Record: Decodable {
      var file: String
      var sha256: String
      var flagsOffset: Int
      var flags: UInt8
      var protectionOffset: Int
      var protection: UInt32
    }
    var records: [Record]
  }
  private func fixture(_ name: String) throws -> Data {
    let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
      .appendingPathComponent("LayerProtection").appendingPathComponent(name)
    return try Data(contentsOf: url)
  }

  func testIndependentPhotoshopRecordsAndExactReencoding() throws {
    let manifest = try JSONDecoder().decode(Manifest.self, from: fixture("manifest.json"))
    XCTAssertEqual(manifest.records.count, 9)
    for record in manifest.records {
      let data = try fixture(record.file)
      XCTAssertEqual(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
        record.sha256, record.file)
      XCTAssertEqual(data[record.flagsOffset], record.flags)
      let raw = data.subdata(in: record.protectionOffset..<record.protectionOffset+4)
      let decoded = try PSDLayerProtection.decode(layerFlags: record.flags, record: raw)
      XCTAssertEqual(decoded.rawValue, record.protection, record.file)
      XCTAssertEqual(try PSDLayerProtection.encode(decoded), raw, record.file)
      XCTAssertEqual(try PSDLayerProtection.layerFlags(record.flags, protection: decoded),
        record.flags, record.file)
      let document = try PSDCodec.read(data)
      XCTAssertEqual(document.layers.first?.protection.rawValue, record.protection, record.file)
      for format: PSDFileFormat in [.psd, .psb] {
        let encoded = try PSDCodec.writeRasterLayers(document, format: format)
        XCTAssertEqual(try PSDCodec.read(encoded).layers.first?.protection.rawValue,
          record.protection, record.file)
      }
      for order in RasterEncodingOptions.TIFFByteOrder.allCases {
        // Full opaque Photoshop shmd conversion to little-endian TIFF is still
        // explicitly unsupported. Exercise flags on an owned metadata-free model;
        // the big-endian branch additionally preserves the complete source metadata.
        var target = document
        if order == .littleEndian {
          target.sourceMetadata = nil
          for i in target.layers.indices { target.layers[i].sourceTags = nil }
        }
        let bytes = try RasterIO.encoded(target, type: .tiff,
          options: .init(tiffByteOrder: order, tiffLayers: true))
        XCTAssertEqual(try RasterIO.read(bytes).layers.first?.protection.rawValue,
          record.protection, record.file)
      }
    }
  }

  func testNativeProtectedFillMatchesIndependentPhotoshopVisiblePixels() throws {
    let original = try PSDCodec.read(fixture("ps-lock-transparency.psd"))
    let expected = try PSDCodec.read(fixture("ps-lock-transparency-fill-black.psd"))
    var session = EditorSession(document: original)
    try session.execute(.fill(original.layers[0].id, .black))
    guard case .raster(let actual) = session.document.layers[0].content,
      case .raster(let reference) = expected.layers[0].content else { return XCTFail("Missing raster") }
    XCTAssertEqual(actual.width, reference.width)
    XCTAssertEqual(actual.height, reference.height)
    for y in 0..<actual.height { for x in 0..<actual.width {
      let a = actual.pixel(x: x, y: y), b = reference.pixel(x: x, y: y)
      XCTAssertEqual(a.a, b.a)
      if b.a > 0 { XCTAssertEqual(a, b) }
    } }
    try session.undo(); XCTAssertEqual(session.document, original)
  }

  func testLegacyTransparencyFlagIsNotFullProtection() throws {
    let alpha = try PSDLayerProtection.decode(layerFlags: 1, record: nil)
    XCTAssertEqual(alpha, .transparency)
    XCTAssertFalse(alpha.fullyLocks)
    XCTAssertFalse(alpha.locksImage)
    XCTAssertEqual(try PSDLayerProtection.decode(layerFlags: 1,
      record: Data([0, 0, 0, 4])), [.transparency, .position])
    let three = try PSDLayerProtection.decode(layerFlags: 0, record: Data([0, 0, 0, 7]))
    XCTAssertFalse(three.fullyLocks)
    XCTAssertEqual(try PSDLayerProtection.layerFlags(0xfe, protection: .position), 0xfe)
    XCTAssertEqual(try PSDLayerProtection.layerFlags(0xfe, protection: .image), 0xff)
  }

  func testAllKnownBitsAndMalformedOrUnknownRecords() throws {
    for raw in UInt32(0)...15 {
      for high: UInt32 in [0, 0x8000_0000] {
        let protection = LayerProtection(rawValue: raw | high)
        let data = try PSDLayerProtection.encode(protection)
        XCTAssertEqual(try PSDLayerProtection.decode(layerFlags: 0, record: data), protection)
      }
    }
    for length in [0, 1, 2, 3, 5, 8] {
      XCTAssertThrowsError(try PSDLayerProtection.decode(layerFlags: 0,
        record: Data(repeating: 0, count: length)))
    }
    for bit in 4..<31 {
      let protection = LayerProtection(rawValue: 1 << bit)
      XCTAssertThrowsError(try PSDLayerProtection.encode(protection))
      let raw = protection.rawValue
      let bytes = Data([UInt8(truncatingIfNeeded: raw >> 24),
        UInt8(truncatingIfNeeded: raw >> 16), UInt8(truncatingIfNeeded: raw >> 8),
        UInt8(truncatingIfNeeded: raw)])
      XCTAssertThrowsError(try PSDLayerProtection.decode(layerFlags: 0, record: bytes))
      XCTAssertThrowsError(try PSDLayerProtection.layerFlags(0, protection: protection))
    }
  }
}
