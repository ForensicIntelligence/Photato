import AppKit
import PhotoCraftCore
import XCTest

@testable import PhotoCraft

final class LayerTextEditingTests: XCTestCase {
  @MainActor func testMenuHistoryUsesNativeTextAndNeverFallsThroughToDocument() async throws {
    let app = AppDelegate()
    let document = CraftNSDocument(model: try CraftDocument(width: 3, height: 2))
    app.controller.addDocument(document)
    document.makeWindowControllers()
    XCTAssertTrue(app.controller.documentWindows.activate(document))
    let store = document.store
    defer { document.close() }
    store.perform(.opacity(store.activeLayer!.id, 0.5))
    let original = store.document
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.borderless],
      backing: .buffered, defer: false)
    let text = NSTextView(frame: window.contentView!.bounds)
    text.allowsUndo = true
    window.contentView = text
    window.makeFirstResponder(text)
    defer {
      window.contentView = nil
      window.orderOut(nil)
    }
    let undo = NSMenuItem(title: "Undo", action: #selector(AppDelegate.undo), keyEquivalent: "z")
    let redo = NSMenuItem(title: "Redo", action: #selector(AppDelegate.redo), keyEquivalent: "z")
    XCTAssertEqual(app.validateHistoryMenu(undo, in: window), false)
    await app.performHistory(redo: false, in: window)?.value
    XCTAssertEqual(store.document, original)
    let manager = try XCTUnwrap(text.undoManager)
    manager.groupsByEvent = false
    manager.beginUndoGrouping()
    text.insertText("Typed name", replacementRange: NSRange(location: 0, length: 0))
    manager.endUndoGrouping()
    XCTAssertEqual(app.validateHistoryMenu(undo, in: window), true)
    XCTAssertEqual(undo.title, manager.undoMenuItemTitle)
    await app.performHistory(redo: false, in: window)?.value
    XCTAssertEqual(text.string, "")
    XCTAssertEqual(app.validateHistoryMenu(redo, in: window), true)
    await app.performHistory(redo: true, in: window)?.value
    XCTAssertEqual(text.string, "Typed name")
    XCTAssertEqual(store.document, original)
    XCTAssertEqual(store.session.undoStack.count, 1)
    text.isEditable = false
    XCTAssertEqual(app.validateHistoryMenu(undo, in: window), false)
    await app.performHistory(redo: false, in: window)?.value
    XCTAssertEqual(store.document, original)
    window.makeFirstResponder(window)
    XCTAssertEqual(app.validateHistoryMenu(undo, in: window), true)
    await app.performHistory(redo: false, in: window)?.value
    XCTAssertEqual(store.activeLayer?.opacity, 1)
    XCTAssertEqual(app.validateHistoryMenu(redo, in: window), true)
    XCTAssertEqual(redo.title, "Redo Layer Opacity")
    store.geometryBusy = true
    XCTAssertEqual(app.validateHistoryMenu(redo, in: window), false)
  }

  @MainActor func testRetiredEditorUndoCannotRewriteNewLayerDraft() throws {
    _ = NSApplication.shared
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    let ids = store.document.layers.map(\.id)
    store.beginLayerName(ids[0])
    let old = try XCTUnwrap(store.layerNameDraft)
    let coordinator = LayerNameField(store: store, draft: old, visibleIDs: ids).makeCoordinator()
    let field = LayerNameField.NameField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    coordinator.field = field
    field.delegate = coordinator
    field.stringValue = old.originalName
    let window = NSWindow(
      contentRect: field.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = field
    defer {
      coordinator.removeMonitor()
      field.delegate = nil
      window.contentView = nil
      window.orderOut(nil)
    }
    field.selectText(nil)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    let manager = try XCTUnwrap(editor.undoManager)
    manager.groupsByEvent = false
    manager.beginUndoGrouping()
    editor.insertText(
      "First", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    manager.endUndoGrouping()
    store.beginLayerName(ids[1])
    let next = try XCTUnwrap(store.layerNameDraft)
    next.text = "Second"
    manager.undo()
    XCTAssertTrue(store.layerNameDraft === next)
    XCTAssertEqual(next.text, "Second")
    XCTAssertEqual(store.document.layers[0].name, "First")
  }
  @MainActor func testMenuBarAndPopupMouseEventsKeepRenameForEditMenu() throws {
    _ = NSApplication.shared
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.beginLayerName(store.document.layers[0].id)
    let draft = try XCTUnwrap(store.layerNameDraft)
    let coordinator = LayerNameField(store: store, draft: draft, visibleIDs: [draft.layerID])
      .makeCoordinator()
    let field = LayerNameField.NameField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    field.stringValue = "Pending"
    coordinator.field = field
    let window = NSWindow(
      contentRect: field.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = field
    let popup = NSWindow(
      contentRect: field.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    popup.level = .popUpMenu
    defer {
      coordinator.removeMonitor()
      window.contentView = nil
      window.orderOut(nil)
      popup.orderOut(nil)
    }
    for number in [0, popup.windowNumber] {
      let event = try XCTUnwrap(
        NSEvent.mouseEvent(
          with: .leftMouseDown, location: NSPoint(x: 20, y: 20), modifierFlags: [], timestamp: 0,
          windowNumber: number, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
      coordinator.handleMouseDown(event)
      XCTAssertTrue(store.layerNameDraft === draft)
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }

  @MainActor func testNativeNameFieldProvidesTypingUndoSeparateFromDocument() throws {
    _ = NSApplication.shared
    let store = try GroupWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    store.beginLayerName(store.document.layers[0].id)
    let draft = try XCTUnwrap(store.layerNameDraft)
    let parent = LayerNameField(
      store: store, draft: draft, visibleIDs: store.document.layers.map(\.id))
    let coordinator = parent.makeCoordinator()
    let field = LayerNameField.NameField(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
    field.delegate = coordinator
    coordinator.field = field
    field.stringValue = draft.originalName
    let window = NSWindow(
      contentRect: field.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = field
    defer {
      field.delegate = nil
      window.contentView = nil
      window.orderOut(nil)
    }
    field.selectText(nil)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    print(
      "Native layer field editor allowsUndo=\(editor.allowsUndo); manager=\(editor.undoManager != nil)"
    )
    XCTAssertTrue(editor.allowsUndo)
    let manager = try XCTUnwrap(editor.undoManager)
    manager.groupsByEvent = false
    manager.beginUndoGrouping()
    editor.insertText(
      "Renamed", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    manager.endUndoGrouping()
    XCTAssertEqual(draft.text, "Renamed")
    XCTAssertTrue(manager.canUndo)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("undo:"), with: nil))
    XCTAssertEqual(editor.string, draft.originalName)
    XCTAssertEqual(draft.text, draft.originalName)
    XCTAssertTrue(editor.tryToPerform(NSSelectorFromString("redo:"), with: nil))
    XCTAssertEqual(editor.string, "Renamed")
    XCTAssertTrue(store.layerNameDraft === draft)
    store.finishLayerName()
    XCTAssertEqual(store.activeLayer?.name, "Renamed")
    XCTAssertEqual(store.session.undoStack.count, 1)
  }
}
