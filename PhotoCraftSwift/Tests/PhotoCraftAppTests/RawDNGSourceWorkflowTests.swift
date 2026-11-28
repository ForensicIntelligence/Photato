import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawDNGSourceWorkflowTests: XCTestCase {
  @MainActor func testAuthenticatedSourceSaveRequiresAssociationPermissionAndCurrentSettings() async throws {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Raw")
    let source = try Data(contentsOf: fixtures.appendingPathComponent("raw-with-embedded-xmp.dng"))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("Local.dng")
    try source.write(to: url)

    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, _ in
      let prepared = try PreparedLocalDocument.read(url, format: .raw)
      let document = prepared.makeDocument(url: url)
      service.controller.addDocument(document)
      defer { document.close() }
      try service.share(document)
      let id = try XCTUnwrap(document.store.document.activeLayerID)
      let parameters = ["layerID": id.uuidString]
      XCTAssertTrue(document.canSaveRawSourceSettings(layerID: id))
      let disabled = try await helper.edit(service, document, "raw.saveSourceSettings", parameters)
      XCTAssertEqual(disabled, 403)
      XCTAssertEqual(try Data(contentsOf: url), source)
      service.setDocumentSavesEnabled(true)

      let edit = try await helper.edit(service, document, "raw.develop", [
        "layerID": id.uuidString, "settings": ["adjustments": ["exposure": 1.75]]
      ])
      XCTAssertEqual(edit, 200)
      let snapshot = document.store.document
      let history = document.store.historyStateLabels
      let saved = try await helper.edit(service, document, "raw.saveSourceSettings", parameters)
      XCTAssertEqual(saved, 200)
      XCTAssertEqual(document.store.document, snapshot)
      XCTAssertEqual(document.store.historyStateLabels, history)
      let reopened = try RawSourceIO.read(url)
      XCTAssertEqual(reopened.layers.first?.smartObject?.rawDevelopment?.adjustments.exposure, 1.75)
      let bytes = try Data(contentsOf: url)
      XCTAssertEqual(bytes[8..<source.count], source[8..<source.count])

      // The editor still embeds its original source. A replacement on disk
      // cannot be overwritten by replaying the prior save command.
      try source.write(to: url, options: .atomic)
      let conflict = try await helper.edit(service, document, "raw.saveSourceSettings", parameters)
      XCTAssertEqual(conflict, 409)
      XCTAssertEqual(try Data(contentsOf: url), source)
    }
  }
}
