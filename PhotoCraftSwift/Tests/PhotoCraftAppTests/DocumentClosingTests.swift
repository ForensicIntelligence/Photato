import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class DocumentClosingTests: XCTestCase {
  @MainActor func controller() -> CraftDocumentController {
    _ = NSApplication.shared
    let result = CraftDocumentController(workspaces: WorkspaceLibrary())
    result.documentClosing.reviewer = nil
    result.documentClosing.saver = nil
    return result
  }
  @MainActor func document(_ controller: CraftDocumentController, name: String = "Close test",
    dirty: Bool = false, visible: Bool = true) throws -> CraftNSDocument
  {
    let doc = CraftNSDocument(model: try EditableLifecycleModel.make(width: 4, height: 3, name: name))
    controller.addDocument(doc)
    if visible { doc.makeWindowControllers() }
    if dirty { try doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id, name + " edited")) }
    return doc
  }
  @MainActor func cleanup(_ c: CraftDocumentController) {
    c.documentClosing.reviewer = nil
    c.documentClosing.saver = nil
    for doc in c.documents { doc.close() }
  }
  @MainActor func run(_ c: CraftDocumentController, _ docs: [CraftNSDocument],
    mode: DocumentCloseMode = .review, scope: DocumentCloseScope = .all,
    retained: CraftNSDocument? = nil) async throws -> DocumentCloseState
  {
    let id = try c.documentClosing.prepare(docs, scope: scope, mode: mode, retained: retained)
    c.documentClosing.start(id)
    await c.documentClosing.task?.value
    return try XCTUnwrap(c.documentClosing.state)
  }
  @MainActor func testCleanDockedFloatingAndHeadlessDocumentsCloseWithoutReview() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, name: "A"), b = try document(c, name: "B")
    let d = try document(c, name: "Headless", visible: false)
    c.documentWindows.float(b)
    c.documentClosing.reviewer = { _, _ in XCTFail("Clean documents need no prompt"); return .init(action: .cancel) }
    let result = try await run(c, [a, b, d])
    XCTAssertEqual(result.phase, .completed)
    XCTAssertEqual(result.closed, 3)
    XCTAssertTrue(c.documents.isEmpty)
    XCTAssertTrue(c.documentWindows.groups.isEmpty)
    XCTAssertFalse(c.documentClosing.isActive)
    XCTAssertNil(a.closeWorkflowID)
  }
  @MainActor func testCloseOthersKeepsExactDocumentInstanceWithSharedModelID() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, name: "A")
    let kept = CraftNSDocument(model: a.store.document)
    c.addDocument(kept); kept.makeWindowControllers()
    let b = try document(c, name: "B")
    c.documentWindows.float(b)
    let expected = kept.store.document
    let result = try await run(c, c.closeTargets(excluding: kept), scope: .others, retained: kept)
    XCTAssertEqual(result.closed, 2)
    XCTAssertEqual(c.documents.count, 1)
    XCTAssertTrue(c.documents.first === kept)
    XCTAssertTrue(c.currentDocument === kept)
    XCTAssertEqual(kept.store.document, expected)
  }
  @MainActor func testCancelAfterFirstAcceptedClosePreservesRemainingModelsAndHistory() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, name: "A", dirty: true)
    let b = try document(c, name: "B", dirty: true)
    let d = try document(c, name: "C", dirty: true)
    let bModel = b.store.document, dModel = d.store.document
    let history = b.store.session.undoStack.count
    var reviewed: [CraftNSDocument] = []
    c.documentClosing.reviewer = { doc, _ in
      reviewed.append(doc)
      return .init(action: doc === a ? .discard : .cancel)
    }
    let result = try await run(c, [a, b, d])
    XCTAssertEqual(result.phase, .cancelled)
    XCTAssertEqual(result.closed, 1)
    XCTAssertEqual(reviewed.count, 2)
    XCTAssertNil(a.ownerController)
    XCTAssertEqual(c.documents.count, 2)
    XCTAssertEqual(b.store.document, bModel)
    XCTAssertEqual(d.store.document, dModel)
    XCTAssertEqual(b.store.session.undoStack.count, history)
    XCTAssertTrue(b.isDocumentEdited)
    XCTAssertNil(b.closeWorkflowID)
  }
  @MainActor func testApplyDiscardToAllReviewsOnceAndRemovesRecoveryBackup() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, name: "A", dirty: true), b = try document(c, name: "B", dirty: true)
    try await a.writeRecoverySnapshot()
    let backup = try XCTUnwrap(a.autosavedContentsFileURL)
    var prompts = 0
    c.documentClosing.reviewer = { _, remaining in
      XCTAssertTrue(remaining); prompts += 1
      return .init(action: .discard, applyToAll: true)
    }
    let result = try await run(c, [a, b])
    XCTAssertEqual(result.phase, .completed)
    XCTAssertEqual(prompts, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
  }
  @MainActor func testNativeSaveDelegatePreservesBytesBeforeClosing() async throws {
    let c = controller(); defer { cleanup(c) }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    var docs: [CraftNSDocument] = [], expected: [(URL, CraftDocument)] = []
    for i in 0..<2 {
      let source = folder.appendingPathComponent("\(i).photato")
      let model = try EditableLifecycleModel.make(width: 3, height: 2)
      try NativeArchive.write(model, to: source)
      let doc = try XCTUnwrap(c.makeDocument(withContentsOf: source, ofType: CraftNSDocument.nativeType) as? CraftNSDocument)
      c.addDocument(doc); doc.makeWindowControllers()
      try doc.store.executeEditorCommand(.renameLayer(model.layers[0].id, "Saved \(i)"))
      docs.append(doc); expected.append((source, doc.store.document))
    }
    var prompts = 0
    c.documentClosing.reviewer = { _, _ in prompts += 1; return .init(action: .save, applyToAll: true) }
    let result = try await run(c, docs)
    XCTAssertEqual(result.phase, .completed)
    XCTAssertEqual(result.closed, 2)
    XCTAssertEqual(prompts, 1)
    for (url, model) in expected {
      XCTAssertEqual(try NativeArchive.read(url), model)
      XCTAssertEqual(try Data(contentsOf: url), try NativeArchive.encodeChunked(model))
    }
  }
  @MainActor func testSaveFailureStopsBatchAndRetainsDirtyDocument() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, dirty: true), b = try document(c, dirty: true)
    let model = a.store.document
    c.documentClosing.saver = { _ in throw CocoaError(.fileWriteOutOfSpace) }
    let result = try await run(c, [a, b], mode: .save)
    XCTAssertEqual(result.phase, .failed)
    XCTAssertEqual(result.closed, 0)
    XCTAssertNotNil(result.error)
    XCTAssertEqual(a.store.document, model)
    XCTAssertTrue(a.isDocumentEdited)
    XCTAssertEqual(c.documents.count, 2)
  }
  @MainActor func testEditsDuringReviewPreventDiscardingChangedContent() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, dirty: true)
    c.documentClosing.reviewer = { doc, _ in
      try! doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id, "Later edit"))
      return .init(action: .discard)
    }
    let result = try await run(c, [a])
    XCTAssertEqual(result.phase, .failed)
    XCTAssertEqual(result.closed, 0)
    XCTAssertEqual(a.store.document.layers[0].name, "Later edit")
    XCTAssertTrue(a.ownerController === c)
  }
  @MainActor func testBusyRecoveryAndOverlappingCloseAreRejectedBeforeMutation() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, dirty: true)
    a.recoveryWriteBusy = true
    XCTAssertThrowsError(try c.documentClosing.prepare([a], scope: .all))
    a.recoveryWriteBusy = false
    let id = try c.documentClosing.prepare([a], scope: .all, mode: .discard)
    XCTAssertThrowsError(try c.documentClosing.prepare([a], scope: .document))
    do { try await a.writeRecoverySnapshot(); XCTFail("Reserved close must block recovery") } catch {}
    XCTAssertNil(a.autosavedContentsFileURL)
    c.documentClosing.cancel(id)
    XCTAssertEqual(c.documentClosing.state?.phase, .cancelled)
    XCTAssertTrue(a.ownerController === c)
    XCTAssertNil(a.closeWorkflowID)
  }
  @MainActor func testRealNativeReviewCanBeCancelledWithoutLosingEdits() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, dirty: true)
    let expected = a.store.document
    let id = try c.documentClosing.prepare([a], scope: .document)
    c.documentClosing.start(id)
    for _ in 0..<100 where a.windowForSheet?.attachedSheet == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertNotNil(a.windowForSheet?.attachedSheet)
    c.documentClosing.cancel(id)
    await c.documentClosing.task?.value
    XCTAssertEqual(c.documentClosing.state?.phase, .cancelled)
    XCTAssertEqual(a.store.document, expected)
    XCTAssertTrue(a.isDocumentEdited)
    XCTAssertTrue(a.ownerController === c)
  }
  @MainActor func testSaveAsCancellationKeepsUnsavedDocumentOpen() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, dirty: true)
    let id = try c.documentClosing.prepare([a], scope: .document, mode: .save)
    c.documentClosing.start(id)
    for _ in 0..<100 where a.closeSavePanel == nil {
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTAssertNotNil(a.closeSavePanel)
    c.documentClosing.cancel(id)
    await c.documentClosing.task?.value
    XCTAssertEqual(c.documentClosing.state?.phase, .cancelled)
    XCTAssertNil(a.fileURL)
    XCTAssertTrue(a.isDocumentEdited)
    XCTAssertTrue(a.ownerController === c)
  }
  @MainActor func testControllerDelegateReceivesExactContextAndSuccess() async throws {
    let c = controller(); defer { cleanup(c) }
    _ = try document(c)
    let probe = CloseCallbackProbe()
    let context = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)
    defer { context.deallocate() }
    c.closeAllDocuments(withDelegate: probe,
      didCloseAllSelector: #selector(CloseCallbackProbe.closed(_:completed:context:)), contextInfo: context)
    await c.documentClosing.task?.value
    XCTAssertTrue(probe.controller === c)
    XCTAssertEqual(probe.completed, true)
    XCTAssertEqual(probe.context, context)
    XCTAssertTrue(c.documents.isEmpty)
  }
  @MainActor func testQuitReviewCancellationAndBusyTerminationKeepDocuments() async throws {
    let app = AppDelegate(workspaces: WorkspaceLibrary())
    let c = app.controller; defer { cleanup(c) }
    let a = try document(c, dirty: true)
    c.documentClosing.reviewer = { _, _ in .init(action: .cancel) }
    let probe = CloseCallbackProbe()
    c.reviewUnsavedDocuments(withAlertTitle: nil, cancellable: true, delegate: probe,
      didReviewAllSelector: #selector(CloseCallbackProbe.closed(_:completed:context:)), contextInfo: nil)
    await c.documentClosing.task?.value
    XCTAssertEqual(probe.completed, false)
    XCTAssertTrue(a.ownerController === c)
    a.fileOperationBusy = true
    XCTAssertEqual(app.applicationShouldTerminate(NSApp), .terminateCancel)
    a.fileOperationBusy = false
    // A new dirty document arriving after AppKit's review must get another review.
    XCTAssertEqual(app.applicationShouldTerminate(NSApp), .terminateCancel)
  }
  @MainActor func testCancellationDuringSaveFinishesWriteButKeepsRemainingDocuments() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, dirty: true), b = try document(c, dirty: true)
    var reachedSave = false
    c.documentClosing.saver = { doc in
      reachedSave = true
      c.documentClosing.cancel(try XCTUnwrap(c.documentClosing.state?.id))
      doc.updateChangeCount(.changeCleared)
      return true
    }
    let result = try await run(c, [a, b], mode: .save)
    XCTAssertTrue(reachedSave)
    XCTAssertEqual(result.phase, .cancelled)
    XCTAssertEqual(result.closed, 0)
    XCTAssertTrue(a.ownerController === c)
    XCTAssertTrue(b.isDocumentEdited)
  }
  @MainActor func testNewDocumentDuringQuitPreventsSuccessfulTermination() async throws {
    let c = controller(); defer { cleanup(c) }
    let a = try document(c, dirty: true)
    c.documentClosing.reviewer = { _, _ in
      _ = try? self.document(c, name: "Arrived during review", dirty: true)
      return .init(action: .discard)
    }
    let result = try await run(c, [a], scope: .quit)
    XCTAssertEqual(result.phase, .failed)
    XCTAssertEqual(result.closed, 1)
    XCTAssertEqual(c.documents.count, 1)
    XCTAssertTrue(c.documents[0].isDocumentEdited)
  }
  @MainActor func testFactoryCloseMenusBindAndValidateWithoutShortcutChanges() throws {
    let menus = PhotoshopMenuTests()
    try menus.withMenus { app, menu in
      let c = app.controller; defer { cleanup(c) }
      let items = menus.allItems(menu)
      let all = try XCTUnwrap(items.first { $0.identifier?.rawValue == "File > Close All" })
      let others = try XCTUnwrap(items.first { $0.identifier?.rawValue == "File > Close Others" })
      XCTAssertEqual(all.action, #selector(AppDelegate.closeAllDocuments))
      XCTAssertEqual(others.action, #selector(AppDelegate.closeOtherDocuments))
      XCTAssertEqual(all.keyEquivalent, "w")
      XCTAssertEqual(others.keyEquivalent, "p")
      XCTAssertEqual(all.keyEquivalentModifierMask, [.command, .option])
      XCTAssertEqual(others.keyEquivalentModifierMask, [.command, .option])
      XCTAssertFalse(app.validateMenuItem(all))
      let a = try document(c)
      XCTAssertTrue(app.validateMenuItem(all))
      XCTAssertFalse(app.validateMenuItem(others))
      _ = try document(c)
      XCTAssertTrue(app.validateMenuItem(others))
      a.recoveryWriteBusy = true
      XCTAssertFalse(app.validateMenuItem(all))
      a.recoveryWriteBusy = false
    }
  }
}

@MainActor private final class CloseCallbackProbe: NSObject {
  var controller: NSDocumentController?
  var completed: Bool?
  var context: UnsafeMutableRawPointer?
  @objc func closed(_ controller: NSDocumentController, completed: Bool, context: UnsafeMutableRawPointer?) {
    self.controller = controller; self.completed = completed; self.context = context
  }
}
