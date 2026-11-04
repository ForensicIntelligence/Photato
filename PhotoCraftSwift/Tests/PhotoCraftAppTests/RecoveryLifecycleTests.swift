import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class RecoveryLifecycleTests: XCTestCase {
  @MainActor func controller() -> CraftDocumentController {
    _ = NSApplication.shared
    return CraftDocumentController(workspaces: WorkspaceLibrary())
  }

  @MainActor func testBackgroundRecoveryPreservesIdentityPixelsAndSupportedPaintHistory() async throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for depth in PixelDepth.allCases {
      let helper = RecoveryIndexTests()
      let index = RecoveryIndexStore(directoryURL: folder.appendingPathComponent(depth.rawValue))
      let controller = helper.controller(index)
      let original = try CraftNSDocument.blankModel(width: 4, height: 3, depth: depth)
      let id = try XCTUnwrap(original.activeLayerID)
      XCTAssertTrue(original.layers[0].isBackground)
      var painted = original
      try Command.fill(id, .black).apply(to: &painted)
      let (context, backup, _) = try helper.seed(index, model: painted)
      let savedBytes = try Data(contentsOf: backup)
      try await controller.discoverIndexedRecovery(display: false)
      let document = try XCTUnwrap(controller.documents.compactMap { $0 as? CraftNSDocument }
        .first { $0.recoveryGroupID == context.recoveryID })
      XCTAssertEqual(document.recoverySnapshotContext?.snapshotID, context.snapshotID)
      defer { document.close() }
      XCTAssertEqual(document.store.document, painted)
      XCTAssertTrue(document.store.document.layers[0].isBackground)
      XCTAssertTrue(document.isDocumentEdited)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      try document.store.executeEditorCommand(.fill(id, .white))
      let afterPaint = document.store.document
      XCTAssertNotEqual(afterPaint, painted)
      XCTAssertTrue(afterPaint.layers[0].isBackground)
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      XCTAssertThrowsError(try document.store.executeEditorCommand(.renameLayer(id, "Invalid rename")))
      XCTAssertEqual(document.store.document, afterPaint)
      XCTAssertEqual(document.store.session.undoStack.count, 1)
      let undone = await document.store.undo()
      XCTAssertTrue(undone)
      XCTAssertEqual(document.store.document, painted)
      let redone = await document.store.redo()
      XCTAssertTrue(redone)
      XCTAssertEqual(document.store.document, afterPaint)
      XCTAssertEqual(try Data(contentsOf: backup), savedBytes)
    }
  }

  @MainActor func testDefaultTimerAndNativeUntitledRecoveryFactory() throws {
    let controller = controller()
    XCTAssertEqual(controller.autosavingDelay, 600)
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let recovery = folder.appendingPathComponent("recovery-snapshot")
    let model = try EditableLifecycleModel.make(
      width: 5, height: 3, depth: .f32, background: Pixel(0.13, 0.27, 0.39, 0.52),
      name: "Recovered unsaved work")
    try NativeArchive.write(model, to: recovery)
    let document = try XCTUnwrap(
      controller.makeDocument(
        for: nil, withContentsOf: recovery, ofType: CraftNSDocument.nativeType)
        as? CraftNSDocument)
    defer { document.close() }
    XCTAssertEqual(document.store.document, model)
    XCTAssertNil(document.fileURL)
    XCTAssertEqual(document.autosavedContentsFileURL, recovery)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertTrue(document.store.session.undoStack.isEmpty)
    XCTAssertEqual(document.persistenceFormat, .native)
  }

  @MainActor func testRecoveryFactoryKeepsOriginalAssociationAndModifiedState() throws {
    let controller = controller()
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for format in DocumentIO.Format.allCases {
      let original = try EditableLifecycleModel.make(width: 4, height: 2)
      let source = folder.appendingPathComponent("original." + format.rawValue)
      let sourceBytes = try DocumentIO.encodeForPersistence(original, format: format)
      try sourceBytes.write(to: source)
      var session = EditorSession(document: original)
      try session.execute(.renameLayer(original.activeLayerID!, "Unsaved edit"))
      let recovery = folder.appendingPathComponent(UUID().uuidString + ".photato")
      try NativeArchive.write(session.document, to: recovery)
      let document = try XCTUnwrap(
        controller.makeDocument(
          for: source, withContentsOf: recovery, ofType: CraftNSDocument.nativeType)
          as? CraftNSDocument)
      XCTAssertEqual(document.store.document, session.document)
      XCTAssertEqual(document.fileURL, source)
      XCTAssertEqual(document.persistenceFormat, format)
      XCTAssertTrue(document.sourceSaveNeedsReview)
      XCTAssertTrue(document.isDocumentEdited)
      XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
      document.close()
    }
  }

  @MainActor func testMissingOrChangedOriginalCannotAuthorizeRecoverySaveBack() throws {
    let controller = controller()
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let recovery = folder.appendingPathComponent("recovery.photato")
    let model = try EditableLifecycleModel.make(width: 3, height: 2)
    try NativeArchive.write(model, to: recovery)
    let source = folder.appendingPathComponent("missing.psb")
    let document = try XCTUnwrap(
      controller.makeDocument(
        for: source, withContentsOf: recovery, ofType: CraftNSDocument.nativeType)
        as? CraftNSDocument)
    defer { document.close() }
    XCTAssertEqual(document.store.document, model)
    XCTAssertEqual(document.persistenceFormat, .psb)
    XCTAssertTrue(document.sourceSaveNeedsReview)
    XCTAssertTrue(document.isDocumentEdited)
    XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
  }

  @MainActor func testCorruptRecoveryRejectsWithoutOpeningOrChangingSource() throws {
    let controller = controller()
    let before = controller.documents.count
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("original.photato")
    let original = try NativeArchive.encodeChunked(EditableLifecycleModel.make(width: 2, height: 2))
    try original.write(to: source)
    let recovery = folder.appendingPathComponent("corrupt.photato")
    try Data(original.prefix(25)).write(to: recovery)
    XCTAssertThrowsError(
      try controller.makeDocument(
        for: source, withContentsOf: recovery, ofType: CraftNSDocument.nativeType))
    XCTAssertEqual(controller.documents.count, before)
    XCTAssertEqual(try Data(contentsOf: source), original)
  }

  @MainActor func testRestorationReturnsTheNativeSharedWorkspaceWindow() async throws {
    let controller = controller()
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let a = try DocumentWorkspaceTests().fixture(controller, name: "Recovered A")
    let b = try DocumentWorkspaceTests().fixture(controller, name: "Recovered B")
    let state = NSKeyedArchiver(requiringSecureCoding: true)
    let restored = try await a.restoreWindow(withIdentifier: .init("recovered"), state: state)
    XCTAssertTrue(restored === controller.documentWindows.group(for: a)?.window)
    XCTAssertTrue(restored === controller.documentWindows.group(for: b)?.window)
    XCTAssertTrue(controller.currentDocument === a)
  }

  @MainActor func testAutomaticRecoveryWriteDoesNotCommitUnfinishedFieldEdits() async throws {
    let controller = controller()
    let document = CraftNSDocument(model: try EditableLifecycleModel.make(width: 4, height: 3))
    controller.addDocument(document)
    defer { document.close() }
    try document.store.executeEditorCommand(
      .renameLayer(document.store.document.activeLayerID!, "Committed name"))
    try await NumericFieldEditingTests().withPositionFields(document: document) { store, _, x, _ in
      _ = try NumericFieldEditingTests().replace(x, with: "17")
      let committed = store.document
      let revision = store.revision
      let history = store.session.undoStack.count
      try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        document.autosave(withImplicitCancellability: false) { error in
          if let error { c.resume(throwing: error) } else { c.resume() }
        }
      }
      XCTAssertNotNil(store.numericEditor)
      XCTAssertEqual(store.document, committed)
      XCTAssertEqual(store.revision, revision)
      XCTAssertEqual(store.session.undoStack.count, history)
      let file = try XCTUnwrap(document.autosavedContentsFileURL)
      XCTAssertEqual(try NativeArchive.read(file), committed)
      store.finishNumericField(cancel: true)
    }
  }

  @MainActor func testAPIAndNativeSnapshotsPreserveExactContentDirtyHistoryAndSource() async throws
  {
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, document in
      let folder = try DocumentPersistenceTests().directory()
      defer { try? FileManager.default.removeItem(at: folder) }
      let source = folder.appendingPathComponent("original.photato")
      let bytes = try NativeArchive.encodeChunked(document.store.document)
      try bytes.write(to: source)
      document.fileURL = source
      let store = document.store
      try store.executeEditorCommand(.opacity(store.document.activeLayerID!, 0.5))
      let revision = service.revision(store)
      let expected = store.document
      let history = store.session.undoStack.count
      try service.share(document)
      let code = try await api.edit(service, document, "document.autosave")
      XCTAssertEqual(code, 200)
      let snapshot = try XCTUnwrap(document.autosavedContentsFileURL)
      XCTAssertEqual(try NativeArchive.read(snapshot), expected)
      XCTAssertEqual(try Data(contentsOf: source), bytes)
      XCTAssertEqual(store.document, expected)
      XCTAssertEqual(service.revision(store), revision)
      XCTAssertEqual(store.session.undoStack.count, history)
      XCTAssertTrue(document.isDocumentEdited)
      XCTAssertFalse(document.hasUnautosavedChanges)
      XCTAssertFalse(document.recoveryWriteBusy)
      let state = document.recoveryState
      XCTAssertEqual(state["enabled"] as? Bool, true)
      XCTAssertEqual(state["intervalSeconds"] as? Double, 600)
      XCTAssertEqual(state["hasSnapshot"] as? Bool, true)
      let schema = AutomationService.recoveryStateSchema
      XCTAssertEqual(Set(try XCTUnwrap(schema["required"] as? [String])), Set(state.keys))
      let stale = try await api.edit(service, document, "document.autosave", revision: "stale")
      XCTAssertEqual(stale, 409)
      document.recoveryWriteBusy = true
      let busy = try await api.edit(service, document, "document.autosave")
      document.recoveryWriteBusy = false
      XCTAssertEqual(busy, 409)
      let undone = await store.undo()
      XCTAssertTrue(undone)
      try store.executeEditorCommand(.renameLayer(store.document.activeLayerID!, "Native backup"))
      try await document.writeRecoverySnapshot()
      XCTAssertEqual(
        try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), store.document)
      XCTAssertEqual(try Data(contentsOf: source), bytes)
    }
  }

  @MainActor func testFailedRecoveryWriteKeepsLastSnapshotAndCanRetry() async throws {
    let controller = controller()
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let document = CraftNSDocument(model: try EditableLifecycleModel.make(width: 3, height: 2))
    controller.addDocument(document)
    defer { document.close() }
    let layer = try XCTUnwrap(document.store.document.activeLayerID)
    try document.store.executeEditorCommand(.renameLayer(layer, "First backup"))
    try await document.writeRecoverySnapshot()
    let snapshot = try XCTUnwrap(document.autosavedContentsFileURL)
    let bytes = try Data(contentsOf: snapshot)
    try document.store.executeEditorCommand(.renameLayer(layer, "Next backup"))
    let expected = document.store.document
    let revision = document.store.revision
    let history = document.store.session.undoStack.count
    let parentFile = folder.appendingPathComponent("not-a-directory")
    try Data([42]).write(to: parentFile)
    let error = await withCheckedContinuation { (c: CheckedContinuation<Error?, Never>) in
      document.save(
        to: parentFile.appendingPathComponent("cannot-write.photato"),
        ofType: CraftNSDocument.nativeType, for: .autosaveElsewhereOperation
      ) { c.resume(returning: $0) }
    }
    XCTAssertNotNil(error)
    XCTAssertTrue(document.lastRecoveryWriteFailed)
    XCTAssertFalse(document.recoveryWriteBusy)
    XCTAssertEqual(try Data(contentsOf: snapshot), bytes)
    XCTAssertEqual(document.store.document, expected)
    XCTAssertEqual(document.store.revision, revision)
    XCTAssertEqual(document.store.session.undoStack.count, history)
    XCTAssertTrue(document.isDocumentEdited)
    try await document.writeRecoverySnapshot()
    XCTAssertFalse(document.lastRecoveryWriteFailed)
    XCTAssertEqual(
      try NativeArchive.read(try XCTUnwrap(document.autosavedContentsFileURL)), expected)
  }

  @MainActor func testRecoveredSourceRequiresSaveAsBeforeOverwriting() async throws {
    let controller = controller()
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("original.photato")
    let recovery = folder.appendingPathComponent("recovery.photato")
    let destination = folder.appendingPathComponent("reviewed.photato")
    let original = try EditableLifecycleModel.make(width: 4, height: 3)
    try NativeArchive.write(original, to: source)
    let originalBytes = try Data(contentsOf: source)
    var edited = EditorSession(document: original)
    try edited.execute(.renameLayer(original.activeLayerID!, "Recovered edit"))
    try NativeArchive.write(edited.document, to: recovery)
    let document = try XCTUnwrap(
      controller.makeDocument(
        for: source, withContentsOf: recovery, ofType: CraftNSDocument.nativeType)
        as? CraftNSDocument)
    controller.addDocument(document)
    defer { document.close() }
    do {
      try await document.persistDocument(to: source, format: .native, operation: .saveOperation)
      XCTFail("Recovery must not silently overwrite the original")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("Save As"))
    }
    XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    XCTAssertEqual(document.store.document, edited.document)
    XCTAssertTrue(document.isDocumentEdited)
    try await document.persistDocument(
      to: destination, format: .native, operation: .saveAsOperation)
    XCTAssertEqual(try Data(contentsOf: source), originalBytes)
    XCTAssertEqual(try NativeArchive.read(destination), edited.document)
    XCTAssertFalse(document.sourceSaveNeedsReview)
    XCTAssertFalse(document.isDocumentEdited)
    XCTAssertEqual(document.fileURL, destination)
  }
}
