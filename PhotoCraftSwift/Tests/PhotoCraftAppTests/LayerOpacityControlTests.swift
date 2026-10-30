import AppKit
import PhotoCraftCore
import XCTest
@testable import PhotoCraft

final class LayerOpacityControlTests: XCTestCase {
  @MainActor func testLivePreviewCommitsOneCommandAndUndoRedo() async throws {
    let original = try CraftDocument(width: 12, height: 8)
    let store = EditorStore(document: original)
    defer { store.renderTask?.cancel() }
    store.beginLayerOpacity()
    let draft = try XCTUnwrap(store.layerOpacityDraft)
    for value in [90.0, 65, 40] { store.previewLayerOpacity(value, draftID: draft.id) }
    await store.renderTask?.value
    XCTAssertEqual(store.document, original)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(store.previewDocument.layers[0].opacity, 0.4)
    let preview = try XCTUnwrap(store.surface)
    XCTAssertEqual(preview.pixel(x: 3, y: 3).a, 0.4, accuracy: 0.005)
    store.finishLayerOpacity(draft.id)
    await store.renderTask?.value
    XCTAssertEqual(store.surface, preview)
    XCTAssertEqual(store.session.undoStack.count, 1)
    var expected = original
    try Command.opacity(original.layers[0].id, 0.4).apply(to: &expected)
    XCTAssertEqual(store.document, expected)
    let undone = await store.undo(); XCTAssertTrue(undone)
    XCTAssertEqual(store.document, original)
    let redone = await store.redo(); XCTAssertTrue(redone)
    XCTAssertEqual(store.document, expected)
  }

  @MainActor func testCancelAndUnchangedAcceptancePreserveRedoAndDirtyState() async throws {
    let store = EditorStore(document: try CraftDocument(width: 4, height: 3))
    defer { store.renderTask?.cancel() }
    store.perform(.opacity(store.activeLayer!.id, 0.7))
    _ = await store.undo()
    let original = store.document, redo = store.session.redoStack
    var changes = 0
    store.onChange = { _ in changes += 1 }
    store.beginLayerOpacity()
    let draft = try XCTUnwrap(store.layerOpacityDraft)
    store.previewLayerOpacity(0, draftID: draft.id)
    XCTAssertEqual(store.previewDocument.layers[0].opacity, 0)
    store.finishLayerOpacity(draft.id, cancel: true)
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(store.session.redoStack.map(\.id), redo.map(\.id))
    XCTAssertEqual(try store.session.redoStack.map { try $0.restoredDocument() }, try redo.map { try $0.restoredDocument() })
    store.beginLayerOpacity(); store.finishLayerOpacity()
    XCTAssertEqual(store.session.redoStack.map(\.id), redo.map(\.id))
    XCTAssertEqual(try store.session.redoStack.map { try $0.restoredDocument() }, try redo.map { try $0.restoredDocument() })
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(changes, 0)
  }

  @MainActor func testInvalidBusyLockedAndStaleDraftCannotApply() throws {
    let store = EditorStore(document: try CraftDocument(width: 4, height: 3))
    defer { store.renderTask?.cancel() }
    store.geometryBusy = true; store.beginLayerOpacity(); XCTAssertNil(store.layerOpacityDraft)
    store.geometryBusy = false
    store.perform(.lock(store.activeLayer!.id, true))
    store.beginLayerOpacity(); XCTAssertNil(store.layerOpacityDraft)
    store.perform(.lock(store.activeLayer!.id, false))
    store.beginLayerOpacity()
    let draft = try XCTUnwrap(store.layerOpacityDraft)
    for value in [Double.nan, .infinity, -1, 101] {
      store.previewLayerOpacity(value, draftID: draft.id)
    }
    XCTAssertEqual(draft.value, 1)
    store.previewLayerOpacity(25, draftID: draft.id)
    let replacement = try CraftDocument(width: 5, height: 2)
    store.session = EditorSession(document: replacement)
    store.finishLayerOpacity(draft.id)
    XCTAssertEqual(store.document, replacement)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    store.beginLayerOpacity()
    let current = try XCTUnwrap(store.layerOpacityDraft)
    store.previewLayerOpacity(10, draftID: draft.id)
    store.finishLayerOpacity(draft.id, cancel: true)
    XCTAssertTrue(store.layerOpacityDraft === current)
    XCTAssertEqual(current.value, 1)
    store.finishLayerOpacity(cancel: true)
  }

