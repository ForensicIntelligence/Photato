import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

actor LayerContentGate {
  private var started = false
  private var released = false
  private var startWaiter: CheckedContinuation<Void, Never>?
  private var releaseWaiter: CheckedContinuation<Void, Never>?
  func enter() async {
    started = true; startWaiter?.resume(); startWaiter = nil
    if !released { await withCheckedContinuation { releaseWaiter = $0 } }
  }
  func waitForStart() async { if !started { await withCheckedContinuation { startWaiter = $0 } } }
  func release() { released = true; releaseWaiter?.resume(); releaseWaiter = nil }
}
final class LayerContentFilterWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 3, depth: depth)
    let empty = Layer(name: "Empty", content: .raster(try Surface(width: 4, height: 3, depth: depth)))
    let full = Layer(name: "Full", content: .raster(try Surface(width: 4, height: 3, depth: depth, fill: .white)))
    let group = Layer(name: "Group", content: .group(.init()))
    d.layers = [empty, full, group]; d.activeLayerID = full.id; return d
  }
  var filter: LayerPanelFilter { var f = LayerPanelFilter(); f.mode = .attribute; f.attribute = .empty; return f }
  @MainActor func stop(_ s: EditorStore) { s.layerContentFilter.close(); s.renderTask?.cancel(); s.linkedSourceController?.stop() }

  @MainActor func testNativeAsyncEmptyNotEmptySelectionHistoryRecordingAndAPIStateAtEveryDepth() async throws {
    for depth in PixelDepth.allCases {
      let d = try fixture(depth), s = EditorStore(document: d); defer { stop(s) }
      s.renderTask?.cancel(); await s.renderTask?.value
      var changes = 0; s.onChange = { _ in changes += 1 }
      try s.session.execute(.opacity(d.layers[1].id, 0.5)); try s.session.undo()
      try s.session.startActionRecording(name: "Filter view")
      let revision = s.revision
      let accepted = await s.layerContentFilter.start(filter, in: s).value
      XCTAssertTrue(accepted); XCTAssertEqual(s.layersInPanel().map(\.name), ["Empty"])
      XCTAssertNil(s.document.activeLayerID); XCTAssertTrue(s.selectedLayerIDs.isEmpty)
      XCTAssertEqual(s.revision, revision); XCTAssertEqual(changes, 0)
      XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertEqual(s.session.redoStack.count, 1)
      XCTAssertEqual(s.session.actionRecording?.snapshot.steps.count, 0)
      var expected = d; expected.activeLayerID = nil
      XCTAssertEqual(try NativeArchive.encodeChunked(s.document), try NativeArchive.encodeChunked(expected))
      var inverse = filter; inverse.attribute = .notEmpty
      try await s.applyEvaluatedLayerFilter(inverse)
      XCTAssertEqual(s.layersInPanel().map(\.name), ["Group", "Full"]); XCTAssertNil(s.document.activeLayerID)
      let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: s.layerFilterState))
      XCTAssertNoThrow(try BrushAPI.merge(value, schema: LayerFilterAPI.stateSchema))
    }
  }
  @MainActor func testCancelledSupersededStaleAndClosedQueriesCannotPublishLateResults() async throws {
    for context in ["cancel", "supersede", "stale", "lifecycle", "close"] {
      let s = EditorStore(document: try fixture()); defer { stop(s) }
      let gate = LayerContentGate(), original = s.layerPanelFilter
      s.layerContentFilter.evaluate = { source in await gate.enter(); return try source.emptyLayerIDs() }
      let request = s.layerContentFilter.start(filter, in: s)
      await gate.waitForStart()
      XCTAssertEqual(s.layerPanelFilter, original); XCTAssertEqual(s.layerContentFilter.phase, .running)
      XCTAssertFalse(s.geometryBusy)
      switch context {
      case "cancel": s.layerContentFilter.cancel()
      case "supersede": s.editLayerFilter { $0.mode = .name; $0.name = "Full" }
      case "stale": s.session.selectLayer(s.document.layers[0].id)
      case "lifecycle": s.layerPanelGeneration = UUID()
      default: s.layerContentFilter.close()
      }
      await gate.release(); let accepted = await request.value
      XCTAssertFalse(accepted, context); XCTAssertFalse(s.layerPanelFilter.requiresContentEvaluation)
      XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testNativeDocumentReadKeepsQueriesAvailableAndActualCloseCancelsTheWorker() async throws {
    _ = NSApplication.shared
    _ = CraftDocumentController(workspaces: WorkspaceLibrary())
    let doc = CraftNSDocument(model: try fixture()), s = doc.store
    defer { doc.close() }
    try await s.applyEvaluatedLayerFilter(filter)
    let replacement = try fixture(.u16)
    try doc.read(from: NativeArchive.encodeChunked(replacement), ofType: CraftNSDocument.nativeType)
    try await s.applyEvaluatedLayerFilter(filter)
    XCTAssertEqual(s.layersInPanel().map(\.name), ["Empty"])
    XCTAssertTrue(s.layerContentFilter.isResolved(in: s))
    let gate = LayerContentGate()
    s.layerContentFilter.evaluate = { source in await gate.enter(); return try source.emptyLayerIDs() }
    var inverse = filter; inverse.attribute = .notEmpty
    let request = s.layerContentFilter.start(inverse, in: s)
    await gate.waitForStart(); doc.close(); await gate.release()
    let accepted = await request.value
    XCTAssertFalse(accepted); XCTAssertFalse(s.layerContentFilter.isResolved(in: s))
    let closedRequest = await s.layerContentFilter.start(filter, in: s).value
    XCTAssertFalse(closedRequest); XCTAssertNotEqual(s.layerContentFilter.phase, .running)
  }
  @MainActor func testDerivedRefreshInvalidatesOldMembershipAndDoesNotBlockEditing() async throws {
    let s = EditorStore(document: try fixture()); defer { stop(s) }
    try await s.applyEvaluatedLayerFilter(filter)
    XCTAssertEqual(s.layersInPanel().map(\.name), ["Empty"])
    let gate = LayerContentGate()
    s.layerContentFilter.evaluate = { source in await gate.enter(); return try source.emptyLayerIDs() }
    var changed = s.document
    changed.layers[0].content = .raster(try Surface(width: 4, height: 3, fill: .black))
    s.session = EditorSession(document: changed)
    XCTAssertFalse(s.layerContentFilter.isResolved(in: s)); XCTAssertTrue(s.layersInPanel().isEmpty)
    await gate.waitForStart(); XCTAssertFalse(s.geometryBusy)
    await gate.release(); let accepted = await s.layerContentFilter.waitForCurrent()
    XCTAssertTrue(accepted); XCTAssertTrue(s.layerContentFilter.isResolved(in: s)); XCTAssertTrue(s.layersInPanel().isEmpty)
    XCTAssertEqual(s.document, changed)
  }
  @MainActor func testHTTPEmptyMatchesNativeAndPreservesAllContentAtEveryDepth() async throws {
    let h = AutomationTests()
    try await h.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, doc in
      for depth in PixelDepth.allCases {
        let d = try self.fixture(depth), native = EditorStore(document: d), s = doc.store
        defer { self.stop(native) }
        s.session = EditorSession(document: d); try service.share(doc)
        try await native.applyEvaluatedLayerFilter(self.filter)
        let code = try await h.edit(service, doc, LayerFilterAPI.command,
          ["operation": "configure", "filter": ["mode": "attribute", "attribute": "empty"]])
        XCTAssertEqual(code, 200); XCTAssertEqual(s.layerPanelFilter, native.layerPanelFilter)
        XCTAssertEqual(s.document, native.document); XCTAssertEqual(s.layersInPanel().map(\.id), native.layersInPanel().map(\.id))
        XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertNil(s.document.activeLayerID)
      }
    }
  }
  @MainActor func testHTTPRevocationCancellationAndChangedViewRejectBeforePublication() async throws {
    let h = AutomationTests()
    for context in ["revoke", "cancel", "view"] {
      try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
        let s = doc.store; s.session = EditorSession(document: try self.fixture()); try service.share(doc)
        let original = s.layerPanelFilter, gate = LayerContentGate()
        s.layerContentFilter.evaluate = { source in await gate.enter(); return try source.emptyLayerIDs() }
        let request = Task { try await h.edit(service, doc, LayerFilterAPI.command,
          ["operation": "configure", "filter": ["mode": "attribute", "attribute": "empty"]]) }
        await gate.waitForStart()
        switch context {
        case "revoke": service.revoke(try XCTUnwrap(service.shares.first?.id))
        case "cancel":
          let code = try await h.edit(service, doc, LayerFilterAPI.command, ["operation": "cancel"])
          XCTAssertEqual(code, 200)
        default: s.selectedLayerIDs = [s.document.layers[0].id]
        }
        await gate.release(); let code = try await request.value
        XCTAssertEqual(code, 409, context); XCTAssertEqual(s.layerPanelFilter, original)
        XCTAssertTrue(s.session.undoStack.isEmpty)
      }
    }
  }
}
