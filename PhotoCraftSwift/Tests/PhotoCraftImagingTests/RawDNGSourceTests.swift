import Foundation
import XCTest
import PhotoCraftCore
@testable import PhotoCraftImaging

final class RawDNGSourceTests: XCTestCase {
  private struct Fixture {
    let url: URL
    let sidecar: URL
    let original: Data
  }

  private func withDNG(_ body: (Fixture) throws -> Void) throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let fixture = root.appendingPathComponent("PhotoCraftAppTests/Fixtures/Raw/raw-with-embedded-xmp.dng")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let dng = directory.appendingPathComponent("Source.dng")
    let original = try Data(contentsOf: fixture)
    try original.write(to: dng)
    try body(Fixture(url: dng, sidecar: directory.appendingPathComponent("Source.xmp"), original: original))
  }

  private func packet(exposure: Float) -> Data {
    Data("""
    <x:xmpmeta xmlns:x="adobe:ns:meta/">
      <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
        <rdf:Description rdf:about="" xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
          xmlns:dc="http://purl.org/dc/elements/1.1/" crs:Exposure2012="\(exposure)">
          <dc:creator><rdf:Seq><rdf:li>Owned sidecar creator</rdf:li></rdf:Seq></dc:creator>
        </rdf:Description>
      </rdf:RDF>
    </x:xmpmeta>
    """.utf8)
  }

  func testSourceSaveWithoutSidecarReopensAndChecksTheCapturedSource() throws {
    try withDNG { fixture in
      let before = try RawSourceIO.prepareLocal(fixture.url)
      let source = try XCTUnwrap(before.dngSource)
      var settings = try XCTUnwrap(before.document.layers.first?.smartObject?.rawDevelopment)
      settings.adjustments.exposure = 1.5
      settings.exposure = 0.25
      settings.boost = 0.75
      settings.adjustments.seed = 42
      _ = try source.save(settings: settings)
      let bytes = try Data(contentsOf: fixture.url)
      XCTAssertEqual(bytes[8..<fixture.original.count], fixture.original[8..<fixture.original.count])
      let after = try RawSourceIO.read(fixture.url)
      XCTAssertEqual(after.layers.first?.smartObject?.rawDevelopment, settings)
      let tiff = try TIFFContainer(bytes, metadata: false, additionalTags: [700])
      let xmp = try XCTUnwrap(tiff.root.fields[700]?.data)
      let portable = try CameraRawXMP.read(xmp, into: RawDevelopment())
      XCTAssertEqual(portable.adjustments.exposure, 1.5)
      XCTAssertEqual(portable.exposure, 0)
      XCTAssertThrowsError(try source.save(settings: settings)) { error in
        XCTAssertEqual(error as? RawDNGSource.SaveError, .sourceChanged)
      }
      XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }
  }

  func testSourceSaveIncorporatesSidecarAndKeepsUnrelatedXMPMetadata() throws {
    try withDNG { fixture in
      let originalSidecar = packet(exposure: 1.25)
      try originalSidecar.write(to: fixture.sidecar)
      let before = try RawSourceIO.prepareLocal(fixture.url)
      let source = try XCTUnwrap(before.dngSource)
      XCTAssertTrue(source.hasSidecar)
      var settings = try XCTUnwrap(before.document.layers.first?.smartObject?.rawDevelopment)
      XCTAssertEqual(settings.adjustments.exposure, 1.25)
      XCTAssertEqual(settings.adjustments.contrast, 0)
      settings.adjustments.exposure = 1.75
      let retired = fixture.sidecar.deletingLastPathComponent().appendingPathComponent("Retired.xmp")
      let committed = try source.save(settings: settings) { try FileManager.default.moveItem(at: $0, to: retired) }
      XCTAssertFalse(committed.hasSidecar)
      XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.sidecar.path))
      XCTAssertEqual(try Data(contentsOf: retired), originalSidecar)
      let output = try Data(contentsOf: fixture.url)
      let tiff = try TIFFContainer(output, metadata: false, additionalTags: [700, 50706])
      let xmp = try XCTUnwrap(tiff.root.fields[700]?.data)
      XCTAssertTrue(String(decoding: xmp, as: UTF8.self).contains("Owned sidecar creator"))
      let reopened = try RawSourceIO.read(fixture.url)
      XCTAssertEqual(reopened.layers.first?.smartObject?.rawDevelopment?.adjustments, settings.adjustments)
      XCTAssertEqual(output[8..<fixture.original.count], fixture.original[8..<fixture.original.count])
    }
  }

  func testRetirementFailureRollsBackTheDNGAndExternalSidecarChangeBlocksWriting() throws {
    struct Refused: Error {}
    try withDNG { fixture in
      let xmp = packet(exposure: 1.25)
      try xmp.write(to: fixture.sidecar)
      let before = try RawSourceIO.prepareLocal(fixture.url)
      let source = try XCTUnwrap(before.dngSource)
      var settings = try XCTUnwrap(before.document.layers.first?.smartObject?.rawDevelopment)
      settings.adjustments.exposure = 1.75
      XCTAssertThrowsError(try source.save(settings: settings) { _ in throw Refused() }) { error in
        XCTAssertTrue(error is Refused)
      }
      XCTAssertEqual(try Data(contentsOf: fixture.url), fixture.original)
      XCTAssertEqual(try Data(contentsOf: fixture.sidecar), xmp)
      let external = packet(exposure: 2.5)
      try external.write(to: fixture.sidecar, options: .atomic)
      XCTAssertThrowsError(try source.save(settings: settings)) { error in
        XCTAssertEqual(error as? RawDNGSource.SaveError, .sourceChanged)
      }
      XCTAssertEqual(try Data(contentsOf: fixture.url), fixture.original)
      XCTAssertEqual(try Data(contentsOf: fixture.sidecar), external)
    }
  }
}
