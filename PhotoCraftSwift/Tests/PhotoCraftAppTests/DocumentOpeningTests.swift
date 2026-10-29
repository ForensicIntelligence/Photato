import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class OpeningGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var entered = false
  private var released = false
  private var main = true
  var started: Bool { condition.lock(); defer { condition.unlock() }; return entered }
  var ranOnMain: Bool { condition.lock(); defer { condition.unlock() }; return main }
  func wait() {
    condition.lock(); defer { condition.unlock() }
    entered = true; main = Thread.isMainThread
    while !released { if !condition.wait(until: Date().addingTimeInterval(10)) { break } }
  }
  func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}

final class DocumentOpeningTests: XCTestCase {
  @MainActor func controller() -> CraftDocumentController {
    _ = NSApplication.shared
    let c = CraftDocumentController(workspaces: WorkspaceLibrary())
    c.documentOpening.reader = PreparedLocalDocument.read
    return c
  }
  @MainActor func cleanup(_ c: CraftDocumentController) {
    c.documentOpening.reader = PreparedLocalDocument.read
    for doc in c.documents { doc.close() }
  }
  func fixture(_ folder: URL, name: String = "source.photato", format: DocumentIO.Format = .native) throws -> URL {
    let url = folder.appendingPathComponent(name)
    let model = try CraftDocument(width: 5, height: 3, name: "Opening fixture")
    try DocumentIO.encode(model, format: format).write(to: url)
    return url
  }
  @MainActor func wait(_ gate: OpeningGate) async throws {
    for _ in 0..<200 where !gate.started { try await Task.sleep(for: .milliseconds(5)) }
    XCTAssertTrue(gate.started)
  }
  func testNativeLegacyAndChunkedWithoutExtensionsRetainExactModels() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = try CraftDocument(width: 5, height: 3)
    for (i, bytes) in [try NativeArchive.encode(model), try NativeArchive.encodeChunked(model)].enumerated() {
      let url = folder.appendingPathComponent("without-extension-\(i)")
      try bytes.write(to: url)
      XCTAssertEqual(DocumentOpenFormat.detect(url), .native)
      XCTAssertTrue(DocumentIO.isNativeFile(url))
      XCTAssertEqual(try DocumentIO.read(url), model)
      XCTAssertEqual(try PreparedLocalDocument.read(url, format: .native).model, model)
    }
  }
  func testMislabeledRasterAndPhotoshopContainersUseActualFormat() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    for format in [DocumentIO.Format.png, .jpeg, .tiff, .psd, .psb] {
      let url = try fixture(folder, name: format.rawValue + ".photato", format: format)
      XCTAssertEqual(DocumentOpenFormat.detect(url)?.persistenceFormat, format)
      XCTAssertFalse(DocumentIO.isNativeFile(url))
      let prepared = try PreparedLocalDocument.read(url, format: DocumentOpenFormat(rawValue: format.rawValue)!)
      XCTAssertEqual(prepared.format, format)
      XCTAssertEqual(prepared.model.width, 5)
      XCTAssertThrowsError(try PreparedLocalDocument.read(url, format: .native))
      let bytes = try Data(contentsOf: url)
      XCTAssertEqual(DocumentOpenFormat.detect(bytes)?.persistenceFormat, format)
    }
  }
  func testSelectedFormatMismatchAndInvalidNativePayloadNeverFallBack() throws {
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try fixture(folder, format: .psb)
    XCTAssertThrowsError(try PreparedLocalDocument.read(url, format: .psd))
    try Data("PHOTATO\0truncated".utf8).write(to: url)
    XCTAssertEqual(DocumentOpenFormat.detect(url), .native)
    XCTAssertThrowsError(try PreparedLocalDocument.read(url, format: .automatic))
  }
  @MainActor func testOpenPanelAllDocumentsAndFormatSelectionHaveAccessibleControls() {
    _ = NSApplication.shared
    let panel = NSOpenPanel()
    DocumentIO.configureOpenPanel(panel)
    let accessory = DocumentOpenAccessory(panel: panel)
    XCTAssertGreaterThanOrEqual(accessory.view.frame.width, 230)
    XCTAssertGreaterThan(accessory.view.frame.height, 40)
    XCTAssertGreaterThan(accessory.formats.frame.height, 0)
    XCTAssertGreaterThan(accessory.show.frame.height, 0)
    XCTAssertEqual(accessory.format, .automatic)
    XCTAssertFalse(panel.allowsOtherFileTypes)
    accessory.formats.selectItem(at: DocumentOpenFormat.allCases.firstIndex(of: .psb)!)
    accessory.changed()
    XCTAssertEqual(panel.allowedContentTypes.map(\.identifier), ["com.adobe.photoshop-large-image"])
    accessory.show.selectItem(at: 1); accessory.changed()
    XCTAssertTrue(panel.allowsOtherFileTypes)
    XCTAssertTrue(panel.allowedContentTypes.isEmpty)
    XCTAssertEqual(accessory.formats.accessibilityLabel(), "File format")
    XCTAssertTrue(panel.allowsMultipleSelection)
  }
  @MainActor func testBackgroundReadCancellationPreservesDocumentsAndBlocksLifecycleConflicts() async throws {
    let c = controller(); defer { cleanup(c) }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try fixture(folder)
    let original = try DocumentClosingTests().document(c, dirty: true)
    let expected = original.store.document
    let gate = OpeningGate(); defer { gate.release() }
    c.documentOpening.reader = { url, format in gate.wait(); try Task.checkCancellation(); return try PreparedLocalDocument.read(url, format: format) }
    var replies = 0, cancelled = false
    let id = try c.documentOpening.begin([url], display: false, completion: { _, _, error in
      replies += 1; cancelled = (error as NSError?)?.code == NSUserCancelledError
    })
    try await wait(gate)
    XCTAssertFalse(gate.ranOnMain)
    XCTAssertFalse(c.documentClosing.canStart([original]))
    XCTAssertThrowsError(try c.documentOpening.begin([url], display: false))
    do { try await c.discoverIndexedRecovery(display: false); XCTFail("Recovery raced opening") } catch {}
    c.documentOpening.cancel(id)
    gate.release()
    await c.documentOpening.task?.value
    XCTAssertEqual(replies, 1)
    XCTAssertTrue(cancelled)
    XCTAssertFalse(c.documentOpening.isActive)
    XCTAssertEqual(c.documents.count, 1)
    XCTAssertEqual(original.store.document, expected)
    XCTAssertTrue(original.isDocumentEdited)
  }
  @MainActor func testBatchKeepsSuccessOnFailureAndAvoidsDuplicateDirtyDocument() async throws {
    let c = controller(); defer { cleanup(c) }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try fixture(folder)
    let bad = folder.appendingPathComponent("missing.photato")
    try c.documentOpening.begin([url, bad, url], display: false)
    await c.documentOpening.task?.value
    XCTAssertEqual(c.documentOpening.state?.opened, 1)
    XCTAssertEqual(c.documentOpening.state?.failed, 1)
    XCTAssertEqual(c.documentOpening.state?.alreadyOpen, 1)
    let doc = try XCTUnwrap(c.documents.first as? CraftNSDocument)
    try doc.store.executeEditorCommand(.renameLayer(doc.store.document.layers[0].id, "Retain edits"))
    let expected = doc.store.document
    try c.documentOpening.begin([url], display: false)
    await c.documentOpening.task?.value
    XCTAssertEqual(c.documents.count, 1)
    XCTAssertTrue(c.documents[0] === doc)
    XCTAssertEqual(doc.store.document, expected)
    XCTAssertTrue(doc.isDocumentEdited)
  }
  @MainActor func testCancellingRemainingBatchKeepsAcceptedFirstFile() async throws {
    let c = controller(); defer { cleanup(c) }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = try fixture(folder), second = try fixture(folder, name: "second.photato")
    let gate = OpeningGate(); defer { gate.release() }
    c.documentOpening.reader = { url, format in
      if url == second { gate.wait(); try Task.checkCancellation() }
      return try PreparedLocalDocument.read(url, format: format)
    }
    let id = try c.documentOpening.begin([first, second], display: false, showProgress: true)
    try await wait(gate)
    XCTAssertEqual(c.documents.count, 1)
    let progress = try XCTUnwrap(c.documentOpening.progress as? DocumentOpeningProgress)
    progress.cancelOpening()
    XCTAssertEqual(c.documentOpening.state?.id, id)
    gate.release(); await c.documentOpening.task?.value
    XCTAssertEqual(c.documentOpening.state?.opened, 1)
    XCTAssertEqual(c.documents.count, 1)
    XCTAssertNil(c.documentOpening.progress)
  }
  @MainActor func testReadSnapshotDateDoesNotAdoptLaterExternalWrite() async throws {
    let c = controller(); defer { cleanup(c) }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try fixture(folder)
    let before = try NativeArchive.read(url)
    let gate = OpeningGate(); defer { gate.release() }
    c.documentOpening.reader = { url, format in
      let prepared = try PreparedLocalDocument.read(url, format: format)
      gate.wait(); return prepared
    }
    try c.documentOpening.begin([url], display: false)
    try await wait(gate)
    let changed = try CraftDocument(width: 8, height: 4)
    try NativeArchive.write(changed, to: url)
    let later = Date().addingTimeInterval(10)
    try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: url.path)
    gate.release(); await c.documentOpening.task?.value
    let doc = try XCTUnwrap(c.documents.first as? CraftNSDocument)
    XCTAssertEqual(doc.store.document, before)
    XCTAssertNotEqual(doc.fileModificationDate, try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
    XCTAssertEqual(try NativeArchive.read(url), changed)
  }
  @MainActor func testQueuedCancellationInvokesSDKCallbackOnceOnMainThread() async throws {
    let c = controller(); defer { cleanup(c) }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = try fixture(folder)
    let gate = OpeningGate(); defer { gate.release() }
    c.documentOpening.reader = { url, format in
      gate.wait(); try Task.checkCancellation()
      return try PreparedLocalDocument.read(url, format: format)
    }
    var replies = 0
    c.openDocument(withContentsOf: url, display: false) { doc, existed, error in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertNil(doc); XCTAssertFalse(existed)
      XCTAssertEqual((error as NSError?)?.code, NSUserCancelledError)
      replies += 1
    }
    try await wait(gate)
    c.documentOpening.cancel(try XCTUnwrap(c.documentOpening.state?.id))
    gate.release()
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(replies, 1)
    XCTAssertTrue(c.documents.isEmpty)
  }
}
