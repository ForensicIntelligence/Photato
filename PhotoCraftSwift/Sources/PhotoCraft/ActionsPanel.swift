import AppKit
import PhotoCraftCore
import SwiftUI
import UniformTypeIdentifiers

struct ActionsPanel: View {
  @Bindable var store: EditorStore
  @State private var selected: UUID?
  @State private var stepID: UUID?
  @State private var name = "Action 1"
  @State private var set = "My Actions"
  @State private var message: String?
  var recording: RecordedAction? { store.session.actionRecording?.snapshot }
  var action: RecordedAction? { recording ?? store.actions.file.actions.first { $0.id == selected } }
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(store.document.name).font(.caption).foregroundStyle(.secondary)
      if let error = store.actions.loadError { Text(error).foregroundStyle(.red) }
      if recording == nil {
        Picker("Action", selection: $selected) {
          Text("Choose an action").tag(nil as UUID?)
          ForEach(store.actions.file.actions) { action in Text("\(action.set) / \(action.name)").tag(Optional(action.id)) }
        }
        HStack { TextField("Set", text: $set); TextField("Action name", text: $name) }
        HStack {
          Button("Record", systemImage: "record.circle") { attempt { try store.startRecordingAction(name: name, set: set) } }.disabled(!store.canUseActions)
          Button("Play", systemImage: "play.fill") { if let action { store.playAction(action) } }.disabled(action == nil || !store.canUseActions)
          Button("Rename") { attempt { if var action { action.name = name; action.set = set; try store.actions.save(action) } } }.disabled(action == nil)
        }
      } else {
        Label("Recording: \(recording!.name)", systemImage: "record.circle.fill").foregroundStyle(.red)
        HStack {
          Button("Stop", systemImage: "stop.fill") { attempt { selected = try store.stopRecordingAction().id } }.disabled(!store.canUseActions)
          Button("Discard Recording") { attempt { _ = try store.stopRecordingAction(save: false) } }.disabled(!store.canUseActions)
        }
      }
      List(selection: $stepID) {
        ForEach(action?.steps ?? []) { step in
          HStack(alignment: .top) {
            Toggle("Enabled", isOn: Binding(get: { step.enabled }, set: { enabled in editStep(step.id) { $0.enabled = enabled } })).labelsHidden().disabled(recording != nil)
            VStack(alignment: .leading) {
              Text(step.name)
              if let reason = step.operation.unsupportedReason { Text(reason).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }
          }.tag(step.id)
        }
      }.frame(minHeight: 160)
      HStack {
        Button("↑") { moveStep(-1) }.help("Move step up")
        Button("↓") { moveStep(1) }.help("Move step down")
        Button("Delete Step") { attempt { if var action, let stepID { action.steps.removeAll { $0.id == stepID }; try store.actions.save(action) } } }
      }.disabled(recording != nil || stepID == nil)
      HStack {
        Button("Load…") { importActions() }
        Button("Save…") { exportAction() }.disabled(action == nil)
        Spacer()
        Button("Delete Action", role: .destructive) { attempt { if let selected { try store.actions.remove(selected); self.selected = nil } } }.disabled(selected == nil)
      }.disabled(recording != nil)
      if store.geometryBusy {
        HStack { ProgressView().controlSize(.small); Text(store.status); Button("Cancel") { store.geometryTask?.cancel() } }
      }
      if let message { Text(message).font(.caption).foregroundStyle(.red) }
      Text("Pixel coordinates and dimensions are absolute. Layer references follow the active layer or a recorded layer name.").font(.caption).foregroundStyle(.secondary)
    }.padding(12).frame(minWidth: 340, minHeight: 380)
    .onChange(of: selected) { _, _ in if let action { name = action.name; set = action.set } }
  }
  func attempt(_ operation: () throws -> Void) { do { try operation(); message = nil } catch { message = error.localizedDescription } }
  func editStep(_ id: UUID, _ edit: (inout RecordedActionStep) -> Void) { attempt { if var action, let index = action.steps.firstIndex(where: { $0.id == id }) { edit(&action.steps[index]); try store.actions.save(action) } } }
  func moveStep(_ delta: Int) { attempt { if var action, let index = action.steps.firstIndex(where: { $0.id == stepID }), action.steps.indices.contains(index + delta) { action.steps.swapAt(index, index + delta); try store.actions.save(action) } } }
  func importActions() {
    let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "photatoactions") ?? .json]; panel.allowsMultipleSelection = false
    panel.begin { result in if result == .OK, let url = panel.url { attempt { try store.actions.importFile(ActionLibrary.read(url)) } } }
  }
  func exportAction() {
    guard let action else { return }
    let panel = NSSavePanel(); panel.nameFieldStringValue = action.name + ".photatoactions"
    panel.allowedContentTypes = [UTType(filenameExtension: "photatoactions") ?? .json]
    panel.begin { result in if result == .OK, let url = panel.url { attempt { try store.actions.exportFile(action.id).write(to: url, options: .atomic) } } }
  }
}

struct ActionsPanelRoot: View {
  @Bindable var documents: DocumentWindows
  var body: some View {
    if let document = documents.activeDocument { ActionsPanel(store: document.store).id(ObjectIdentifier(document.store)) }
    else { Text("Open an image to record or play actions.").padding(30) }
  }
}
@MainActor extension AppDelegate {
  @objc func showActions() {
    if actionsWindow == nil {
      let panel = FloatingPanelWindow(contentRect: NSRect(x: 150, y: 150, width: 400, height: 500), styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
      panel.title = "Actions"; panel.isReleasedWhenClosed = false; panel.isFloatingPanel = true
      panel.hidesOnDeactivate = true; panel.documents = controller.documentWindows
      panel.contentView = NSHostingView(rootView: ActionsPanelRoot(documents: controller.documentWindows))
      panel.appearance = NSAppearance(named: .darkAqua); panel.tabbingMode = .disallowed
      actionsWindow = NSWindowController(window: panel)
    }
    actionsWindow?.showWindow(nil)
  }
}
