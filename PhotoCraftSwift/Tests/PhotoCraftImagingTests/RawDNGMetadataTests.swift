import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RawDNGMetadataTests: XCTestCase {
  private func fixture(_ name: String) throws -> Data {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    return try Data(contentsOf: root.appendingPathComponent("PhotoCraftAppTests/Fixtures/Raw/" + name))
  }

  func testEmbeddedSettingsRetainAllOriginalPayloadBytesAndReopenAsRAW() throws {
    let source = try fixture("raw-with-embedded-xmp.dng")
    var settings = RawDevelopment()
    settings.adjustments["exposure"] = 1.5
    settings.adjustments["contrast"] = 21
    let output = try RawSourceIO.dngWithSettings(source, settings: settings)
    XCTAssertEqual(output.prefix(4), source.prefix(4))
    XCTAssertEqual(output[8..<source.count], source[8..<source.count])
    let tiff = try TIFFContainer(output, metadata: false, additionalTags: [700, 50706])
    let packet = try XCTUnwrap(tiff.root.fields[700]?.data)
    XCTAssertEqual(try CameraRawXMP.read(packet, into: RawDevelopment()), settings)
    let original = try RawSourceIO.inspect(source)
    let reopened = try RawSourceIO.open(output, fileName: "Test.dng")
    XCTAssertEqual(reopened.width, original.nativeWidth)
    XCTAssertEqual(reopened.height, original.nativeHeight)
    XCTAssertEqual(reopened.layers.first?.smartObject?.rawDevelopment?.adjustments, settings.adjustments)
    XCTAssertEqual(reopened.layers.first?.smartObject?.data, output)
  }

  func testMetadataUpdatePreservesUnrelatedFieldsAndClearsPriorCustomWhiteBalance() throws {
    let original = Data("""
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:settings="http://ns.adobe.com/camera-raw-settings/1.0/"
          xmlns:xmp="http://ns.adobe.com/xap/1.0/" settings:WhiteBalance="Custom"
          settings:Temperature="4100" settings:Tint="21" settings:Exposure2012="0.75"
          xmp:Label="Owned fixture metadata"/>
      </rdf:RDF>
    </x:xmpmeta>
    """.utf8)
    var settings = RawDevelopment()
    settings.adjustments["exposure"] = 1.75
    let packet = try CameraRawXMP.write(settings, replacing: original)
    XCTAssertTrue(String(decoding: packet, as: UTF8.self).contains("Owned fixture metadata"))
    XCTAssertEqual(try CameraRawXMP.read(packet, into: RawDevelopment()), settings)
    XCTAssertFalse(String(decoding: packet, as: UTF8.self).contains("4100"))
    XCTAssertThrowsError(try CameraRawXMP.write(settings, replacing: Data("invalid".utf8)))
  }

  func testBigEndianNumericEntryAndFollowingDirectoryAreRetained() throws {
    var source = Data([77, 77, 0, 42, 0, 0, 0, 8, 0, 2])
    source.append(contentsOf: [0xc6, 0x12, 0, 1, 0, 0, 0, 4, 1, 4, 0, 0])
    source.append(contentsOf: [0xf0, 0xff, 0, 4, 0, 0, 0, 1, 0x12, 0x34, 0x56, 0x78])
    source.append(contentsOf: [0, 0, 0, 38, 0, 0, 0, 0, 0, 0])
    let output = try RawSourceIO.dngWithSettings(source, settings: RawDevelopment())
    let tiff = try TIFFContainer(output, metadata: true)
    XCTAssertNotNil(tiff.root.next)
    XCTAssertEqual(tiff.root.fields[0xf0ff]?.data, Data([0x12, 0x34, 0x56, 0x78]))
    XCTAssertNotNil(tiff.root.fields[700])
    XCTAssertEqual(output[8..<source.count], source[8..<source.count])
    source[10] = 0
    XCTAssertThrowsError(try RawSourceIO.dngWithSettings(source, settings: RawDevelopment()))
  }
}
