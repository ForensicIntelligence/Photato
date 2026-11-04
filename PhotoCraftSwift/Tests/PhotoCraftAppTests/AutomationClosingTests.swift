import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class AutomationClosingTests: XCTestCase {
  @MainActor func body(_ service: AutomationService, scope: String = "all", mode: String = "discard")
    -> [String: Any]
  { ["revision": service.documentClosingRevision, "scope": scope, "mode": mode] }
  @MainActor func wait(_ service: AutomationService) async throws {
    for _ in 0..<200 where service.controller.documentClosing.isActive {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertFalse(service.controller.documentClosing.isActive)
  }
  @MainActor func testHTTPPermissionSchemaInvalidBusyAndStaleRequestsDoNotClose() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      let path = "/v1/document-closing"
      let unauthorized = try await api.request(service, path: path, authenticate: false)
      XCTAssertEqual(unauthorized.0.statusCode, 401)
      let read = try await api.request(service, path: path)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: read.1) as? [String: Any])
      let schema = try XCTUnwrap(AutomationService.documentClosingCapabilities["stateSchema"] as? [String: Any])
      XCTAssertEqual(Set(state.keys), Set(schema["required"] as? [String] ?? []))
      XCTAssertEqual(state["openDocuments"] as? Int, 1)
      let denied = try await api.request(service, path: path, body: body(service))
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentClosingEnabled(true)
      for (field, value) in [("mode", "unknown"), ("scope", "window"), ("unknown", "x"), ("revision", "stale")] {
        var invalid = body(service); invalid[field] = value
        let response = try await api.request(service, path: path, body: invalid)
        XCTAssertEqual(response.0.statusCode, field == "revision" ? 409 : 400)
      }
      let media = try await api.request(service, path: path, body: body(service), headers: ["Content-Type": "text/plain"])
      XCTAssertEqual(media.0.statusCode, 415)
      document.fileOperationBusy = true
      let busy = try await api.request(service, path: path, body: body(service))
      document.fileOperationBusy = false
      XCTAssertEqual(busy.0.statusCode, 409)
      XCTAssertTrue(document.ownerController === service.controller)
      XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    }
  }
  @MainActor func testFailedAcceptanceDeliveryCancelsQueuedWork() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      service.setDocumentClosingEnabled(true)
      let request = AutomationRequest(method: "POST", path: "/v1/document-closing",
        headers: ["authorization": "Bearer \(try XCTUnwrap(service.token))", "content-type": "application/json"],
        body: try JSONSerialization.data(withJSONObject: body(service)))
      let response = await service.handle(request)
      XCTAssertEqual(response.status, 202)
      XCTAssertEqual(service.controller.documentClosing.state?.phase, .queued)
      XCTAssertTrue(document.ownerController === service.controller)
      response.didSend?(false)
      XCTAssertEqual(service.controller.documentClosing.state?.phase, .cancelled)
      XCTAssertNil(document.closeWorkflowID)
      XCTAssertTrue(document.ownerController === service.controller)
    }
  }
  @MainActor func testHTTPClosesUnsharedOthersAndPreservesSelectedSharedInstance() async throws {
    let api = AutomationTests()
    try await api.withService { service, kept in
      let c = service.controller
      let a = try DocumentClosingTests().document(c, name: "Unshared A", dirty: true)
      let b = CraftNSDocument(model: kept.store.document)
      c.addDocument(b); b.makeWindowControllers()
      defer { for doc in c.documents where doc !== kept { doc.close() } }
      try service.share(kept)
      let id = try XCTUnwrap(service.shares.first?.id)
      service.setDocumentClosingEnabled(true)
      var request = body(service, scope: "others")
      request["sharedDocumentID"] = id.uuidString
      let expected = kept.store.document
      let response = try await api.request(service, path: "/v1/document-closing", body: request)
      XCTAssertEqual(response.0.statusCode, 202)
      try await wait(service)
      XCTAssertEqual(c.documentClosing.state?.phase, .completed)
      XCTAssertEqual(c.documentClosing.state?.closed, 2)
      XCTAssertEqual(c.documents.count, 1)
      XCTAssertTrue(c.documents.first === kept)
      XCTAssertEqual(kept.store.document, expected)
      XCTAssertNil(a.ownerController)
      XCTAssertNil(b.ownerController)
    }
  }
  @MainActor func testRevocationDuringReviewKeepsModifiedDocumentsOpen() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      let c = service.controller
      defer { c.documentClosing.reviewer = nil }
      try document.store.executeEditorCommand(.renameLayer(document.store.document.layers[0].id, "Modified"))
      c.documentClosing.reviewer = { _, _ in
        service.setDocumentClosingEnabled(false)
        return .init(action: .discard, applyToAll: true)
      }
      service.setDocumentClosingEnabled(true)
      let response = try await api.request(service, path: "/v1/document-closing",
        body: body(service, mode: "review"))
      XCTAssertEqual(response.0.statusCode, 202)
      try await wait(service)
      XCTAssertEqual(c.documentClosing.state?.phase, .cancelled)
      XCTAssertTrue(document.isDocumentEdited)
      XCTAssertTrue(document.ownerController === c)
      XCTAssertFalse(service.documentClosingEnabled)
    }
  }
  @MainActor func testAutomaticSaveRequiresPermissionSharedAssociationAndPreservesExactBytes() async throws {
    let api = AutomationTests()
    try await api.withService { service, unused in
      let c = service.controller
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let url = folder.appendingPathComponent("saved.photato")
      let original = try EditableLifecycleModel.make(width: 3, height: 2)
      try NativeArchive.write(original, to: url)
      let doc = try XCTUnwrap(c.makeDocument(withContentsOf: url, ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
      c.addDocument(doc)
      defer { if doc.ownerController != nil { doc.close() } }
      try doc.store.executeEditorCommand(.renameLayer(original.layers[0].id, "API saved"))
      let expected = doc.store.document
      service.setDocumentClosingEnabled(true)
      let denied = try await api.request(service, path: "/v1/document-closing", body: body(service, mode: "save"))
      XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentSavesEnabled(true)
      let unshared = try await api.request(service, path: "/v1/document-closing", body: body(service, mode: "save"))
      XCTAssertEqual(unshared.0.statusCode, 403)
      try service.share(doc)
      let response = try await api.request(service, path: "/v1/document-closing", body: body(service, mode: "save"))
      XCTAssertEqual(response.0.statusCode, 202)
      try await wait(service)
      XCTAssertEqual(c.documentClosing.state?.phase, .completed)
      XCTAssertEqual(try NativeArchive.read(url), expected)
      XCTAssertEqual(try Data(contentsOf: url), try NativeArchive.encodeChunked(expected))
      XCTAssertNil(doc.ownerController)
      XCTAssertNil(unused.ownerController)
    }
  }
  @MainActor func testHTTPUnsavedAutoSaveRejectsBeforeAnyClose() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      try document.store.executeEditorCommand(.renameLayer(document.store.document.layers[0].id, "Unsaved"))
      try service.share(document)
      service.setDocumentClosingEnabled(true)
      service.setDocumentSavesEnabled(true)
      let response = try await api.request(service, path: "/v1/document-closing", body: body(service, mode: "save"))
      XCTAssertEqual(response.0.statusCode, 409)
      XCTAssertTrue(document.ownerController === service.controller)
      XCTAssertNil(document.fileURL)
    }
  }
  @MainActor func testHTTPQuitRunsOnlyAfterAcceptanceAndSuccessfulClose() async throws {
    let api = AutomationTests()
    var terminations = 0
    try await api.withService(applicationTerminator: { terminations += 1 }) { service, document in
      service.setDocumentClosingEnabled(true)
      let response = try await api.request(service, path: "/v1/document-closing", body: body(service, scope: "quit"))
      XCTAssertEqual(response.0.statusCode, 202)
      try await wait(service)
      XCTAssertEqual(terminations, 1)
      XCTAssertEqual(service.controller.documentClosing.state?.phase, .completed)
      XCTAssertNil(document.ownerController)
      service.stop()
      XCTAssertFalse(service.documentClosingEnabled)
    }
  }
  @MainActor func testQueuedCloseBlocksAPIEditingAndCancelRestoresAvailability() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      try service.share(document)
      service.setDocumentClosingEnabled(true)
      let request = AutomationRequest(method: "POST", path: "/v1/document-closing",
        headers: ["authorization": "Bearer \(try XCTUnwrap(service.token))", "content-type": "application/json"],
        body: try JSONSerialization.data(withJSONObject: body(service)))
      let queued = await service.handle(request)
      XCTAssertEqual(queued.status, 202)
      XCTAssertThrowsError(try service.preflight(document))
      let id = try XCTUnwrap(service.controller.documentClosing.state?.id)
      let wrong = try await api.request(service, path: "/v1/document-closing/cancel",
        body: ["operationID": UUID().uuidString])
      XCTAssertEqual(wrong.0.statusCode, 409)
      let cancelled = try await api.request(service, path: "/v1/document-closing/cancel",
        body: ["operationID": id.uuidString])
      XCTAssertEqual(cancelled.0.statusCode, 200)
      XCTAssertNoThrow(try service.preflight(document))
      queued.didSend?(true)
      XCTAssertEqual(service.controller.documentClosing.state?.phase, .cancelled)
      XCTAssertTrue(document.ownerController === service.controller)
    }
  }
  @MainActor func testHTTPActiveReviewCancellationKeepsDirtyDocument() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      document.makeWindowControllers()
      try document.store.executeEditorCommand(.renameLayer(document.store.document.layers[0].id, "Keep"))
      let expected = document.store.document
      service.setDocumentClosingEnabled(true)
      let response = try await api.request(service, path: "/v1/document-closing",
        body: body(service, mode: "review"))
      XCTAssertEqual(response.0.statusCode, 202)
      for _ in 0..<200 where document.windowForSheet?.attachedSheet == nil {
        try await Task.sleep(for: .milliseconds(10))
      }
      XCTAssertNotNil(document.windowForSheet?.attachedSheet)
      let id = try XCTUnwrap(service.controller.documentClosing.state?.id)
      let cancel = try await api.request(service, path: "/v1/document-closing/cancel",
        body: ["operationID": id.uuidString])
      XCTAssertEqual(cancel.0.statusCode, 200)
      try await wait(service)
      XCTAssertEqual(service.controller.documentClosing.state?.phase, .cancelled)
      XCTAssertEqual(document.store.document, expected)
      XCTAssertTrue(document.isDocumentEdited)
      document.close()
    }
  }
  @MainActor func testNewDocumentDuringAPIReviewStopsBeforeDiscard() async throws {
    let api = AutomationTests()
    try await api.withService { service, document in
      let c = service.controller
      defer {
        c.documentClosing.reviewer = nil
        for doc in c.documents where doc !== document { doc.close() }
      }
      try document.store.executeEditorCommand(.renameLayer(document.store.document.layers[0].id, "Keep"))
      c.documentClosing.reviewer = { _, _ in
        _ = try? DocumentClosingTests().document(c, dirty: true)
        return .init(action: .discard)
      }
      service.setDocumentClosingEnabled(true)
      let response = try await api.request(service, path: "/v1/document-closing",
        body: body(service, mode: "review"))
      XCTAssertEqual(response.0.statusCode, 202)
      try await wait(service)
      XCTAssertEqual(c.documentClosing.state?.phase, .failed)
      XCTAssertEqual(c.documentClosing.state?.closed, 0)
      XCTAssertEqual(c.documents.count, 2)
      XCTAssertTrue(document.isDocumentEdited)
    }
  }
}
