import AppKit
import SwiftUI

/// Native editable status-bar percentage with document-aware commit and Escape cancellation.
struct ZoomPercentageField: NSViewRepresentable {
  @Bindable var store: EditorStore
  var activateDocument: () -> Bool = { true }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField()
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.alignment = .center
    field.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
    field.textColor = NSColor(white: 0.88, alpha: 1)
    field.delegate = context.coordinator
    field.target = context.coordinator
    field.action = #selector(Coordinator.submit(_:))
    field.setAccessibilityLabel("Canvas zoom percentage")
    field.toolTip = "Enter zoom percentage"
    return field
  }
  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.synchronize(field, with: self)
  }
  @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: ZoomPercentageField
    var editingDocument: UUID?
    var presentedZoom: Double?
    init(_ parent: ZoomPercentageField) { self.parent = parent }
    func synchronize(_ field: NSTextField, with next: ZoomPercentageField) {
      // Observe zoom even while the field editor is active. An external Fit/zoom
      // command supersedes its draft; unrelated updates preserve typed text.
      let zoom = next.store.effectiveZoom
      let superseded = parent.store !== next.store || (presentedZoom != nil && presentedZoom != zoom)
      let wasEditing = field.currentEditor() != nil
      if superseded {
        editingDocument = nil
        field.abortEditing()
      }
      parent = next
      presentedZoom = zoom
      if field.currentEditor() == nil {
        field.stringValue = CanvasViewport.percentage(zoom)
      }
      if superseded && wasEditing { focusCanvas(from: field) }
    }
    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
      guard parent.activateDocument() else { return false }
      editingDocument = parent.store.identity
      return true
    }
    @objc func submit(_ field: NSTextField) {
      commit(field)
      // Return finishes navigation so tool shortcuts do not enter this field.
      focusCanvas(from: field)
    }
    private func focusCanvas(from field: NSTextField) {
      func canvas(in view: NSView) -> CraftCanvas? {
        if let canvas = view as? CraftCanvas, canvas.store === parent.store,
          !canvas.isHiddenOrHasHiddenAncestor { return canvas }
        for child in view.subviews {
          if let found = canvas(in: child) { return found }
        }
        return nil
      }
      guard let window = field.window else { return }
      window.makeFirstResponder(window.contentView.flatMap { canvas(in: $0) })
    }
    private func commit(_ field: NSTextField) {
      let target = editingDocument
      editingDocument = nil
      if target == parent.store.identity,
        let value = CanvasViewport.parsePercentage(field.stringValue)
      {
        parent.store.setZoom(value)
      }
      field.stringValue = CanvasViewport.percentage(parent.store.effectiveZoom)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
      if let field = notification.object as? NSTextField { commit(field) }
      editingDocument = nil
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool
    {
      guard command == #selector(NSResponder.cancelOperation(_:)),
        let field = control as? NSTextField
      else { return false }
      editingDocument = nil
      field.stringValue = CanvasViewport.percentage(parent.store.effectiveZoom)
      focusCanvas(from: field)
      return true
    }
  }
}
