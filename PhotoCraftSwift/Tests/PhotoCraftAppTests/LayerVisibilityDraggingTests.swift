import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI
import XCTest

@testable import PhotoCraft

final class LayerVisibilityDraggingTests: XCTestCase {
  @MainActor func testPreviewIsTransientAtomicAndUndoable() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let before = store.document
    let ids = before.layers.map(\.id)
    store.selectedLayerIDs = [ids[1], ids[2]]
    var changes = 0
    store.onChange = { _ in changes += 1 }
    let token = try XCTUnwrap(store.beginLayerVisibilityDrag(ids[0]))
    store.extendLayerVisibilityDrag(token, over: [ids[2], ids[1], ids[0], UUID()])
    XCTAssertEqual(store.previewDocument.layers.map(\.visible), [false, false, false])
    XCTAssertEqual(store.document, before)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertEqual(changes, 0)
    let preview = try Renderer.composite(store.previewDocument)
    store.finishLayerVisibilityDrag(token)
    XCTAssertEqual(try Renderer.composite(store.document), preview)
    XCTAssertEqual(store.document.layers.map(\.id), ids)
    XCTAssertEqual(store.selectedLayerIDs, [ids[1], ids[2]])
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(changes, 1)
    await store.undo()
    XCTAssertEqual(store.document, before)
    await store.redo()
    XCTAssertEqual(store.document.layers.map(\.visible), [false, false, false])
  }

  @MainActor func testHiddenStartShowsRowsAndRevisitingNeverRetoggles() async throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.perform(.visibility(ids[0], false))
    store.perform(.visibility(ids[2], false))
    let token = try XCTUnwrap(store.beginLayerVisibilityDrag(ids[0]))
    store.extendLayerVisibilityDrag(token, over: [ids[1], ids[2]])
    store.extendLayerVisibilityDrag(token, over: [ids[2], ids[1], ids[0]])
    XCTAssertEqual(store.previewDocument.layers.map(\.visible), [true, true, true])
    XCTAssertTrue(store.layerEyeVisible(store.document.layers[0]))
    store.finishLayerVisibilityDrag(token)
    await store.undo()
    XCTAssertEqual(store.document.layers.map(\.visible), [false, true, false])
  }

  @MainActor func testCancellationPreservesBytesDirtyHistoryAndSoloRestoration() throws {
    let doc = CraftNSDocument(model: try GroupWorkflowTests().store().document)
    defer { doc.close() }
    let store = doc.store
    let ids = store.document.layers.map(\.id)
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    let before = store.document
    let count = store.session.undoStack.count
    doc.updateChangeCount(.changeCleared)
    let data = try doc.data(ofType: CraftNSDocument.nativeType)
    let token = try XCTUnwrap(store.beginLayerVisibilityDrag(ids[1]))
    store.extendLayerVisibilityDrag(token, over: ids)
    XCTAssertEqual(
      try doc.data(ofType: CraftNSDocument.nativeType), data,
      "Autosave contains committed document state, never the temporary preview")
    store.finishLayerVisibilityDrag(token, cancel: true)
    XCTAssertEqual(store.document, before)
    XCTAssertFalse(doc.isDocumentEdited)
    XCTAssertEqual(store.session.undoStack.count, count)
    XCTAssertNotNil(store.layerVisibilityIsolation)
    store.toggleLayerVisibility(ids[0], modifiers: .option)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, true, true])
  }

  @MainActor func testDraftBlocksCompetingCommandsAndStaleTokensCannotFinishNewGesture()
    async throws
  {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let before = store.document
    let ids = before.layers.map(\.id)
    let first = try XCTUnwrap(store.beginLayerVisibilityDrag(ids[0]))
    store.perform(.visibility(ids[1], false))
    store.setLayerColor(.red)
    store.select(ids[2])
    await store.undo()
    XCTAssertNil(store.beginLayerVisibilityDrag(ids[1]))
    XCTAssertFalse(store.canBeginLayerCreation)
    XCTAssertEqual(store.document, before)
    store.finishLayerVisibilityDrag(first, cancel: true)
    let second = try XCTUnwrap(store.beginLayerVisibilityDrag(ids[1]))
    store.extendLayerVisibilityDrag(first, over: ids)
    store.finishLayerVisibilityDrag(first)
    XCTAssertEqual(store.layerVisibilityDraft?.id, second)
    store.finishLayerVisibilityDrag(second)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, false, true])
  }

  @MainActor func testExternalEditsAndDocumentReplacementNeverReceiveStalePreview() throws {
    let doc = CraftNSDocument(model: try GroupWorkflowTests().store().document)
    defer { doc.close() }
    let store = doc.store
    let ids = store.document.layers.map(\.id)
    let first = try XCTUnwrap(store.beginLayerVisibilityDrag(ids[0]))
    try store.session.execute(.renameLayer(ids[1], "External edit"))
    let external = store.document
    store.finishLayerVisibilityDrag(first)
    XCTAssertEqual(store.document, external)
    let second = try XCTUnwrap(store.beginLayerVisibilityDrag(ids[0]))
    let replacement = try CraftNSDocument.blankModel(width: 3, height: 2)
    try doc.read(from: NativeArchive.encode(replacement), ofType: CraftNSDocument.nativeType)
    store.extendLayerVisibilityDrag(second, over: ids)
    store.finishLayerVisibilityDrag(second)
    XCTAssertEqual(store.document, replacement)
    XCTAssertNil(store.layerVisibilityDraft)
    _ = store.beginLayerVisibilityDrag(replacement.layers[0].id)
    doc.close()
    XCTAssertNil(store.layerVisibilityDraft)
  }

  @MainActor func testWindowClosureAndForeignWindowReleaseCancelTracking() throws {
    let store = try GroupWorkflowTests().store()
    let tracker = LayerEyeTracking()
    let window = window()
    let other = self.window()
    defer {
      tracker.cancel()
      window.close()
      other.close()
      store.renderTask?.cancel()
    }
    let buttons = controls(store, tracker: tracker, in: try XCTUnwrap(window.contentView))
    let before = store.document
    for close in [false, true] {
      buttons[0].mouseDown(with: try event(.leftMouseDown, NSPoint(x: 11, y: 18), in: window))
      buttons[0].mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 11, y: 55), in: window))
      if close {
        window.close()
      } else {
        buttons[0].mouseUp(with: try event(.leftMouseUp, NSPoint(x: 11, y: 55), in: other))
      }
      XCTAssertNil(tracker.store)
      XCTAssertNil(store.layerVisibilityDraft)
      XCTAssertEqual(store.document, before)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testStaleExternalMutationDuringNativeDragKeepsExternalEdit() throws {
    let store = try GroupWorkflowTests().store()
    let tracker = LayerEyeTracking()
    let window = window()
    defer {
      tracker.cancel()
      window.close()
      store.renderTask?.cancel()
    }
    let buttons = controls(store, tracker: tracker, in: try XCTUnwrap(window.contentView))
    buttons[0].mouseDown(with: try event(.leftMouseDown, NSPoint(x: 11, y: 18), in: window))
    buttons[0].mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 11, y: 55), in: window))
    try store.session.execute(.renameLayer(buttons[2].layerID, "External"))
    let external = store.document
    buttons[0].mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 11, y: 92), in: window))
    buttons[0].mouseUp(with: try event(.leftMouseUp, NSPoint(x: 11, y: 92), in: window))
    XCTAssertEqual(store.document, external)
    XCTAssertNil(store.layerVisibilityDraft)
    XCTAssertNil(tracker.store)
    XCTAssertEqual(store.session.undoStack.count, 1)
  }

  @MainActor func event(
    _ type: NSEvent.EventType, _ point: NSPoint, in window: NSWindow,
    modifiers: NSEvent.ModifierFlags = []
  ) throws -> NSEvent {
    try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type, location: point, modifierFlags: modifiers,
        timestamp: 0, windowNumber: window.windowNumber, context: nil,
        eventNumber: 0, clickCount: 1, pressure: 1))
  }

  @MainActor func controls(
    _ store: EditorStore, tracker: LayerEyeTracking, in root: NSView,
    y: CGFloat = 0
  ) -> [LayerEyeButton] {
    store.document.layers.enumerated().map { index, layer in
      let button = LayerEyeButton()
      button.store = store
      button.layerID = layer.id
      button.tracking = tracker
      tracker.buttons.add(button)
      button.frame = NSRect(x: 0, y: y + CGFloat(index) * 37, width: 22, height: 36)
      root.addSubview(button)
      return button
    }
  }

  @MainActor func window() -> NSWindow {
    _ = NSApplication.shared
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    return window
  }

  @MainActor func testNativeDragCrossesSkippedRowsAndDoesNotBecomeClickOnRelease() throws {
    let store = try GroupWorkflowTests().store()
    let tracker = LayerEyeTracking()
    let window = window()
    defer {
      tracker.cancel()
      window.close()
      store.renderTask?.cancel()
    }
    let buttons = controls(store, tracker: tracker, in: try XCTUnwrap(window.contentView))
    let before = store.document
    buttons[0].mouseDown(with: try event(.leftMouseDown, NSPoint(x: 11, y: 18), in: window))
    buttons[0].mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 11, y: 92), in: window))
    XCTAssertEqual(store.previewDocument.layers.map(\.visible), [false, false, false])
    XCTAssertEqual(store.document, before)
    buttons[0].mouseUp(with: try event(.leftMouseUp, NSPoint(x: 11, y: 92), in: window))
    buttons[0].mouseUp(with: try event(.leftMouseUp, NSPoint(x: 11, y: 18), in: window))
    XCTAssertEqual(store.document.layers.map(\.visible), [false, false, false])
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertNil(tracker.token)
    XCTAssertNil(tracker.store)
  }

  @MainActor func testClickOptionClickAndAccessiblePressKeepExistingRoutes() throws {
    let store = try GroupWorkflowTests().store()
    let tracker = LayerEyeTracking()
    let window = window()
    defer {
      tracker.cancel()
      window.close()
      store.renderTask?.cancel()
    }
    let buttons = controls(store, tracker: tracker, in: try XCTUnwrap(window.contentView))
    let point = NSPoint(x: 11, y: 18)
    buttons[0].mouseDown(with: try event(.leftMouseDown, point, in: window))
    buttons[0].mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 12, y: 19), in: window))
    buttons[0].mouseUp(with: try event(.leftMouseUp, point, in: window))
    XCTAssertEqual(store.document.layers.map(\.visible), [false, true, true])
    buttons[0].performClick(nil)
    XCTAssertEqual(store.document.layers.map(\.visible), [true, true, true])
    for _ in 0..<2 {
      buttons[0].mouseDown(with: try event(.leftMouseDown, point, in: window, modifiers: .option))
      buttons[0].mouseUp(with: try event(.leftMouseUp, point, in: window))
    }
    XCTAssertEqual(store.document.layers.map(\.visible), [true, true, true])
    XCTAssertNil(store.layerVisibilityIsolation)
    XCTAssertEqual(store.session.undoStack.count, 4)
  }

  @MainActor func testNativeCancellationOnEscapeAndDeactivationLeavesNoHistory() throws {
    let store = try GroupWorkflowTests().store()
    let tracker = LayerEyeTracking()
    let window = window()
    defer {
      tracker.cancel()
      window.close()
      store.renderTask?.cancel()
    }
    let buttons = controls(store, tracker: tracker, in: try XCTUnwrap(window.contentView))
    let before = store.document
    for notification in [false, true] {
      buttons[0].mouseDown(with: try event(.leftMouseDown, NSPoint(x: 11, y: 18), in: window))
      buttons[0].mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 11, y: 92), in: window))
      XCTAssertNotNil(store.layerVisibilityDraft)
      if notification {
        NotificationCenter.default.post(
          name: NSApplication.didResignActiveNotification, object: nil)
      } else {
        buttons[0].cancelOperation(nil)
      }
      buttons[0].mouseUp(with: try event(.leftMouseUp, NSPoint(x: 11, y: 92), in: window))
      XCTAssertEqual(store.document, before)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(tracker.store)
    }
  }

  @MainActor func testPanelWindowAndDocumentBoundariesExcludeForeignRows() throws {
    let store = try GroupWorkflowTests().store()
    let other = try GroupWorkflowTests().store()
    let tracker = LayerEyeTracking()
    let otherPanel = LayerEyeTracking()
    let window = window()
    let foreignWindow = self.window()
    defer {
      tracker.cancel()
      otherPanel.cancel()
      window.close()
      foreignWindow.close()
      store.renderTask?.cancel()
      other.renderTask?.cancel()
    }
    let root = try XCTUnwrap(window.contentView)
    let own = controls(store, tracker: tracker, in: root)
    let foreign = controls(other, tracker: tracker, in: root)
    let anotherPanel = controls(store, tracker: otherPanel, in: root)
    let secondWindow = controls(
      store, tracker: tracker, in: try XCTUnwrap(foreignWindow.contentView))
    // Keep only row zero in this panel. Other rows exist in other scopes at the drag's end.
    own[1].removeFromSuperview()
    own[2].removeFromSuperview()
    own[0].mouseDown(with: try event(.leftMouseDown, NSPoint(x: 11, y: 18), in: window))
    own[0].mouseDragged(with: try event(.leftMouseDragged, NSPoint(x: 11, y: 92), in: window))
    own[0].mouseUp(with: try event(.leftMouseUp, NSPoint(x: 11, y: 92), in: window))
    XCTAssertEqual(store.document.layers.map(\.visible), [false, true, true])
    XCTAssertEqual(other.document.layers.map(\.visible), [true, true, true])
    XCTAssertEqual(foreign.count + anotherPanel.count + secondWindow.count, 9)
  }

  @MainActor func testAutoscrollRevealsRowsAndKeepsGestureWhenOriginLeavesViewport() throws {
    let store = try GroupWorkflowTests().store()
    let tracker = LayerEyeTracking()
    let window = window()
    defer {
      tracker.cancel()
      window.close()
      store.renderTask?.cancel()
    }
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 80, height: 55))
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 111))
    scroll.documentView = content
    window.contentView?.addSubview(scroll)
    let buttons = controls(store, tracker: tracker, in: content)
    scroll.contentView.scroll(to: .zero)
    let start = buttons[0].convert(NSPoint(x: 11, y: 18), to: nil)
    let edge = scroll.contentView.convert(NSPoint(x: 11, y: 53), to: nil)
    buttons[0].mouseDown(with: try event(.leftMouseDown, start, in: window))
    buttons[0].mouseDragged(with: try event(.leftMouseDragged, edge, in: window))
    for _ in 0..<6 { tracker.autoscroll() }
    XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
    XCTAssertEqual(store.previewDocument.layers.map(\.visible), [false, false, false])
    buttons[0].mouseUp(with: try event(.leftMouseUp, edge, in: window))
    XCTAssertEqual(store.session.undoStack.count, 1)
  }

  @MainActor func testHostedLayersHaveNativeHitTargetsAndScrollAncestor() async throws {
    let store = try GroupWorkflowTests().store()
    // Show all three targets without relying on initial active-row centering.
    store.workspaceLibrary.resizeProperties(to: 160)
    let window = window()
    defer {
      window.close()
      store.renderTask?.cancel()
    }
    let host = NSHostingView(rootView: WorkspaceView(store: store))
    host.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
    window.setContentSize(host.frame.size)
    window.contentView = host
    try await Task.sleep(for: .milliseconds(200))
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let buttons = descendants(host).compactMap { $0 as? LayerEyeButton }
    XCTAssertEqual(buttons.count, 3)
    for button in buttons {
      XCTAssertNotNil(button.enclosingScrollView)
      XCTAssertEqual(button.bounds.size, NSSize(width: 22, height: 36))
      let visible = button.visibleRect.intersection(button.bounds)
      if !visible.isEmpty {
        let point = host.superview!.convert(NSPoint(x: visible.midX, y: visible.midY), from: button)
        XCTAssertTrue(
          host.hitTest(point) === button,
          "eye=\(button.frame) visible=\(visible) hostPoint=\(point) hit=\(String(describing: host.hitTest(point)))"
        )
      }
      XCTAssertTrue(button.accessibilityLabel()?.hasPrefix("Visibility of Shape") == true)
    }
    let eye = try XCTUnwrap(buttons.first { !$0.visibleRect.intersection($0.bounds).isEmpty })
    let tracker = try XCTUnwrap(eye.tracking)
    defer { tracker.cancel() }
    let clipped = eye.visibleRect.intersection(eye.bounds)
    let start = eye.convert(NSPoint(x: clipped.midX, y: clipped.midY), to: nil)
    let end = NSPoint(x: start.x + 5, y: start.y)
    eye.mouseDown(with: try event(.leftMouseDown, start, in: window))
    eye.mouseDragged(with: try event(.leftMouseDragged, end, in: window))
    XCTAssertEqual(
      Set(try XCTUnwrap(store.layerVisibilityDraft).values.keys), [eye.layerID],
      "A short horizontal drag must not sweep every row sharing SwiftUI's oversized visibleRect")
    eye.mouseUp(with: try event(.leftMouseUp, end, in: window))
    XCTAssertEqual(store.document.layers.filter { !$0.visible }.map(\.id), [eye.layerID])
    XCTAssertEqual(store.session.undoStack.count, 1)

  }
}
