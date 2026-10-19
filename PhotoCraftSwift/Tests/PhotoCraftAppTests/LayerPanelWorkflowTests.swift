import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest

@testable import PhotoCraft

final class LayerPanelWorkflowTests: XCTestCase {
  @MainActor func testPendingNameSurvivesSaveAndDocumentSwitch() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    let a = CraftNSDocument(model: try CraftDocument(width: 3, height: 2))
    let b = CraftNSDocument(model: try CraftDocument(width: 3, height: 2))
    defer {
      a.close()
      b.close()
    }
    for document in [a, b] {
      controller.addDocument(document)
      document.makeWindowControllers()
    }
    XCTAssertTrue(controller.documentWindows.activate(a))
    let id = a.store.activeLayer!.id
    a.store.beginLayerName(id)
    a.store.layerNameDraft?.text = "Saved name"
    let saved = try NativeArchive.decode(a.data(ofType: CraftNSDocument.nativeType))
    XCTAssertEqual(saved.layers[0].name, "Saved name")
    XCTAssertNil(a.store.layerNameDraft)
    a.store.beginLayerName(id)
    a.store.layerNameDraft?.text = "Before switch"
    XCTAssertTrue(controller.documentWindows.activate(b))
    XCTAssertEqual(a.store.activeLayer?.name, "Before switch")
    XCTAssertEqual(a.store.session.undoStack.count, 2)
    XCTAssertNil(a.store.layerNameDraft)
    XCTAssertTrue(b.store.session.undoStack.isEmpty)
    XCTAssertTrue(a.isDocumentEdited)
  }
  @MainActor func testNativeHostedFieldSelectsNameAndCommitsOnlyOutsideClick() throws {
    _ = NSApplication.shared
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let id = store.document.layers[0].id
    store.beginLayerName(id)
    let draft = try XCTUnwrap(store.layerNameDraft)
    let host = NSHostingView(rootView: LayerNameField(store: store, draft: draft, visibleIDs: [id]))
    host.frame = NSRect(x: 0, y: 0, width: 200, height: 22)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 300, height: 80), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.contentView?.addSubview(host)
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    func find(_ view: NSView) -> LayerNameField.NameField? {
      if let field = view as? LayerNameField.NameField { return field }
      return view.subviews.compactMap(find).first
    }
    let field = try XCTUnwrap(find(host))
    XCTAssertEqual(field.stringValue, draft.originalName)
    XCTAssertEqual(
      field.currentEditor()?.selectedRange,
      NSRange(location: 0, length: draft.originalName.utf16.count))
    let coordinator = try XCTUnwrap(field.delegate as? LayerNameField.Coordinator)
    defer { coordinator.removeMonitor() }
    XCTAssertTrue(store.layerNameDraft === draft)
    field.currentEditor()?.string = "Outside commit"
    coordinator.controlTextDidChange(
      Notification(name: NSControl.textDidChangeNotification, object: field))
    let inside = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
    let insideEvent = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: inside, modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
    )
    coordinator.handleMouseDown(insideEvent)
    XCTAssertNotNil(store.layerNameDraft)
    let outsideEvent = try XCTUnwrap(
      NSEvent.mouseEvent(
        with: .leftMouseDown, location: NSPoint(x: 280, y: 70), modifierFlags: [], timestamp: 0,
        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)
    )
    coordinator.handleMouseDown(outsideEvent)
    XCTAssertNil(store.layerNameDraft)
    XCTAssertEqual(store.activeLayer?.name, "Outside commit")
    XCTAssertEqual(store.session.undoStack.count, 1)
    coordinator.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: field))
    XCTAssertEqual(store.session.undoStack.count, 1)
  }

  @MainActor func testContextMaskAndDuplicateUseClickedLayerAndPreserveSelection() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.performLayerPanel(.addMask, context: ids[2])
    XCTAssertEqual(store.activeLayer?.id, ids[2])
    XCTAssertNotNil(store.document.layers[2].mask)
    XCTAssertNil(store.document.layers[0].mask)
    store.performLayerPanel(.deleteMask, context: ids[2])
    XCTAssertNil(store.document.layers[2].mask)
    store.selectedLayerIDs = [ids[0], ids[2]]
    store.performLayerPanel(.duplicate, context: ids[2])
    XCTAssertEqual(store.duplicateLayerDraft?.selected, [ids[0], ids[2]])
    XCTAssertEqual(store.session.undoStack.count, 2)
  }
  @MainActor func testRenameCommitCancelAndNoOpHaveExpectedUndo() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let original = store.document
    let id = original.layers[0].id
    var changes = 0
    store.onChange = { _ in changes += 1 }
    for name in [original.layers[0].name, "  ", String(repeating: "a", count: 65_536)] {
      store.beginLayerName(id)
      store.layerNameDraft?.text = name
      store.finishLayerName()
      XCTAssertEqual(store.document, original)
    }
    store.beginLayerName(id)
    store.layerNameDraft?.text = "Discard"
    store.finishLayerName(cancel: true)
    XCTAssertEqual(changes, 0)
    store.beginLayerName(id)
    let draft = try XCTUnwrap(store.layerNameDraft)
    draft.text = "  Mountain  "
    store.finishLayerName(draft.id)
    store.finishLayerName(draft.id)
    XCTAssertEqual(store.activeLayer?.name, "Mountain")
    XCTAssertEqual(changes, 1)
    XCTAssertEqual(store.session.undoStack.count, 1)
    store.undo()
    XCTAssertEqual(store.document, original)
    store.redo()
    XCTAssertEqual(store.activeLayer?.name, "Mountain")
  }
  @MainActor func testStaleCallbacksCannotCommitAnotherRename() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.beginLayerName(ids[0])
    let old = try XCTUnwrap(store.layerNameDraft)
    old.text = "One"
    store.beginLayerName(ids[1])
    let current = try XCTUnwrap(store.layerNameDraft)
    current.text = "Two"
    store.finishLayerName(old.id)
    XCTAssertTrue(store.layerNameDraft === current)
    try store.session.execute(.renameLayer(ids[1], "External"))
    store.finishLayerName(current.id)
    XCTAssertEqual(store.activeLayer?.name, "External")
    XCTAssertEqual(store.session.undoStack.count, 2)
    store.beginLayerName(ids[2])
    store.layerNameDraft?.text = "Deleted target"
    try store.session.execute(.deleteLayer(ids[2]))
    store.finishLayerName()
    XCTAssertNil(store.layerNameDraft)
    XCTAssertEqual(store.session.undoStack.count, 3)
  }
  @MainActor func testTabTraversesVisibleRowsAndDoesNotWrap() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.reversed().map(\.id)
    let visible = [ids[0], ids[2]]
    store.beginLayerName(ids[0])
    store.layerNameDraft?.text = "Top"
    store.advanceLayerName(try XCTUnwrap(store.layerNameDraft).id, by: 1, visibleIDs: visible)
    XCTAssertEqual(store.layerNameDraft?.layerID, ids[2])
    store.layerNameDraft?.text = "Bottom"
    store.advanceLayerName(try XCTUnwrap(store.layerNameDraft).id, by: -1, visibleIDs: visible)
    XCTAssertEqual(store.layerNameDraft?.text, "Top")
    store.advanceLayerName(try XCTUnwrap(store.layerNameDraft).id, by: -1, visibleIDs: visible)
    XCTAssertNil(store.layerNameDraft)
    XCTAssertEqual(store.session.undoStack.count, 2)
    XCTAssertEqual(store.document.layers[1].name, "Shape 1")
  }
  @MainActor func testSelectingAndOpeningDialogCommitBeforeCapturingDocument() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.beginLayerName(ids[0])
    store.layerNameDraft?.text = "Named"
    store.select(ids[1])
    XCTAssertEqual(store.document.layers[0].name, "Named")
    XCTAssertNil(store.layerNameDraft)
    store.beginLayerName(ids[1])
    store.layerNameDraft?.text = "Second"
    store.beginDuplicate()
    XCTAssertEqual(store.duplicateLayerDraft?.original.layers[1].name, "Second")
    XCTAssertNil(store.layerNameDraft)
    XCTAssertEqual(store.session.undoStack.count, 2)
  }
  @MainActor func testContextDeletePreservesSelectedSetAndUnselectedRowTargetsItself() throws {
    let store = try GroupWorkflowTests().store()
    store.layerDeletionConfirmation = { _ in .contents }
    defer { store.renderTask?.cancel() }
    let original = store.document
    let ids = original.layers.map(\.id)
    store.selectedLayerIDs = [ids[0], ids[2]]
    store.performLayerPanel(.delete, context: ids[2])
    XCTAssertEqual(store.document.layers.map(\.id), [ids[1]])
    XCTAssertEqual(store.session.undoStack.count, 1)
    store.undo()
    XCTAssertEqual(store.document, original)
    store.selectedLayerIDs = [ids[0], ids[2]]
    store.performLayerPanel(.delete, context: ids[1])
    XCTAssertEqual(store.document.layers.map(\.id), [ids[0], ids[2]])
    XCTAssertEqual(store.session.undoStack.count, 1)
  }
  @MainActor func testMultiselectionNeverUsesSingleLayerActions() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.selectedLayerIDs = Set(store.document.layers.prefix(2).map(\.id))
    let original = store.document
    for action: LayerPanelAction in [
      .rename, .rasterize, .ungroup, .clipping, .addMask, .applyMask, .deleteMask, .toggleMask,
    ] {
      XCTAssertFalse(store.canPerformLayerPanel(action))
      store.performLayerPanel(action)
      XCTAssertEqual(store.document, original)
    }
    store.geometryBusy = true
    for action in LayerPanelAction.allCases { XCTAssertFalse(store.canPerformLayerPanel(action)) }
    store.geometryBusy = false
    store.selectedLayerIDs = Set(store.document.layers.map(\.id))
    XCTAssertFalse(store.canPerformLayerPanel(.delete))
  }
  @MainActor func testNativeFieldDelegateOwnsReturnEscapeAndTab() throws {
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.reversed().map(\.id)
    store.beginLayerName(ids[0])
    let first = try XCTUnwrap(store.layerNameDraft)
    let parent = LayerNameField(store: store, draft: first, visibleIDs: ids)
    let coordinator = parent.makeCoordinator()
    let field = LayerNameField.NameField()
    coordinator.field = field
    field.stringValue = "Top"
    XCTAssertTrue(
      coordinator.control(
        field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertTab(_:))))
    XCTAssertEqual(store.layerNameDraft?.layerID, ids[1])
    coordinator.controlTextDidEndEditing(
      Notification(name: NSControl.textDidEndEditingNotification, object: field))
    XCTAssertEqual(store.layerNameDraft?.layerID, ids[1])
    coordinator.parent = LayerNameField(
      store: store, draft: try XCTUnwrap(store.layerNameDraft), visibleIDs: ids)
    field.stringValue = "Discard"
    XCTAssertTrue(
      coordinator.control(
        field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
    XCTAssertNil(store.layerNameDraft)
    XCTAssertEqual(store.document.layers[1].name, "Shape 1")
    XCTAssertEqual(store.session.undoStack.count, 1)
    store.beginLayerName(ids[1])
    coordinator.parent = LayerNameField(
      store: store, draft: try XCTUnwrap(store.layerNameDraft), visibleIDs: ids)
    field.stringValue = "Middle"
    XCTAssertTrue(
      coordinator.control(
        field, textView: NSTextView(), doCommandBy: #selector(NSResponder.insertNewline(_:))))
    XCTAssertEqual(store.activeLayer?.name, "Middle")
    XCTAssertNil(store.layerNameDraft)
  }
  @MainActor func testRenameMainMenuBindingKeepsFactoryShortcutAndGuards() throws {
    try PhotoshopMenuTests().withMenus { app, menu in
      let document = CraftNSDocument(model: try CraftDocument(width: 4, height: 4))
      app.controller.addDocument(document)
      document.makeWindowControllers()
      XCTAssertTrue(app.controller.documentWindows.activate(document))
      defer {
        document.store.renderTask?.cancel()
        document.close()
      }
      let items = PhotoshopMenuTests().allItems(menu)
      let rename = try XCTUnwrap(items.first { $0.identifier?.rawValue == "Layer > Rename Layer…" })
      XCTAssertEqual(rename.action, #selector(AppDelegate.renameLayer))
      XCTAssertEqual(rename.keyEquivalent, "")
      XCTAssertTrue(app.validateMenuItem(rename))
      app.renameLayer()
      XCTAssertNotNil(document.store.layerNameDraft)
      document.store.finishLayerName(cancel: true)
      document.store.perform(.lock(document.store.activeLayer!.id, true))
      XCTAssertFalse(app.validateMenuItem(rename))
      let delete = try XCTUnwrap(items.first { $0.action == #selector(AppDelegate.delete) })
      XCTAssertFalse(app.validateMenuItem(delete))
    }
  }
}
