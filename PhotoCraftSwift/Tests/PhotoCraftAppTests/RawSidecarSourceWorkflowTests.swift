import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawSidecarSourceWorkflowTests: XCTestCase {
  @MainActor func testAuthenticatedVendorRAWSettingsSaveCreatesSiblingAndKeepsTheSource() async throws {
    let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Raw/nikon-d70s.nef")
    let original = try Data(contentsOf: fixture)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: folder) }
    let raw = folder.appendingPathComponent("Local.nef")
    let sidecar = folder.appendingPathComponent("Local.xmp")
    try original.write(to: raw)

    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      XCTAssertEqual(DocumentOpenFormat.detect(original), .raw)
      let prepared = try PreparedLocalDocument.read(raw, format: .automatic)
      let document = prepared.makeDocument(url: raw)
      service.controller.addDocument(document)
      defer { document.close() }
      try service.share(document)
      let layer = try XCTUnwrap(document.store.document.activeLayerID)
      let params = ["layerID": layer.uuidString]
      XCTAssertTrue(document.canSaveRawSourceSettings(layerID: layer))
      let denied = try await helper.edit(service, document, "raw.saveSourceSettings", params)
      XCTAssertEqual(denied, 403)
      service.setDocumentSavesEnabled(true)
      let change = try await helper.edit(service, document, "raw.develop", [
        "layerID": layer.uuidString, "settings": ["adjustments": ["exposure": 1.25]]
      ], timeout: 30)
      XCTAssertEqual(change, 200)
      let undo = document.store.historyStateLabels
      let state = document.store.document
      let saved = try await helper.edit(service, document, "raw.saveSourceSettings", params)
      XCTAssertEqual(saved, 200)
      XCTAssertEqual(try Data(contentsOf: raw), original)
      let packet = try Data(contentsOf: sidecar)
      XCTAssertEqual(try CameraRawXMP.read(packet, into: RawDevelopment()).adjustments.exposure, 1.25)
      XCTAssertEqual(document.store.historyStateLabels, undo)
      XCTAssertEqual(document.store.document, state)
    }
  }
}
