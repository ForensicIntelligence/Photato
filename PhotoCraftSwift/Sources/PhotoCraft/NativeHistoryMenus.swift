import AppKit

@MainActor extension AppDelegate {
  /// Inspect the explicit native window so text editing in floating panels and dialogs
  /// cannot accidentally undo the globally active document.
  func validateHistoryMenu(_ item: NSMenuItem, in window: NSWindow?) -> Bool? {
    guard item.action == #selector(undo) || item.action == #selector(redo) else { return nil }
    let redo = item.action == #selector(self.redo)
    if let text = window?.firstResponder as? NSTextView {
      let manager = text.undoManager
      item.title =
        redo ? manager?.redoMenuItemTitle ?? "Redo" : manager?.undoMenuItemTitle ?? "Undo"
      return text.isEditable && (redo ? manager?.canRedo : manager?.canUndo) == true
    }
    if redo {
      item.title = store?.session.redoStack.last.map { "Redo \($0.label)" } ?? "Redo"
    } else {
      item.title = store?.session.undoStack.last.map { "Undo \($0.label)" } ?? "Undo"
    }
    guard let store, !store.geometryBusy, !store.hasToneDraft else { return false }
    return redo
      ? store.transformDraft == nil && !store.session.redoStack.isEmpty
      : store.transformDraft != nil || !store.session.undoStack.isEmpty
  }

  func performHistory(redo: Bool, in window: NSWindow?) {
    if let text = window?.firstResponder as? NSTextView {
      guard text.isEditable,
        (redo ? text.undoManager?.canRedo : text.undoManager?.canUndo) == true
      else { return }
      _ = text.tryToPerform(NSSelectorFromString(redo ? "redo:" : "undo:"), with: nil)
      return
    }
    if redo { store?.redo() } else { store?.undo() }
  }
}
