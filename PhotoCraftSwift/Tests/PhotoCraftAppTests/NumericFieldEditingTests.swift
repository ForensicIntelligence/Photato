import AppKit
import PhotoCraftCore
import SwiftUI
import XCTest

@testable import PhotoCraft

final class NumericFieldEditingTests: XCTestCase {
  @MainActor func withWorkspaceFields(
    floating: Bool = false,
    _ body: (EditorStore, NSWindow, NSTextField, NSTextField) throws -> Void
  ) throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let document = try DocumentWorkspaceTests().fixture(controller, name: "Numeric key loop")
    let window: NSWindow
    if floating {
      XCTAssertTrue(
        controller.workspaces.floatPanels(
          .group("properties"),
          frame: FloatingPanelFrame(NSRect(x: 100, y: 100, width: 322, height: 460))))
      let panels = controller.documentWindows.floatingPanels
      panels.synchronize()
      window = try XCTUnwrap(panels.controllers["properties"]?.window)
    } else {
      window = try XCTUnwrap(controller.documentWindows.current?.window)
    }
    let content = try XCTUnwrap(window.contentView)
    window.layoutIfNeeded()
    content.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    let x = try XCTUnwrap(fields(content).first { $0.accessibilityLabel() == "X" })
    let y = try XCTUnwrap(fields(content).first { $0.accessibilityLabel() == "Y" })
    try body(document.store, window, x, y)
  }

  @MainActor func testFullWorkspaceForwardAndUntouchedReverseFieldTraversal() throws {
    try withWorkspaceFields { store, window, x, y in
      let editor = try replace(x, with: "23")
      editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
      XCTAssertEqual(store.activeLayerBounds?.x, 23)
      let next = try XCTUnwrap(y.currentEditor() as? NSTextView)
      XCTAssertTrue(window.firstResponder === next)
      next.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
      let previous = try XCTUnwrap(x.currentEditor() as? NSTextView)
      XCTAssertTrue(window.firstResponder === previous)
      XCTAssertEqual(previous.string, "23")
      XCTAssertEqual(previous.selectedRange(), NSRange(location: 0, length: 2))
      previous.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
      store.undo()
      XCTAssertEqual(store.activeLayerBounds?.x, 0)
    }
  }

  @MainActor func testTabKeyEventsNavigateDocumentAndFloatingPanelFields() throws {
    for floating in [false, true] {
      try withWorkspaceFields(floating: floating) { store, window, x, y in
        let layout = store.workspace
        @MainActor func tab(backwards: Bool) throws {
          let event = try XCTUnwrap(
            NSEvent.keyEvent(
              with: .keyDown, location: .zero, modifierFlags: backwards ? [.shift] : [],
              timestamp: 0, windowNumber: window.windowNumber, context: nil,
              characters: backwards ? "\u{19}" : "\t",
              charactersIgnoringModifiers: backwards ? "\u{19}" : "\t",
              isARepeat: false, keyCode: 48))
          window.sendEvent(event)
        }
        _ = try replace(x, with: "23")
        try tab(backwards: false)
        XCTAssertEqual(store.activeLayerBounds?.x, 23)
        XCTAssertNotNil(y.currentEditor())
        try tab(backwards: true)
        let previous = try XCTUnwrap(x.currentEditor() as? NSTextView)
        XCTAssertEqual(previous.string, "23")
        XCTAssertEqual(previous.selectedRange(), NSRange(location: 0, length: 2))
        XCTAssertEqual(store.workspace, layout)
        XCTAssertEqual(store.session.undoStack.count, 1)
        previous.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        store.undo()
        XCTAssertEqual(store.activeLayerBounds?.x, 0)
      }
    }
  }

  @MainActor func withPositionFields(
    document: CraftNSDocument? = nil,
    _ body: (EditorStore, NSWindow, NSTextField, NSTextField) throws -> Void
  ) throws {
    _ = NSApplication.shared
    let store = try document?.store ?? TransformWorkflowTests().store()
    let layer = try XCTUnwrap(store.activeLayer)
    let workspace = WorkspaceView(store: store)
    let host = NSHostingView(
      rootView: HStack {
        workspace.numberField(
          "X", value: workspace.layerPositionBinding(layer, horizontal: true),
          range: -1_000_000...1_000_000)
        workspace.numberField(
          "Y", value: workspace.layerPositionBinding(layer, horizontal: false),
          range: -1_000_000...1_000_000)
      }.font(.system(size: 11)).padding(12))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 250, height: 70),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      store.renderTask?.cancel()
      window.contentView = nil
      window.close()
    }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    let editable = fields(host).filter(\.isEditable).sorted {
      $0.convert(.zero, to: host).x < $1.convert(.zero, to: host).x
    }
    XCTAssertEqual(editable.count, 2)
    try body(store, window, XCTUnwrap(editable.first), XCTUnwrap(editable.last))
  }

  @MainActor func testPositionTypingIsDraftUntilReturnAndOneHistoryEntry() throws {
    try withPositionFields { store, window, x, _ in
      let original = store.document
      x.selectText(nil)
      let editor = try XCTUnwrap(x.currentEditor() as? NSTextView)
      editor.insertText(
        "1", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      editor.insertText("7", replacementRange: NSRange(location: 1, length: 0))
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      XCTAssertEqual(store.document, original, "Typing must not move pixels before commit")
      XCTAssertTrue(store.session.undoStack.isEmpty)
      editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      XCTAssertEqual(store.activeLayerBounds?.x, 17)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertFalse(window.firstResponder is NSTextView)
      store.undo()
      XCTAssertEqual(store.document, original)
      store.redo()
      XCTAssertEqual(store.activeLayerBounds?.x, 17)
    }
  }

  @MainActor func replace(_ field: NSTextField, with text: String) throws -> NSTextView {
    field.selectText(nil)
    let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
    editor.insertText(
      text, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
    return editor
  }

  @MainActor func testEscapeCancelsWithoutHistoryOrDirtyNotification() throws {
    try withPositionFields { store, window, _, y in
      var changes = 0
      store.onChange = { _ in changes += 1 }
      let original = store.document
      let editor = try replace(y, with: "-12")
      editor.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
      XCTAssertEqual(store.document, original)
      XCTAssertEqual(changes, 0)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(store.numericEditor)
      XCTAssertFalse(window.firstResponder is NSTextView)
      XCTAssertEqual(y.stringValue, "3")
    }
  }

  @MainActor func testTabAndBacktabCommitAndSelectNeighborWithoutHidingPanels() throws {
    try withPositionFields { store, window, x, y in
      let layout = store.workspace
      let editor = try replace(x, with: "17")
      editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
      XCTAssertEqual(store.activeLayerBounds?.x, 17)
      let next = try XCTUnwrap(y.currentEditor() as? NSTextView)
      XCTAssertTrue(window.firstResponder === next)
      XCTAssertEqual(next.selectedRange(), NSRange(location: 0, length: next.string.utf16.count))
      next.insertText("-12", replacementRange: next.selectedRange())
      next.doCommand(by: #selector(NSResponder.insertBacktab(_:)))
      XCTAssertEqual(store.activeLayerBounds?.y, -12)
      let previous = try XCTUnwrap(x.currentEditor() as? NSTextView)
      XCTAssertTrue(window.firstResponder === previous)
      XCTAssertEqual(previous.string, "17")
      XCTAssertEqual(previous.selectedRange(), NSRange(location: 0, length: 2))
      XCTAssertEqual(store.session.undoStack.count, 2)
      XCTAssertEqual(store.workspace, layout)
      previous.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
      store.undo()
      XCTAssertEqual(store.activeLayerBounds?.y, 3)
      XCTAssertEqual(store.activeLayerBounds?.x, 17)
    }
  }

  @MainActor func testChangingNativeFieldFocusCommitsPreviousValueOnlyOnce() throws {
    try withPositionFields { store, _, x, y in
      _ = try replace(x, with: "23")
      y.selectText(nil)
      XCTAssertEqual(store.activeLayerBounds?.x, 23)
      XCTAssertEqual(store.activeLayerBounds?.y, 3)
      XCTAssertEqual(store.session.undoStack.count, 1)
      _ = try replace(y, with: "-12")
      store.finishNumericField()
      XCTAssertEqual(store.activeLayerBounds?.x, 23)
      XCTAssertEqual(store.activeLayerBounds?.y, -12)
      store.finishNumericField()
      XCTAssertEqual(store.session.undoStack.count, 2)
    }
  }

  @MainActor func testNativeTextUndoRedoOnlyChangesDraftUntilCommit() throws {
    try withPositionFields { store, _, x, _ in
      let original = store.document
      x.selectText(nil)
      let editor = try XCTUnwrap(x.currentEditor() as? NSTextView)
      XCTAssertTrue(editor.allowsUndo)
      let manager = try XCTUnwrap(editor.undoManager)
      manager.groupsByEvent = false
      manager.beginUndoGrouping()
      editor.insertText(
        "173", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
      manager.endUndoGrouping()
      manager.undo()
      XCTAssertEqual(editor.string, "4")
      XCTAssertEqual(store.document, original)
      manager.redo()
      XCTAssertEqual(editor.string, "173")
      XCTAssertEqual(store.document, original)
      editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      XCTAssertEqual(store.activeLayerBounds?.x, 173)
      XCTAssertEqual(store.session.undoStack.count, 1)
    }
  }

  @MainActor func testNumericParsingConsumesEntireLocalizedFiniteInputAndClamps() throws {
    let store = try TransformWorkflowTests().store()
    defer { store.renderTask?.cancel() }
    var value = 0.0
    let binding = Binding(get: { value }, set: { value = $0 })
    var field = NativeNumericField(
      store: store, label: "Test", value: binding,
      range: -2_000...2_000, locale: Locale(identifier: "en_US"))
    let coordinator = field.makeCoordinator()
    XCTAssertEqual(coordinator.parsed("1,234"), 1234)
    XCTAssertEqual(coordinator.parsed(" -12 "), -12)
    XCTAssertEqual(coordinator.parsed("9000"), 2000)
    for invalid in ["", "-", "12junk", "NaN", "Infinity", "1+2"] {
      XCTAssertNil(coordinator.parsed(invalid), invalid)
    }
    field.locale = Locale(identifier: "de_DE")
    coordinator.update(field)
    XCTAssertEqual(coordinator.parsed("1.234"), 1234)
    XCTAssertEqual(coordinator.parsed("-12,5"), -12.5)
    XCTAssertEqual(value, 0)
  }

  @MainActor func testInvalidAndUnchangedInputDoNotCreateHistory() throws {
    try withPositionFields { store, _, x, _ in
      for text in ["4", "", "-", "nonsense"] {
        let editor = try replace(x, with: text)
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(store.activeLayerBounds?.x, 4)
        XCTAssertTrue(store.session.undoStack.isEmpty)
        XCTAssertEqual(x.stringValue, "4")
      }
    }
  }

  @MainActor func testConcurrentPositionChangeRejectsStaleDraft() throws {
    try withPositionFields { store, _, x, _ in
      let editor = try replace(x, with: "17")
      let id = try XCTUnwrap(store.activeLayer?.id)
      try store.session.execute(.move(id, 27, 3))
      editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      XCTAssertEqual(store.activeLayerBounds?.x, 27)
      XCTAssertEqual(store.session.undoStack.count, 1)
      XCTAssertEqual(x.stringValue, "27")
    }
  }

  @MainActor func testCommandBoundaryCommitsPositionBeforeIndependentEdit() throws {
    try withPositionFields { store, _, x, _ in
      _ = try replace(x, with: "17")
      let id = try XCTUnwrap(store.activeLayer?.id)
      store.perform(.opacity(id, 0.5))
      XCTAssertEqual(store.activeLayerBounds?.x, 17)
      XCTAssertEqual(store.activeLayer?.opacity, 0.5)
      XCTAssertEqual(store.session.undoStack.count, 2)
      XCTAssertNil(store.numericEditor)
      store.undo()
      XCTAssertEqual(store.activeLayer?.opacity, 1)
      XCTAssertEqual(store.activeLayerBounds?.x, 17)
      store.undo()
      XCTAssertEqual(store.activeLayerBounds?.x, 4)
    }
  }

  @MainActor func testSaveCommitsAndReadCancelsWithoutRetargeting() throws {
    let document = CraftNSDocument(model: try TransformWorkflowTests().store().document)
    defer { document.close() }
    try withPositionFields(document: document) { store, _, x, _ in
      let original = try document.data(ofType: CraftNSDocument.nativeType)
      _ = try replace(x, with: "17")
      let saved = try document.data(ofType: CraftNSDocument.nativeType)
      XCTAssertEqual(try NativeArchive.decode(saved).layers[0].x, 17)
      XCTAssertEqual(store.session.undoStack.count, 1)
      _ = try replace(x, with: "99")
      try document.read(from: original, ofType: CraftNSDocument.nativeType)
      XCTAssertEqual(store.activeLayerBounds?.x, 4)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(store.numericEditor)
    }
  }

  @MainActor func testCloseCancelsAndRetiredCoordinatorCannotCommit() throws {
    let document = CraftNSDocument(model: try TransformWorkflowTests().store().document)
    try withPositionFields(document: document) { store, _, x, _ in
      let original = store.document
      _ = try replace(x, with: "17")
      let editor = try XCTUnwrap(store.numericEditor)
      document.close()
      editor.finishNumericEditing(cancel: false)
      XCTAssertEqual(store.document, original)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(store.numericEditor)
    }
  }

  @MainActor func testContextReplacementCancelsRatherThanEditingDifferentTarget() throws {
    try withPositionFields { store, _, x, _ in
      _ = try replace(x, with: "17")
      let coordinator = try XCTUnwrap(store.numericEditor as? NativeNumericField.Coordinator)
      store.layerPanelGeneration = UUID()
      var parent = coordinator.parent
      parent.value = .constant(91)
      coordinator.update(parent)
      coordinator.finishNumericEditing(cancel: false)
      XCTAssertEqual(store.activeLayerBounds?.x, 4)
      XCTAssertTrue(store.session.undoStack.isEmpty)
      XCTAssertNil(store.numericEditor)
    }
  }

  @MainActor func testPercentFieldDefersOpacityAndPreservesDisabledState() throws {
    _ = NSApplication.shared
    let store = try TransformWorkflowTests().store()
    let layer = try XCTUnwrap(store.activeLayer)
    let workspace = WorkspaceView(store: store)
    let binding = Binding<Float>(
      get: { store.activeLayer?.opacity ?? 1 },
      set: { store.perform(.opacity(layer.id, $0)) })
    let host = NSHostingView(
      rootView: workspace.percentField("Opacity:", value: binding).padding(8))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 50),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer {
      store.renderTask?.cancel()
      window.contentView = nil
      window.close()
    }
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    func fields(_ view: NSView) -> [NSTextField] {
      (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap(fields)
    }
    let field = try XCTUnwrap(fields(host).first(where: \.isEditable))
    let editor = try replace(field, with: "63")
    XCTAssertEqual(store.activeLayer?.opacity, 1)
    XCTAssertTrue(store.session.undoStack.isEmpty)
    editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))
    XCTAssertEqual(store.activeLayer?.opacity, Float(0.63))
    XCTAssertEqual(store.session.undoStack.count, 1)
    XCTAssertEqual(field.stringValue, "63")
    let disabled = NSHostingView(
      rootView: workspace.percentField("Opacity:", value: binding).disabled(true))
    window.contentView = disabled
    window.layoutIfNeeded()
    disabled.layoutSubtreeIfNeeded()
    let lockedField = try XCTUnwrap(fields(disabled).first(where: \.isEditable))
    XCTAssertFalse(lockedField.isEnabled)
  }

  @MainActor func testLayerSelectionCommitsBeforeChangingTarget() throws {
    try withPositionFields { store, _, x, _ in
      let originalID = try XCTUnwrap(store.activeLayer?.id)
      let other = Layer(
        name: "Other", content: .shape(.init(kind: .rectangle, width: 3, height: 2, color: .white)))
      store.perform(.addLayer(other))
      store.select(originalID)
      _ = try replace(x, with: "17")
      store.select(other.id)
      XCTAssertEqual(store.document.layers.first(where: { $0.id == originalID })?.x, 17)
      XCTAssertEqual(store.activeLayer?.id, other.id)
      XCTAssertEqual(store.activeLayer?.x, 0)
      XCTAssertNil(store.numericEditor)
    }
  }

  @MainActor func testRejectedNumericCommitPreventsDocumentSwitch() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let a = try DocumentWorkspaceTests().fixture(controller, name: "Numeric A")
    let b = try DocumentWorkspaceTests().fixture(controller, name: "Numeric B")
    XCTAssertTrue(controller.documentWindows.activate(a))
    try a.store.session.execute(.lock(XCTUnwrap(a.store.activeLayer?.id), true))
    try withPositionFields(document: a) { store, _, x, _ in
      _ = try replace(x, with: "17")
      XCTAssertFalse(controller.documentWindows.activate(b))
      XCTAssertTrue(controller.currentDocument === a)
      XCTAssertNotNil(store.error)
      XCTAssertEqual(store.activeLayerBounds?.x, 0)
      store.error = nil
    }
  }

  @MainActor func testRejectedNumericCommitPreventsCleanDocumentClose() throws {
    let controller = CraftDocumentController(workspaces: WorkspaceLibrary())
    defer { DocumentWorkspaceTests().cleanup(controller) }
    let a = try DocumentWorkspaceTests().fixture(controller, name: "Numeric close")
    try a.store.session.execute(.lock(XCTUnwrap(a.store.activeLayer?.id), true))
    XCTAssertFalse(a.isDocumentEdited)
    try withPositionFields(document: a) { store, _, x, _ in
      _ = try replace(x, with: "17")
      var allowed: Bool?
      controller.documentWindows.requestClose(a) { allowed = $0 }
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      XCTAssertEqual(allowed, false)
      XCTAssertTrue(controller.documents.contains(where: { $0 === a }))
      XCTAssertNotNil(store.error)
      store.error = nil
    }
  }

  @MainActor func testUntouchedFieldExitAndOtherFieldRetirementPreserveFocusOwnership() throws {
    try withPositionFields { store, window, x, y in
      x.selectText(nil)
      let initial = try XCTUnwrap(x.currentEditor() as? NSTextView)
      initial.doCommand(by: #selector(NSResponder.insertNewline(_:)))
      XCTAssertFalse(window.firstResponder is NSTextView)
      y.selectText(nil)
      let untouched = try XCTUnwrap(y.currentEditor() as? NSTextView)
      untouched.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
      XCTAssertFalse(window.firstResponder is NSTextView)
      let editing = try replace(y, with: "-12")
      let other = try XCTUnwrap(x.delegate as? NativeNumericField.Coordinator)
      other.finishNumericEditing(cancel: true)
      XCTAssertTrue(window.firstResponder === editing)
      XCTAssertNotNil(store.numericEditor)
      editing.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
      XCTAssertTrue(store.session.undoStack.isEmpty)
    }
  }
}
