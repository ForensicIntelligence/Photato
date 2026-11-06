import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

/// Dialog visibility is independent of encoder capability and explicit output requests.
enum SaveDialogFormats {
  static let defaults = Set(DocumentIO.Format.allCases)
  static let menuPath = "Edit > Customize Save Dialog File Formats"
  static func ordered(_ selection: Set<DocumentIO.Format>) -> [DocumentIO.Format] {
    DocumentIO.Format.allCases.filter { selection.contains($0) }
  }
  static func parse(_ values: [String]) throws -> Set<DocumentIO.Format> {
    guard values.count <= DocumentIO.Format.allCases.count, Set(values).count == values.count else {
      throw CraftError.invalid("Choose unique supported save formats.")
    }
    return try Set(values.map { value in
      guard let format = DocumentIO.Format(rawValue: value) else {
        throw CraftError.invalid("Unknown save format.")
      }
      return format
    })
  }
  static var schema: [String: Any] {
    ["type": "array", "uniqueItems": true, "maxItems": DocumentIO.Format.allCases.count,
      "items": ["type": "string", "enum": DocumentIO.Format.allCases.map(\.rawValue)]]
  }
}

@MainActor extension CraftNSDocument {
  var dialogSaveFormats: [DocumentIO.Format] {
    saveFormats.filter { fileHandlingPreferences.saveDialogFormats.contains($0) }
  }
  var dialogCopyFormats: [DocumentIO.Format] {
    SaveDialogFormats.ordered(fileHandlingPreferences.saveDialogFormats)
  }
  func explainUnavailableSaveFormats() {
    store.error = "No compatible save formats are selected. Choose Edit > Customize Save Dialog File Formats to select formats or restore defaults."
  }
}

@MainActor @Observable final class SaveDialogFormatsDraft {
  let controller: CraftDocumentController
  let revision: UUID
  var selected: Set<DocumentIO.Format>
  var error: String?
  init(controller: CraftDocumentController) {
    self.controller = controller
    revision = controller.recoveryPreferences.revision
    selected = controller.recoveryPreferences.value.saveDialogFormats
    error = controller.recoveryPreferences.loadError
  }
  func restoreDefaults() { selected = SaveDialogFormats.defaults }
  func clearFormats() { selected = [] }
  func apply() -> Bool {
    do {
      var next = controller.recoveryPreferences.value
      next.saveDialogFormats = selected
      try controller.setRecoveryPreferences(next, revision: revision)
      error = nil
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
}

struct SaveDialogFormatsView: View {
  @Bindable var draft: SaveDialogFormatsDraft
  let dismiss: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Choose the formats shown in Save As and Save a Copy.")
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          ForEach(DocumentIO.Format.allCases, id: \.rawValue) { format in
            Toggle("\(format.title) (.\(format.rawValue))", isOn: Binding(
              get: { draft.selected.contains(format) },
              set: { enabled in
                if enabled { draft.selected.insert(format) } else { draft.selected.remove(format) }
              }))
              .toggleStyle(.checkbox).accessibilityIdentifier("saveFormats." + format.rawValue)
          }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
      }.frame(height: 180)
      if draft.selected.isEmpty {
        Text("Save As and Save a Copy need a selected, compatible format.")
          .font(.caption).foregroundStyle(.secondary)
      }
      if let error = draft.error {
        Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("Restore Defaults") { draft.restoreDefaults() }
        Button("Clear Formats") { draft.clearFormats() }
        Spacer()
        Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
        Button("Done") { if draft.apply() { dismiss() } }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 560)
  }
}

@MainActor final class SaveDialogFormatsWindowController: NSWindowController {
  let draft: SaveDialogFormatsDraft
  init(controller: CraftDocumentController) {
    draft = SaveDialogFormatsDraft(controller: controller)
    let window = PhotatoWindow(contentRect: .init(x: 0, y: 0, width: 600, height: 310),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Customize Save Dialog File Formats"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.contentView = NSHostingView(rootView: SaveDialogFormatsView(draft: draft) { [weak self] in self?.close() })
    window.center()
  }
  required init?(coder: NSCoder) { nil }
}

@MainActor extension AppDelegate {
  @objc func customizeSaveDialogFileFormats() {
    if saveFormatsWindow?.window?.isVisible != true {
      saveFormatsWindow = SaveDialogFormatsWindowController(controller: controller)
    }
    saveFormatsWindow?.showWindow(nil)
    saveFormatsWindow?.window?.makeKeyAndOrderFront(nil)
  }
}
