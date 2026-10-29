import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AutomationRecentDocumentsTests: XCTestCase {
  func object(_ data: Data) throws -> [String: Any] {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
  }
  @MainActor func testHTTPPermissionSchemaLimitAndClearMatchNativeWithoutExposingPaths() async throws {
    let api = AutomationTests()
    try await api.withService { service, _ in
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let settings = service.controller.recoveryPreferences
      let source = try DocumentOpeningTests().fixture(folder, name: "Private filename.photato")
      settings.remember(source)
      let bytes = try Data(contentsOf: source)
      let denied = try await api.request(service, path: "/v1/recent-documents")
      XCTAssertEqual(denied.0.statusCode, 403)
      XCTAssertFalse(String(decoding: denied.1, as: UTF8.self).contains("Private filename"))
      service.setRecentFilesEnabled(true)
      let response = try await api.request(service, path: "/v1/recent-documents")
      let state = try object(response.1)
      let schema = try XCTUnwrap(AutomationService.recentDocumentsCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      XCTAssertFalse(String(decoding: response.1, as: UTF8.self).contains(folder.path))
      XCTAssertEqual((state["entries"] as? [[String: Any]])?.first?["name"] as? String, "Private filename.photato")
      let limited = try await api.request(service, path: "/v1/recent-documents/limit",
        body: ["revision": settings.recentRevision.uuidString, "limit": 7])
      XCTAssertEqual(limited.0.statusCode, 200)
      XCTAssertEqual(settings.value.recentFileLimit, 7)
      let cleared = try await api.request(service, path: "/v1/recent-documents/clear",
        body: ["revision": settings.recentRevision.uuidString])
      XCTAssertEqual(cleared.0.statusCode, 200)
      XCTAssertTrue(settings.recentDocuments.isEmpty)
      XCTAssertEqual(try Data(contentsOf: source), bytes)
      service.stop()
      XCTAssertFalse(service.recentFilesEnabled)
    }
  }
  @MainActor func testHTTPReopenPreservesDirtyIdentityAndDoesNotShareOrAlterSource() async throws {
    let api = AutomationTests()
    try await api.withService { service, original in
      let c = service.controller, settings = c.recoveryPreferences
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder); for doc in c.documents where doc !== original { doc.close() } }
      let source = try DocumentOpeningTests().fixture(folder)
      let bytes = try Data(contentsOf: source)
      settings.remember(source); let id = try XCTUnwrap(settings.recentDocuments.first?.id)
      service.setRecentFilesEnabled(true)
      let response = try await api.request(service, path: "/v1/recent-documents/open",
        body: ["revision": settings.recentRevision.uuidString, "id": id.uuidString])
      XCTAssertEqual(response.0.statusCode, 202)
      XCTAssertEqual(try object(response.1)["shared"] as? Bool, false)
      await c.documentOpening.waitUntilIdle()
      let doc = try XCTUnwrap(c.document(for: source) as? CraftNSDocument)
      XCTAssertEqual(doc.store.document, try NativeArchive.read(source))
      try doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id, "Dirty"))
      let model = doc.store.document
      let repeated = try await api.request(service, path: "/v1/recent-documents/open",
        body: ["revision": settings.recentRevision.uuidString, "id": id.uuidString])
      XCTAssertEqual(repeated.0.statusCode, 202)
      await c.documentOpening.waitUntilIdle()
      XCTAssertTrue(c.document(for: source) === doc)
      XCTAssertEqual(doc.store.document, model); XCTAssertTrue(doc.isDocumentEdited)
      XCTAssertTrue(service.shares.isEmpty)
      XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
  }
  @MainActor func testOwnOpeningCancellationAndRevocationNeedNoTransferPermission() async throws {
    let api = AutomationTests()
    try await api.withService { service, original in
      let c = service.controller, settings = c.recoveryPreferences
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder); c.documentOpening.reader = PreparedLocalDocument.read }
      let source = try DocumentOpeningTests().fixture(folder)
      settings.remember(source); let entry = try XCTUnwrap(settings.recentDocuments.first)
      for revoke in [false, true] {
        let gate = OpeningGate(); defer { gate.release() }
        c.documentOpening.reader = { url, format in
          gate.wait(); try Task.checkCancellation(); return try PreparedLocalDocument.read(url, format: format)
        }
        service.setRecentFilesEnabled(true)
        let response = try await api.request(service, path: "/v1/recent-documents/open",
          body: ["revision": settings.recentRevision.uuidString, "id": entry.id.uuidString])
        XCTAssertEqual(response.0.statusCode, 202)
        try await DocumentOpeningTests().wait(gate)
        XCTAssertFalse(service.documentTransfersEnabled)
        let id = try XCTUnwrap(c.documentOpening.state?.id)
        if revoke { service.setRecentFilesEnabled(false) }
        else {
          XCTAssertEqual(service.documentOpeningState["canCancel"] as? Bool, true)
          let cancel = try await api.request(service, path: "/v1/document-opening/cancel", body: ["operationID": id.uuidString])
          XCTAssertEqual(cancel.0.statusCode, 200)
        }
        gate.release(); await c.documentOpening.waitUntilIdle()
        XCTAssertEqual(c.documents.count, 1); XCTAssertTrue(c.documents[0] === original)
        XCTAssertTrue(c.documentOpening.state?.cancellationRequested == true)
        XCTAssertNil(service.ownedRecentOpening)
        XCTAssertEqual(settings.recentDocuments, [entry])
      }
    }
  }
  @MainActor func testInvalidStaleBusyRequestsAndLegacyRecoveryUpdatesPreserveLimit() async throws {
    let api = AutomationTests()
    try await api.withService { service, original in
      let c = service.controller, settings = c.recoveryPreferences
      service.setRecentFilesEnabled(true)
      try c.setRecentFileLimit(7, revision: settings.recentRevision)
      for limit in [-1.0, 101, 1.5] {
        let response = try await api.request(service, path: "/v1/recent-documents/limit",
          body: ["revision": settings.recentRevision.uuidString, "limit": limit])
        XCTAssertEqual(response.0.statusCode, 400)
      }
      let extra = try await api.request(service, path: "/v1/recent-documents/clear",
        body: ["revision": settings.recentRevision.uuidString, "path": "/private"])
      XCTAssertEqual(extra.0.statusCode, 400)
      let stale = try await api.request(service, path: "/v1/recent-documents/clear", body: ["revision": UUID().uuidString])
      XCTAssertEqual(stale.0.statusCode, 409)
      let media = try await api.request(service, path: "/v1/recent-documents/clear",
        body: ["revision": settings.recentRevision.uuidString], headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      let missing = try await api.request(service, path: "/v1/recent-documents/open",
        body: ["revision": settings.recentRevision.uuidString, "id": UUID().uuidString])
      XCTAssertEqual(missing.0.statusCode, 404)
      original.fileOperationBusy = true
      let busy = try await api.request(service, path: "/v1/recent-documents/limit",
        body: ["revision": settings.recentRevision.uuidString, "limit": 0])
      original.fileOperationBusy = false
      XCTAssertEqual(busy.0.statusCode, 409)
      service.setPreferenceChangesEnabled(true)
      let legacy = try await api.request(service, path: "/v1/preferences/recovery",
        body: ["revision": settings.revision.uuidString, "enabled": false, "intervalMinutes": 5])
      XCTAssertEqual(legacy.0.statusCode, 200)
      XCTAssertEqual(settings.value.recentFileLimit, 7)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testChangedRecentRevisionDuringReadPreventsPublicationAndMissingFileRemainsListed() async throws {
    let api = AutomationTests()
    try await api.withService { service, original in
      let c = service.controller, settings = c.recoveryPreferences
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder); c.documentOpening.reader = PreparedLocalDocument.read }
      let source = try DocumentOpeningTests().fixture(folder)
      settings.remember(source); var entry = try XCTUnwrap(settings.recentDocuments.first)
      let gate = OpeningGate(); defer { gate.release() }
      c.documentOpening.reader = { url, format in gate.wait(); return try PreparedLocalDocument.read(url, format: format) }
      service.setRecentFilesEnabled(true)
      let response = try await api.request(service, path: "/v1/recent-documents/open",
        body: ["revision": settings.recentRevision.uuidString, "id": entry.id.uuidString])
      XCTAssertEqual(response.0.statusCode, 202)
      try await DocumentOpeningTests().wait(gate)
      try settings.clearRecent(revision: settings.recentRevision)
      gate.release(); await c.documentOpening.waitUntilIdle()
      XCTAssertEqual(c.documents.count, 1); XCTAssertTrue(c.documents[0] === original)
      XCTAssertEqual(c.documentOpening.state?.failed, 1)
      c.documentOpening.reader = PreparedLocalDocument.read
      settings.remember(source); entry = try XCTUnwrap(settings.recentDocuments.first)
      try FileManager.default.removeItem(at: source)
      let missing = try await api.request(service, path: "/v1/recent-documents/open",
        body: ["revision": settings.recentRevision.uuidString, "id": entry.id.uuidString])
      XCTAssertEqual(missing.0.statusCode, 202)
      await c.documentOpening.waitUntilIdle()
      XCTAssertEqual(c.documentOpening.state?.failed, 1)
      XCTAssertNotNil(c.documentOpening.state?.lastError)
      XCTAssertEqual(settings.recentDocuments, [entry])
      let status = try await api.request(service, path: "/v1/document-opening")
      XCTAssertFalse(String(decoding: status.1, as: UTF8.self).contains(source.path))
    }
  }
}
