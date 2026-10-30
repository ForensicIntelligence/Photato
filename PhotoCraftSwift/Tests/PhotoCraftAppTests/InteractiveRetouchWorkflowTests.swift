import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class InteractiveRetouchWorkflowTests: XCTestCase {
  @MainActor private func makeStore(_ tool: EditorTool = .cloneStamp) async throws -> EditorStore {
    var doc = try CraftDocument(width: 256, height: 192)
    var pixels = try Surface(width: 256, height: 192)
    for y in 0..<192 { for x in 0..<256 {
      let red: Float = [.blur, .sharpen, .smudge].contains(tool)
        ? (Float((x/8+y/8)%2)*0.7+0.15) : Float(x)/255
      pixels.setPixel(x: x, y: y, Pixel(red, Float(y)/191, 0.3))
    } }
    doc.layers[0].content = .raster(pixels)
    doc.layers.append(Layer(name: "Adjustment", content: .adjustment(.brightnessContrast(0.04, 0.1))))
    let state = CloneSources(); state.showOverlay = false
    let store = EditorStore(document: doc, cloneState: state)
    store.tool = tool; store.retouchSettings.brush.size = 12; store.setCloneSource(at: .init(25, 25))
    if tool == .sharpen { store.retouchSettings.focus.protectDetail = false }
    await store.renderTask?.value; return store
  }
  @MainActor private func settle(_ store: EditorStore) async {
    await store.clonePrepareTask?.value; await store.retouchPreviewTask?.value; await store.renderTask?.value
  }
  @MainActor func testHTTPReportsPresentationStateAndRejectsEditsDuringGesture() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, document in
      let store = document.store; store.tool = .dodge; store.retouchSettings.brush.size = 2
      try service.share(document); let share = try XCTUnwrap(service.shares.first?.id)
      store.beginClone(.init(x: 1, y: 1)); store.extendClone(.init(x: 2, y: 1))
      await store.retouchPreviewTask?.value; await store.renderTask?.value
      let response = try await helper.request(service, path: "/v1/documents/\(share)")
      XCTAssertEqual(response.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: response.1) as? [String: Any])
      let state = try XCTUnwrap(json["retouchPreview"] as? [String: Any])
      XCTAssertEqual(state["active"] as? Bool, true); XCTAssertEqual(state["displayedSamples"] as? Int, 2)
      XCTAssertEqual(state["targetFPS"] as? Int, 60); XCTAssertEqual(state["performanceGuarantee"] as? Bool, false)
      let status = try await helper.edit(service, document, "paint.stroke", ["points": [["x": 1, "y": 1]]])
      XCTAssertEqual(status, 409)
      store.cancelClone(); await store.renderTask?.value
      XCTAssertEqual(store.retouchPreviewState["active"] as? Bool, false)
    }
  }
  @MainActor func testQueuedSamplesRetainWorkerAndCommitOneUndoStep() async throws {
    let store = try await makeStore(); defer { store.cancelClone(); store.renderTask?.cancel() }
    let before = store.document
    store.beginClone(.init(x: 70, y: 80)); await settle(store)
    let worker = try XCTUnwrap(store.interactiveRetouchPreview)
    for i in 1...160 { store.extendClone(.init(x: 70 + Double(i), y: 80 + sin(Double(i)/8)*25)) }
    await settle(store)
    XCTAssertTrue(store.interactiveRetouchPreview === worker)
    XCTAssertEqual(store.retouchPreviewSampleCount, 161)
    XCTAssertEqual(store.document, before); XCTAssertTrue(store.session.undoStack.isEmpty)
    var expected = before; try XCTUnwrap(store.cloneDraft?.command).apply(to: &expected)
    XCTAssertEqual(store.surface, try Renderer.composite(expected))
    XCTAssertEqual(store.retouchPreviewState["displayedSamples"] as? Int, 161)
    XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: store.retouchPreviewState))
    XCTAssertNotNil((BrushAPI.capabilities["interactivePreview"] as? [String: Any])?["retouching"])
    store.finishClone(); await store.geometryTask?.value; await store.renderTask?.value
    XCTAssertEqual(store.document, expected); XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertNil(store.interactiveRetouchPreview); XCTAssertNil(store.retouchPreviewTask)
    await store.undo(); XCTAssertEqual(store.document, before)
    await store.redo(); XCTAssertEqual(store.document, expected)
  }
  @MainActor func testCancelAndReplacementDiscardQueuedAndPreparingWork() async throws {
    let store = try await makeStore(); defer { store.cancelClone(); store.renderTask?.cancel() }
    let before = store.document
    store.beginClone(.init(x: 70, y: 80)); await settle(store)
    store.extendClone(.init(x: 170, y: 130))
    let pending = store.retouchPreviewTask; store.cancelClone()
    await pending?.value; await store.renderTask?.value
    XCTAssertEqual(store.document, before); XCTAssertEqual(store.surface, try Renderer.composite(before))
    XCTAssertNil(store.interactiveRetouchPreview); XCTAssertNil(store.cloneDraft)
    store.beginClone(.init(x: 40, y: 40)); let preparing = store.clonePrepareTask
    store.session = EditorSession(document: try CraftDocument(width: 32, height: 32))
    await preparing?.value; await store.renderTask?.value
    XCTAssertNil(store.cloneDraft); XCTAssertEqual(store.document.width, 32)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
  @MainActor func testFinishingBeforeSourcePreparationStillCommitsAllInputOnce() async throws {
    let store = try await makeStore(); defer { store.cancelClone(); store.renderTask?.cancel() }
    let before = store.document
    store.beginClone(.init(x: 70, y: 80)); store.extendClone(.init(x: 100, y: 95)); store.finishClone()
    await store.clonePrepareTask?.value; await store.geometryTask?.value; await store.renderTask?.value
    XCTAssertNil(store.error); XCTAssertNil(store.cloneDraft)
    XCTAssertNotEqual(store.document, before); XCTAssertEqual(store.session.undoStack.count, 1)
    await store.undo(); XCTAssertEqual(store.document, before)
  }
  @MainActor func testCompleteAlgorithmToolsRemainExactWithPacedInput() async throws {
    for tool in [EditorTool.healingBrush, .spotHealing, .dodge, .burn, .sponge, .blur, .sharpen, .smudge] {
      let store = try await makeStore(tool); let original = store.document
      store.beginClone(.init(x: 70, y: 80))
      for i in 1...20 { store.extendClone(.init(x: 70 + Double(i)*3, y: 80 + sin(Double(i))*5)) }
      await settle(store)
      XCTAssertNil(store.error); XCTAssertEqual(store.retouchPreviewSampleCount, 21)
      var expected = original; try XCTUnwrap(store.cloneDraft?.previewCommand).apply(to: &expected)
      XCTAssertEqual(store.surface, try Renderer.composite(expected), "\(tool)")
      XCTAssertEqual(store.document, original)
      store.cancelClone(); await store.renderTask?.value
      XCTAssertEqual(store.surface, try Renderer.composite(original))
    }
  }
  @MainActor func testToningAndFocusRetainWorkingStateAndCapturedSettingsThroughHistory() async throws {
    for tool in [EditorTool.dodge, .burn, .sponge, .blur, .sharpen, .smudge] {
      let store = try await makeStore(tool); let original = store.document
      store.beginClone(.init(x: 70, y: 80)); await settle(store)
      let worker = try XCTUnwrap(store.interactiveRetouchPreview)
      for i in 1...150 { store.extendClone(.init(x: 70 + Double(i), y: 80 + sin(Double(i)/8)*25)) }
      // Global tool changes cannot alter an already captured stroke.
      store.retouchSettings.brush.flow = 0; store.retouchSettings.toning.exposure = 0
      store.retouchSettings.focus.strength = 0
      await settle(store)
      XCTAssertTrue(store.interactiveRetouchPreview === worker)
      XCTAssertEqual(store.retouchPreviewSampleCount, 151); XCTAssertEqual(store.document, original)
      var expected = original; try XCTUnwrap(store.cloneDraft?.command).apply(to: &expected)
      XCTAssertTrue(expected != original, "The \(tool) history fixture must produce an actual edit")
      XCTAssertEqual(store.surface, try Renderer.composite(expected))
      store.finishClone(); await store.geometryTask?.value; await store.renderTask?.value
      XCTAssertNil(store.error); XCTAssertEqual(store.document, expected)
      XCTAssertEqual(store.session.undoStack.count, 1); XCTAssertNil(store.interactiveRetouchPreview)
      await store.undo(); XCTAssertEqual(store.document, original)
      await store.redo(); XCTAssertEqual(store.document, expected)
      store.retouchSettings.brush.flow = 1; store.retouchSettings.toning.exposure = 0.5
      store.retouchSettings.focus.strength = 0.5
      store.beginClone(.init(x: 50, y: 50)); store.extendClone(.init(x: 120, y: 100))
      let pending = store.retouchPreviewTask; store.cancelClone()
      await pending?.value; await store.renderTask?.value
      XCTAssertEqual(store.document, expected); XCTAssertEqual(store.surface, try Renderer.composite(expected))
      XCTAssertNil(store.retouchPreviewTask); XCTAssertNil(store.interactiveRetouchPreview)
    }
  }

  @MainActor func testFocusBoundaryFallsBackWithoutDroppingSamples() async throws {
    for tool in [EditorTool.blur, .sharpen, .smudge] {
      let store = try await makeStore(tool); let original = store.document
      store.beginClone(.init(x: 70,y: 80)); await settle(store)
      XCTAssertNotNil(store.interactiveRetouchPreview)
      store.extendClone(.init(x: 1,y: 1)); await settle(store)
      XCTAssertNil(store.error); XCTAssertEqual(store.retouchPreviewSampleCount,2)
      var expected = original; try XCTUnwrap(store.cloneDraft?.previewCommand).apply(to: &expected)
      XCTAssertEqual(store.surface,try Renderer.composite(expected))
      store.cancelClone(); await store.renderTask?.value
      XCTAssertEqual(store.document,original); XCTAssertEqual(store.surface,try Renderer.composite(original))
    }
  }

}
