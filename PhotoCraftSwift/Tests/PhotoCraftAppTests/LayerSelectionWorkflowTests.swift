import AppKit
import SwiftUI
import XCTest
import PhotoCraftCore
import PhotoCraftImaging
@testable import PhotoCraft

final class LayerSelectionWorkflowTests: XCTestCase {
  @MainActor func stop(_ s: EditorStore) {
    s.layerContentFilter.close(); s.renderTask?.cancel(); s.geometryTask?.cancel()
    s.linkedSourceController?.stop()
  }
  func action(_ name: String, _ operations: [ActionOperation]) -> RecordedAction {
    var a = RecordedAction(name: name)
    a.steps = operations.map { RecordedActionStep(name: "Owned selection", operation: $0) }
    return a
  }
  @MainActor func testNativeNoneAtEverySupportedComponentDepthPreservesAllSamplesHistoryAndPixelSelection() async throws {
    let helper = ModeChannelWorkflowTests()
    for mode in DocumentColorMode.componentModes { for depth in mode.depths {
      let source = try helper.fixture(mode, depth), s = EditorStore(document: source)
      defer { stop(s) }
      s.renderTask?.cancel(); await s.renderTask?.value
      let id = try XCTUnwrap(source.activeLayerID)
      try s.session.execute(.opacity(id, 0.5)); try s.session.undo()
      let pixels = try Renderer.composite(s.document)
      let revision = s.revision
      var dirty = 0; s.onChange = { _ in dirty += 1 }
      XCTAssertTrue(s.canDeselectLayers); XCTAssertTrue(s.deselectLayers())
      var expected = source; expected.activeLayerID = nil
      XCTAssertEqual(s.document, expected)
      XCTAssertEqual(try NativeArchive.encodeChunked(s.document), try NativeArchive.encodeChunked(expected))
      XCTAssertEqual(try Renderer.composite(s.document), pixels)
      XCTAssertTrue(s.selectedLayerIDs.isEmpty); XCTAssertTrue(s.session.undoStack.isEmpty)
      XCTAssertEqual(s.session.redoStack.count, 1); XCTAssertEqual(dirty, 0); XCTAssertEqual(s.revision, revision)
      let generation = s.sessionGeneration
      XCTAssertFalse(s.deselectLayers()); XCTAssertEqual(s.sessionGeneration, generation)
    } }
  }
  @MainActor func testCommandClickLastClearsActiveAndRemovingOtherRowsNeverTargetsAnUnselectedLayer() throws {
    let source = try LayerFilterWorkflowTests().fixture(), s = EditorStore(document: source)
    defer { stop(s) }
    let a = source.layers[2].id, b = source.layers[3].id
    s.select(a); s.select(a, modifiers: .command)
    XCTAssertNil(s.document.activeLayerID); XCTAssertTrue(s.groupSelectionIDs.isEmpty)
    s.select(a); s.select(b, modifiers: .command)
    XCTAssertEqual(s.groupSelectionIDs, [a, b]); XCTAssertEqual(s.document.activeLayerID, b)
    s.select(b, modifiers: .command)
    XCTAssertEqual(s.groupSelectionIDs, [a]); XCTAssertEqual(s.document.activeLayerID, a)
    let before = s.document; s.select(UUID(), modifiers: .command)
    XCTAssertEqual(s.document, before); XCTAssertEqual(s.groupSelectionIDs, [a])
    XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testBlankPanelAll16ModifiersBusyGuardsAndFactoryMenuHaveNoInventedShortcut() throws {
    let s = EditorStore(document: try LayerFilterWorkflowTests().fixture()); defer { stop(s) }
    let id = try XCTUnwrap(s.document.activeLayerID)
    let flags: [NSEvent.ModifierFlags] = [.command, .control, .option, .shift]
    for bits in 0..<16 {
      s.select(id)
      let modifier = flags.enumerated().reduce(NSEvent.ModifierFlags()) { bits & (1 << $1.offset) == 0 ? $0 : $0.union($1.element) }
      s.clickEmptyLayerPanel(modifiers: modifier)
      XCTAssertEqual(s.document.activeLayerID, bits == 0 ? nil : id)
    }
    s.select(id); s.geometryBusy = true
    XCTAssertFalse(s.deselectLayers()); XCTAssertEqual(s.document.activeLayerID, id)
    s.geometryBusy = false; s.beginLayerProtection()
    XCTAssertFalse(s.deselectLayers()); s.layerProtectionDraft = nil
    try PhotoshopMenuTests().withMenus { _, menu in
      let item = try XCTUnwrap(PhotoshopMenuTests().allItems(menu).first { $0.identifier?.rawValue == "Select > Deselect Layers" })
      XCTAssertEqual(item.action, #selector(AppDelegate.deselectLayers)); XCTAssertEqual(item.keyEquivalent, "")
    }
  }
  @MainActor func testUserDeselectionRecordsActions49AndCanStopWithoutAnActiveLayer() throws {
    let s = EditorStore(document: try LayerFilterWorkflowTests().fixture(), actions: ActionLibrary())
    defer { stop(s) }
    try s.startRecordingAction(name: "Owned no layer", set: "Owned")
    XCTAssertTrue(s.deselectLayers()); XCTAssertTrue(s.canStopRecordingAction)
    let recorded = try s.stopRecordingAction(save: false)
    XCTAssertEqual(recorded.steps.count, 1)
    guard case .deselectLayers = recorded.steps[0].operation else { return XCTFail("Missing semantic deselection.") }
    let data = try ActionLibraryFile(actions: [recorded]).encoded()
    let file = try ActionLibraryFile.decode(data)
    XCTAssertEqual(file.version, 49); XCTAssertEqual(file.requiredVersion, 49)
    // A subsequent document edit still plays as one prepared Undo transaction.
    let mixed = action("None then new layer", [.deselectLayers, .newLayer(.init(name: "After none"), below: false)])
    XCTAssertFalse(mixed.isLayerSelectionOnly)
    let original = s.document
    var playback = EditorSession(document: original)
    let prepared = try RecordedActionRenderer.prepare(mixed, in: original)
    try playback.execute(prepared.command)
    XCTAssertEqual(playback.document.layers.count, original.layers.count + 1)
    XCTAssertEqual(playback.document.layers.first { $0.id == playback.document.activeLayerID }?.name, "After none")
    XCTAssertEqual(playback.undoStack.count, 1)
    try playback.undo(); XCTAssertEqual(playback.document, original)
    var bad = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); bad["version"] = 48
    XCTAssertThrowsError(try ActionLibraryFile.decode(JSONSerialization.data(withJSONObject: bad)))
    try s.startRecordingAction(name: "Start with no layer", set: "Owned")
    _ = try s.stopRecordingAction(save: false)
    XCTAssertTrue(s.session.undoStack.isEmpty)
  }
  @MainActor func testSelectionOnlyPlaybackPublishesFinalStateAtomicallyWithoutUndoAndPreservesRedo() throws {
    let source = try LayerFilterWorkflowTests().fixture(), s = EditorStore(document: source)
    defer { stop(s) }
    let id = try XCTUnwrap(source.activeLayerID)
    try s.session.execute(.opacity(id, 0.5)); try s.session.undo()
    let recipe = action("None", [.select(.named(source.layers[3].name, occurrence: 0)), .deselectLayers])
    XCTAssertTrue(recipe.isLayerSelectionOnly)
    XCTAssertTrue(try s.applyLayerSelectionAction(recipe)); XCTAssertNil(s.document.activeLayerID)
    XCTAssertTrue(s.session.undoStack.isEmpty); XCTAssertEqual(s.session.redoStack.count, 1)
    let selection = action("Select from none", [.select(.named(source.layers[2].name, occurrence: 0))])
    XCTAssertTrue(s.canPlayAction(selection)); s.playAction(selection)
    XCTAssertEqual(s.document.activeLayerID, id); XCTAssertEqual(s.selectedLayerIDs, [id])
    XCTAssertTrue(s.session.undoStack.isEmpty)
    let huge = try CraftDocument(width: 300000, height: 300000)
    let hugeBefore = huge
    XCTAssertNil(try action("Sparse none", [.deselectLayers]).layerSelection(in: huge))
    XCTAssertEqual(huge, hugeBefore)
    let before = s.document
    let invalid = action("Atomic missing target", [.deselectLayers, .select(.named("Never exists", occurrence: 0))])
    XCTAssertThrowsError(try s.applyLayerSelectionAction(invalid)); XCTAssertEqual(s.document, before)
  }
  @MainActor func testFilteredIsolationAndContentQueryCannotResurrectDeselectedRows() async throws {
    let s = EditorStore(document: try LayerFilterWorkflowTests().fixture()); defer { stop(s) }
    s.toggleLayerIsolation(); XCTAssertFalse(s.layersInPanel().isEmpty)
    XCTAssertTrue(s.deselectLayers()); XCTAssertTrue(s.layerFilterIsolated)
    XCTAssertTrue(s.layersInPanel().isEmpty)
    try s.setLayerFilter(LayerPanelFilter())
    let id = s.document.layers[2].id; s.select(id)
    let gate = LayerContentGate()
    s.layerContentFilter.evaluate = { source in await gate.enter(); return try source.emptyLayerIDs() }
    var f = LayerPanelFilter(); f.mode = .attribute; f.attribute = .empty
    let pending = s.layerContentFilter.start(f, in: s)
    await gate.waitForStart(); XCTAssertTrue(s.deselectLayers()); await gate.release()
    let accepted = await pending.value
    XCTAssertFalse(accepted); XCTAssertNil(s.document.activeLayerID)
    XCTAssertEqual(s.layerPanelFilter, LayerPanelFilter())
  }
  @MainActor func testNativeHTTPSelectionEquivalenceAndSourceBoundRevisions() async throws {
    let h = AutomationTests()
    try await h.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, doc in
      let source = try LayerFilterWorkflowTests().fixture(), s = doc.store, native = EditorStore(document: source)
      defer { self.stop(native) }
      s.session = EditorSession(document: source); try service.share(doc)
      let id = source.layers[2].id
      let operations: [[String: Any]] = [
        ["operation": "none"], ["operation": "select", "layerID": id.uuidString],
        ["operation": "select", "layerID": id.uuidString, "mode": "toggle"],
        ["operation": "all"], ["operation": "none"],
      ]
      for parameters in operations {
        let before = service.revision(s)
        let code = try await h.edit(service, doc, LayerSelectionAPI.command, parameters)
        XCTAssertEqual(code, 200)
        let c = try AutomationCommand(data: JSONSerialization.data(withJSONObject: ["command": LayerSelectionAPI.command, "revision": "native", "parameters": parameters]))
        try native.applyLayerSelectionAPI(c)
        XCTAssertEqual(s.document, native.document); XCTAssertEqual(s.groupSelectionIDs, native.groupSelectionIDs)
        if !s.groupSelectionIDs.isEmpty { XCTAssertTrue(s.document.activeLayerID.map { s.groupSelectionIDs.contains($0) } == true) }
        XCTAssertEqual(service.revision(s).count, 64)
        XCTAssertNotEqual(service.revision(s), before)
        let value = try JSONDecoder().decode(AutomationValue.self, from: JSONSerialization.data(withJSONObject: s.layerSelectionState))
        XCTAssertNoThrow(try BrushAPI.merge(value, schema: LayerSelectionAPI.stateSchema))
      }
      XCTAssertTrue(s.session.undoStack.isEmpty)
    }
  }
  @MainActor func testHTTPInvalidMissingBusyStaleAndSelectionPlaybackAreAtomic() async throws {
    let h = AutomationTests()
    try await h.withService(actions: ActionLibrary(), pressedMouseButtons: { 0 }) { service, doc in
      let s = doc.store; s.session = EditorSession(document: try LayerFilterWorkflowTests().fixture()); try service.share(doc)
      let before = s.document
      for parameters in [["operation": "select"], ["operation": "none", "mode": "toggle"],
        ["operation": "all", "layerID": UUID().uuidString], ["operation": "select", "layerID": "invalid"]] {
        let code = try await h.edit(service, doc, LayerSelectionAPI.command, parameters)
        XCTAssertEqual(code, 400); XCTAssertEqual(s.document, before)
      }
      let missing = try await h.edit(service, doc, LayerSelectionAPI.command, ["operation": "select", "layerID": UUID().uuidString])
      XCTAssertEqual(missing, 404)
      let stale = try await h.edit(service, doc, LayerSelectionAPI.command, ["operation": "none"], revision: "old")
      XCTAssertEqual(stale, 409)
      s.beginLayerProtection()
      let busy = try await h.edit(service, doc, LayerSelectionAPI.command, ["operation": "none"])
      XCTAssertEqual(busy, 409); s.layerProtectionDraft = nil
      let recipe = self.action("Owned API no layer", [.deselectLayers]); try s.actions.save(recipe)
      let played = try await h.edit(service, doc, "actions.play", ["actionID": recipe.id.uuidString])
      XCTAssertEqual(played, 200); XCTAssertNil(s.document.activeLayerID); XCTAssertTrue(s.session.undoStack.isEmpty)
      var expected = before; expected.activeLayerID = nil; XCTAssertEqual(s.document, expected)
    }
  }
  @MainActor func testHostedPanelKeepsLazyRowsAndEmptyHitAreaWithinOwnedLayout() throws {
    _ = NSApplication.shared
    let s = EditorStore(document: try CraftDocument(width: 4, height: 3)); defer { stop(s) }
    let host = NSHostingView(rootView: WorkspaceView(store: s).layersPanelContent(.layers).frame(width: 320, height: 520))
    let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 520), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false; window.contentView = host
    defer { window.contentView = nil; window.close() }
    window.layoutIfNeeded(); host.layoutSubtreeIfNeeded()
    XCTAssertEqual(host.bounds.width, 320, accuracy: 0.5); XCTAssertEqual(host.bounds.height, 520, accuracy: 0.5)
    func emptyArea(_ view: NSView) -> LayerPanelEmptySelectionButton? {
      if let button = view as? LayerPanelEmptySelectionButton { return button }
      return view.subviews.lazy.compactMap { emptyArea($0) }.first
    }
    let area = try XCTUnwrap(emptyArea(host), "The empty layer panel area must expose its own native action.")
    XCTAssertEqual(area.accessibilityIdentifier(), "layers.deselectEmptyArea")
    XCTAssertEqual(area.accessibilityRole(), .button)
    XCTAssertGreaterThan(area.bounds.width, 300)
    XCTAssertGreaterThan(area.bounds.height, 250, "The complete blank viewport must accept deselection.")
    let center = area.convert(NSPoint(x: area.bounds.midX, y: area.bounds.midY), to: nil)
    XCTAssertTrue(host.hitTest(host.convert(center, from: nil)) === area)
    XCTAssertTrue(area.accessibilityPerformPress())
    XCTAssertNil(s.document.activeLayerID)
    s.select(s.document.layers[0].id)
    func event(_ type: NSEvent.EventType, _ offset: CGFloat = 0) throws -> NSEvent {
      try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .init(x: center.x + offset, y: center.y), modifierFlags: [],
        timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    area.mouseDown(with: try event(.leftMouseDown))
    area.mouseDragged(with: try event(.leftMouseDragged, 10))
    area.mouseUp(with: try event(.leftMouseUp))
    XCTAssertNotNil(s.document.activeLayerID, "Dragging through blank space must not deselect.")
    area.mouseDown(with: try event(.leftMouseDown)); area.mouseUp(with: try event(.leftMouseUp))
    XCTAssertNil(s.document.activeLayerID)
    if let dir = ProcessInfo.processInfo.environment["PHOTATO_TEST_CAPTURE_DIR"],
      let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: rep)
      try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: dir).appendingPathComponent("layer-selection-panel.png"))
    }
  }
}
