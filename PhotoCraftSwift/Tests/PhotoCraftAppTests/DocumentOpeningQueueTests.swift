import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class DocumentOpeningQueueTests: XCTestCase {
  @MainActor func testSDKBatchPreservesEveryCallbackAndAlreadyOpenDirtyIdentity() async throws {
    let helper = DocumentOpeningTests(), c = helper.controller()
    defer { helper.cleanup(c) }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try helper.fixture(folder), b = try helper.fixture(folder, name: "second.photato")
    var calls = [Int](repeating: 0, count: 4)
    for (index, url) in [a, b, a, folder.appendingPathComponent("missing")].enumerated() {
      c.openDocument(withContentsOf: url, display: false) { doc, existed, error in
        XCTAssertTrue(Thread.isMainThread); calls[index] += 1
        if index == 3 { XCTAssertNil(doc); XCTAssertNotNil(error) }
        else { XCTAssertNotNil(doc); XCTAssertNil(error); XCTAssertEqual(existed, index == 2) }
      }
    }
    XCTAssertTrue(c.documentOpening.hasPendingRequests)
    XCTAssertFalse(c.documentClosing.canStart([]))
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(calls, [1, 1, 1, 1]); XCTAssertEqual(c.documents.count, 2)
    XCTAssertEqual(c.documentOpening.state?.total, 4)
    let original = try XCTUnwrap(c.document(for: a) as? CraftNSDocument)
    try original.store.executeEditorCommand(.renameLayer(original.store.document.layers[0].id, "Dirty"))
    let model = original.store.document
    c.openDocument(withContentsOf: a, display: false) { doc, existed, error in
      XCTAssertTrue(doc === original); XCTAssertTrue(existed); XCTAssertNil(error)
    }
    await c.documentOpening.waitUntilIdle()
    XCTAssertTrue(original.isDocumentEdited); XCTAssertEqual(original.store.document, model)
  }
  @MainActor func testCancelCallsUnstartedBatchCallbacksAndLaterBatchStillOpens() async throws {
    let helper = DocumentOpeningTests(), c = helper.controller()
    defer { helper.cleanup(c) }
    let folder = try DocumentPersistenceTests().directory()
    defer { try? FileManager.default.removeItem(at: folder) }
    let urls = try (0..<4).map { try helper.fixture(folder, name: "\($0).photato") }
    let gate = OpeningGate(); defer { gate.release() }
    c.documentOpening.reader = { url, format in
      if url == urls[1] { gate.wait(); try Task.checkCancellation() }
      return try PreparedLocalDocument.read(url, format: format)
    }
    var calls = [Int](repeating: 0, count: 4), cancelled: [Int] = []
    for i in 0..<3 {
      c.openDocument(withContentsOf: urls[i], display: false) { _, _, error in
        calls[i] += 1
        if (error as NSError?)?.code == NSUserCancelledError { cancelled.append(i) }
      }
    }
    try await helper.wait(gate)
    let id = try XCTUnwrap(c.documentOpening.state?.id)
    c.openDocument(withContentsOf: urls[3], display: false) { _, _, error in calls[3] += 1; XCTAssertNil(error) }
    XCTAssertEqual(c.documentOpening.queuedCount, 1)
    c.documentOpening.cancel(id); gate.release()
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(calls, [1, 1, 1, 1]); XCTAssertEqual(cancelled, [1, 2])
    XCTAssertEqual(c.documents.count, 2)
    XCTAssertNotEqual(c.documentOpening.state?.id, id)
    XCTAssertFalse(c.documentOpening.hasPendingRequests)
  }
  @MainActor func testStartupRecoveryFinishesBeforeQueuedOpenWithoutExtraUntitled() async throws {
    _ = NSApplication.shared
    let helper = RecoveryIndexTests(), folder = try helper.folder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let index = RecoveryIndexStore(directoryURL: folder.appendingPathComponent("Recovery"))
    let (_, _, recovered) = try helper.seed(index)
    let delegate = AppDelegate(workspaces: WorkspaceLibrary(), recoveryIndex: index)
    let c = delegate.controller
    defer { for doc in c.documents { doc.close() } }
    let source = try DocumentOpeningTests().fixture(folder)
    c.pendingUntitledRequest = true
    var calls = 0
    c.openDocument(withContentsOf: source, display: false) { doc, _, error in
      calls += 1; XCTAssertNotNil(doc); XCTAssertNil(error)
      XCTAssertTrue(c.initialRecoveryFinished)
      XCTAssertTrue(c.documents.compactMap { ($0 as? CraftNSDocument)?.store.document.id }.contains(recovered.id))
    }
    XCTAssertTrue(delegate.applicationOpenUntitledFile(NSApp))
    await c.documentOpening.waitUntilIdle()
    XCTAssertEqual(calls, 1); XCTAssertEqual(c.documents.count, 2)
    XCTAssertFalse(c.pendingUntitledRequest)
    XCTAssertEqual(c.recoveryPreferences.recentDocuments.count, 1, "Recovery-only opens must not enter recents")
  }
}
