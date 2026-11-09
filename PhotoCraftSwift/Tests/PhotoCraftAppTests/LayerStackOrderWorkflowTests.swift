import AppKit
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

private final class StackOrderGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var ready = false
  func wait() { condition.lock(); while !ready { condition.wait() }; condition.unlock() }
  func release() { condition.lock(); ready = true; condition.broadcast(); condition.unlock() }
}

final class LayerStackOrderWorkflowTests: XCTestCase {
  func fixture(_ depth: PixelDepth = .u8) throws -> CraftDocument {
    var d = try CraftDocument(width: 4, height: 3, depth: depth)
    d.layers = try Array("ABCDE").enumerated().map { i, name in
      var layer = Layer(name: String(name), content: .raster(try Surface(width: 4, height: 3,
        depth: depth, fill: Pixel(Float(i) / 4, 0.25, 0.75, 0.5))))
      layer.mask = try Surface(width: 4, height: 3, depth: depth, fill: .white)
      layer.colorLabel = .blue
      return layer
    }
    d.activeLayerID = d.layers[1].id
    d.selection = .init(x: 1, y: 0, width: 2, height: 2)
    return d
  }
  let expected: [LayerStackOperation: [String]] = [
    .bringToFront: ["A", "C", "E", "B", "D"], .bringForward: ["A", "C", "B", "E", "D"],
    .sendBackward: ["B", "A", "D", "C", "E"], .sendToBack: ["B", "D", "A", "C", "E"],
    .reverse: ["A", "D", "C", "B", "E"],
  ]
  @MainActor func stop(_ s: EditorStore) { s.geometryTask?.cancel(); s.renderTask?.cancel() }
  @MainActor func waitForWork(_ s: EditorStore) async {
    let limit = Date().addingTimeInterval(10)
    while !s.geometryBusy && Date() < limit { await Task.yield() }
    XCTAssertTrue(s.geometryBusy)
  }

