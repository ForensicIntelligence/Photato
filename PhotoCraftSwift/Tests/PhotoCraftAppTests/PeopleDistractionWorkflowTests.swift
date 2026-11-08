import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

private struct OwnedDistractionDetector: PeopleDetecting {
  func people(in image: Surface) async throws -> [DetectedObjectMask] {
    let mask = try SelectionMask.make(.rectangle(.init(x: 10, y: 10, width: 4, height: 4)), width: image.width, height: image.height, antiAlias: false)
    return [.init(instanceID: 1, mask: mask)]
  }
}

private struct NoProtectedDistractionSubject: ForegroundDetecting {
  func mask(for image: Surface) async throws -> SelectionMask {
    try SelectionMask(width: image.width, height: image.height, bytes: Array(repeating: 0, count: image.width * image.height))
  }
}

private actor DistractionDetectionGate {
  var entered = false
  var continuation: CheckedContinuation<Void, Never>?
  func wait() async { entered = true; await withCheckedContinuation { continuation = $0 } }
  func release() { continuation?.resume(); continuation = nil }
}
private struct DelayedDistractionDetector: PeopleDetecting {
  let gate: DistractionDetectionGate
  func people(in image: Surface) async throws -> [DetectedObjectMask] {
    await gate.wait(); return try await OwnedDistractionDetector().people(in: image)
  }
}
private struct EmptyDistractionDetector: PeopleDetecting {
  func people(in image: Surface) async throws -> [DetectedObjectMask] { [] }
}
private struct FailedDistractionDetector: PeopleDetecting {
  func people(in image: Surface) async throws -> [DetectedObjectMask] { throw CraftError.unavailable("Owned person detection failure") }
}
private final class DistractionPreviewGate: @unchecked Sendable {
  let lock = NSCondition()
  var entered = false, released = false
  var ready: Bool { lock.lock(); defer { lock.unlock() }; return entered }
  func wait() throws {
    lock.lock(); entered = true
    while !released {
      if Task.isCancelled { lock.unlock(); throw CancellationError() }
      _ = lock.wait(until: Date(timeIntervalSinceNow: 0.01))
    }
    lock.unlock(); try Task.checkCancellation()
  }
  func release() { lock.lock(); released = true; lock.broadcast(); lock.unlock() }
}

