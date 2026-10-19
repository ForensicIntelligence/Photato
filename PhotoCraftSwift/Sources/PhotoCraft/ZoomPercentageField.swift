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
    if context.coordinator.parent.store !== store {
      // An unfinished value must never commit into a newly selected document.
      context.coordinator.editingDocument = nil
      field.abortEditing()
    }
    context.coordinator.parent = self
    if field.currentEditor() == nil {
      field.stringValue = CanvasViewport.percentage(store.effectiveZoom)
    }
  }
  @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: ZoomPercentageField
    var editingDocument: UUID?
    init(_ parent: ZoomPercentageField) { self.parent = parent }
    func control(_ control: NSControl, textShouldBeginEditing fieldEditor: NSText) -> Bool {
      guard parent.activateDocument() else { return false }
      editingDocument = parent.store.identity
      return true
    }
    @objc func submit(_ field: NSTextField) {
      if editingDocument == parent.store.identity,
        let value = CanvasViewport.parsePercentage(field.stringValue)
      {
        parent.store.setZoom(value)
      }
      field.stringValue = CanvasViewport.percentage(parent.store.effectiveZoom)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
      if let field = notification.object as? NSTextField { submit(field) }
      editingDocument = nil
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool
    {
      guard command == #selector(NSResponder.cancelOperation(_:)),
        let field = control as? NSTextField
      else { return false }
      editingDocument = nil
      field.stringValue = CanvasViewport.percentage(parent.store.effectiveZoom)
      field.window?.makeFirstResponder(nil)
      return true
    }
  }
}
