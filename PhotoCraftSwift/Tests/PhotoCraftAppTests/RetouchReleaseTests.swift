import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class RetouchReleaseTests: XCTestCase {
  private let retainedTools: [EditorTool] = [.cloneStamp, .dodge, .burn, .sponge, .blur, .sharpen, .smudge]
  private func fixture() throws -> CraftDocument {
    var doc = try CraftDocument(width: 256, height: 192)
    var pixels = try Surface(width: 256, height: 192)
    pixels.mapPixels { x, y, _ in Pixel(Float((x / 8 + y / 8) % 2) * 0.7 + 0.15, Float(y) / 191, Float(x) / 255) }
    doc.layers[0].content = .raster(pixels)
    return doc
  }
  @MainActor private func makeStore(_ tool: EditorTool, recording: Bool = false) async throws -> EditorStore {
    let state = CloneSources(); state.showOverlay = false
    let store = EditorStore(document: try fixture(), cloneState: state, actions: ActionLibrary())
    store.tool = tool; store.retouchSettings.brush.size = 12; store.retouchSettings.focus.protectDetail = false
    store.setCloneSource(at: .init(25, 25)); await store.renderTask?.value
    if recording { try store.startRecordingAction(name: "Retouch", set: "Test") }
    store.beginClone(.init(x: 70, y: 80)); await settle(store)
    return store
  }
  @MainActor private func settle(_ store: EditorStore) async {
    await store.clonePrepareTask?.value; await store.retouchPreviewTask?.value; await store.renderTask?.value
  }
  @MainActor func testPendingReleaseAcrossRetouchToolsPreservesPixelsAndHistory() async throws {
    for tool in retainedTools + [.healingBrush, .spotHealing] {
      let store = try await makeStore(tool, recording: true); defer { store.cancelClone(); store.renderTask?.cancel() }
      let original = store.document, worker = store.interactiveRetouchPreview
      for i in 1..<40 { store.extendClone(.init(x: 70 + Double(i) * 3, y: 80 + sin(Double(i) / 4) * 20)) }
      let command = try XCTUnwrap(store.cloneDraft?.command), points = try XCTUnwrap(store.cloneDraft?.points)
      var expected = original; try command.apply(to: &expected)
      store.finishClone(); await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertNil(store.error); XCTAssertFalse(store.geometryBusy)
      XCTAssertTrue(store.document == expected, "\(tool)"); XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertNil(store.interactiveRetouchPreview)
      let action = try store.stopRecordingAction()
      XCTAssertEqual(action.steps.first?.operation.unsupportedReason,
        ActionOperation(recording: command, in: original).unsupportedReason)
      await store.undo(); XCTAssertTrue(store.document == original)
      await store.redo(); XCTAssertTrue(store.document == expected)
      if retainedTools.contains(tool) {
        let worker = try XCTUnwrap(worker)
        do { _ = try await worker.prepareCommit(base: original, points: points); XCTFail("Owner was not consumed") } catch {}
      }
    }
  }
  @MainActor func testBoundaryOnUnseenFinalSampleFallsBackToCompleteFocusCommand() async throws {
    for tool in [EditorTool.blur, .sharpen, .smudge] {
      let store = try await makeStore(tool); defer { store.cancelClone(); store.renderTask?.cancel() }
      let original = store.document
      store.extendClone(.init(x: 1, y: 1))
      var expected = original; try XCTUnwrap(store.cloneDraft?.command).apply(to: &expected)
      store.finishClone(); await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertNil(store.error); XCTAssertTrue(store.document == expected); XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }
  @MainActor func testCancellationAndIdenticalSessionReplacementRejectLateCommits() async throws {
    for tool in retainedTools { for replace in [false, true] {
      let store = try await makeStore(tool); defer { store.cancelClone(); store.renderTask?.cancel() }
      let original = store.document
      store.extendClone(.init(x: 170, y: 120)); store.finishClone()
      if replace { store.session = EditorSession(document: original) } else { store.geometryTask?.cancel() }
      await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertTrue(store.document == original); XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertFalse(store.geometryBusy)
    } }
  }
  @MainActor func testNativeAPIHistoryAndBusyStateShareRetainedCommit() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store; store.session = EditorSession(document: try self.fixture())
      store.tool = .dodge; store.retouchSettings.brush.size = 12
      try service.share(document)
      let original = store.document
      store.beginClone(.init(x: 70, y: 80)); await self.settle(store)
      store.extendClone(.init(x: 160, y: 90))
      let busy = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(busy, 409)
      var expected = original; try XCTUnwrap(store.cloneDraft?.command).apply(to: &expected)
      store.finishClone(); await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertTrue(store.document == expected); XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(store.retouchPreviewState["active"] as? Bool, false)
      let undo = try await helper.edit(service, document, "history.undo"); XCTAssertEqual(undo, 200)
      XCTAssertTrue(store.document == original)
      let redo = try await helper.edit(service, document, "history.redo"); XCTAssertEqual(redo, 200)
      XCTAssertTrue(store.document == expected)
    }
  }
}
