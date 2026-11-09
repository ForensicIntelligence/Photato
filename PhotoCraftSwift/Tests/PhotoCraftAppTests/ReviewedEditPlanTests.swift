import AppKit
import ImageIO
import PhotoCraftAI
import PhotoCraftCore
import PhotoCraftImaging
import XCTest
@testable import PhotoCraft

final class ReviewedEditPlanTests: XCTestCase {
  let plan = NativeEditPlan(summary: "Desaturate, then invert the selected pixels.", operations: [.desaturate, .invert])
  @MainActor func store(_ depth: PixelDepth = .u8) throws -> EditorStore {
    _ = NSApplication.shared
    var document = try CraftDocument(width: 8, height: 6, depth: depth)
    var surface = try Surface(width: 8, height: 6, depth: depth)
    for y in 0..<6 { for x in 0..<8 {
      let pixel = Pixel(Float(x + 1) / 10, Float(y + 1) / 8, 0.25, Float((x + y) % 3 + 1) / 3)
      if depth == .f32 { surface.setLinearPixel(x: x, y: y, pixel) } else { surface.setPixel(x: x, y: y, pixel) }
    } }
    document.layers[0].content = .raster(surface)
    document.selection = IntRect(x: 1, y: 1, width: 5, height: 3)
    let store = EditorStore(document: document); store.renderTask?.cancel(); return store
  }
  func testStrictPlanFormatRejectsCodeTargetsUnknownOperationsAndUnboundedPlans() throws {
    if let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
      let layout = ["Command": MemoryLayout<Command>.size, "ActionOperation": MemoryLayout<ActionOperation>.size,
        "Layer": MemoryLayout<Layer>.size, "PreparedEdit": MemoryLayout<PreparedEdit>.size]
      try JSONSerialization.data(withJSONObject: layout, options: [.sortedKeys]).write(to: URL(fileURLWithPath: path).appendingPathComponent("command-layout.json"))
    }
    let accepted = try NativeEditPlan.decode(JSONEncoder().encode(plan)); XCTAssertEqual(accepted, plan)
    for value in [
      "{\"summary\":\"x\",\"operations\":[\"evalScript\"]}",
      "{\"summary\":\"x\",\"operations\":[\"invert\"],\"target\":\"arbitrary\"}",
      "{\"summary\":\"x\",\"operations\":[\"invert\"],\"provider\":\"onDevice\"}",
      "{\"summary\":\"x\",\"operations\":[]}", "[]", "null"
    ] { XCTAssertThrowsError(try NativeEditPlan.decode(Data(value.utf8)), value) }
    XCTAssertThrowsError(try NativeEditPlan(summary: " ", operations: [.invert]).validate())
    XCTAssertThrowsError(try NativeEditPlan(summary: String(repeating: "é", count: 257), operations: [.invert]).validate())
    XCTAssertThrowsError(try NativeEditPlan(summary: "Too many", operations: Array(repeating: .invert, count: 9)).validate())
    XCTAssertThrowsError(try NativeEditPlan.decode(Data(repeating: 32, count: 8193)))
  }
  func testRGBValidationStillChecksEveryLayerForUnownedNativeComponents() throws {
    var source = try CraftDocument(width: 2, height: 2)
    for _ in 0..<2 { var layer = source.layers[0]; layer.id = UUID(); source.layers.append(layer) }
    try source.validate()
    let native = try source.convertingMode(.init(mode: .rgb, depth: .u8))
    let samples = try XCTUnwrap(native.layers[0].nativeMode)
    for index in source.layers.indices {
      var malformed = source; malformed.layers[index].nativeMode = samples
      XCTAssertThrowsError(try malformed.validate(), "Unowned native components at layer \(index)")
    }
  }
  @MainActor func testPreviewIsReadOnlyAllDepthsThenAtomicApplyUndoRedoAndReopen() async throws {
    for depth in PixelDepth.allCases {
      let s = try store(depth); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
      let source = s.document
      try await s.prepareReviewedEditPlan(plan)
      let review = try XCTUnwrap(s.editPlanReview), prepared = try XCTUnwrap(review.prepared)
      XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
      XCTAssertEqual(prepared.before.width, 8); XCTAssertEqual(prepared.after.height, 6)
      XCTAssertEqual(review.origin, .supplied); XCTAssertTrue(s.canApplyEditPlan)
      var expected = source
      try Command.desaturate(try XCTUnwrap(source.activeLayerID)).apply(to: &expected)
      try Command.applyAdjustment(try XCTUnwrap(source.activeLayerID), .invert).apply(to: &expected)
      try s.applyReviewedEditPlan(review.id)
      XCTAssertEqual(s.document, expected); XCTAssertEqual(s.document.selection, source.selection)
      XCTAssertEqual(s.session.undoStack.count, 1); XCTAssertEqual(review.phase, "applied"); XCTAssertNil(review.prepared)
      XCTAssertThrowsError(try s.applyReviewedEditPlan(review.id))
      let reopened = try DocumentIO.decode(DocumentIO.encode(s.document, format: .native), native: true, name: "Owned edit plan")
      XCTAssertEqual(reopened, expected)
      await s.undo(); XCTAssertEqual(s.document, source)
      await s.redo(); XCTAssertEqual(s.document, expected)
      if depth == .u8, let path = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"] {
        try DocumentIO.encode(source, format: .native).write(to: URL(fileURLWithPath: path).appendingPathComponent("edit-plan-owned-source.photato"))
        try DocumentIO.encode(expected, format: .native).write(to: URL(fileURLWithPath: path).appendingPathComponent("edit-plan-owned-result.photato"))
      }
    }
  }
  @MainActor func testEveryDeclaredOperationUsesExistingNativeCommandAllDepths() async throws {
    for depth in PixelDepth.allCases { for operation in NativeEditOperation.allCases {
      let s = try store(depth); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
      let source = s.document, id = try XCTUnwrap(source.activeLayerID)
      let command: Command
      switch operation {
      case .autoTone: command = .autoCorrection(id, .tone)
      case .autoContrast: command = .autoCorrection(id, .contrast)
      case .autoColor: command = .autoCorrection(id, .color)
      case .desaturate: command = .desaturate(id)
      case .invert: command = .applyAdjustment(id, .invert)
      case .adjustment: throw CraftError.invalid("Parameterized edits are tested separately with explicit values.")
      }
      var expected = source; try command.apply(to: &expected)
      try await s.prepareReviewedEditPlan(NativeEditPlan(summary: operation.title, operations: [operation]))
      try s.applyReviewedEditPlan(try XCTUnwrap(s.editPlanReview).id)
      XCTAssertEqual(s.document, expected, "\(depth) \(operation)")
    } }
  }
  @MainActor func testEditThenUndoInvalidatesPreparedPlanEvenWhenDocumentMatches() async throws {
    let s = try store(); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    let source = s.document
    try await s.prepareReviewedEditPlan(plan); let review = try XCTUnwrap(s.editPlanReview)
    try s.executeEditorCommand(.renameLayer(source.layers[0].id, "Temporary")); await s.undo()
    XCTAssertEqual(s.document, source); XCTAssertFalse(s.canApplyEditPlan)
    XCTAssertThrowsError(try s.applyReviewedEditPlan(review.id)); XCTAssertEqual(s.document, source)
  }
  @MainActor func testReadOnlyPreviewAndCancelKeepExistingCanvasRenderingAlive() async throws {
    let s = try store(); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    s.render(); let canvas = try XCTUnwrap(s.renderTask), source = s.document
    try await s.prepareReviewedEditPlan(plan)
    XCTAssertFalse(canvas.isCancelled)
    s.cancelReviewedEditPlan(); XCTAssertFalse(canvas.isCancelled)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testProtectionAndNonCompositeTargetsRejectWithoutHistory() async throws {
    let s = try store(); defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    var locked = s.document; locked.layers[0].locked = true; s.session = EditorSession(document: locked)
    XCTAssertFalse(s.canReviewEditPlan)
    do { try await s.prepareReviewedEditPlan(plan); XCTFail("Locked target accepted") } catch { }
    XCTAssertEqual(s.document, locked); XCTAssertTrue(s.session.undoStack.isEmpty)
    s.session = EditorSession(document: try store().document); s.componentTarget = .red
    XCTAssertFalse(s.canReviewEditPlan)
  }
  @MainActor func testCancelDuringPreparationCannotPublishOrChangeReplacement() async throws {
    let s = try store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    let source = s.document
    s.editPlanPreparation = { plan, source in await gate.wait(); return try PreparedEditPlan.prepare(plan, source: source) }
    let task = Task { try await s.prepareReviewedEditPlan(plan) }
    try await ImageGenerationLifecycleTests().wait(gate)
    let old = try XCTUnwrap(s.editPlanReview); s.cancelReviewedEditPlan()
    s.editPlanPreparation = { try PreparedEditPlan.prepare($0, source: $1) }
    try await s.prepareReviewedEditPlan(NativeEditPlan(summary: "Replacement", operations: [.invert]))
    let replacement = try XCTUnwrap(s.editPlanReview)
    await gate.release()
    do { try await task.value; XCTFail("Cancelled work completed") } catch { }
    XCTAssertTrue(s.editPlanReview === replacement); XCTAssertNotEqual(old.id, replacement.id)
    XCTAssertEqual(old.phase, "cancelled"); XCTAssertTrue(s.canApplyEditPlan)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertFalse(s.geometryBusy)
  }
  @MainActor func testCloseLifecycleAndFailedPreparationRemainAtomic() async throws {
    let s = try store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    let source = s.document
    s.editPlanPreparation = { plan, source in await gate.wait(); return try PreparedEditPlan.prepare(plan, source: source) }
    let task = Task { try await s.prepareReviewedEditPlan(plan) }
    try await ImageGenerationLifecycleTests().wait(gate); s.cancelReviewedEditPlan(); s.layerPanelGeneration = UUID()
    await gate.release(); do { try await task.value; XCTFail("Closed work completed") } catch { }
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
    s.editPlanPreparation = { _, _ in throw CraftError.invalid("Owned preparation failure") }
    do { try await s.prepareReviewedEditPlan(plan); XCTFail("Failed preparation accepted") } catch { }
    XCTAssertEqual(s.editPlanReview?.phase, "failed"); XCTAssertNil(s.editPlanReview?.prepared)
    XCTAssertFalse(s.geometryBusy); XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testInjectedModelSuggestionIsPreviewedBeforeApplyingAndCancellationIsFenced() async throws {
    let s = try store(), gate = ImageGenerationLifecycleTests.Gate()
    defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    let source = s.document, expected = plan
    s.editPlanPrompt = "Owned injected suggestion; no model call"; s.editPlanProvider = .privateCloudCompute
    s.editPlanProposal = { prompt, provider in
      XCTAssertEqual(prompt, "Owned injected suggestion; no model call"); XCTAssertEqual(provider, .privateCloudCompute)
      return expected
    }
    await s.proposeReviewedEditPlan()
    XCTAssertEqual(s.editPlanReview?.origin, .privateCloudCompute); XCTAssertEqual(s.editPlanReview?.plan, plan)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertTrue(s.canApplyEditPlan)
    s.cancelReviewedEditPlan()
    s.editPlanProposal = { _, _ in await gate.wait(); return expected }
    let task = Task { await s.proposeReviewedEditPlan() }
    try await ImageGenerationLifecycleTests().wait(gate); s.cancelReviewedEditPlan(); await gate.release(); await task.value
    XCTAssertEqual(s.editPlanReview?.phase, "cancelled"); XCTAssertNil(s.editPlanReview?.prepared)
    XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertFalse(s.geometryBusy)
  }
  @MainActor func testNoOpPlanDoesNotCreateUndoOrDirtyChange() async throws {
    _ = NSApplication.shared
    let s = EditorStore(document: try CraftDocument(width: 2, height: 2)); s.renderTask?.cancel()
    defer { s.cancelReviewedEditPlan(); s.renderTask?.cancel() }
    let before = s.document
    try await s.prepareReviewedEditPlan(NativeEditPlan(summary: "Invert twice", operations: [.invert, .invert]))
    try s.applyReviewedEditPlan(try XCTUnwrap(s.editPlanReview).id)
    XCTAssertEqual(s.document, before); XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testHTTPPlanPreviewApplyRevisionPermissionsAndNativeEquivalence() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      defer { doc.store.cancelReviewedEditPlan(); doc.store.renderTask?.cancel() }
      try service.share(doc); let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/edit-plan"
      let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self.plan))
      @MainActor func body() -> [String: Any] { ["operation": "prepare", "revision": service.revision(doc.store), "plan": value] }
      let source = doc.store.document
      let denied = try await helper.request(service, path: path, body: body()); XCTAssertEqual(denied.0.statusCode, 403)
      service.setWorkspacePanelChangesEnabled(true)
      let prepared = try await helper.request(service, path: path, body: body()); XCTAssertEqual(prepared.0.statusCode, 200, String(decoding: prepared.1, as: UTF8.self))
      let review = try XCTUnwrap(doc.store.editPlanReview); XCTAssertEqual(review.origin, .supplied)
      XCTAssertEqual(doc.store.document, source); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      let revision = service.revision(doc.store)
      let forbiddenPreview = try await helper.request(service, path: path + "/previews/after", headers: ["X-Photato-Revision": revision]); XCTAssertEqual(forbiddenPreview.0.statusCode, 403)
      service.setDocumentTransfersEnabled(true)
      for side in ["before", "after"] {
        let response = try await helper.request(service, path: path + "/previews/\(side)", headers: ["X-Photato-Revision": service.revision(doc.store)])
        XCTAssertEqual(response.0.statusCode, 200)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(response.1 as CFData, nil)); XCTAssertEqual(CGImageSourceGetCount(image), 1)
      }
      let stale = try await helper.request(service, path: path, body: ["operation": "apply", "revision": "stale", "requestID": review.id.uuidString]); XCTAssertEqual(stale.0.statusCode, 409)
      let apply = try await helper.request(service, path: path, body: ["operation": "apply", "revision": service.revision(doc.store), "requestID": review.id.uuidString]); XCTAssertEqual(apply.0.statusCode, 200)
      var expected = EditorSession(document: source); try expected.executePrepared(PreparedEditPlan.prepare(self.plan, source: source).edit)
      XCTAssertEqual(doc.store.document, expected.document)
      let repeatApply = try await helper.request(service, path: path, body: ["operation": "apply", "revision": service.revision(doc.store), "requestID": review.id.uuidString]); XCTAssertEqual(repeatApply.0.statusCode, 409)
      let state = try await helper.request(service, path: path); XCTAssertEqual(state.0.statusCode, 200)
      let json = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any]); XCTAssertEqual(json["phase"] as? String, "applied")
      XCTAssertEqual((json["providers"] as? [[String: Any]])?.count, 2)
      XCTAssertEqual(json["workspaceSection"] as? String, "image"); XCTAssertEqual(json["workspacePresented"] as? Bool, false)
    }
  }
  @MainActor func testHTTPStrictPlanAndPermissionRevocationDuringPreparation() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, doc in
      defer { doc.store.cancelReviewedEditPlan(); doc.store.renderTask?.cancel() }
      try service.share(doc); service.setWorkspacePanelChangesEnabled(true)
      let share = try XCTUnwrap(service.shares.first), path = "/v1/documents/\(share.id)/edit-plan", source = doc.store.document
      let bad = try await helper.request(service, path: path, body: ["operation": "prepare", "revision": service.revision(doc.store), "plan": ["summary": "x", "operations": ["invert"], "provider": "onDevice"]]); XCTAssertEqual(bad.0.statusCode, 400)
      let gate = ImageGenerationLifecycleTests.Gate()
      doc.store.editPlanPreparation = { plan, source in await gate.wait(); return try PreparedEditPlan.prepare(plan, source: source) }
      let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self.plan))
      let request = AutomationRequest(method: "POST", path: path, headers: ["authorization": "Bearer " + (service.token ?? "")], body: try JSONSerialization.data(withJSONObject: ["operation": "prepare", "revision": service.revision(doc.store), "plan": value]))
      let task = Task { await service.handle(request) }
      try await ImageGenerationLifecycleTests().wait(gate); service.setWorkspacePanelChangesEnabled(false)
      await gate.release(); let response = await task.value; XCTAssertEqual(response.status, 409)
      XCTAssertEqual(doc.store.document, source); XCTAssertTrue(doc.store.session.undoStack.isEmpty)
      XCTAssertNil(doc.store.editPlanReview?.prepared); XCTAssertFalse(doc.store.canApplyEditPlan)
    }
  }
}
