import AppKit
import Foundation
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class IllustratorExportGate: @unchecked Sendable {
  private let lock = NSCondition()
  private var started = false, released = false
  var ready: Bool { lock.lock(); defer { lock.unlock() }; return started }
  func wait() throws {
    lock.lock(); started = true; lock.broadcast()
    while !released {
      if Task.isCancelled { lock.unlock(); throw CancellationError() }
      _ = lock.wait(until: Date(timeIntervalSinceNow: 0.01))
    }
    lock.unlock(); try Task.checkCancellation()
  }
  func release() { lock.lock(); released = true; lock.broadcast(); lock.unlock() }
}
final class IllustratorPathExportWorkflowTests: XCTestCase {
  private func fixture() throws -> CraftDocument {
    var source = try CraftDocument(width: 240, height: 120, name: "Owned paths")
    source.resolution = 144
    source.paths = [NamedPath(name: "Curve", path: VectorPath(components: [.init(knots: [
      .init(.init(20, 30), outgoing: .init(60, 10)), .init(.init(200, 90), incoming: .init(150, 110), smooth: true)
    ])]), isWorkPath: false)]
    return source
  }
  @MainActor private func wait(_ gate: IllustratorExportGate) async throws {
    for _ in 0..<1000 { if gate.ready { return }; try await Task.sleep(for: .milliseconds(2)) }
    XCTFail("Export worker did not start"); throw CancellationError()
  }
  @MainActor func testNativeOptionsDefaultsAccessibilityAndSharedPreparationLeaveHistoryUntouched() async throws {
    _ = NSApplication.shared
    let source = try fixture(), store = EditorStore(document: source)
    defer { store.renderTask?.cancel() }
    let options = try IllustratorPathExportOptions(source)
    XCTAssertEqual(options.alert.messageText, "Export Paths to File")
    XCTAssertEqual(options.picker.itemTitles, ["Document Bounds", "Curve"])
    XCTAssertEqual(options.picker.accessibilityLabel(), "Path")
    XCTAssertEqual(options.selection, .init(.saved, id: source.paths![0].id))
    let actual = try await store.encodedIllustratorPaths()
    XCTAssertEqual(actual, try IllustratorPathExport.encoded(source))
    XCTAssertEqual(store.document, source); XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertNil(store.illustratorExportID); XCTAssertNil(store.illustratorExportWorker); XCTAssertFalse(store.geometryBusy)
    XCTAssertEqual(AutomationCommand.definitions.count, 267)
  }
  @MainActor func testHTTPBytesMatchNativeAndStateSchemasWithNoDocumentRevisionOrDirtyChanges() async throws {
    let helper = AutomationTests(), source = try fixture()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: source)
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first), revision = service.revision(document.store)
      let result = try await helper.request(service, path: "/v1/documents/\(share.id)/paths.ai", headers: ["X-Photato-Revision": revision])
      XCTAssertEqual(result.0.statusCode, 200, String(decoding: result.1, as: UTF8.self))
      XCTAssertEqual(result.0.mimeType, "application/postscript")
      let native = try await document.store.encodedIllustratorPaths()
      XCTAssertEqual(result.1, native)
      let selected = try await helper.request(service, path: "/v1/documents/\(share.id)/paths.ai", headers: [
        "X-Photato-Path-Target": "documentBounds", "X-Photato-Path-Filename": "Owned%20bounds.ai"])
      XCTAssertEqual(selected.0.statusCode, 200)
      XCTAssertEqual(selected.1, try IllustratorPathExport.encoded(source, selection: .init(.documentBounds), title: "Owned bounds.ai"))
      let raw = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: document.store.pathState))
      XCTAssertNoThrow(try BrushAPI.merge(raw, schema: PathAPI.stateSchema))
      XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: IllustratorPathExportAPI.capabilities))
      XCTAssertEqual(document.store.document, source); XCTAssertEqual(service.revision(document.store), revision)
      XCTAssertTrue(document.store.session.undoStack.isEmpty); XCTAssertFalse(document.isDocumentEdited)
    }
  }
  @MainActor func testHTTPPermissionRevisionInvalidMissingAndBusyGuardsDoNotExport() async throws {
    let helper = AutomationTests(), source = try fixture()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      document.store.session = EditorSession(document: source); try service.share(document)
      let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/paths.ai"
      let denied = try await helper.request(service, path: path); XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      for headers in [["X-Photato-Path-Target": "other"], ["X-Photato-Path-ID": UUID().uuidString],
        ["X-Photato-Path-Target": "saved"], ["X-Photato-Path-Target": "all", "X-Photato-Path-ID": UUID().uuidString],
        ["X-Photato-Path-Filename": "%0Ainject"], ["X-Photato-Path-Filename": "..%2Fprivate.ai"], ["X-Photato-Path-Filename": "%ZZ"]] {
        let invalid = try await helper.request(service, path: path, headers: headers)
        XCTAssertEqual(invalid.0.statusCode, 400, String(decoding: invalid.1, as: UTF8.self))
      }
      let missing = try await helper.request(service, path: path, headers: ["X-Photato-Path-Target": "saved", "X-Photato-Path-ID": UUID().uuidString])
      XCTAssertEqual(missing.0.statusCode, 404)
      let stale = try await helper.request(service, path: path, headers: ["X-Photato-Revision": "stale"]); XCTAssertEqual(stale.0.statusCode, 409)
      document.store.geometryBusy = true
      let busy = try await helper.request(service, path: path); XCTAssertEqual(busy.0.statusCode, 409)
      document.store.geometryBusy = false
      service.revoke(share.id)
      let revoked = try await helper.request(service, path: path); XCTAssertEqual(revoked.0.statusCode, 404)
      XCTAssertEqual(document.store.document, source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testNativeCancellationAndChangedSourceDiscardPreparedOutput() async throws {
    for change in [false, true] {
      let source = try fixture(), store = EditorStore(document: source), gate = IllustratorExportGate()
      defer { gate.release(); store.renderTask?.cancel() }
      store.illustratorPathPreparation = { source, selection, title in try gate.wait(); return try IllustratorPathExport.encoded(source, selection: selection, title: title) }
      let pending = Task { try await store.encodedIllustratorPaths() }
      try await wait(gate)
      XCTAssertTrue(store.geometryBusy); XCTAssertNotNil(store.illustratorExportID)
      if change { var changed = store.document; changed.name = "Changed source"; store.session = EditorSession(document: changed) } else { store.geometryTask?.cancel() }
      gate.release()
      do { _ = try await pending.value; XCTFail("Cancelled or changed export delivered bytes") }
      catch is CancellationError {} catch { XCTFail("Unexpected \(error)") }
      XCTAssertNil(store.illustratorExportID); XCTAssertNil(store.illustratorExportWorker); XCTAssertFalse(store.geometryBusy)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
  @MainActor func testRevokingTransfersCancelsOnlyOwnedAPIExport() async throws {
    let helper = AutomationTests(), source = try fixture()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let gate = IllustratorExportGate(); defer { gate.release() }
      document.store.session = EditorSession(document: source)
      document.store.illustratorPathPreparation = { source, selection, title in try gate.wait(); return try IllustratorPathExport.encoded(source, selection: selection, title: title) }
      try service.share(document); service.setDocumentTransfersEnabled(true)
      let share = try XCTUnwrap(service.shares.first)
      let pending = Task { try await helper.request(service, path: "/v1/documents/\(share.id)/paths.ai") }
      try await self.wait(gate)
      let worker = try XCTUnwrap(document.store.illustratorExportWorker)
      service.setDocumentTransfersEnabled(false); XCTAssertTrue(worker.isCancelled)
      gate.release(); let result = try await pending.value; XCTAssertNotEqual(result.0.statusCode, 200)
      XCTAssertEqual(document.store.document, source); XCTAssertTrue(document.store.session.undoStack.isEmpty)
      XCTAssertNil(document.store.illustratorExportID); XCTAssertFalse(document.store.geometryBusy)
    }
  }
}
