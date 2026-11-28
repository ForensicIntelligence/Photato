import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class RawDNGWorkflowTests: XCTestCase {
  @MainActor func testAuthenticatedDNGCopyUsesCurrentSettingsAndRetainsOriginalAndHistory() async throws {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Raw")
    let source = try Data(contentsOf: fixtures.appendingPathComponent("raw-with-embedded-xmp.dng"))
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, initial in
      defer { for doc in service.controller.documents where doc !== initial { doc.close() } }
      service.setDocumentTransfersEnabled(true)
      let opened = try await AutomationOpeningTests().upload(service, bytes: source, type: "image/x-adobe-dng")
      XCTAssertEqual(opened.0.statusCode, 201)
      let share = try XCTUnwrap(service.shares.last)
      let document = try XCTUnwrap(share.document)
      let layerID = try XCTUnwrap(document.store.document.layers.first?.id)
      let root = "/v1/documents/\(share.id.uuidString)/smart-objects/\(layerID.uuidString)/"
      let command = try await helper.edit(service, document, "raw.develop", [
        "layerID": layerID.uuidString, "settings": ["adjustments": ["exposure": 1.5]]
      ])
      XCTAssertEqual(command, 200)

      let snapshot = document.store.document
      let revision = service.revision(document.store)
      let history = document.store.historyStateLabels
      let stale = try await helper.request(service, path: root + "source.dng",
        headers: ["X-Photato-Revision": "stale"])
      XCTAssertEqual(stale.0.statusCode, 409)
      let denied = try await helper.request(service, path: root + "source.dng", authenticate: false)
      XCTAssertEqual(denied.0.statusCode, 401)
      let original = try await helper.request(service, path: root + "source")
      XCTAssertEqual(original.1, source)

      let copy = try await helper.request(service, path: root + "source.dng",
        headers: ["X-Photato-Revision": revision])
      XCTAssertEqual(copy.0.statusCode, 200)
      XCTAssertEqual(copy.0.value(forHTTPHeaderField: "Content-Type"), "image/x-adobe-dng")
      XCTAssertEqual(copy.0.value(forHTTPHeaderField: "X-Photato-Revision"), revision)
      XCTAssertEqual(copy.1[8..<source.count], source[8..<source.count])
      let reopened = try RawSourceIO.open(copy.1, fileName: "API Copy.dng")
      XCTAssertEqual(reopened.layers.first?.smartObject?.rawDevelopment?.adjustments.exposure, 1.5)
      XCTAssertEqual(document.store.document, snapshot)
      XCTAssertEqual(service.revision(document.store), revision)
      XCTAssertEqual(document.store.historyStateLabels, history)

      service.setDocumentTransfersEnabled(false)
      let disabled = try await helper.request(service, path: root + "source.dng")
      XCTAssertEqual(disabled.0.statusCode, 403)
    }
  }
}
