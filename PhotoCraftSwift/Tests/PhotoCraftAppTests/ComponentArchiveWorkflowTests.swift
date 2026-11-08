import AppKit
import XCTest
import PhotoCraftCore
@testable import PhotoCraft

final class ComponentArchiveWorkflowTests: XCTestCase {
  @MainActor func testNative86HTTPDownloadImportAndRevisionGuards() async throws {
    let helper = AutomationTests(), files = DocumentIOWorkflowTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      try service.share(document); service.setDocumentTransfersEnabled(true)
      try document.store.executeEditorCommand(.documentMode(.init(mode: .cmyk, depth: .u16)))
      let original = document.store.document, share = try XCTUnwrap(service.shares.first)
      let path = "/v1/documents/\(share.id)/file.photato"
      let stale = try await files.request(service, path: path, headers: ["X-Photato-Archive-Version": "86", "X-Photato-Revision": "stale"])
      XCTAssertEqual(stale.0.statusCode, 409)
      let saved = try await files.request(service, path: path, headers: ["X-Photato-Archive-Version": "86"])
      XCTAssertEqual(saved.0.statusCode, 200, String(decoding: saved.1, as: UTF8.self))
      XCTAssertEqual(try NativeArchive.decodePaged(saved.1), original)
      let imported = try await files.request(service, path: "/v1/documents/import", data: saved.1, type: "application/vnd.photato.document")
      XCTAssertEqual(imported.0.statusCode, 201)
      let reopened = try XCTUnwrap(service.controller.documents.compactMap { $0 as? CraftNSDocument }.first { $0 !== document })
      defer { reopened.store.renderTask?.cancel(); reopened.updateChangeCount(.changeCleared); reopened.close() }
      XCTAssertEqual(reopened.store.document, original)
      let archives = try XCTUnwrap(AutomationService.documentTransferCapabilities["nativeArchives"] as? [String: Any])
      XCTAssertEqual(archives["readVersions"] as? [Int], Array(1...89)); XCTAssertEqual(archives["componentPageVersion"] as? Int, 86)
      let input = try XCTUnwrap(RasterStorageAPI.capabilities["nativePagedInput"] as? [String: Any])
      XCTAssertEqual(input["componentApplicationMaximumPixels"] as? Int, 90_000_000_000)
      XCTAssertEqual(input["componentPageLeafEntries"] as? Int, 1024)
      service.setDocumentTransfersEnabled(false)
      let revoked = try await files.request(service, path: path, headers: ["X-Photato-Archive-Version": "86"])
      XCTAssertEqual(revoked.0.statusCode, 403)
    }
  }
}
