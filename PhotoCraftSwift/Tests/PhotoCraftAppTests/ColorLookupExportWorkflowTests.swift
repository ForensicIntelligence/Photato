import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private final class LUTExportGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var started = false, released = false
  func wait() throws {
    condition.lock(); started = true; condition.broadcast()
    while !released {
      if Task.isCancelled { condition.unlock(); throw CancellationError() }
      _ = condition.wait(until: Date(timeIntervalSinceNow: 0.01))
    }
    condition.unlock(); try Task.checkCancellation()
  }
  func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
  var hasStarted: Bool { condition.lock(); defer { condition.unlock() }; return started }
}

final class ColorLookupExportWorkflowTests: XCTestCase {
  private func fixture() throws -> CraftDocument {
    var d = try CraftDocument(width: 8, height: 6)
    d.layers[0].background = true
    d.layers.append(Layer(name: "Invert", content: .adjustment(.invert)))
    return d
  }
  @MainActor private func wait(_ gate: LUTExportGate) async throws {
    for _ in 0..<1000 {
      if gate.hasStarted { return }
      try await Task.sleep(for: .milliseconds(2))
    }
    XCTFail("Export worker did not start"); throw CancellationError()
  }
  @MainActor func testNativeMenuDraftCancellationAndEncodingLeaveHistoryAndPixelsUntouched() async throws {
    _ = NSApplication.shared
    let store = EditorStore(document: try fixture())
    defer { store.cancelColorLookupExport(); store.renderTask?.cancel() }
    let original = store.document
    XCTAssertTrue(store.canExportColorLookup)
    store.beginColorLookupExport()
    let draft = try XCTUnwrap(store.colorLookupExportDraft)
    XCTAssertTrue(store.hasToneDraft); XCTAssertFalse(store.canExportImages)
    XCTAssertEqual(draft.size, 32); XCTAssertEqual(draft.title, "Color Lookup")
    let data = try await store.encodedColorLookup(size: 2, title: "Owned", draft: draft)
    XCTAssertEqual(data, try ColorLookupExport.cube(original, size: 2, title: "Owned"))
    XCTAssertEqual(store.document, original); XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertFalse(store.geometryBusy); XCTAssertNil(store.colorLookupExportID)
    store.cancelColorLookupExport(); XCTAssertTrue(store.canExportColorLookup)
    let menu = NSApp.mainMenu, windows = NSApp.windowsMenu, help = NSApp.helpMenu
    defer { NSApp.mainMenu = menu; NSApp.windowsMenu = windows; NSApp.helpMenu = help }
    AppDelegate().buildMenus()
    let item = try XCTUnwrap(NSApp.mainMenu?.item(withTitle: "File")?.submenu?
      .item(withTitle: "Export")?.submenu?.item(withTitle: "Color Lookup Tables…"))
    XCTAssertEqual(item.action, #selector(AppDelegate.exportColorLookupTables))
    XCTAssertEqual(item.keyEquivalent, "")
  }
  @MainActor func testHTTPBytesMatchNativeAndDiscoverableStateWithoutDirtyOrUndoChanges() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let source = try fixture(); document.store.session = EditorSession(document: source)
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first), revision = service.revision(document.store)
      let result = try await helper.request(service, path: "/v1/documents/\(share.id)/color-lookup.cube",
        headers: ["X-Photato-LUT-Grid-Points": "3", "X-Photato-LUT-Description": "Owned%20export", "X-Photato-Revision": revision])
      XCTAssertEqual(result.0.statusCode, 200)
      let native = try await document.store.encodedColorLookup(size: 3, title: "Owned export")
      XCTAssertEqual(result.1, native)
      XCTAssertEqual(try ColorLUTFile.read(result.1, name: "owned.cube").size, 3)
      XCTAssertEqual(document.store.document, source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertFalse(document.isDocumentEdited); XCTAssertEqual(service.revision(document.store), revision)
      let state = try XCTUnwrap(service.state(share, document: document)["colorLookupExport"] as? [String: Any])
      XCTAssertEqual(state["available"] as? Bool, true); XCTAssertEqual(state["busy"] as? Bool, false)
      let capabilities = try XCTUnwrap(AutomationService.colorLookupCapabilities["stackExport"] as? [String: Any])
      XCTAssertEqual(capabilities["path"] as? String, "/v1/documents/{id}/color-lookup.cube")
      XCTAssertTrue(JSONSerialization.isValidJSONObject(capabilities))
    }
  }
  @MainActor func testHTTPTransferInvalidBusyStaleAndUnsupportedGuardsAreAtomic() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let source = try fixture(); document.store.session = EditorSession(document: source)
      try service.share(document); let share = try XCTUnwrap(service.shares.first)
      let path = "/v1/documents/\(share.id)/color-lookup.cube"
      let denied = try await helper.request(service, path: path); XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      for value in ["1", "130", "2.5", "unknown"] {
        let result = try await helper.request(service, path: path, headers: ["X-Photato-LUT-Grid-Points": value])
        XCTAssertEqual(result.0.statusCode, 400)
      }
      let title = try await helper.request(service, path: path, headers: ["X-Photato-LUT-Description": "%0A"])
      XCTAssertEqual(title.0.statusCode, 400)
      let stale = try await helper.request(service, path: path, headers: ["X-Photato-Revision": "stale"])
      XCTAssertEqual(stale.0.statusCode, 409)
      document.store.geometryBusy = true
      let busy = try await helper.request(service, path: path)
      document.store.geometryBusy = false; XCTAssertEqual(busy.0.statusCode, 409)
      XCTAssertEqual(document.store.document, source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      var unsupported = source; unsupported.layers[0].background = nil
      document.store.session = EditorSession(document: unsupported)
      let invalid = try await helper.request(service, path: path, headers: ["X-Photato-LUT-Grid-Points": "2"])
      XCTAssertEqual(invalid.0.statusCode, 422)
      XCTAssertEqual(document.store.document, unsupported); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testTransferRevocationCancelsSharedWorkerAndReturnsNoCube() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let source = try fixture(), gate = LUTExportGate()
      defer { gate.release() }
      document.store.session = EditorSession(document: source)
      document.store.colorLookupExportPreparation = { document, size, title in
        try gate.wait(); return try ColorLookupExport.cube(document, size: size, title: title)
      }
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first)
      let pending = Task { try await helper.request(service, path: "/v1/documents/\(share.id)/color-lookup.cube",
        headers: ["X-Photato-LUT-Grid-Points": "2"]) }
      try await wait(gate)
      XCTAssertTrue(document.store.geometryBusy); XCTAssertNotNil(document.store.colorLookupExportID)
      service.setDocumentTransfersEnabled(false); gate.release()
      let result = try await pending.value
      XCTAssertEqual(result.0.statusCode, 409)
      XCTAssertFalse(String(data: result.1, encoding: .utf8)?.contains("LUT_3D_SIZE") == true)
      XCTAssertEqual(document.store.document, source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertFalse(document.store.geometryBusy); XCTAssertNil(document.store.colorLookupExportID)
    }
  }
  @MainActor func testNativeCancelAndChangedSourceCannotDeliverOldExport() async throws {
    let store = EditorStore(document: try fixture()), gate = LUTExportGate()
    defer { gate.release(); store.cancelColorLookupExport(); store.renderTask?.cancel() }
    let original = store.document
    store.colorLookupExportPreparation = { document, size, title in
      try gate.wait(); return try ColorLookupExport.cube(document, size: size, title: title)
    }
    store.beginColorLookupExport(); let draft = try XCTUnwrap(store.colorLookupExportDraft)
    let pending = Task { try await store.encodedColorLookup(size: 2, title: "Owned", draft: draft) }
    try await wait(gate); store.cancelColorLookupExport(); gate.release()
    do { _ = try await pending.value; XCTFail("Cancelled native export returned bytes") }
    catch { XCTAssertTrue(error is CancellationError) }
    XCTAssertEqual(store.document, original); XCTAssertFalse(store.geometryBusy)
    store.beginColorLookupExport(); let stale = try XCTUnwrap(store.colorLookupExportDraft)
    var changed = original; changed.name = "Changed"
    store.session = EditorSession(document: changed)
    do { _ = try await store.encodedColorLookup(size: 2, title: "Owned", draft: stale); XCTFail("Stale draft exported") }
    catch { XCTAssertEqual(store.document, changed) }
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testExplicitAPICancelStopsOnlyTheMatchingLUTExportAndAllowsRetry() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let source = try fixture(), gate = LUTExportGate()
      defer { gate.release() }
      document.store.session = EditorSession(document: source)
      document.store.colorLookupExportPreparation = { document, size, title in
        try gate.wait(); return try ColorLookupExport.cube(document, size: size, title: title)
      }
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/color-lookup.cube"
      let pending = Task { try await helper.request(service, path: path, headers: ["X-Photato-LUT-Grid-Points": "2"]) }
      try await wait(gate)
      let operation = try XCTUnwrap(document.store.colorLookupExportID)
      let wrong = try await helper.edit(service, document, "image.export.cancel", ["operationID": UUID().uuidString])
      XCTAssertEqual(wrong, 409); XCTAssertEqual(document.store.colorLookupExportID, operation)
      let cancel = try await helper.edit(service, document, "image.export.cancel", ["operationID": operation.uuidString])
      XCTAssertEqual(cancel, 200); gate.release()
      let cancelled = try await pending.value
      XCTAssertEqual(cancelled.0.statusCode, 409)
      XCTAssertTrue(service.documentTransfersEnabled); XCTAssertFalse(document.store.geometryBusy)
      XCTAssertNil(document.store.colorLookupExportID); XCTAssertEqual(document.store.document, source)
      XCTAssertTrue(document.store.session.undoStack.isEmpty)
      let retry = try await helper.request(service, path: path, headers: ["X-Photato-LUT-Grid-Points": "2"])
      XCTAssertEqual(retry.0.statusCode, 200)
      XCTAssertEqual(try ColorLUTFile.read(retry.1, name: "retry.cube").size, 2)
      XCTAssertEqual(document.store.document, source)
    }
  }
}
