import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class DocumentPersistenceTests: XCTestCase {
  final class Gate: @unchecked Sendable {
    private let lock = NSCondition()
    private var started = false
    private var released = false
    var entered: Bool {
      lock.lock()
      defer { lock.unlock() }
      return started
    }
    func wait() {
      lock.lock()
      defer { lock.unlock() }
      started = true
      while !released {
        if !lock.wait(until: Date().addingTimeInterval(5)) { break }
      }
    }
    func release() {
      lock.lock()
      released = true
      lock.broadcast()
      lock.unlock()
    }
  }
  func directory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
  @MainActor func waitFor(_ gate: Gate) async throws {
    for _ in 0..<100 where !gate.entered { try await Task.sleep(for: .milliseconds(10)) }
    XCTAssertTrue(gate.entered)
  }
  @MainActor func model() throws -> CraftDocument {
    try CraftNSDocument.blankModel(width: 5, height: 3, background: Pixel(0.2, 0.4, 0.8, 1))
  }
  @MainActor func testCopyAllFormatsMatchesHTTPDownloadAndKeepsDocumentOwnershipAndHistory()
    async throws
  {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = folder.appendingPathComponent("original.pcswift")
      let original = try NativeArchive.encode(doc.store.document)
      try original.write(to: source)
      doc.fileURL = source
      try doc.store.executeEditorCommand(
        .opacity(try XCTUnwrap(doc.store.document.activeLayerID), 0.5))
      let snapshot = doc.store.document
      service.setDocumentTransfersEnabled(true)
      try service.share(doc)
      let id = try XCTUnwrap(service.shares.first?.id)
      for format in DocumentIO.Format.allCases {
        let target = folder.appendingPathComponent("copy." + format.rawValue)
        try await doc.copyDocument(to: target, format: format)
        let reply = try await AutomationTests().request(
          service, path: "/v1/documents/\(id)/file.\(format.rawValue)",
          headers: format == .native ? ["X-Photato-Archive-Version": "11"] : [:])
        XCTAssertEqual(reply.0.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: target), reply.1)
        XCTAssertEqual(doc.store.document, snapshot)
        XCTAssertEqual(doc.fileURL, source)
        XCTAssertEqual(doc.fileType, CraftNSDocument.nativeType)
        XCTAssertTrue(doc.isDocumentEdited)
        XCTAssertEqual(doc.store.session.undoStack.count, 1)
        XCTAssertTrue(doc.store.session.redoStack.isEmpty)
        XCTAssertFalse(doc.fileOperationBusy)
      }
      XCTAssertEqual(try Data(contentsOf: source), original)
      await doc.store.undo()
      await doc.store.redo()
      XCTAssertEqual(doc.store.document, snapshot)
    }
  }
  @MainActor func testCopyRefusesOriginalAliasesAndFailedEncoderPreservesDestination() async throws
  {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let doc = CraftNSDocument(model: try model())
    defer { doc.store.renderTask?.cancel() }
    let source = folder.appendingPathComponent("source.pcswift")
    let original = try NativeArchive.encode(doc.store.document)
    try original.write(to: source)
    doc.fileURL = source
    let symbolic = folder.appendingPathComponent("symlink.pcswift")
    try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: source)
    let hard = folder.appendingPathComponent("hardlink.pcswift")
    try FileManager.default.linkItem(at: source, to: hard)
    for target in [source, symbolic, hard] {
      do {
        try await doc.copyDocument(to: target, format: .native)
        XCTFail("Overwrote original")
      } catch { XCTAssertTrue(error.localizedDescription.contains("different file")) }
    }
    let target = folder.appendingPathComponent("existing.png")
    try Data("keep".utf8).write(to: target)
    do {
      try await doc.copyDocument(to: target, format: .png) { _, _ in
        throw CraftError.invalid("encoder failed")
      }
      XCTFail("Expected encoder failure")
    } catch { XCTAssertTrue(error.localizedDescription.contains("encoder failed")) }
    XCTAssertEqual(try Data(contentsOf: source), original)
    XCTAssertEqual(try Data(contentsOf: target), Data("keep".utf8))
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertFalse(doc.fileOperationBusy)
  }
  @MainActor func testCopyCancellationAndStaleResultNeverWrite() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let doc = CraftNSDocument(model: try model())
    defer { doc.store.renderTask?.cancel() }
    for cancel in [false, true] {
      let gate = Gate()
      let target = folder.appendingPathComponent("copy-\(cancel).pcswift")
      let task = Task {
        try await doc.copyDocument(to: target, format: .native) { model, format in
          gate.wait()
          return try DocumentIO.encode(model, format: format)
        }
      }
      try await waitFor(gate)
      XCTAssertFalse(doc.canRunFileCommand)
      if cancel {
        task.cancel()
      } else {
        try doc.store.executeEditorCommand(
          .opacity(try XCTUnwrap(doc.store.document.activeLayerID), 0.4))
      }
      gate.release()
      do {
        try await task.value
        XCTFail("Expected stale/cancelled copy")
      } catch {}
      XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
      XCTAssertFalse(doc.fileOperationBusy)
    }
  }
  @MainActor func testRecoveryAutosaveDoesNotReplaceExplicitSaveAndConfirmedCopyCanReplace()
    async throws
  {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let doc = CraftNSDocument(model: try model())
    defer {
      doc.store.renderTask?.cancel()
      doc.updateChangeCount(.changeCleared)
      doc.close()
    }
    let source = folder.appendingPathComponent("saved.pcswift")
    let bytes = try NativeArchive.encode(doc.store.document)
    try bytes.write(to: source)
    doc.fileURL = source
    try doc.store.executeEditorCommand(
      .opacity(try XCTUnwrap(doc.store.document.activeLayerID), 0.2))
    let edited = doc.store.document
    XCTAssertFalse(CraftNSDocument.autosavesInPlace)
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      doc.autosave(withImplicitCancellability: false) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    XCTAssertTrue(doc.isDocumentEdited)
    try await doc.revertDocument()
    await doc.store.undo()
    XCTAssertEqual(doc.store.document, edited)
    // The native Save panel provides the replace confirmation before passing this flag.
    try await doc.copyDocument(to: source, format: .native, allowReplacingSource: true)
    XCTAssertEqual(try NativeArchive.decode(Data(contentsOf: source)), edited)
    XCTAssertTrue(doc.isDocumentEdited)
    XCTAssertEqual(doc.fileURL, source)
  }
  @MainActor func testExplicitSaveRefreshesWorkspaceDirtyPresentation() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let doc = try DocumentWorkspaceTests().fixture(controller, name: "Save state")
    let source = folder.appendingPathComponent("saved.pcswift")
    try NativeArchive.encode(doc.store.document).write(to: source)
    doc.fileURL = source
    await Task.yield()
    let group = try XCTUnwrap(controller.documentWindows.current)
    try doc.store.executeEditorCommand(.opacity(doc.store.document.layers[0].id, 0.75))
    XCTAssertTrue(group.window?.isDocumentEdited == true)
    let content = try XCTUnwrap(group.window?.contentView)
    func tabs(_ view: NSView) -> [DocumentTabButton] {
      (view as? DocumentTabButton).map { [$0] } ?? view.subviews.flatMap(tabs)
    }
    content.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    let tab = try XCTUnwrap(tabs(content).first { $0.documentID == doc.store.identity.uuidString })
    XCTAssertTrue(tab.title.hasSuffix(" *"))
    let revision = group.workspace.revision
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      doc.save(to: source, ofType: CraftNSDocument.nativeType, for: .saveOperation) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
    XCTAssertEqual(try NativeArchive.decode(Data(contentsOf: source)), doc.store.document)
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertTrue(group.window?.isDocumentEdited == false)
    XCTAssertGreaterThan(group.workspace.revision, revision)
    content.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertFalse(tab.title.hasSuffix(" *"))
    await doc.store.undo()
    XCTAssertTrue(group.window?.isDocumentEdited == true)
    await doc.store.redo()
    XCTAssertTrue(group.window?.isDocumentEdited == false)
  }
  @MainActor func testRevertReloadsDiskPreservesIdentityAndSupportsUndoRedoAndCleanState()
    async throws
  {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let original = try model()
    let doc = CraftNSDocument(model: original)
    defer { doc.store.renderTask?.cancel() }
    let source = folder.appendingPathComponent("saved.pcswift")
    doc.fileURL = source
    var saved = original
    saved.id = UUID()
    saved.layers[0].name = "Saved externally"
    try NativeArchive.encode(saved).write(to: source)
    try doc.store.executeEditorCommand(.opacity(original.layers[0].id, 0.25))
    let edited = doc.store.document
    try await doc.revertDocument()
    saved.id = original.id
    XCTAssertEqual(doc.store.document, saved)
    XCTAssertEqual(doc.store.session.undoStack.map(\.label), ["Layer Opacity", "Revert"])
    XCTAssertFalse(doc.isDocumentEdited)
    await doc.store.undo()
    XCTAssertEqual(doc.store.document, edited)
    XCTAssertTrue(doc.isDocumentEdited)
    await doc.store.redo()
    XCTAssertEqual(doc.store.document, saved)
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertEqual(doc.fileURL, source)
    XCTAssertFalse(doc.fileOperationBusy)
  }
  @MainActor func testRevertImportedPNGAndFailuresDoNotDestroyEdits() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("source.png")
    try DocumentIO.encode(model(), format: .png).write(to: source)
    let imported = try DocumentIO.read(source)
    let doc = CraftNSDocument(model: imported)
    defer { doc.store.renderTask?.cancel() }
    doc.importedSourceURL = source
    try doc.store.executeEditorCommand(.opacity(imported.layers[0].id, 0.3))
    let edited = doc.store.document
    try await doc.revertDocument()
    XCTAssertEqual(doc.store.document.layers[0].opacity, 1)
    XCTAssertEqual(doc.store.document.id, imported.id)
    XCTAssertNil(doc.fileURL)
    XCTAssertEqual(doc.importedSourceURL, source)
    await doc.store.undo()
    XCTAssertEqual(doc.store.document, edited)
    let history = doc.store.session.undoStack.count
    try Data("invalid".utf8).write(to: source)
    do {
      try await doc.revertDocument()
      XCTFail("Decoded corrupt file")
    } catch {}
    XCTAssertEqual(doc.store.document, edited)
    XCTAssertEqual(doc.store.session.undoStack.count, history)
    XCTAssertTrue(doc.isDocumentEdited)
    doc.store.geometryBusy = true
    XCTAssertFalse(doc.canRevertDocument)
    do {
      try await doc.revertDocument()
      XCTFail("Reverted during edit")
    } catch {}
    doc.store.geometryBusy = false
    XCTAssertFalse(doc.fileOperationBusy)
  }
  @MainActor func testRevertRejectsConcurrentEditAndCancellation() async throws {
    let doc = CraftNSDocument(model: try model())
    defer { doc.store.renderTask?.cancel() }
    doc.importedSourceURL = URL(fileURLWithPath: "/unused-test-source.png")
    let saved = doc.store.document
    for cancel in [false, true] {
      let gate = Gate()
      let task = Task {
        try await doc.revertDocument(reader: { _ in
          gate.wait()
          return saved
        })
      }
      try await waitFor(gate)
      if cancel {
        task.cancel()
      } else {
        try doc.store.executeEditorCommand(.opacity(saved.layers[0].id, 0.25))
      }
      let before = doc.store.document
      let history = doc.store.session.undoStack.count
      gate.release()
      do {
        try await task.value
        XCTFail("Accepted stale Revert")
      } catch {}
      XCTAssertEqual(doc.store.document, before)
      XCTAssertEqual(doc.store.session.undoStack.count, history)
      XCTAssertFalse(doc.fileOperationBusy)
    }
  }
  @MainActor func testHTTPRevertRequiresPermissionSourceRevisionAndSharesDesktopHistory()
    async throws
  {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let api = AutomationTests()
    try await api.withService(pressedMouseButtons: { 0 }) { service, doc in
      try service.share(doc)
      var result = try await api.edit(service, doc, "document.revert")
      XCTAssertEqual(result, 403)
      service.setDocumentTransfersEnabled(true)
      result = try await api.edit(service, doc, "document.revert")
      XCTAssertEqual(result, 409)
      let source = folder.appendingPathComponent("saved.pcswift")
      let original = doc.store.document
      try NativeArchive.encode(original).write(to: source)
      doc.fileURL = source
      try doc.store.executeEditorCommand(.opacity(try XCTUnwrap(original.activeLayerID), 0.2))
      let edited = doc.store.document
      result = try await api.edit(service, doc, "document.revert", revision: "stale")
      XCTAssertEqual(result, 409)
      result = try await api.edit(service, doc, "document.revert", ["path": "/unrequested"])
      XCTAssertEqual(result, 400)
      result = try await api.edit(service, doc, "document.revert")
      XCTAssertEqual(result, 200)
      XCTAssertEqual(doc.store.document, original)
      XCTAssertFalse(doc.isDocumentEdited)
      result = try await api.edit(service, doc, "history.undo")
      XCTAssertEqual(result, 200)
      XCTAssertEqual(doc.store.document, edited)
      XCTAssertTrue(doc.isDocumentEdited)
      result = try await api.edit(service, doc, "history.redo")
      XCTAssertEqual(result, 200)
      XCTAssertEqual(doc.store.document, original)
      XCTAssertFalse(doc.isDocumentEdited)
    }
  }
  @MainActor func testHTTPRevertRevocationWhileReadingLeavesEditsIntact() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let gate = Gate()
    try await AutomationTests().withService(
      pressedMouseButtons: { 0 },
      documentDecoder: { data, native, name in
        gate.wait()
        return try DocumentIO.decodeUpload(data, native: native, name: name)
      }
    ) { service, doc in
      let source = folder.appendingPathComponent("source.pcswift")
      try NativeArchive.encode(doc.store.document).write(to: source)
      doc.fileURL = source
      try doc.store.executeEditorCommand(
        .opacity(try XCTUnwrap(doc.store.document.activeLayerID), 0.2))
      let edited = doc.store.document
      service.setDocumentTransfersEnabled(true)
      try service.share(doc)
      let task = Task { try await AutomationTests().edit(service, doc, "document.revert") }
      try await self.waitFor(gate)
      service.setDocumentTransfersEnabled(false)
      service.setDocumentTransfersEnabled(true)
      gate.release()
      let code = try await task.value
      XCTAssertEqual(code, 409)
      XCTAssertEqual(doc.store.document, edited)
      XCTAssertTrue(doc.isDocumentEdited)
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
    }
  }
  @MainActor func testHTTPRevertBusyAndConcurrentDesktopEditAreConflicts() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let gate = Gate()
    try await AutomationTests().withService(
      pressedMouseButtons: { 0 },
      documentDecoder: { data, native, name in
        gate.wait()
        return try DocumentIO.decodeUpload(data, native: native, name: name)
      }
    ) { service, doc in
      let source = folder.appendingPathComponent("saved.pcswift")
      try NativeArchive.encode(doc.store.document).write(to: source)
      doc.fileURL = source
      service.setDocumentTransfersEnabled(true)
      try service.share(doc)
      let task = Task { try await AutomationTests().edit(service, doc, "document.revert") }
      try await self.waitFor(gate)
      let busy = try await AutomationTests().edit(service, doc, "history.undo")
      XCTAssertEqual(busy, 409)
      try doc.store.executeEditorCommand(
        .opacity(try XCTUnwrap(doc.store.document.activeLayerID), 0.1))
      let changed = doc.store.document
      gate.release()
      let conflict = try await task.value
      XCTAssertEqual(conflict, 409)
      XCTAssertEqual(doc.store.document, changed)
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
    }
  }
  @MainActor func testFileMenusUseFactoryBindingsAndCopyAccessoryDeclaresConversion() throws {
    try PhotoshopMenuTests().withMenus { _, menu in
      let items = PhotoshopMenuTests().allItems(menu)
      let copy = try XCTUnwrap(items.first { $0.identifier?.rawValue == "File > Save a Copy…" })
      XCTAssertEqual(copy.action, #selector(AppDelegate.saveCopy))
      XCTAssertEqual(copy.keyEquivalent, "s")
      XCTAssertEqual(copy.keyEquivalentModifierMask, [.option, .command])
      let revert = try XCTUnwrap(items.first { $0.identifier?.rawValue == "File > Revert" })
      XCTAssertEqual(revert.action, #selector(AppDelegate.revertFile))
      XCTAssertEqual(revert.keyEquivalent, "")
      let panel = NSSavePanel()
      panel.nameFieldStringValue = "Example copy.pcswift"
      let accessory = DocumentCopyAccessory(panel: panel, initial: .native)
      XCTAssertEqual(
        accessory.formats.itemTitles,
        ["Photato", "Photoshop", "Large Document Format", "PNG", "JPEG", "TIFF"])
      accessory.formats.selectItem(withTitle: "JPEG")
      accessory.updateFormat()
      XCTAssertEqual(panel.nameFieldStringValue, "Example copy.jpeg")
      XCTAssertTrue(accessory.explanation.stringValue.contains("8-bit"))
      XCTAssertEqual(panel.allowedContentTypes.first, .jpeg)
    }
  }
}
