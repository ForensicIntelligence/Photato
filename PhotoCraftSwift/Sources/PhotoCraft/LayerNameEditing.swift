import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class LayerNameDraft: Identifiable {
  let id = UUID()
  let layerID: UUID
  let originalName: String
  var text: String
  init(_ layer: Layer) {
    layerID = layer.id
    originalName = layer.name
    text = layer.name
  }
}

extension EditorStore {
  func canRenameLayer(_ id: UUID) -> Bool {
    canBeginLayerCreation && document.layers.contains { $0.id == id } && !document.isLocked(id)
  }
  func beginLayerName(_ id: UUID) {
    finishLayerName()
    guard canRenameLayer(id), let layer = document.layers.first(where: { $0.id == id }) else {
      return
    }
    select(id)
    layerNameDraft = LayerNameDraft(layer)
    workspaceLibrary.selectPanel(.layers, reveal: true)
  }
  /// Clear ownership before dispatching the command: focus callbacks may arrive again.
  func finishLayerName(_ expected: UUID? = nil, cancel: Bool = false) {
    guard let draft = layerNameDraft, expected == nil || expected == draft.id else { return }
    WorkspaceLayoutDiagnostics.log(
      "rename.finish", ["draft": draft.id.uuidString, "cancel": cancel])
    layerNameDraft = nil
    guard !cancel, canRenameLayer(draft.layerID),
      let layer = document.layers.first(where: { $0.id == draft.layerID }),
      layer.name == draft.originalName
    else { return }
    let name = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.utf16.count <= 65_535, name != layer.name else { return }
    perform(.renameLayer(layer.id, name))
  }
  func advanceLayerName(_ expected: UUID, by delta: Int, visibleIDs: [UUID]) {
    guard let draft = layerNameDraft, draft.id == expected,
      let index = visibleIDs.firstIndex(of: draft.layerID)
    else { return }
    finishLayerName(expected)
    let next = index + delta
    if visibleIDs.indices.contains(next) { beginLayerName(visibleIDs[next]) }
  }
}

/// Native field editor keeps text shortcuts local instead of firing canvas shortcuts.
struct LayerNameField: NSViewRepresentable {
  let store: EditorStore
  let draft: LayerNameDraft
  let visibleIDs: [UUID]
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NameField {
    let field = NameField()
    field.font = .systemFont(ofSize: 10)
    field.isBordered = false
    field.drawsBackground = true
    field.backgroundColor = .textBackgroundColor
    field.textColor = .textColor
    field.focusRingType = .none
    field.lineBreakMode = .byTruncatingTail
    field.setAccessibilityLabel("Layer name")
    field.delegate = context.coordinator
    context.coordinator.field = field
    context.coordinator.installMonitor()
    return field
  }
  func updateNSView(_ field: NameField, context: Context) {
    let changed = field.draftID != draft.id
    context.coordinator.parent = self
    if changed || field.currentEditor() == nil { field.stringValue = draft.text }
    if changed {
      field.draftID = draft.id
      field.needsInitialFocus = true
      field.requestInitialFocus()
    }
  }
  static func dismantleNSView(_ field: NameField, coordinator: Coordinator) {
    coordinator.removeMonitor()
    field.delegate = nil
  }

  @MainActor final class NameField: NSTextField {
    var draftID: UUID?
    var needsInitialFocus = false
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      requestInitialFocus()
    }
    func requestInitialFocus() {
      guard needsInitialFocus, window != nil else { return }
      let expected = draftID
      DispatchQueue.main.async { [weak self] in
        guard let self, self.needsInitialFocus, self.draftID == expected, self.window != nil
        else { return }
        self.needsInitialFocus = false
        WorkspaceLayoutDiagnostics.log(
          "rename.focus",
          [
            "draft": self.draftID?.uuidString ?? "",
            "frame": WorkspaceLayoutDiagnostics.rect(self.frame),
          ])
        self.selectText(nil)
      }
    }
  }

  @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: LayerNameField
    weak var field: NameField?
    var monitor: Any?
    var undoObservers: [NSObjectProtocol] = []
    init(_ parent: LayerNameField) { self.parent = parent }
    func installMonitor() {
      monitor = NSEvent.addLocalMonitorForEvents(matching: [
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
      ]) { [weak self] event in
        self?.handleMouseDown(event)
        return event
      }
    }
    func handleMouseDown(_ event: NSEvent) {
      guard let field, let window = field.window, event.windowNumber > 0 else { return }
      // Menu-bar/windowless events and native menu windows keep the field editor as
      // the Edit-menu target. Ordinary document/panel clicks commit before dispatch.
      if event.windowNumber == window.windowNumber {
        if !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) { finish() }
      } else if let target = event.window, target.level.rawValue < NSWindow.Level.mainMenu.rawValue
      {
        finish()
      }
    }
    func removeMonitor() {
      if let monitor { NSEvent.removeMonitor(monitor) }
      monitor = nil
      removeUndoObservers()
    }
    func removeUndoObservers() {
      undoObservers.forEach(NotificationCenter.default.removeObserver)
      undoObservers.removeAll()
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
      removeUndoObservers()
      guard let editor = field?.currentEditor() as? NSTextView, let manager = editor.undoManager
      else { return }
      for name in [Notification.Name.NSUndoManagerDidUndoChange, .NSUndoManagerDidRedoChange] {
        undoObservers.append(
          NotificationCenter.default.addObserver(forName: name, object: manager, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.synchronizeText() }
          })
      }
    }
    func synchronizeText() {
      guard parent.store.layerNameDraft === parent.draft, let field else { return }
      parent.draft.text = field.currentEditor()?.string ?? field.stringValue
    }
    func controlTextDidChange(_ notification: Notification) {
      synchronizeText()
    }
    func controlTextDidEndEditing(_ notification: Notification) { finish() }
    func finish(cancel: Bool = false, advance: Int? = nil) {
      guard parent.store.layerNameDraft === parent.draft else { return }
      removeUndoObservers()
      if let field { parent.draft.text = field.currentEditor()?.string ?? field.stringValue }
      if let advance {
        parent.store.advanceLayerName(parent.draft.id, by: advance, visibleIDs: parent.visibleIDs)
      } else {
        parent.store.finishLayerName(parent.draft.id, cancel: cancel)
      }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool
    {
      switch command {
      case #selector(NSResponder.insertNewline(_:)): finish()
      case #selector(NSResponder.insertTab(_:)): finish(advance: 1)
      case #selector(NSResponder.insertBacktab(_:)): finish(advance: -1)
      case #selector(NSResponder.cancelOperation(_:)): finish(cancel: true)
      default: return false
      }
      control.window?.makeFirstResponder(nil)
      return true
    }
  }
}
