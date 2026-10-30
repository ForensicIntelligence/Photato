import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class BrushReleaseTests: XCTestCase {
  @MainActor func testReleaseRetainsPendingPreviewAndRecordsOriginalCommand() async throws {
    let original = try CraftDocument(width: 320, height: 240)
    let store = EditorStore(document: original, actions: ActionLibrary(), brushes: BrushLibrary())
    defer { store.cancelBrush(); store.renderTask?.cancel() }
    store.tool = .brush; store.brush.size = 16; store.brushOptions.flow = 0.4
    store.brushOptions.smoothing.amount = 0.9
    try store.startRecordingAction(name: "Held release", set: "Test")
    store.beginBrush(.init(x: 20, y: 60, time: 0), zoom: 1)
    for i in 1..<80 { store.extendBrush(.init(x: 20 + Double(i) * 3, y: 80 + sin(Double(i) / 4) * 30, time: Double(i) * 8)) }
    let worker = try XCTUnwrap(store.interactiveBrushPreview)
    let command = try XCTUnwrap(store.brushGesture?.command)
    var expected = original; try command.apply(to: &expected)
    // Finish before the queued preview task gets the main actor again.
    store.finishBrush(); await store.geometryTask?.value; await store.renderTask?.value
    XCTAssertNil(store.error); XCTAssertFalse(store.geometryBusy)
    XCTAssertTrue(store.document == expected); XCTAssertEqual(store.session.undoStack.count, 1)
    let action = try store.stopRecordingAction(); var replay = original
    try action.apply(to: &replay); XCTAssertTrue(replay == expected)
    await store.undo(); XCTAssertTrue(store.document == original)
    _ = await store.requestHistory(redo: true).value; XCTAssertTrue(store.document == expected)
    // The retained worker has been consumed; it cannot silently create a second edit.
    do { _ = try await worker.prepareCommit(base: original, points: []); XCTFail("Finished worker accepted a second commit") } catch {}
  }

  @MainActor func testCancelledOrReplacedSessionCannotReceiveLateBrushCommit() async throws {
    for replace in [false, true] {
      let original = try CraftDocument(width: 320, height: 240)
      let store = EditorStore(document: original, brushes: BrushLibrary())
      defer { store.cancelBrush(); store.renderTask?.cancel() }
      store.tool = .brush; store.brush.size = 32
      store.beginBrush(.init(x: 20, y: 30, time: 0), zoom: 1)
      for i in 1..<80 { store.extendBrush(.init(x: 20 + Double(i) * 3, y: 80, time: Double(i) * 8)) }
      store.finishBrush()
      if replace { store.session = EditorSession(document: original) }
      else { store.geometryTask?.cancel() }
      await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertTrue(store.document == original); XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertFalse(store.geometryBusy)
    }
  }
}
