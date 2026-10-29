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
    if let draft=store?.selectMaskDraft{item.title=(redo ? "Redo ":"Undo ")+draft.title;return draft.ready && (redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty)}
    if let draft = store?.skyWorkspace {
      item.title = redo ? "Redo Sky Replacement" : "Undo Sky Replacement"
      return draft.ready && (redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty)
    }
    if let draft = store?.vanishingWorkspace {
      item.title = redo ? "Redo Vanishing Point" : "Undo Vanishing Point"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty || !draft.pending.isEmpty
    }
    if let draft = store?.wideAngleWorkspace {
      item.title = redo ? "Redo Adaptive Wide Angle" : "Undo Adaptive Wide Angle"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty || !draft.polygon.isEmpty
    }
    if let draft = store?.lensCorrectionWorkspace {
      item.title = redo ? "Redo Lens Correction" : "Undo Lens Correction"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty
    }
    if let draft = store?.inkModeWorkspace { item.title = (redo ? "Redo " : "Undo ") + draft.request.title; return !draft.committing && (redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty) }
    if let draft = store?.restrictedModeWorkspace { item.title = (redo ? "Redo " : "Undo ") + draft.request.title; return !draft.committing && (redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty) }
    if let draft = store?.documentModeWorkspace { item.title = (redo ? "Redo " : "Undo ") + "Color Mode"; return !draft.committing && (redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty) }
    if let draft=store?.activeClassicToneWorkspace {item.title=(redo ? "Redo ":"Undo ")+draft.request.settings.kind.title;return !draft.committing && (redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty)}
    if let draft = store?.proceduralWorkspace {item.title=(redo ? "Redo ":"Undo ")+draft.request.settings.kind.title;return !draft.committing && (redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty)}
    if let draft = store?.classicDetailWorkspace {item.title=(redo ? "Redo ":"Undo ")+draft.filter.kind.title;return redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty}
    if let draft = store?.otherVideoWorkspace {item.title=(redo ? "Redo ":"Undo ")+draft.filter.kind.title;return redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty}
    if let draft = store?.renderWorkspace {item.title=(redo ? "Redo ":"Undo ")+draft.filter.kind.title;return redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty}
    if let draft = store?.stylizeWorkspace {item.title=(redo ? "Redo ":"Undo ")+draft.filter.kind.title;return redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty}
    if let draft = store?.pixelateWorkspace { item.title=(redo ? "Redo ":"Undo ")+draft.filter.kind.title;return redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty }
    if let draft = store?.distortionWorkspace { item.title=(redo ? "Redo ":"Undo ")+draft.filter.kind.title;return redo ? !draft.redoStates.isEmpty:!draft.undoStates.isEmpty }
    if let draft = store?.lensBlurWorkspace {
      item.title = redo ? "Redo Lens Blur" : "Undo Lens Blur"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty
    }
    if let draft = store?.photoDetailWorkspace {
      item.title = (redo ? "Redo " : "Undo ") + draft.filter.kind.title
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty
    }
    if let draft = store?.artisticGalleryWorkspace {
      item.title = redo ? "Redo Filter Gallery" : "Undo Filter Gallery"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty
    }
    if let draft = store?.blurGalleryWorkspace {
      item.title = redo ? "Redo Blur Gallery" : "Undo Blur Gallery"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty
    }
    if let draft = store?.perspectiveWorkspace {
      item.title = redo ? "Redo Perspective Warp" : "Undo Perspective Warp"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty
    }
    if let draft = store?.puppetWorkspace {
      item.title = redo ? "Redo Puppet Warp" : "Undo Puppet Warp"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty
    }
    if let draft = store?.warpDraft {
      item.title = redo ? "Redo Warp" : "Undo Warp"
      return redo ? !draft.redoStates.isEmpty : !draft.undoStates.isEmpty
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

  @discardableResult
  func performHistory(redo: Bool, in window: NSWindow?) -> Task<Bool, Never>? {
    if let text = window?.firstResponder as? NSTextView {
      guard text.isEditable,
        (redo ? text.undoManager?.canRedo : text.undoManager?.canUndo) == true
      else { return nil }
      _ = text.tryToPerform(NSSelectorFromString(redo ? "redo:" : "undo:"), with: nil)
      return nil
    }
    if let draft=store?.selectMaskDraft{if redo{draft.redo()}else{draft.undo()};return nil}
    if let draft = store?.skyWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.vanishingWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.wideAngleWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.lensCorrectionWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.inkModeWorkspace { if redo { draft.redo() } else { draft.undo() }; return nil }
    if let draft = store?.restrictedModeWorkspace { if redo { draft.redo() } else { draft.undo() }; return nil }
    if let draft = store?.documentModeWorkspace { if redo { draft.redo() } else { draft.undo() }; return nil }
    if let draft=store?.activeClassicToneWorkspace {if redo{draft.redo()}else{draft.undo()};return nil}
    if let draft = store?.proceduralWorkspace {if !draft.committing {if redo {draft.redo()} else {draft.undo()}};return nil}
    if let draft = store?.classicDetailWorkspace {if redo {draft.redo()} else {draft.undo()};return nil}
    if let draft = store?.otherVideoWorkspace {if redo {draft.redo()} else {draft.undo()};return nil}
    if let draft = store?.renderWorkspace {if redo {draft.redo()} else {draft.undo()};return nil}
    if let draft = store?.stylizeWorkspace {if redo {draft.redo()} else {draft.undo()};return nil}
    if let draft = store?.pixelateWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.distortionWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.lensBlurWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.photoDetailWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.artisticGalleryWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.blurGalleryWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.perspectiveWorkspace { if redo { draft.redo() } else { draft.undo() };return nil }
    if let draft = store?.puppetWorkspace { if redo { draft.redo() } else { draft.undo() }; return nil }
    if let draft = store?.warpDraft { if redo { draft.redo() } else { draft.undo() }; return nil }
    return store?.requestHistory(redo: redo)
  }
}
