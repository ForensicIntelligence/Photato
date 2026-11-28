import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawSidecarWorkflowTests: XCTestCase {
  private let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Raw")

  private func bytes(_ name: String) throws -> Data {
    try Data(contentsOf: fixtures.appendingPathComponent(name))
  }

  func testLocalRawOpenUsesSidecarBeforeEmbeddedSettingsWithOriginalBytesIntact() throws {
    let original = try bytes("raw-with-embedded-xmp.dng")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let rawURL = directory.appendingPathComponent("Proof.dng")
    let xmpURL = directory.appendingPathComponent("Proof.xmp")
    try original.write(to: rawURL)
    let originalDocument = try PreparedLocalDocument.read(rawURL, format: .raw)
    XCTAssertNil(originalDocument.format)
    let embedded = try XCTUnwrap(originalDocument.model.layers[0].smartObject?.rawDevelopment)
    XCTAssertEqual(embedded.adjustments.exposure, 0.75)
    XCTAssertEqual(embedded.adjustments.contrast, 21)
    XCTAssertEqual(embedded.adjustments.highlights, -17)
    XCTAssertEqual(embedded.adjustments.vibrance, 9)

    let packet = try bytes("camera-raw-sidecar-override.xmp")
    try packet.write(to: xmpURL)
    let opened = try PreparedLocalDocument.read(rawURL, format: .automatic).model
    let layer = try XCTUnwrap(opened.layers.first)
    let object = try XCTUnwrap(layer.smartObject)
    let sidecar = try XCTUnwrap(object.rawDevelopment)
    XCTAssertEqual(sidecar.adjustments.exposure, 1.25)
    XCTAssertEqual(sidecar.adjustments.contrast, 0)
    XCTAssertEqual(sidecar.adjustments.highlights, 0)
    XCTAssertEqual(sidecar.adjustments.vibrance, 0)
    XCTAssertEqual(object.data, original)
    XCTAssertNotEqual(layer.content, originalDocument.model.layers[0].content)
    XCTAssertEqual(try NativeArchive.decode(NativeArchive.encode(opened)), opened)
    XCTAssertEqual(try SmartObjectIO.sourceDocument(object).layers[0].content, layer.content)
    XCTAssertEqual(try Data(contentsOf: xmpURL), packet)
    XCTAssertEqual(try Data(contentsOf: rawURL), original)

    try Data("invalid XMP".utf8).write(to: xmpURL, options: .atomic)
    let fallback = try PreparedLocalDocument.read(rawURL, format: .raw).model
    XCTAssertEqual(fallback.layers[0].smartObject?.rawDevelopment, embedded)
  }

  func testEmbeddedRawSourceUsesMatchingSiblingWithoutApplyingUnrelatedXMP() throws {
    let original = try bytes("synthetic-bayer.dng")
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let raw = directory.appendingPathComponent("Coat.dng")
    try original.write(to: raw)
    let packet = try bytes("camera-raw-source-settings.xmp")
    try packet.write(to: directory.appendingPathComponent("Another.xmp"))
    let unconfigured = try XCTUnwrap(PreparedEmbeddedSource.read(raw).document)
    XCTAssertEqual(unconfigured.layers[0].smartObject?.rawDevelopment?.adjustments.exposure, 0)
    try packet.write(to: directory.appendingPathComponent("Coat.XMP"))
    let configured = try PreparedEmbeddedSource.read(raw)
    let decoded = try XCTUnwrap(configured.document)
    XCTAssertEqual(configured.data, original)
    XCTAssertEqual(decoded.layers[0].smartObject?.rawDevelopment?.adjustments.exposure, 0.75)
    XCTAssertNotEqual(decoded.layers[0].content, unconfigured.layers[0].content)
  }

  @MainActor func testAuthenticatedRawImportAcceptsXMPAndRejectsMismatchedOrInvalidSidecars() async throws {
    let source = try bytes("raw-with-embedded-xmp.dng")
    let xmp = try bytes("camera-raw-sidecar-override.xmp")
    let headers = ["X-Photato-Raw-XMP": xmp.base64EncodedString()]
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, original in
      defer { for doc in service.controller.documents where doc !== original { doc.close() } }
      service.setDocumentTransfersEnabled(true)
      let upload = AutomationOpeningTests()
      let mismatch = try await upload.upload(service, bytes: source, type: "image/png", headers: headers)
      XCTAssertEqual(mismatch.0.statusCode, 415)
      let bad = try await upload.upload(service, bytes: source, type: "image/x-adobe-dng",
        headers: ["X-Photato-Raw-XMP": "not base64"])
      XCTAssertEqual(bad.0.statusCode, 400)
      XCTAssertTrue(service.shares.isEmpty)
      let ordinary = try await upload.upload(service, bytes: source, type: "image/x-adobe-dng")
      XCTAssertEqual(ordinary.0.statusCode, 201, String(decoding: ordinary.1, as: UTF8.self))
      let embedded = try XCTUnwrap(service.shares.last?.document)
      XCTAssertEqual(embedded.store.document.layers[0].smartObject?.rawDevelopment?.adjustments.contrast, 21)
      let result = try await upload.upload(service, bytes: source, type: "application/octet-stream", format: "raw", headers: headers)
      XCTAssertEqual(result.0.statusCode, 201, String(decoding: result.1, as: UTF8.self))
      let doc = try XCTUnwrap(service.shares.last?.document)
      let object = try XCTUnwrap(doc.store.document.layers[0].smartObject)
      XCTAssertEqual(object.rawDevelopment?.adjustments.exposure, 1.25)
      XCTAssertEqual(object.rawDevelopment?.adjustments.contrast, 0)
      XCTAssertEqual(object.data, source)
    }
  }
}
