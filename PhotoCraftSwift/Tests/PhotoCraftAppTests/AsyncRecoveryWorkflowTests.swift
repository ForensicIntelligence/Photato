import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class AsyncRecoveryWorkflowTests: XCTestCase {
  @MainActor func fixture() throws -> CraftNSDocument {
    let controller = RecoveryLifecycleTests().controller()
    let document = CraftNSDocument(model: try CraftNSDocument.blankModel(width: 8, height: 5))
    controller.addDocument(document)
    try document.store.executeEditorCommand(.fill(document.store.document.activeLayerID!, .black))
    return document
  }
  func encoder(_ gate: DocumentPersistenceTests.Gate, fails: Bool = false) -> RecoveryEncoder {
    { document, url, context in
      XCTAssertFalse(Thread.isMainThread)
      gate.wait()
      if fails { throw CocoaError(.fileWriteOutOfSpace) }
      try NativeArchive.writeRecovery(document, context: context, to: url)
    }
  }

  @MainActor func testBackgroundSnapshotKeepsCOWPixelsAndLaterEditsUnautosaved() async throws {
    let document = try fixture()
    defer { document.close() }
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    document.recoveryEncoder = encoder(gate)
    let before = document.store.document
    let task = Task { try await document.writeRecoverySnapshot() }
    try await DocumentPersistenceTests().waitFor(gate)
    XCTAssertTrue(document.recoveryWriteBusy)
    XCTAssertFalse(document.canRunFileCommand)
    try document.store.executeEditorCommand(.fill(before.activeLayerID!, .white))
    let latest = document.store.document
    let revision = document.store.revision
    let history = document.store.session.undoStack.count
    gate.release()
    try await task.value
    XCTAssertEqual(try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), before)
    XCTAssertEqual(document.store.document, latest)
    XCTAssertEqual(document.store.revision, revision)
    XCTAssertEqual(document.store.session.undoStack.count, history)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertTrue(document.hasUnautosavedChanges)
    XCTAssertFalse(document.recoveryWriteBusy)
    XCTAssertNil(document.recoveryWrites.current())
    document.recoveryEncoder = NativeRecoveryWriting.write
    try await document.writeRecoverySnapshot()
    XCTAssertEqual(try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), latest)
    XCTAssertFalse(document.hasUnautosavedChanges)
    XCTAssertTrue(document.isDocumentEdited)
  }

  @MainActor func testUndoDuringBackupKeepsNewStateUnautosaved() async throws {
    let document = try fixture()
    defer { document.close() }
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    document.recoveryEncoder = encoder(gate)
    let captured = document.store.document
    let task = Task { try await document.writeRecoverySnapshot() }
    try await DocumentPersistenceTests().waitFor(gate)
    XCTAssertTrue(document.recoveryWriteBusy)
    let undone = await document.store.undo()
    XCTAssertTrue(undone)
    let latest = document.store.document
    gate.release()
    try await task.value
    XCTAssertEqual(
      try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), captured)
    XCTAssertEqual(document.store.document, latest)
    XCTAssertFalse(document.isDocumentEdited)
    XCTAssertTrue(document.hasUnautosavedChanges)
    document.recoveryEncoder = NativeRecoveryWriting.write
    try await document.writeRecoverySnapshot()
    if let snapshot = document.autosavedContentsFileURL {
      XCTAssertEqual(try NativeArchive.read(snapshot), latest)
    }
    XCTAssertFalse(document.hasUnautosavedChanges)
    XCTAssertFalse(document.isDocumentEdited)
  }

  @MainActor func testReadReplacementRejectsUntilBackupFinishes() async throws {
    let document = try fixture()
    defer { document.close() }
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    document.recoveryEncoder = encoder(gate)
    let captured = document.store.document
    let replacement = try CraftNSDocument.blankModel(width: 3, height: 2)
    let bytes = try NativeArchive.encodeChunked(replacement)
    let task = Task { try await document.writeRecoverySnapshot() }
    try await DocumentPersistenceTests().waitFor(gate)
    XCTAssertTrue(document.recoveryWriteBusy)
    XCTAssertThrowsError(try document.read(from: bytes, ofType: CraftNSDocument.nativeType))
    XCTAssertEqual(document.store.document, captured)
    gate.release()
    try await task.value
    try document.read(from: bytes, ofType: CraftNSDocument.nativeType)
    XCTAssertEqual(document.store.document, replacement)
  }

  @MainActor func testCloseWaitsWithoutBlockingThenRemovesRecovery() async throws {
    let document = try fixture()
    let controller = try XCTUnwrap(document.ownerController)
    defer { document.close() }
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    document.recoveryEncoder = encoder(gate)
    let task = Task { try await document.writeRecoverySnapshot() }
    try await DocumentPersistenceTests().waitFor(gate)
    document.close()
    XCTAssertTrue(document.recoveryWriteBusy)
    XCTAssertTrue(controller.documents.contains { $0 === document })
    gate.release()
    try await task.value
    XCTAssertFalse(document.recoveryWriteBusy)
    XCTAssertNil(document.ownerController)
    XCTAssertFalse(controller.documents.contains { $0 === document })
    if let url = document.autosavedContentsFileURL {
      XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
  }

  @MainActor func testAutomaticBackupDefersDuringOtherFileOperation() async throws {
    let document = try fixture()
    defer { document.close() }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    document.fileOperationBusy = true
    let target = folder.appendingPathComponent("must-not-write.photato")
    let error = await withCheckedContinuation { (c: CheckedContinuation<Error?, Never>) in
      document.save(
        to: target, ofType: CraftNSDocument.nativeType, for: .autosaveElsewhereOperation
      ) {
        c.resume(returning: $0)
      }
    }
    document.fileOperationBusy = false
    XCTAssertEqual((error as NSError?)?.code, NSUserCancelledError)
    XCTAssertFalse(document.recoveryWriteBusy)
    XCTAssertFalse(document.lastRecoveryWriteFailed)
    XCTAssertNil(document.recoveryWrites.current())
    XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    try await document.writeRecoverySnapshot()
    XCTAssertNotNil(document.autosavedContentsFileURL)
  }

  @MainActor func testHTTPStateRespondsWhileWorkerRunsAndMutationsReject() async throws {
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, document in
      defer { document.close() }
      let gate = DocumentPersistenceTests.Gate()
      defer { gate.release() }
      document.recoveryEncoder = encoder(gate)
      try document.store.executeEditorCommand(.fill(document.store.document.activeLayerID!, .white))
      try service.share(document)
      let id = try XCTUnwrap(service.shares.first?.id)
      let task = Task { try await api.edit(service, document, "document.autosave") }
      try await DocumentPersistenceTests().waitFor(gate)
      XCTAssertTrue(document.recoveryWriteBusy)
      let response = try await api.request(service, path: "/v1/documents/\(id)")
      XCTAssertEqual(response.0.statusCode, 200)
      let state = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      XCTAssertEqual((state["recovery"] as? [String: Any])?["isWriting"] as? Bool, true)
      let busy = try await api.edit(service, document, "document.autosave")
      XCTAssertEqual(busy, 409)
      let edit = try await api.edit(service, document, "history.undo")
      XCTAssertEqual(edit, 409)
      XCTAssertEqual(AutomationService.recoveryCapabilities["backgroundWriting"] as? Bool, true)
      gate.release()
      let code = try await task.value
      XCTAssertEqual(code, 200)
      XCTAssertEqual(
        try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)),
        document.store.document)
    }
  }

  @MainActor func testHTTPRevocationDoesNotReturnContentAfterBackup() async throws {
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, document in
      defer { document.close() }
      let gate = DocumentPersistenceTests.Gate()
      defer { gate.release() }
      document.recoveryEncoder = encoder(gate)
      try document.store.executeEditorCommand(.fill(document.store.document.activeLayerID!, .white))
      try service.share(document)
      let task = Task { try await api.edit(service, document, "document.autosave") }
      try await DocumentPersistenceTests().waitFor(gate)
      XCTAssertTrue(document.recoveryWriteBusy)
      service.revoke(try XCTUnwrap(service.shares.first?.id))
      gate.release()
      let code = try await task.value
      XCTAssertEqual(code, 409)
      XCTAssertTrue(service.shares.isEmpty)
      XCTAssertFalse(document.recoveryWriteBusy)
      XCTAssertEqual(
        try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)),
        document.store.document)
    }
  }

  @MainActor func testBackgroundFailurePreservesPreviousBackupAndNewerEdits() async throws {
    let document = try fixture()
    defer { document.close() }
    try await document.writeRecoverySnapshot()
    let previous = try XCTUnwrap(document.autosavedContentsFileURL)
    let bytes = try Data(contentsOf: previous)
    let layer = try XCTUnwrap(document.store.document.activeLayerID)
    try document.store.executeEditorCommand(.renameLayer(layer, "Before write"))
    let gate = DocumentPersistenceTests.Gate()
    defer { gate.release() }
    document.recoveryEncoder = encoder(gate, fails: true)
    let task = Task { try await document.writeRecoverySnapshot() }
    try await DocumentPersistenceTests().waitFor(gate)
    XCTAssertTrue(document.recoveryWriteBusy)
    try document.store.executeEditorCommand(.fill(layer, .white))
    let latest = document.store.document
    gate.release()
    do {
      try await task.value
      XCTFail("Expected injected out-of-space failure")
    } catch {
      XCTAssertEqual((error as NSError).code, NSFileWriteOutOfSpaceError)
    }
    XCTAssertEqual(try Data(contentsOf: previous), bytes)
    XCTAssertEqual(document.store.document, latest)
    XCTAssertTrue(document.lastRecoveryWriteFailed)
    XCTAssertTrue(document.hasUnautosavedChanges)
    XCTAssertFalse(document.recoveryWriteBusy)
    XCTAssertNil(document.recoveryWrites.current())
    document.recoveryEncoder = NativeRecoveryWriting.write
    try await document.writeRecoverySnapshot()
    XCTAssertFalse(document.lastRecoveryWriteFailed)
    XCTAssertEqual(try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), latest)
  }
}
