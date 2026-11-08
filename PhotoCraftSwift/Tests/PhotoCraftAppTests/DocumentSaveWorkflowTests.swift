import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest

@testable import PhotoCraft

final class DocumentSaveWorkflowTests: XCTestCase {
  func directory() throws -> URL { try DocumentPersistenceTests().directory() }
  func fixture(depth: PixelDepth = .u8) throws -> CraftDocument {
    var doc = try CraftDocument(width: 5, height: 3, depth: depth, name: "Save workflow")
    var pixels = try Surface(width: 5, height: 3, depth: depth)
    for y in 0..<3 {
      for x in 0..<5 { pixels.setPixel(x: x, y: y, Pixel(Float(x) / 4, Float(y) / 2, 0.25)) }
    }
    doc.layers[0].content = .raster(pixels)
    return doc
  }
  @MainActor func save(
    _ doc: CraftNSDocument, to url: URL, format: DocumentIO.Format,
    operation: NSDocument.SaveOperationType = .saveAsOperation
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      doc.save(to: url, ofType: format.typeIdentifier, for: operation) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }
  @MainActor func testOpenEditSaveBackEveryWritableFormatAndSaveAsChangesOwnership() async throws {
    _ = NSApplication.shared
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    for format in DocumentIO.Format.allCases where format != .exr { // Existing8-bit fixture; EXR has dedicated32-bit workflow coverage.
      let source = folder.appendingPathComponent("source." + format.rawValue)
      try DocumentIO.encode(fixture(), format: format).write(to: source)
      let doc = try XCTUnwrap(
        controller.makeDocument(withContentsOf: source, ofType: format.typeIdentifier)
          as? CraftNSDocument)
      controller.addDocument(doc)
      defer { doc.close() }
      XCTAssertEqual(doc.fileURL, source)
      XCTAssertEqual(doc.persistenceFormat, format)
      XCTAssertNil(doc.importedSourceURL)
      XCTAssertNotNil(doc.fileModificationDate)
      try doc.store.executeEditorCommand(
        .fill(try XCTUnwrap(doc.store.document.activeLayerID), Pixel(0.2, 0.4, 0.8)))
      let snapshot = doc.store.document
      let expected = try DocumentIO.encodeForPersistence(snapshot, format: format)
      try await save(doc, to: source, format: format, operation: .saveOperation)
      XCTAssertEqual(try Data(contentsOf: source), expected)
      XCTAssertEqual(doc.store.document, snapshot)
      XCTAssertFalse(doc.isDocumentEdited)
      XCTAssertEqual(doc.store.session.undoStack.count, 1)
      let native = folder.appendingPathComponent(format.rawValue + "-copy.photato")
      try await save(doc, to: native, format: .native)
      XCTAssertEqual(doc.persistenceFormat, .native)
      XCTAssertEqual(doc.fileURL, native)
      XCTAssertEqual(try NativeArchive.decode(Data(contentsOf: native)), snapshot)
      XCTAssertEqual(try Data(contentsOf: source), expected)
      await doc.store.undo()
      XCTAssertTrue(doc.isDocumentEdited)
      await doc.store.redo()
      XCTAssertEqual(doc.store.document, snapshot)
    }
  }
  @MainActor func testRepresentabilityRejectsFlatteningDepthLossAndUnsupportedPSDWithoutWriting()
    async throws
  {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    var model = try fixture()
    model.layers.append(
      Layer(name: "Keep editable", content: .raster(try Surface(width: 2, height: 2, fill: .white)))
    )
    let doc = CraftNSDocument(model: model)
    defer { doc.close() }
    XCTAssertEqual(doc.saveFormats, [.native, .psd, .psb, .tiff])
    let target = folder.appendingPathComponent("existing.png")
    try Data("existing".utf8).write(to: target)
    do {
      try await save(doc, to: target, format: .png)
      XCTFail("Flattened ordinary Save As")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: target), Data("existing".utf8))
    XCTAssertNil(doc.fileURL)
    for depth in [PixelDepth.u16, .f32] {
      let model = try fixture(depth: depth)
      XCTAssertNotNil(DocumentIO.persistenceIssue(model, format: .jpeg))
      if depth == .f32 {
        XCTAssertNotNil(DocumentIO.persistenceIssue(model, format: .png))
        XCTAssertNil(DocumentIO.persistenceIssue(model, format: .tiff))
      }
      XCTAssertNil(DocumentIO.persistenceIssue(model, format: .psd))
    }
    var transparent = try fixture()
    transparent.layers[0].content = .raster(try Surface(width: 5, height: 3, fill: .clear))
    XCTAssertNotNil(DocumentIO.persistenceIssue(transparent, format: .jpeg))
    XCTAssertNil(DocumentIO.persistenceIssue(transparent, format: .png))
    var moved = try fixture()
    moved.layers[0].x = 1
    XCTAssertNotNil(DocumentIO.persistenceIssue(moved, format: .png))
    XCTAssertTrue(DocumentIO.Format.jpeg.saveNotice.contains("changes pixels"))
    XCTAssertTrue(DocumentIO.Format.psd.saveNotice.contains("32-bit output equivalence"))
  }
  @MainActor func testSourceFormatUsesImageContentAndCommonFilenameAliases() async throws {
    _ = NSApplication.shared
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let cases: [(String, DocumentIO.Format)] = [
      ("jpg", .jpeg), ("JPG", .jpeg), ("jpe", .jpeg),
      ("tif", .tiff), ("TIF", .tiff), ("jpeg", .png),
      ("pcswift", .native), ("PCSWIFT", .native),
      ("psd", .psb), ("psb", .psd), ("PSB", .psb),
    ]
    for (index, item) in cases.enumerated() {
      let (suffix, format) = item
      let url = folder.appendingPathComponent("source-\(index).\(suffix)")
      try DocumentIO.encode(fixture(), format: format).write(to: url)
      let doc = try XCTUnwrap(
        controller.makeDocument(withContentsOf: url, ofType: "Raster Image") as? CraftNSDocument)
      controller.addDocument(doc)
      defer { doc.close() }
      XCTAssertEqual(doc.fileURL, url, suffix)
      XCTAssertEqual(doc.persistenceFormat, format, suffix)
      XCTAssertNil(doc.importedSourceURL, suffix)
      try doc.store.executeEditorCommand(
        .fill(try XCTUnwrap(doc.store.document.activeLayerID), Pixel(0.2, 0.4, 0.8)))
      let expected = try DocumentIO.encodeForPersistence(doc.store.document, format: format)
      try await save(doc, to: url, format: doc.persistenceFormat, operation: .saveOperation)
      XCTAssertEqual(try Data(contentsOf: url), expected, suffix)
      XCTAssertEqual(doc.fileURL, url)
      XCTAssertFalse(doc.isDocumentEdited)
    }
  }
  @MainActor func testRecoveryFromPSDUsesNativeArchiveAndDoesNotReplacePSD() async throws {
    _ = NSApplication.shared
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let doc = CraftNSDocument(model: try fixture())
    defer { doc.close() }
    let source = folder.appendingPathComponent("source.psd")
    try await save(doc, to: source, format: .psd)
    let saved = try Data(contentsOf: source)
    try doc.store.executeEditorCommand(
      .opacity(try XCTUnwrap(doc.store.document.activeLayerID), 0.5))
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
      doc.autosave(withImplicitCancellability: false) { error in
        if let error { c.resume(throwing: error) } else { c.resume() }
      }
    }
    let recovery = try XCTUnwrap(doc.autosavedContentsFileURL)
    XCTAssertEqual(try NativeArchive.decode(Data(contentsOf: recovery)), doc.store.document)
    XCTAssertEqual(try Data(contentsOf: source), saved)
    XCTAssertEqual(doc.fileURL, source)
    XCTAssertEqual(doc.persistenceFormat, .psd)
    XCTAssertTrue(doc.isDocumentEdited)
  }
  @MainActor func testFailedCancelledAndStaleEncodeKeepFileIdentityDirtyStateAndHistory()
    async throws
  {
    _ = NSApplication.shared
    let bootstrap = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { withExtendedLifetime(bootstrap) {} }
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let doc = CraftNSDocument(model: try fixture())
    defer { doc.close() }
    let source = folder.appendingPathComponent("source.photato")
    try await save(doc, to: source, format: .native)
    let sourceBytes = try Data(contentsOf: source)
    try doc.store.executeEditorCommand(
      .renameLayer(try XCTUnwrap(doc.store.document.activeLayerID), "Edited"))
    for cancel in [false, true] {
      let gate = DocumentPersistenceTests.Gate()
      let target = folder.appendingPathComponent("target-\(cancel).psd")
      let task = Task {
        try await doc.persistDocument(
          to: target, format: .psd, operation: .saveAsOperation,
          encoder: { model, format in
            gate.wait()
            return try DocumentIO.encodeForPersistence(model, format: format)
          })
      }
      try await DocumentPersistenceTests().waitFor(gate)
      XCTAssertTrue(doc.fileOperationBusy)
      if cancel {
        task.cancel()
      } else {
        try doc.store.executeEditorCommand(
          .renameLayer(try XCTUnwrap(doc.store.document.activeLayerID), "Concurrent"))
      }
      gate.release()
      do {
        try await task.value
        XCTFail("Saved stale/cancelled snapshot")
      } catch {}
      XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
      XCTAssertEqual(doc.fileURL, source)
      XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
      XCTAssertTrue(doc.isDocumentEdited)
    }
    do {
      try await doc.persistDocument(
        to: source, format: .native, operation: .saveOperation,
        encoder: { _, _ in throw CraftError.invalid("failed encoder") })
      XCTFail("Expected encoder error")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
    XCTAssertFalse(doc.fileOperationBusy)
  }
  @MainActor func testSaveAsRefusesAnotherOpenDocument() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let a = CraftNSDocument(model: try fixture())
    let b = CraftNSDocument(model: try fixture())
    controller.addDocument(a)
    controller.addDocument(b)
    defer {
      a.close()
      b.close()
    }
    let target = folder.appendingPathComponent("owned.photato")
    try await save(a, to: target, format: .native)
    let original = try Data(contentsOf: target)
    do {
      try await save(b, to: target, format: .native)
      XCTFail("Overwrote another open document")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: target), original)
    XCTAssertNil(b.fileURL)
  }
  @MainActor func testHTTPPermissionSaveAsAndSaveMatchNativeOutputAndHistory() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for format in [DocumentIO.Format.psd, .psb] {
      try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, doc in
        try service.share(doc)
        let api = AutomationTests()
        var reply = try await api.edit(service, doc, "document.save")
        XCTAssertEqual(reply, 403)
        XCTAssertFalse(service.documentSavesEnabled)
        XCTAssertNil(service.saveDirectoryURL)
        service.setDocumentSavesEnabled(true)
        reply = try await api.edit(service, doc, "document.save")
        XCTAssertEqual(reply, 409)
        let args: [String: Any] = [
          "name": "API saved", "format": format.rawValue, "replace": false,
        ]
        reply = try await api.edit(service, doc, "document.saveAs", args)
        XCTAssertEqual(reply, 403)
        service.setSaveDirectory(folder)
        let before = doc.store.document
        reply = try await api.edit(service, doc, "document.saveAs", args)
        XCTAssertEqual(reply, 200)
        let target = folder.appendingPathComponent("API saved." + format.rawValue)
        XCTAssertEqual(doc.fileURL, target)
        XCTAssertEqual(doc.persistenceFormat, format)
        XCTAssertEqual(
          try Data(contentsOf: target), try DocumentIO.encodeForPersistence(before, format: format))
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertEqual(doc.store.document, before)
        try doc.store.executeEditorCommand(
          .opacity(try XCTUnwrap(doc.store.document.activeLayerID), 0.75))
        let edited = doc.store.document
        reply = try await api.edit(service, doc, "document.save")
        XCTAssertEqual(reply, 200)
        XCTAssertEqual(
          try Data(contentsOf: target), try DocumentIO.encodeForPersistence(edited, format: format))
        XCTAssertFalse(doc.isDocumentEdited)
        XCTAssertEqual(doc.store.session.undoStack.count, 1)
        let stateReply = try await api.request(
          service, path: "/v1/documents/\(try XCTUnwrap(service.shares.first?.id))")
        let state = try XCTUnwrap(
          JSONSerialization.jsonObject(with: stateReply.1) as? [String: Any])
        XCTAssertEqual(state["persistenceFormat"] as? String, format.rawValue)
        XCTAssertEqual(state["canSave"] as? Bool, true)
        await doc.store.undo()
        await doc.store.redo()
        XCTAssertEqual(doc.store.document, edited)
        service.stop()
        XCTAssertFalse(service.documentSavesEnabled)
        XCTAssertNil(service.saveDirectoryURL)
      }
    }
  }
  @MainActor func testHTTPFilenameOverwriteSymlinkExternalChangeAndStaleGuards() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, doc in
      try service.share(doc)
      service.setDocumentSavesEnabled(true)
      service.setSaveDirectory(folder)
      let api = AutomationTests()
      for name in ["../escape", "/absolute", "nested/file", "a:b", "a\\b", ".hidden"] {
        let reply = try await api.edit(
          service, doc, "document.saveAs", ["name": name, "format": "photato", "replace": false])
        XCTAssertEqual(reply, 400, name)
      }
      let existing = folder.appendingPathComponent("existing.photato")
      try Data("preserve".utf8).write(to: existing)
      let args: [String: Any] = ["name": "existing.photato", "format": "photato", "replace": false]
      var reply = try await api.edit(service, doc, "document.saveAs", args)
      XCTAssertEqual(reply, 409)
      XCTAssertEqual(try Data(contentsOf: existing), Data("preserve".utf8))
      let symbolic = folder.appendingPathComponent("alias.photato")
      try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: existing)
      reply = try await api.edit(
        service, doc, "document.saveAs", ["name": "alias", "format": "photato", "replace": true])
      XCTAssertEqual(reply, 409)
      reply = try await api.edit(
        service, doc, "document.saveAs",
        ["name": "existing", "format": "photato", "replace": true], revision: "stale")
      XCTAssertEqual(reply, 409)
      reply = try await api.edit(
        service, doc, "document.saveAs", ["name": "existing", "format": "photato", "replace": true])
      XCTAssertEqual(reply, 200)
      try Data("external change".utf8).write(to: existing, options: .atomic)
      reply = try await api.edit(service, doc, "document.save")
      XCTAssertEqual(reply, 409)
      XCTAssertEqual(try Data(contentsOf: existing), Data("external change".utf8))
    }
  }
  @MainActor func testHTTPRevocationOrConcurrentEditDuringEncodingNeverWrites() async throws {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    try await AutomationTests().withService(pressedMouseButtons: { 0 }) { service, doc in
      try service.share(doc)
      service.setSaveDirectory(folder)
      for revoke in [true, false] {
        service.setDocumentSavesEnabled(true)
        let gate = DocumentPersistenceTests.Gate()
        doc.saveEncoder = { model, format in
          gate.wait()
          return try DocumentIO.encodeForPersistence(model, format: format)
        }
        let name = "revoked-\(revoke)"
        let task = Task {
          try await AutomationTests().edit(
            service, doc, "document.saveAs", ["name": name, "format": "photato", "replace": false])
        }
        try await DocumentPersistenceTests().waitFor(gate)
        if revoke {
          service.setDocumentSavesEnabled(false)
        } else {
          try doc.store.executeEditorCommand(
            .renameLayer(try XCTUnwrap(doc.store.document.activeLayerID), "Changed during save"))
        }
        gate.release()
        let reply = try await task.value
        XCTAssertEqual(reply, 409)
        XCTAssertFalse(
          FileManager.default.fileExists(
            atPath: folder.appendingPathComponent(name + ".photato").path))
        XCTAssertNil(doc.fileURL)
      }
    }
  }
  @MainActor func testImportedRGB32SourceCannotBeSilentlyOverwrittenBeforeFormatReview()
    async throws
  {
    let folder = try directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let source = folder.appendingPathComponent("original.psd")
    let bytes = try DocumentIO.encode(fixture(depth: .f32), format: .psd)
    try bytes.write(to: source)
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let doc = try XCTUnwrap(
      controller.makeDocument(withContentsOf: source, ofType: DocumentIO.Format.psd.typeIdentifier)
        as? CraftNSDocument)
    defer { doc.close() }
    XCTAssertTrue(doc.sourceSaveNeedsReview)
    do {
      try await save(doc, to: source, format: .psd, operation: .saveOperation)
      XCTFail("Silently replaced original RGB32 source")
    } catch {}
    XCTAssertEqual(try Data(contentsOf: source), bytes)
    let target = folder.appendingPathComponent("explicit.photato")
    try await save(doc, to: target, format: .native)
    XCTAssertFalse(doc.sourceSaveNeedsReview)
    XCTAssertEqual(try NativeArchive.decode(Data(contentsOf: target)), doc.store.document)
    XCTAssertEqual(try Data(contentsOf: source), bytes)
  }

  @MainActor func testSaveAsFormatControlPreservesEligibleTypesAndSelectedFileType() throws {
    _ = NSApplication.shared
    var model = try fixture()
    model.layers.append(Layer(name: "Second", content: .raster(try Surface(width: 2, height: 2))))
    let doc = CraftNSDocument(model: model)
    defer { doc.close() }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Editable.photato"
    XCTAssertTrue(doc.prepareSavePanel(panel))
    let control = try XCTUnwrap(doc.saveAccessory)
    XCTAssertEqual(control.availableFormats, [.native, .psd, .psb, .tiff])
    XCTAssertTrue(panel.accessoryView === control.view)
    control.formats.selectItem(at: 1)
    control.updateFormat()
    XCTAssertEqual(doc.fileTypeFromLastRunSavePanel, "com.adobe.photoshop-image")
    XCTAssertEqual(panel.nameFieldStringValue, "Editable.psd")
    XCTAssertEqual(panel.allowedContentTypes.map(\.identifier), ["com.adobe.photoshop-image"])
    XCTAssertTrue(control.explanation.stringValue.contains("supported editable layers"))
    control.formats.selectItem(at: 0)
    control.updateFormat()
    XCTAssertEqual(doc.fileTypeFromLastRunSavePanel, CraftNSDocument.nativeType)
    XCTAssertEqual(panel.nameFieldStringValue, "Editable.photato")
  }

}