  @MainActor func testNativeSliderKeysStepClampAcceptAndCancel() throws {
    _ = NSApplication.shared
    let slider = LayerOpacitySlider.OpacitySlider()
    slider.minValue = 0; slider.maxValue = 100; slider.doubleValue = 50
    var cancelled: Bool?
    slider.finish = { cancelled = $0 }
    func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws {
      slider.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
        isARepeat: false, keyCode: code)))
    }
    try key(125); XCTAssertEqual(slider.doubleValue, 49)
    try key(126, .shift); XCTAssertEqual(slider.doubleValue, 59)
    slider.doubleValue = 99; try key(124, .shift); XCTAssertEqual(slider.doubleValue, 100)
    slider.doubleValue = 1; try key(123, .shift); XCTAssertEqual(slider.doubleValue, 0)
    try key(36); XCTAssertEqual(cancelled, false)
    try key(53); XCTAssertEqual(cancelled, true)
  }

  @MainActor func testHTTPUsesSameOpacityAndRejectsMutationDuringPreview() async throws {
    let helper = AutomationTests()
    try await helper.withService(pressedMouseButtons: { 0 }) { service, shared in
      try service.share(shared)
      let store = shared.store, original = shared.store.document
      store.beginLayerOpacity()
      let draft = try XCTUnwrap(store.layerOpacityDraft)
      store.previewLayerOpacity(35, draftID: draft.id)
      let params: [String: Any] = ["layerID": original.layers[0].id.uuidString, "opacity": 0.35]
      let busy = try await helper.edit(service, shared, "layer.opacity", params)
      XCTAssertEqual(busy, 409)
      XCTAssertEqual(store.document, original)
      store.finishLayerOpacity()
      let desktop = store.document
      _ = await store.undo()
      let applied = try await helper.edit(service, shared, "layer.opacity", params)
      XCTAssertEqual(applied, 200)
      XCTAssertEqual(store.document, desktop)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testShownPopoverOwnsKeyboardFocusAndCancelsWithoutHistory() async throws {
    _ = NSApplication.shared
    let store = EditorStore(document: try CraftDocument(width: 4, height: 3))
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 240, height: 80),
      styleMask: [.titled], backing: .buffered, defer: false)
    let button = NSButton(frame: NSRect(x: 100, y: 20, width: 30, height: 24))
    window.contentView?.addSubview(button)
    window.makeKeyAndOrderFront(nil)
    let coordinator = LayerOpacityPopup.Coordinator(store: store)
    defer {
      coordinator.close(cancel: true)
      window.orderOut(nil); window.contentView = nil
      store.renderTask?.cancel()
    }
    coordinator.toggle(button)
    try await Task.sleep(for: .milliseconds(30))
    let slider = try XCTUnwrap(coordinator.slider)
    XCTAssertTrue(coordinator.popover.isShown)
    XCTAssertTrue(slider.window?.firstResponder === slider)
    func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws {
      let window = try XCTUnwrap(slider.window)
      let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: flags, timestamp: 0, windowNumber: window.windowNumber, context: nil,
        characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code))
      window.firstResponder?.keyDown(with: event)
    }
    try key(125, .shift)
    XCTAssertEqual(store.layerOpacityDraft?.value, 0.9)
    XCTAssertEqual(store.document.layers[0].opacity, 1)
    try key(53)
    XCTAssertNil(store.layerOpacityDraft)
    XCTAssertFalse(coordinator.popover.isShown)
    XCTAssertTrue(store.session.undoStack.isEmpty)
  }
}
