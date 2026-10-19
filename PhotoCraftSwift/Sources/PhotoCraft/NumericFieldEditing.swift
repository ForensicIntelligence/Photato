import AppKit
import SwiftUI

@MainActor protocol NumericFieldEditing: AnyObject {
  func finishNumericEditing(cancel: Bool)
}

extension EditorStore {
  func finishNumericField(cancel: Bool = false) {
    numericEditor?.finishNumericEditing(cancel: cancel)
  }
}

/// The field owns uncommitted text. Document commands receive one value when the
/// user commits, matching Properties in Photoshop rather than moving per digit.
struct NativeNumericField: NSViewRepresentable {
  let store: EditorStore
  let label: String
  var value: Binding<Double>
  let range: ClosedRange<Double>
  var alignment: NSTextAlignment = .left
  var locale = Locale.current

  struct ContextID: Equatable {
    let owner: UUID
    let generation: UUID
    let layer: UUID?
    let tool: String
    let label: String
  }
  var contextID: ContextID {
    ContextID(
      owner: store.identity, generation: store.layerPanelGeneration,
      layer: store.document.activeLayerID, tool: store.selectedTool.id, label: label)
  }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField()
    field.isBordered = false
    field.isBezeled = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 11)
    field.textColor = NSColor(white: 0.88, alpha: 1)
    field.alignment = alignment
    field.setAccessibilityLabel(label)
    field.delegate = context.coordinator
    context.coordinator.field = field
    return field
  }
  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.update(self)
    field.isEnabled = context.environment.isEnabled
    field.alignment = alignment
    field.setAccessibilityLabel(label)
    if field.currentEditor() == nil { field.stringValue = context.coordinator.formattedValue }
  }
  static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
    coordinator.finishNumericEditing(cancel: true)
    field.delegate = nil
  }

  @MainActor final class Coordinator: NSObject, NSTextFieldDelegate, NumericFieldEditing {
    var parent: NativeNumericField
    weak var field: NSTextField?
    struct Draft {
      let context: ContextID
      let original: Double
      let binding: Binding<Double>
    }
    var draft: Draft?
    init(_ parent: NativeNumericField) { self.parent = parent }
    var formatter: NumberFormatter {
      let result = NumberFormatter()
      result.locale = parent.locale
      result.numberStyle = .decimal
      result.maximumFractionDigits = 0
      result.minimumFractionDigits = 0
      return result
    }
    var formattedValue: String {
      formatter.string(from: NSNumber(value: parent.value.wrappedValue)) ?? ""
    }
    func parsed(_ text: String) -> Double? {
      let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { return nil }
      var result: AnyObject?
      var range = NSRange(location: 0, length: text.utf16.count)
      do {
        try formatter.getObjectValue(&result, for: text, range: &range)
        guard range.location == 0, range.length == text.utf16.count,
          let number = result as? NSNumber, number.doubleValue.isFinite
        else { return nil }
        return min(parent.range.upperBound, max(parent.range.lowerBound, number.doubleValue))
      } catch { return nil }
    }
    func update(_ next: NativeNumericField) {
      if let draft, draft.context != next.contextID {
        finishNumericEditing(cancel: true)
      }
      parent = next
    }
    func controlTextDidBeginEditing(_ notification: Notification) {
      parent.store.finishNumericField()
      draft = Draft(
        context: parent.contextID, original: parent.value.wrappedValue,
        binding: parent.value)
      parent.store.numericEditor = self
    }
    func controlTextDidEndEditing(_ notification: Notification) {
      finish(cancel: false, resign: false)
    }
    func finishNumericEditing(cancel: Bool) { finish(cancel: cancel, resign: true) }
    func resignFieldEditor() {
      guard let field, field.currentEditor() != nil else { return }
      field.window?.makeFirstResponder(nil)
    }
    func finish(cancel: Bool, resign: Bool) {
      guard let draft else {
        if resign { resignFieldEditor() }
        return
      }
      let input = field?.currentEditor()?.string ?? field?.stringValue ?? ""
      self.draft = nil
      if parent.store.numericEditor === self { parent.store.numericEditor = nil }
      if !cancel, draft.context == parent.contextID,
        draft.binding.wrappedValue == draft.original, let number = parsed(input),
        number != draft.original
      {
        draft.binding.wrappedValue = number
      }
      field?.stringValue = formattedValue
      if resign { resignFieldEditor() }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool
    {
      switch command {
      case #selector(NSResponder.insertNewline(_:)):
        finish(cancel: false, resign: true)
      case #selector(NSResponder.cancelOperation(_:)):
        finish(cancel: true, resign: true)
      case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
        finish(cancel: false, resign: false)
        // NSTextField owns the field-editor movement code and key-view loop.
        // Returning false lets AppKit perform its normal forward/backward move.
        return false
      default: return false
      }
      return true
    }
  }
}