final class PeopleDistractionWorkflowTests: XCTestCase {
  @MainActor func testHTTPFindPeoplePreparesRemovalWithoutChangingPixelsSelectionOrHistory() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try RemoveWorkflowTests().fixture(); doc.store.session = EditorSession(document: source)
      doc.store.peopleDetector = OwnedDistractionDetector(); doc.store.foregroundDetector = NoProtectedDistractionSubject(); try service.share(doc)
      defer { doc.store.cancelRemove(); doc.store.renderTask?.cancel() }
      let code = try await h.edit(service, doc, RemoveToolAPI.name, ["operation": "findPeople"])
      XCTAssertEqual(code, 200)
      XCTAssertEqual(doc.store.document, source); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      XCTAssertEqual(doc.store.removeDraft?.detectedPeople, 1)
      XCTAssertEqual(doc.store.removeDraft?.strokes.count, 0)
      XCTAssertNotNil(doc.store.removeDraft?.initialCoverage)
      XCTAssertNil(doc.store.peopleWorkspace.scene)

    }
  }
  @MainActor func store(_ depth: PixelDepth = .u8) throws -> EditorStore {
    _ = NSApplication.shared
    let s = EditorStore(document: try RemoveWorkflowTests().fixture(depth)); s.renderTask?.cancel()
    s.tool = .remove; s.peopleDetector = OwnedDistractionDetector(); s.foregroundDetector = NoProtectedDistractionSubject(); return s
  }
  @MainActor private func wait(_ gate: DistractionDetectionGate) async throws {
    for _ in 0..<1000 { if await gate.entered { return }; try await Task.sleep(for: .milliseconds(2)) }
    throw CraftError.invalid("Owned person detector did not start")
  }
  @MainActor func post(_ h: AutomationTests, _ service: AutomationService, _ doc: CraftNSDocument,
    _ operation: String) async throws -> (HTTPURLResponse, Data) {
    let id = try XCTUnwrap(service.shares.first?.id)
    return try await h.request(service, path: "/v1/documents/\(id)/commands",
      body: ["command": RemoveToolAPI.name, "revision": service.revision(doc.store), "parameters": ["operation": operation]])
  }
  @MainActor func testNativeDetectionIsReadOnlyAndExplicitApplyHasOneUndoAtEveryRGBDepth() async throws {
    for depth in PixelDepth.allCases {
      let s = try store(depth); defer { s.cancelRemove(); s.renderTask?.cancel() }
      let original = s.document
      try await s.detectRemovePeople()
      XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
      let mask = try XCTUnwrap(s.removeDraft?.initialCoverage)
      XCTAssertEqual(mask.bounds, .init(x: 10, y: 10, width: 4, height: 4))
      XCTAssertNotNil(s.removeDraft?.initialOverlay); XCTAssertFalse(s.canFindRemovePeople)
      s.applyRemove(); let job = try XCTUnwrap(s.geometryTask); await job.value; await s.removeCompletionTask?.value
      XCTAssertNil(s.error); XCTAssertEqual(s.session.undoStack.count, 1)
      guard case .raster(let before) = original.layers[0].content,
        case .raster(let after) = s.document.layers[0].content else { return XCTFail("Raster missing") }
      let background = depth == .f32 ? before.linearPixel(x: 0, y: 0) : before.pixel(x: 0, y: 0)
      for y in 0..<24 { for x in 0..<24 {
        let actual = depth == .f32 ? after.linearPixel(x: x, y: y) : after.pixel(x: x, y: y)
        XCTAssertEqual(actual, background, "Owned uniform donor at \(depth) \(x),\(y)")
      } }
      let result = s.document
      XCTAssertEqual(try NativeArchive.decode(NativeArchive.encodeChunked(result)), result)
      await s.undo(); XCTAssertEqual(s.document, original)
      await s.redo(); XCTAssertEqual(s.document, result)
    }
  }
  @MainActor func testRefinementAlwaysWaitsForApplyAndCancellingGestureKeepsDetectedCoverage() async throws {
    let s = try store(); defer { s.cancelRemove(); s.renderTask?.cancel() }
    let original = s.document; try await s.detectRemovePeople()
    var settings = s.removeSettings; settings.size = 1; settings.subtract = true
    try s.updateRemoveSettings(settings)
    XCTAssertTrue(s.beginRemoveStroke(at: .init(x: 10.5, y: 10.5), alternate: false))
    s.finishRemoveStroke(at: .init(x: 10.5, y: 10.5))
    XCTAssertEqual(s.removeDraft?.strokes.count, 1); XCTAssertNil(s.removeApplying)
    XCTAssertEqual(s.document, original); XCTAssertTrue(s.session.undoStack.isEmpty)
    let mask = try RemovePreparation.markCoverage(try XCTUnwrap(s.removeDraft?.request), in: original)
    XCTAssertEqual(mask.byte(at: 10 * 24 + 10), 0); XCTAssertEqual(mask.byte(at: 12 * 24 + 12), 255)
    XCTAssertTrue(s.beginRemoveStroke(at: .init(x: 12, y: 12), alternate: false)); s.cancelRemoveGesture()
    XCTAssertNotNil(s.removeDraft?.initialCoverage); XCTAssertEqual(s.removeDraft?.strokes.count, 1)
    s.cancelRemove(); XCTAssertNil(s.removeDraft); XCTAssertEqual(s.document, original)
  }
  @MainActor func testCancelledAndChangedSourceDetectionsCannotReplaceAReadyReviewOrLeaveBusyState() async throws {
    let s = try store(); defer { s.cancelRemove(); s.renderTask?.cancel() }
    let original = s.document, gate = DistractionDetectionGate()
    s.peopleDetector = DelayedDistractionDetector(gate: gate)
    let old = Task { try await s.detectRemovePeople() }; try await wait(gate)
    XCTAssertTrue(s.geometryBusy); XCTAssertNotNil(s.removeDetectionID)
    s.cancelRemove(); s.peopleDetector = OwnedDistractionDetector(); try await s.detectRemovePeople()
    let replacement = try XCTUnwrap(s.removeDraft?.initialCoverage)
    await gate.release(); do { try await old.value; XCTFail("Cancelled detector published") } catch { }
    XCTAssertEqual(s.removeDraft?.initialCoverage, replacement); XCTAssertFalse(s.geometryBusy)
    s.cancelRemove()
    let changed = DistractionDetectionGate(); s.peopleDetector = DelayedDistractionDetector(gate: changed)
    let task = Task { try await s.detectRemovePeople() }; try await wait(changed)
    var other = original; other.name = "Owned replacement"; s.session = EditorSession(document: other)
    await changed.release(); do { try await task.value; XCTFail("Changed source published") } catch { }
    XCTAssertEqual(s.document, other); XCTAssertNil(s.removeDraft); XCTAssertFalse(s.geometryBusy)
    XCTAssertNil(s.removeDetectionID); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testEmptyFailedAndUnavailableTargetsNeverStageDestructiveWork() async throws {
    let s = try store(); defer { s.cancelRemove(); s.renderTask?.cancel() }
    let source = s.document; s.peopleDetector = EmptyDistractionDetector(); try await s.detectRemovePeople()
    XCTAssertNil(s.removeDraft); XCTAssertFalse(s.geometryBusy); XCTAssertTrue(s.status.contains("No people"))
    s.peopleDetector = FailedDistractionDetector()
    do { try await s.detectRemovePeople(); XCTFail("Failed model succeeded") } catch { }
    XCTAssertNil(s.removeDraft); XCTAssertFalse(s.geometryBusy); XCTAssertNil(s.removeDetectionID)
    s.componentTarget = .red; XCTAssertFalse(s.canFindRemovePeople)
    do { try await s.detectRemovePeople(); XCTFail("Component target accepted") } catch { }
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPMaskPreviewRequiresPermissionAndMatchesExactRefinedNativeCoverage() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let original = try RemoveWorkflowTests().fixture(); doc.store.session = EditorSession(document: original)
      doc.store.peopleDetector = OwnedDistractionDetector(); doc.store.foregroundDetector = NoProtectedDistractionSubject(); try service.share(doc)
      defer { doc.store.cancelRemove(); doc.store.renderTask?.cancel() }
      let found = try await h.edit(service, doc, RemoveToolAPI.name, ["operation": "findPeople"]); XCTAssertEqual(found, 200)
      let denied = try await self.post(h, service, doc, "preview"); XCTAssertEqual(denied.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      let preview = try await self.post(h, service, doc, "preview"); XCTAssertEqual(preview.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: preview.1) as? [String: Any])
      let mask = try XCTUnwrap(json["removalMask"] as? [String: Any])
      let bytes = try XCTUnwrap((mask["coverageBase64"] as? String).flatMap { Data(base64Encoded: $0) })
      var expected = Data(repeating: 0, count: 24 * 24)
      for y in 10..<14 { for x in 10..<14 { expected[y * 24 + x] = 255 } }
      XCTAssertEqual(bytes, expected); XCTAssertEqual(mask["meaning"] as? String, "marksBeforeDocumentSelection")
      let refined = try await h.edit(service, doc, RemoveToolAPI.name,
        ["operation": "stroke", "stroke": ["size": 1, "subtract": true, "points": [[10.5, 10.5]]]])
      XCTAssertEqual(refined, 200); XCTAssertEqual(doc.store.document, original)
      XCTAssertTrue(doc.store.session.undoStack.isEmpty); XCTAssertNotNil(doc.store.removeDraft)
      let current = try RemovePreparation.markCoverage(try XCTUnwrap(doc.store.removeDraft?.request), in: original)
      XCTAssertEqual(current.byte(at: 10 * 24 + 10), 0)
      let expectedEdit = try RemovePreparation.prepare(try XCTUnwrap(doc.store.removeDraft?.request), document: original).result
      let applied = try await h.edit(service, doc, RemoveToolAPI.name, ["operation": "apply"])
      XCTAssertEqual(applied, 200); XCTAssertEqual(doc.store.document, expectedEdit); XCTAssertEqual(doc.store.session.undoStack.count, 1)
      let undone = try await h.edit(service, doc, "history.undo"); XCTAssertEqual(undone, 200); XCTAssertEqual(doc.store.document, original)
      if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try preview.1.write(to: URL(fileURLWithPath: path).appendingPathComponent("people-removal-mask-response.json"))
        try bytes.write(to: URL(fileURLWithPath: path).appendingPathComponent("people-removal-mask.u8"))
      }
    }
  }
  @MainActor func testHTTPDetectionCancellationAndRevocationCannotPublishLateMasks() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let original = try RemoveWorkflowTests().fixture(); doc.store.session = EditorSession(document: original); doc.store.foregroundDetector = NoProtectedDistractionSubject(); try service.share(doc)
      defer { doc.store.cancelRemove(); doc.store.renderTask?.cancel() }
      for revoke in [false, true] {
        let gate = DistractionDetectionGate(); doc.store.peopleDetector = DelayedDistractionDetector(gate: gate)
        let pending = Task { try await h.edit(service, doc, RemoveToolAPI.name, ["operation": "findPeople"]) }
        try await self.wait(gate)
        XCTAssertEqual(RemoveToolAPI.state(doc.store)["busy"] as? Bool, true)
        XCTAssertEqual(RemoveToolAPI.state(doc.store)["detectingPeople"] as? Bool, true)
        if revoke { service.revoke(try XCTUnwrap(service.shares.first?.id)) }
        else {
          let cancelled = try await h.edit(service, doc, RemoveToolAPI.name, ["operation": "cancel"])
          XCTAssertEqual(cancelled, 200)
        }
        await gate.release(); let status = try await pending.value; XCTAssertEqual(status, 409)
        XCTAssertEqual(doc.store.document, original); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
        XCTAssertNil(doc.store.removeDraft); XCTAssertFalse(doc.store.geometryBusy); XCTAssertNil(doc.store.removeDetectionID)
        if revoke { try service.share(doc) }
      }
    }
  }
  @MainActor func testHTTPPreviewRevocationRejectsCapturedBytesAndKeepsReviewAndDocument() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let original = try RemoveWorkflowTests().fixture(); doc.store.session = EditorSession(document: original)
      doc.store.peopleDetector = OwnedDistractionDetector(); doc.store.foregroundDetector = NoProtectedDistractionSubject(); try service.share(doc); service.setDocumentTransfersEnabled(true)
      defer { doc.store.cancelRemove(); doc.store.renderTask?.cancel() }
      let found = try await h.edit(service, doc, RemoveToolAPI.name, ["operation": "findPeople"]); XCTAssertEqual(found, 200)
      let gate = DistractionPreviewGate(); defer { gate.release() }
      doc.store.removePreviewPreparation = { request, source in try gate.wait(); return try RemoveMarkPreview.encode(request, source) }
      let pending = Task { try await self.post(h, service, doc, "preview") }
      for _ in 0..<1000 { if gate.ready { break }; try await Task.sleep(for: .milliseconds(2)) }
      XCTAssertTrue(gate.ready); service.setDocumentTransfersEnabled(false); gate.release()
      let response = try await pending.value; XCTAssertEqual(response.0.statusCode, 409)
      let error = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any]); XCTAssertNil(error["removalMask"])
      XCTAssertNotNil(doc.store.removeDraft); XCTAssertEqual(doc.store.document, original); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
    }
  }

}
