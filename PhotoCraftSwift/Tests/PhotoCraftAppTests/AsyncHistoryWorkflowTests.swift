import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class AsyncHistoryWorkflowTests: XCTestCase {
  /// Hold a completed native preparation before publication, without blocking the main actor.
  func preparer(_ gate: DocumentPersistenceTests.Gate) -> HistoryPreparation {
    { session, redo in
      XCTAssertFalse(Thread.isMainThread)
      let candidate = try NativeHistoryNavigation.prepare(session, redo: redo)
      gate.wait()
      return candidate
    }
  }
  @MainActor func editedDocument(_ gate: DocumentPersistenceTests.Gate) throws -> CraftNSDocument {
    _ = NSApplication.shared
    // Initialize the application's controller before standalone NSDocument.close can
    // implicitly create an AppKit base-class singleton.
    _ = CraftDocumentController()
    let document = CraftNSDocument(
      model: try CraftNSDocument.blankModel(width: 16, height: 8), prepareHistory: preparer(gate))
    document.store.session = EditorSession(document: document.store.document, historyByteLimit: 0)
    try document.store.executeEditorCommand(.opacity(document.store.document.activeLayerID!, 0.5))
    return document
  }

  @MainActor func testNativeWorkerAllowsMainActorAndCancelPreservesDirtyHistoryRevision()
    async throws
  {
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    let document = try editedDocument(gate)
    defer { document.close() }
    let store = document.store
    let edited = store.document
    let revision = store.revision
    let task = store.requestHistory(redo: false)
    try await DocumentPersistenceTests().waitFor(gate)
    XCTAssertTrue(store.geometryBusy)
    XCTAssertNotNil(store.historyOperation)
    XCTAssertFalse(document.canRunFileCommand)
    XCTAssertEqual(store.document, edited)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertThrowsError(try store.executeEditorCommand(.opacity(edited.activeLayerID!, 0.2)))
    let refused = await store.redo()
    XCTAssertFalse(refused)
    store.cancelActiveOperation()
    XCTAssertEqual(store.historyOperation?.cancellationRequested, true)
    gate.release()
    let completed = await task.value
    XCTAssertFalse(completed)
    XCTAssertNil(store.error)
    XCTAssertNil(store.historyOperation)
    XCTAssertFalse(store.geometryBusy)
    XCTAssertEqual(store.document, edited)
    XCTAssertEqual(store.revision, revision)
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertTrue(store.session.redoStack.isEmpty)
    XCTAssertTrue(document.isDocumentEdited)
    let undone = await store.undo()
    XCTAssertTrue(undone)
    XCTAssertFalse(document.isDocumentEdited)
    let redone = await store.redo()
    XCTAssertTrue(redone)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertEqual(store.document, edited)
  }

  @MainActor func testSessionABAEvenWithIdenticalDocumentRejectsPreparedResult() async throws {
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    let document = try editedDocument(gate)
    defer { document.close() }
    let store = document.store
    let original = store.session
    let generation = store.sessionGeneration
    let revision = store.revision
    let task = Task { try await store.navigateHistory(redo: false) }
    try await DocumentPersistenceTests().waitFor(gate)
    // Same value after an intervening write must not resurrect an obsolete history branch.
    store.session = EditorSession(document: original.document)
    store.session = original
    XCTAssertNotEqual(store.sessionGeneration, generation)
    gate.release()
    do {
      _ = try await task.value
      XCTFail("Published stale session")
    } catch {
      XCTAssertTrue(error is HistoryNavigationConflict)
    }
    XCTAssertEqual(store.document, original.document)
    XCTAssertEqual(store.revision, revision)
    XCTAssertEqual(store.session.undoStack.count, original.undoStack.count)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertFalse(store.geometryBusy)
  }

  @MainActor func testReadAndCloseInvalidatePendingHistoryWithoutTouchingReplacement() async throws
  {
    for replace in [false, true] {
      let gate = DocumentPersistenceTests.Gate()
      defer { gate.release() }
      let document = try editedDocument(gate)
      defer { document.close() }
      let store = document.store
      let task = store.requestHistory(redo: false)
      try await DocumentPersistenceTests().waitFor(gate)
      if replace {
        let replacement = try CraftNSDocument.blankModel(width: 3, height: 2, name: "Replacement")
        try document.read(
          from: NativeArchive.encode(replacement), ofType: CraftNSDocument.nativeType)
        XCTAssertEqual(store.document, replacement)
      } else {
        document.close()
      }
      let expected = store.document
      let revision = store.revision
      gate.release()
      let completed = await task.value
      XCTAssertFalse(completed)
      XCTAssertNil(store.error)
      XCTAssertNil(store.historyOperation)
      XCTAssertFalse(store.geometryBusy)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.revision, revision)
    }
  }

  @MainActor func testAwaitingTaskCancellationPropagatesToWorker() async throws {
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    let document = try editedDocument(gate)
    defer { document.close() }
    let store = document.store
    let original = store.document
    let task = Task { try await store.navigateHistory(redo: false) }
    try await DocumentPersistenceTests().waitFor(gate)
    task.cancel()
    gate.release()
    do {
      _ = try await task.value
      XCTFail("Published cancelled worker")
    } catch {
      XCTAssertTrue(error is CancellationError)
    }
    XCTAssertEqual(store.document, original)
    XCTAssertFalse(store.geometryBusy)
    XCTAssertEqual(store.session.undoStack.count, 1)
  }

  @MainActor func testQueuedMenuAndPanelActionsCannotRunAfterReplacementOrClose() async throws {
    for close in [false, true] {
      let gate = DocumentPersistenceTests.Gate()
      gate.release()
      let document = try editedDocument(gate)
      defer { document.close() }
      let store = document.store
      let undo = store.requestHistory(redo: false)
      let panel = store.selectHistoryState(0)
      // Still on this actor turn: neither queued entry point has started.
      if close {
        document.close()
      } else {
        store.session = EditorSession(document: store.document)
      }
      let expected = store.document
      let revision = store.revision
      let result = await undo.value
      await panel.value
      XCTAssertFalse(result)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.revision, revision)
      XCTAssertNil(store.historyOperation)
    }
  }

  @MainActor func testValidationAndRevisionChangeRejectWithoutPublication() async throws {
    for stale in [false, true] {
      let gate = DocumentPersistenceTests.Gate()
      defer { gate.release() }
      let document = try editedDocument(gate)
      defer { document.close() }
      let store = document.store
      let original = store.document
      let task = Task {
        try await store.navigateHistory(
          redo: false,
          validate: { _ in
            if !stale {
              throw AutomationFailure(status: 413, message: "Restored size exceeds limit")
            }
          })
      }
      try await DocumentPersistenceTests().waitFor(gate)
      if stale { store.render() }
      let revision = store.revision
      gate.release()
      do {
        _ = try await task.value
        XCTFail("Published invalid result")
      } catch {
        if stale {
          XCTAssertTrue(error is HistoryNavigationConflict)
        } else {
          XCTAssertEqual((error as? AutomationFailure)?.status, 413)
        }
      }
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(store.revision, revision)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertTrue(document.isDocumentEdited)
      XCTAssertFalse(store.geometryBusy)
    }
  }

  @MainActor func testHTTPCancelIsOperationScopedAndStateRemainsReadableWhileBusy() async throws {
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }, prepareHistory: preparer(gate)) {
      service, document in
      let store = document.store
      store.session = EditorSession(document: store.document, historyByteLimit: 0)
      try store.executeEditorCommand(.opacity(store.document.activeLayerID!, 0.5))
      try service.share(document)
      let original = store.document
      let revision = service.revision(store)
      let task = Task { try await api.edit(service, document, "history.undo") }
      try await DocumentPersistenceTests().waitFor(gate)
      let share = try XCTUnwrap(service.shares.first)
      let response = try await api.request(service, path: "/v1/documents/\(share.id)")
      XCTAssertEqual(response.0.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let operation = try XCTUnwrap(state["historyOperation"] as? [String: Any])
      XCTAssertEqual(operation["active"] as? Bool, true)
      XCTAssertEqual(operation["direction"] as? String, "undo")
      let operationID = try XCTUnwrap(operation["id"] as? String)
      let busy = try await api.edit(service, document, "history.redo")
      XCTAssertEqual(busy, 409)
      for (value, expected) in [("invalid", 400), (UUID().uuidString, 409)] {
        let status = try await api.edit(service, document, "history.cancel", ["operationID": value])
        XCTAssertEqual(status, expected)
        XCTAssertEqual(store.historyOperation?.cancellationRequested, false)
      }
      let stale = try await api.edit(
        service, document, "history.cancel", ["operationID": operationID], revision: "stale")
      XCTAssertEqual(stale, 409)
      let cancelled = try await api.edit(
        service, document, "history.cancel", ["operationID": operationID])
      XCTAssertEqual(cancelled, 200)
      XCTAssertEqual(store.historyOperation?.cancellationRequested, true)
      gate.release()
      let status = try await task.value
      XCTAssertEqual(status, 409)
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(service.revision(store), revision)
      XCTAssertTrue(document.isDocumentEdited)
      XCTAssertNil(store.error)
      XCTAssertNil(store.historyOperation)
      let ended = try await api.edit(
        service, document, "history.cancel", ["operationID": operationID])
      XCTAssertEqual(ended, 409)
      let capabilities = AutomationService.capabilities
      let schemas = try XCTUnwrap(capabilities["stateSchemas"] as? [String: Any])
      let schema = try XCTUnwrap(schemas["historyOperation"] as? [String: Any])
      XCTAssertEqual(Set(try XCTUnwrap(schema["required"] as? [String])), Set(operation.keys))
      XCTAssertTrue(JSONSerialization.isValidJSONObject(capabilities))
    }
  }

  @MainActor func testSharingRevocationCancelsOnlyAPIInitiatedHistory() async throws {
    let api = AutomationTests()
    for native in [false, true] {
      let gate = DocumentPersistenceTests.Gate()
      defer { gate.release() }
      try await api.withService(pressedMouseButtons: { 0 }, prepareHistory: preparer(gate)) {
        service, document in
        let store = document.store
        let original = store.document
        try store.executeEditorCommand(.opacity(original.activeLayerID!, 0.5))
        let edited = store.document
        try service.share(document)
        let shareID = try XCTUnwrap(service.shares.first?.id)
        let task = Task {
          if native { return await store.undo() ? 200 : 409 }
          return try await api.edit(service, document, "history.undo")
        }
        try await DocumentPersistenceTests().waitFor(gate)
        service.revoke(shareID)
        XCTAssertEqual(store.historyOperation?.cancellationRequested, !native)
        gate.release()
        let status = try await task.value
        XCTAssertEqual(status, native ? 200 : 409)
        XCTAssertEqual(store.document, native ? original : edited)
        XCTAssertNil(store.error)
      }
    }
  }
}