  @MainActor func testAllFiveNativeAndHTTPWorkflowsExactBytesHistoryAndSelectionAtEveryDepth() async throws {
    let h = AutomationTests()
    try await h.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, doc in
      for depth in PixelDepth.allCases { for operation in LayerStackOperation.allCases {
        let source = try self.fixture(depth), ids = [source.layers[1].id, source.layers[3].id]
        let native = EditorStore(document: source, actions: ActionLibrary())
        defer { self.stop(native) }
        native.selectedLayerIDs = Set(ids)
        native.maskEditingLayerID = source.layers[1].id
        let target = native.selectedMaskPaintTarget
        native.arrangeLayerStack(operation); await native.geometryTask?.value
        XCTAssertNil(native.error)
        XCTAssertEqual(native.document.layers.map(\.name), self.expected[operation])
        XCTAssertEqual(native.document.activeLayerID, source.activeLayerID)
        XCTAssertEqual(native.document.selection, source.selection)
        XCTAssertEqual(native.selectedLayerIDs, Set(ids)); XCTAssertEqual(native.selectedMaskPaintTarget, target)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: native.document.layers.map { ($0.id, $0) }),
          Dictionary(uniqueKeysWithValues: source.layers.map { ($0.id, $0) }))
        doc.store.session = EditorSession(document: source); doc.store.selectedLayerIDs = Set(ids)
        doc.store.maskEditingLayerID = source.layers[1].id
        try service.share(doc)
        let status = try await h.edit(service, doc, LayerStackOrderAPI.command,
          ["layerIDs": ids.map(\.uuidString), "operation": operation.rawValue])
        XCTAssertEqual(status, 200); XCTAssertEqual(doc.store.document, native.document)
        XCTAssertEqual(try NativeArchive.encodeChunked(doc.store.document), try NativeArchive.encodeChunked(native.document))
        XCTAssertEqual(try Renderer.composite(doc.store.document), try Renderer.composite(native.document))
        XCTAssertEqual(native.session.undoStack.count, 1); XCTAssertEqual(doc.store.session.undoStack.count, 1)
        let arranged = native.document
        await native.undo(); XCTAssertEqual(native.document, source)
        await native.redo(); XCTAssertEqual(native.document, arranged)
        let undo = try await h.edit(service, doc, "history.undo"); XCTAssertEqual(undo, 200)
        XCTAssertEqual(doc.store.document, source)
        let redo = try await h.edit(service, doc, "history.redo"); XCTAssertEqual(redo, 200)
        XCTAssertEqual(doc.store.document, arranged)
      } }
    }
  }

  @MainActor func testMenuFactoryBindingsAvailabilityAndAllModifierCursors() throws {
    try PhotoshopMenuTests().withMenus { _, menu in
      for operation in LayerStackOperation.allCases {
        let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first {
          $0.identifier?.rawValue == "Layer > Arrange > " + operation.title
        })
        XCTAssertEqual(item.action, #selector(AppDelegate.arrangeLayerStack(_:)))
        let front = operation == .bringToFront || operation == .bringForward
        XCTAssertEqual(item.keyEquivalent, operation == .reverse ? "" : (front ? "]" : "["))
        if operation != .reverse {
          XCTAssertEqual(item.keyEquivalentModifierMask,
            operation == .bringToFront || operation == .sendToBack ? [.shift, .command] : [.command])
        }
      }
    }
    let source = try fixture(), s = EditorStore(document: source)
    defer { stop(s) }
    s.selectedLayerIDs = [source.layers[1].id, source.layers[3].id]
    XCTAssertTrue(LayerStackOperation.allCases.allSatisfy(s.canArrangeLayerStack))
    let canvas = CraftCanvas(store: s), flags: [NSEvent.ModifierFlags] = [.control, .command, .option, .shift]
    for bits in 0..<16 {
      let current = flags.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) != 0 ? $0.union($1.element) : $0 }
      canvas.updateCursorModifiers(current); let before = canvas.toolCursor
      _ = s.layerStackOrderState
      canvas.updateCursorModifiers(current); XCTAssertEqual(canvas.toolCursor, before)
    }
    s.selectedLayerIDs = [source.layers.last!.id]
    XCTAssertFalse(s.canArrangeLayerStack(.bringToFront)); XCTAssertFalse(s.canArrangeLayerStack(.bringForward))
    XCTAssertFalse(s.canArrangeLayerStack(.reverse))
    s.arrangeLayerStack(.bringToFront); XCTAssertTrue(s.session.undoStack.isEmpty)
    s.coalescingChanges = true; XCTAssertFalse(s.canArrangeLayerContext); s.coalescingChanges = false
    s.aiBusy = true; XCTAssertFalse(s.canArrangeLayerContext); s.aiBusy = false
  }

  @MainActor func testNativeCancellationChangedSelectionSessionAndClosedOwnerAreAtomic() async throws {
    for scenario in ["cancel", "selection", "session", "close"] {
      let source = try fixture(), doc = CraftNSDocument(model: source), s = doc.store
      defer { stop(s); doc.updateChangeCount(.changeCleared); doc.close() }
      s.selectedLayerIDs = [source.layers[1].id, source.layers[3].id]
      let gate = StackOrderGate(); defer { gate.release() }
      s.layerStackOrderPreparation = { _, request in gate.wait(); try Task.checkCancellation(); return .stackLayers(request) }
      s.arrangeLayerStack(.bringToFront); let task = s.geometryTask
      XCTAssertTrue(s.geometryBusy)
      switch scenario {
      case "cancel": task?.cancel()
      case "selection": s.selectedLayerIDs = [source.layers[2].id]
      case "session": s.session = EditorSession(document: source)
      default: doc.close()
      }
      gate.release(); await task?.value
      XCTAssertEqual(s.document, source, scenario); XCTAssertTrue(s.session.undoStack.isEmpty, scenario)
    }
  }

  @MainActor func testHTTPInvalidUnknownBusyStaleLockedRevokedAndNoopRequestsAreAtomic() async throws {
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      let source = try self.fixture(), s = doc.store, ids = [source.layers[1].id, source.layers[3].id]
      s.session = EditorSession(document: source); s.selectedLayerIDs = Set(ids); try service.share(doc)
      let parameters: [String: Any] = ["layerIDs": ids.map(\.uuidString), "operation": "bringToFront"]
      for bad: [String: Any] in [["layerIDs": []], ["layerIDs": ["bad"]], ["layerIDs": [ids[0].uuidString, ids[0].uuidString]],
        ["operation": "unknown"], ["operation": 3], ["unknown": true]] {
        let code = try await h.edit(service, doc, LayerStackOrderAPI.command, parameters.merging(bad) { _, new in new })
        XCTAssertEqual(code, 400); XCTAssertEqual(s.document, source)
      }
      let unknown = try await h.edit(service, doc, LayerStackOrderAPI.command, ["layerIDs": [UUID().uuidString], "operation": "reverse"])
      XCTAssertEqual(unknown, 404)
      let stale = try await h.edit(service, doc, LayerStackOrderAPI.command, parameters, revision: "stale")
      XCTAssertEqual(stale, 409)
      s.beginLayerProtection()
      let busy = try await h.edit(service, doc, LayerStackOrderAPI.command, parameters)
      XCTAssertEqual(busy, 409); s.layerProtectionDraft = nil
      var locked = source; locked.layers[1].locked = true; s.session = EditorSession(document: locked)
      let denied = try await h.edit(service, doc, LayerStackOrderAPI.command, parameters)
      XCTAssertEqual(denied, 422); XCTAssertEqual(s.document, locked)
      s.session = EditorSession(document: source); s.error = nil
      let noop = try await h.edit(service, doc, LayerStackOrderAPI.command,
        ["layerIDs": [source.layers.last!.id.uuidString], "operation": "bringToFront"])
      XCTAssertEqual(noop, 200); XCTAssertTrue(s.session.undoStack.isEmpty)
      let gate = StackOrderGate(); defer { gate.release() }
      s.layerStackOrderPreparation = { _, request in gate.wait(); try Task.checkCancellation(); return .stackLayers(request) }
      let task = Task { try await h.edit(service, doc, LayerStackOrderAPI.command, parameters) }
      await self.waitForWork(s)
      service.revoke(try XCTUnwrap(service.shares.first?.id)); gate.release()
      let revoked = try await task.value
      XCTAssertEqual(revoked, 409); XCTAssertEqual(s.document, source); XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }

  @MainActor func testPortableActions48RetainSemanticTargetsAndEarlierFeatureMinima() async throws {
    let source = try fixture(.f32), library = ActionLibrary(), s = EditorStore(document: source, actions: library)
    defer { stop(s) }
    s.selectedLayerIDs = [source.layers[1].id, source.layers[3].id]
    try s.startRecordingAction(name: "Arrange selected layers", set: "Owned tests")
    s.arrangeLayerStack(.reverse); await s.geometryTask?.value
    let action = try s.stopRecordingAction(), file = try ActionLibraryFile.decode(library.exportFile(action.id))
    XCTAssertEqual(file.version, 48); XCTAssertEqual(action.steps.count, 1)
    var wire = try XCTUnwrap(JSONSerialization.jsonObject(with: library.exportFile(action.id)) as? [String: Any])
    wire["version"] = 47
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: wire)))
    var other = try fixture(.f32), expected = other
    let byName = Dictionary(uniqueKeysWithValues: other.layers.map { ($0.name, $0) })
    expected.layers = try self.expected[.reverse]!.map { try XCTUnwrap(byName[$0]) }
    try action.apply(to: &other); XCTAssertEqual(other, expected)
    await s.undo(); XCTAssertEqual(s.document, source)
    s.playAction(file.actions[0]); await s.geometryTask?.value
    XCTAssertNil(s.error); XCTAssertEqual(s.document.layers.map(\.name), self.expected[.reverse])
    XCTAssertEqual(s.session.undoStack.count, 1)
    XCTAssertEqual(ActionLibraryFile.maximumVersion, 61)
  }

  @MainActor func testDiscoverySchemaStateAndPublishedContractMetadata() async throws {
    let source = try fixture(), s = EditorStore(document: source)
    defer { stop(s) }
    s.selectedLayerIDs = [source.layers[1].id, source.layers[3].id]
    let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: s.layerStackOrderState))
    XCTAssertNoThrow(try BrushAPI.merge(value, schema: LayerStackOrderAPI.stateSchema))
    XCTAssertTrue(JSONSerialization.isValidJSONObject(LayerStackOrderAPI.capabilities))
    let definition = try XCTUnwrap(AutomationCommand.definitions.first { $0.name == LayerStackOrderAPI.command })
    XCTAssertEqual(Set(definition.parameters.keys), Set(["layerIDs", "operation"]))
    XCTAssertEqual(AutomationCommand.definitions.count, AutomationTests.expectedCommandCount)
    let h = AutomationTests()
    try await h.withService(pressedMouseButtons: { 0 }) { service, doc in
      try service.share(doc)
      let caps = try await h.request(service, path: "/v1/capabilities")
      let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: caps.1) as? [String: Any])
      XCTAssertNotNil(payload["layerStackOrder"])
      let id = try XCTUnwrap(service.shares.first?.id)
      let state = try await h.request(service, path: "/v1/documents/\(id)")
      let body = try XCTUnwrap(JSONSerialization.jsonObject(with: state.1) as? [String: Any])
      XCTAssertNotNil(body["layerStackOrder"])
    }
  }
}
