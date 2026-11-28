import Foundation
import ImageIO
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RawSidecarSourceTests: XCTestCase {
  private static func fixture() throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("PhotoCraftAppTests/Fixtures/Raw/nikon-d70s.nef"))
  }

  private func withNEF(_ body: (URL, URL, Data) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let raw = folder.appendingPathComponent("Test.nef")
    let bytes = try Self.fixture()
    try bytes.write(to: raw)
    try body(raw, raw.deletingPathExtension().appendingPathExtension("xmp"), bytes)
  }

  func testNikonMosaicUsesFullSensorFromBytesRatherThanTheThumbnail() throws {
    let bytes = try Self.fixture()
    XCTAssertEqual(RawSourceIO.type(bytes), "com.nikon.raw-image")
    let sensor = try RawSourceIO.inspect(bytes)
    XCTAssertEqual(sensor.nativeWidth, 3008)
    XCTAssertEqual(sensor.nativeHeight, 2000)
    let source = try RawSourceIO.open(bytes, fileName: "Nikon without a file grant.nef")
    XCTAssertEqual(source.width * source.height, 3008 * 2000)
    XCTAssertEqual(source.layers.first?.smartObject?.data, bytes)
    XCTAssertEqual(source.layers.first?.smartObject?.mediaType, "image/x-camera-raw")

    // The TIFF fields alone must not admit the Nikon preview as a RAW.
    var thumbnailOnly = bytes
    let rawIFD = 848_660
    let count = Int(bytes[rawIFD]) << 8 | Int(bytes[rawIFD + 1])
    let cfaTag = try XCTUnwrap((0..<count).map { rawIFD + 2 + 12 * $0 }.first { index in
      bytes[index] == 0x82 && bytes[index + 1] == 0x8e
    })
    thumbnailOnly[cfaTag] = 0xfd
    XCTAssertNil(RawSourceIO.type(thumbnailOnly))
  }

  func testCreateAndUpdateSidecarRetainingOriginalSensorAndNativeSettings() throws {
    try withNEF { raw, xmp, bytes in
      let before = try RawSourceIO.prepareLocalSettings(raw)
      let captured = try XCTUnwrap(before.source)
      XCTAssertFalse(captured.savesInsideDNG)
      XCTAssertEqual(captured.sidecarURL, xmp)
      XCTAssertFalse(FileManager.default.fileExists(atPath: xmp.path))
      var settings = try XCTUnwrap(before.document.layers.first?.smartObject?.rawDevelopment)
      settings.adjustments.exposure = 1.25
      settings.exposure = 0.25
      let saved = try captured.save(settings: settings)
      XCTAssertEqual(try Data(contentsOf: raw), bytes)
      let output = try Data(contentsOf: xmp)
      XCTAssertEqual(try CameraRawXMP.read(output, into: RawDevelopment()).adjustments.exposure, 1.25)
      XCTAssertEqual(try RawSourceIO.relatedSettings(for: raw), settings)
      XCTAssertThrowsError(try captured.save(settings: settings)) { error in
        XCTAssertEqual(error as? RawDNGSource.SaveError, .sourceChanged)
      }
      settings.adjustments.exposure = 0.75
      _ = try saved.save(settings: settings)
      XCTAssertEqual(try RawSourceIO.relatedSettings(for: raw), settings)
      XCTAssertEqual(try Data(contentsOf: raw), bytes)
    }
  }

  func testExposureOnlyUpdatePreservesAdobeWhiteBalanceAndProcessVersion() throws {
    try withNEF { raw, xmp, bytes in
      let adobe = Data("""
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            crs:Exposure2012="+1.25" crs:ProcessVersion="11.0" crs:HasSettings="True"
            crs:WhiteBalance="As Shot" crs:Temperature="5600" crs:Tint="+3"
            crs:CameraProfile="Adobe Standard" crs:ToneCurveName2012="Medium Contrast"
            crs:SharpenRadius="+1.0" />
        </rdf:RDF>
      </x:xmpmeta>
      """.utf8)
      try adobe.write(to: xmp)
      let prepared = try RawSourceIO.prepareLocalSettings(raw)
      let captured = try XCTUnwrap(prepared.source)
      var settings = try XCTUnwrap(prepared.document.layers.first?.smartObject?.rawDevelopment)
      XCTAssertNil(settings.temperature)
      XCTAssertEqual(settings.adjustments.exposure, 1.25)
      settings.adjustments.exposure = 1.5
      let saved = try captured.save(settings: settings)
      let packet = try Data(contentsOf: xmp)
      let metadata = try XCTUnwrap(CGImageMetadataCreateFromXMPData(packet as CFData))
      func field(_ name: String) -> String? {
        CGImageMetadataCopyStringValueWithPath(metadata, nil, ("crs:" + name) as CFString) as String?
      }
      XCTAssertEqual(field("Exposure2012"), "1.5")
      XCTAssertEqual(field("ProcessVersion"), "11.0")
      XCTAssertEqual(field("WhiteBalance"), "As Shot")
      XCTAssertEqual(field("Temperature"), "5600")
      XCTAssertEqual(field("Tint"), "+3")
      XCTAssertEqual(field("CameraProfile"), "Adobe Standard")
      XCTAssertEqual(field("ToneCurveName2012"), "Medium Contrast")
      XCTAssertEqual(field("SharpenRadius"), "+1.0")
      XCTAssertNil(field("GrainSize"))
      XCTAssertEqual(try RawSourceIO.relatedSettings(for: raw), settings)

      settings.temperature = 6500
      settings.tint = 2
      _ = try saved.save(settings: settings)
      XCTAssertEqual(try RawSourceIO.relatedSettings(for: raw), settings)
      XCTAssertEqual(try Data(contentsOf: raw), bytes)
    }
  }

  func testMetadataOnlySidecarIsPreservedAndExternalReplacementIsRejected() throws {
    try withNEF { raw, xmp, bytes in
      let descriptive = Data("""
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:creator><rdf:Seq><rdf:li>Photato test author</rdf:li></rdf:Seq></dc:creator>
          </rdf:Description>
        </rdf:RDF>
      </x:xmpmeta>
      """.utf8)
      try descriptive.write(to: xmp)
      let before = try RawSourceIO.prepareLocalSettings(raw)
      let captured = try XCTUnwrap(before.source)
      var settings = try XCTUnwrap(before.document.layers.first?.smartObject?.rawDevelopment)
      settings.adjustments.exposure = 1.25
      let updated = try captured.save(settings: settings)
      XCTAssertTrue(String(decoding: try Data(contentsOf: xmp), as: UTF8.self).contains("Photato test author"))
      let external = Data("Externally replaced sidecar".utf8)
      try external.write(to: xmp, options: .atomic)
      XCTAssertThrowsError(try updated.save(settings: settings)) { error in
        XCTAssertEqual(error as? RawDNGSource.SaveError, .sourceChanged)
      }
      XCTAssertEqual(try Data(contentsOf: xmp), external)
      XCTAssertEqual(try Data(contentsOf: raw), bytes)
    }
  }
}
