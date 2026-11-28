import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawISOAdaptiveTests: XCTestCase {
  private let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Fixtures/Raw/synthetic-bayer.dng")

  // The two EV and contrast endpoints were authored on synthetic sensor data
  // and exported using Adobe Camera Raw 18.1.1's Create ISO adaptive preset.
  private var adaptiveXMP: Data {
    xmp("""
      <rdf:li crs:ISO="1600" crs:Exposure2012="2.00" crs:Contrast2012="11" crs:LuminanceSmoothing="10"/>
      <rdf:li crs:ISO="400" crs:Exposure2012="0.00" crs:Contrast2012="0" crs:LuminanceSmoothing="0"/>
      """)
  }

  private func xmp(_ points: String) -> Data {
    Data("""
      <x:xmpmeta xmlns:x="adobe:ns:meta/">
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
            crs:Exposure2012="2.00" crs:Contrast2012="11" crs:Vibrance="14" crs:LuminanceSmoothing="10">
            <crs:ISODependent><rdf:Seq>\(points)</rdf:Seq></crs:ISODependent>
          </rdf:Description>
        </rdf:RDF>
      </x:xmpmeta>
      """.utf8)
  }

  func testAdaptiveDefaultsUseExifISOStopsAndKeepStandardLoadSettingsFixed() throws {
    let bytes = try Data(contentsOf: fixture)
    let policy = RawDefaults(master: .init(mode: .preset, name: "Light and Detail", xmp: adaptiveXMP))
    try policy.validate()
    let points: [(UInt16?, Float, Float, Float)] = [
      (nil, 2, 11, 10), (200, 0, 0, 0), (400, 0, 0, 0),
      (640, 0.6780719, 3.7293956, 3.3903596), (800, 1, 5.5, 5), (1600, 2, 11, 10), (3200, 2, 11, 10),
    ]
    for (iso, exposure, contrast, noise) in points {
      let source = iso.map { withISO($0, source: bytes) } ?? bytes
      let result = try RawSourceIO.open(source, fileName: "Owned.dng", rawDefaults: policy)
      let object = try XCTUnwrap(result.layers[0].smartObject)
      let development = try XCTUnwrap(object.rawDevelopment)
      XCTAssertEqual(development.adjustments.exposure, exposure, accuracy: 0.00001)
      XCTAssertEqual(development.adjustments.contrast, contrast, accuracy: 0.00001)
      XCTAssertEqual(development.adjustments.noiseLuminance, noise, accuracy: 0.00001)
      XCTAssertEqual(development.adjustments.vibrance, 14)
      XCTAssertTrue(object.data == source)
      if iso == 800 {
        XCTAssertEqual(try RawSourceIO.inspect(source).iso, 800)
        var reference = development
        reference.adjustments.exposure = 1
        reference.adjustments.contrast = 5.5
        reference.adjustments.noiseLuminance = 5
        let explicit = try RawSourceIO.open(source, fileName: "Owned.dng", settings: reference)
        XCTAssertTrue(result.layers[0].content == explicit.layers[0].content)
      }
    }
    let loaded = try CameraRawXMP.read(adaptiveXMP, into: RawDevelopment())
    XCTAssertEqual(loaded.adjustments.exposure, 2)
    XCTAssertEqual(loaded.adjustments.contrast, 11)
  }

  @MainActor func testInvalidAdaptiveDefaultsKeepTheCurrentRevisionAndPolicy() throws {
    let preferences = CameraRawPreferences()
    let valid = RawDefaults(master: .init(mode: .preset, name: "Valid", xmp: adaptiveXMP))
    try preferences.setRawDefaults(valid)
    let revision = preferences.revision
    for invalid in [
      "<rdf:li crs:ISO=\"400\" crs:Exposure2012=\"0\"/><rdf:li crs:ISO=\"400\" crs:Exposure2012=\"1\"/>",
      "<rdf:li crs:ISO=\"0\" crs:Exposure2012=\"0\"/><rdf:li crs:ISO=\"800\" crs:Exposure2012=\"1\"/>",
      "<rdf:li crs:ISO=\"400\" crs:Exposure2012=\"NaN\"/><rdf:li crs:ISO=\"800\" crs:Exposure2012=\"1\"/>",
      "<rdf:li crs:ISO=\"400\" crs:Exposure2012=\"6\"/><rdf:li crs:ISO=\"800\" crs:Exposure2012=\"1\"/>",
      "<rdf:li crs:ISO=\"400\" crs:Exposure2012=\"0\"/>",
    ] {
      let invalidPolicy = RawDefaults(master: .init(mode: .preset, name: "Invalid", xmp: xmp(invalid)))
      XCTAssertThrowsError(try preferences.setRawDefaults(invalidPolicy))
      XCTAssertEqual(preferences.revision, revision)
      XCTAssertEqual(preferences.rawDefaults, valid)
    }
  }

  @MainActor func testAuthorizedRAWUploadCanUseISOAdaptiveDefaultsOrFixedXMP() async throws {
    let raw = withISO(800, source: try Data(contentsOf: fixture))
    let policy = RawDefaults(master: .init(mode: .preset, name: "ISO series", xmp: adaptiveXMP))
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, initial in
      defer { for doc in service.controller.documents where doc !== initial { doc.close() } }
      service.setPhotoshopPreferenceChangesEnabled(true)
      service.setDocumentTransfersEnabled(true)
      let route = AutomationService.cameraRawPreferencesPath
      let state = try await helper.request(service, path: route)
      let initialState = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any])
      let revision = try XCTUnwrap(initialState["revision"] as? String)
      let accepted = try await helper.request(service, path: route, body: ["revision": revision, "rawDefaults": policy.apiState])
      XCTAssertEqual(accepted.0.statusCode, 200, String(decoding: accepted.1, as: UTF8.self))

      let modes: [([String: String], Float)] = [(["X-Photato-Raw-Defaults": "desktop"], 1),
        (["X-Photato-Raw-Defaults": "desktop", "X-Photato-Raw-XMP": adaptiveXMP.base64EncodedString()], 2)]
      for (headers, expected) in modes {
        let imported = try await AutomationOpeningTests().upload(service, bytes: raw, type: "image/x-adobe-dng", headers: headers)
        XCTAssertEqual(imported.0.statusCode, 201, String(decoding: imported.1, as: UTF8.self))
        let share = try XCTUnwrap(service.shares.last)
        let document = try XCTUnwrap(share.document)
        let layer = try XCTUnwrap(document.store.document.layers.first)
        let object = try XCTUnwrap(layer.smartObject)
        XCTAssertEqual(object.rawDevelopment?.adjustments.exposure, expected)
        XCTAssertTrue(object.data == raw)
        let response = try await helper.request(service, path: "/v1/documents/\(share.id)/commands", body: [
          "command": "raw.inspect", "revision": service.revision(document.store),
          "parameters": ["layerID": layer.id.uuidString],
        ])
        XCTAssertEqual(response.0.statusCode, 200)
        let inspected = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
        XCTAssertEqual(inspected["iso"] as? Double, 800)
      }
    }
  }

  // Append an EXIF directory and a relocated copy of the original IFD. Sensor
  // rows and their offsets remain untouched in the generated DNG fixture.
  private func withISO(_ iso: UInt16, source: Data) -> Data {
    var bytes = source
    let directory = source.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))) }
    let count = source.withUnsafeBytes { Int(UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: directory, as: UInt16.self))) }
    func littleEndian<T: FixedWidthInteger>(_ number: T) -> Data {
      withUnsafeBytes(of: number.littleEndian) { Data($0) }
    }
    if !bytes.count.isMultiple(of: 2) { bytes.append(0) }
    let exif = UInt32(bytes.count)
    bytes += littleEndian(UInt16(1))
    bytes += littleEndian(UInt16(34_855)) + littleEndian(UInt16(3)) + littleEndian(UInt32(1)) + littleEndian(UInt32(iso))
    bytes += littleEndian(UInt32(0))
    let relocated = UInt32(bytes.count)
    bytes.replaceSubrange(4..<8, with: littleEndian(relocated))
    bytes += littleEndian(UInt16(count + 1))
    let exifPointer = littleEndian(UInt16(34_665)) + littleEndian(UInt16(4)) + littleEndian(UInt32(1)) + littleEndian(exif)
    var appendedExif = false
    for index in 0..<count {
      let offset = directory + 2 + index * 12
      let tag = source.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
      if !appendedExif, tag > 34_665 { bytes += exifPointer; appendedExif = true }
      bytes += source[offset..<(offset + 12)]
    }
    if !appendedExif { bytes += exifPointer }
    bytes += littleEndian(UInt32(0))
    return bytes
  }
}
