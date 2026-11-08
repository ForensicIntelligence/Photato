import AppKit
import PhotoCraftCore
import SwiftUI

struct ScriptEventsView: View {
  @Bindable var store: ScriptEventsStore
  let dispatcher: ScriptEventDispatcher
  let done: () -> Void
  @State private var selected: UUID?
  @State private var event = "startApplication"
  @State private var actionSet = ""
  @State private var actionID: UUID?
  @State private var error: String?
  private var sets: [String] { Array(Set(store.actions.file.actions.map(\.set))).sorted() }
  private var actions: [RecordedAction] { store.actions.file.actions.filter { $0.set == actionSet } }
  private var editable: Bool { store.configuration.enabled && store.loadError == nil && store.actions.loadError == nil }
  private func attempt(_ work: () throws -> Void) {
    do { try work(); error = nil } catch { self.error = error.localizedDescription }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ScrollView {
      VStack(alignment: .leading, spacing: 12) {
      Toggle("Enable Events to Run Scripts/Actions", isOn: Binding(
        get: { store.configuration.enabled }, set: { enabled in attempt { try store.setEnabled(enabled) } }))
        .disabled(store.loadError != nil || store.actions.loadError != nil)
        .accessibilityIdentifier("scriptEvents.enabled")
      HStack(alignment: .top, spacing: 12) {
        Table(store.configuration.bindings, selection: $selected) {
          TableColumn("Event") { Text($0.event.title) }.width(min: 120, ideal: 140)
          TableColumn("Action") { binding in
            let action = store.actions.file.actions.first { $0.id == binding.actionID }
            Text(action.map { "\($0.set) / \($0.name)" } ?? "Action unavailable")
          }
        }.frame(minHeight: 150).accessibilityLabel("Registered event actions")
        VStack {
          Button("Remove") { if let selected { attempt { try store.remove(selected); self.selected = nil } } }
            .disabled(selected == nil)
          Button("Remove All") { attempt { try store.remove(nil); selected = nil } }
            .disabled(store.configuration.bindings.isEmpty)
        }.controlSize(.regular)
      }.disabled(!editable)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
        GridRow {
          Text("Application Event:")
          Picker("Event", selection: $event) {
            Text("Start Application (unavailable)").tag("startApplication").disabled(true)
            ForEach(ScriptEventKind.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            ForEach(["Save Document", "Close Document", "Print Document", "Export Document"], id: \.self) {
              Text("\($0) (unavailable)").tag($0).disabled(true)
            }
          }.labelsHidden().accessibilityIdentifier("scriptEvents.event")
        }
        GridRow {
          Text("Action:")
          HStack {
            Picker("Action set", selection: $actionSet) {
              Text("Choose a set").tag("")
              ForEach(sets, id: \.self) { Text($0).tag($0) }
            }.accessibilityIdentifier("scriptEvents.actionSet")
            Picker("Action", selection: $actionID) {
              Text("Choose an action").tag(nil as UUID?)
              ForEach(actions) { Text($0.name).tag(Optional($0.id)) }
            }.accessibilityIdentifier("scriptEvents.action")
          }
        }
      }.disabled(!editable)
      HStack {
        Text("Load or record Actions in the Actions panel. Scripts and other events are unavailable.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        Spacer()
        Button("Add") {
          guard let kind = ScriptEventKind(rawValue: event), let actionID else { return }
          attempt { try store.add(event: kind, actionID: actionID) }
        }.disabled(!editable || ScriptEventKind(rawValue: event) == nil || actionID == nil
          || store.configuration.bindings.count >= ScriptEventsConfiguration.maximumBindings)
        .accessibilityIdentifier("scriptEvents.add")
      }
      Text("Registered actions apply to new and newly opened documents, including documents created by API clients. Configuration changes are saved immediately.")
        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      if dispatcher.isRunning { ProgressView("Running event Actions…").controlSize(.small) }
      if let result = dispatcher.lastResult {
        Text(result.error.map { "\(result.event.title): \($0)" } ?? "\(result.event.title): \(result.completedActions) Actions completed")
          .font(.caption).foregroundStyle(result.error == nil ? Color.secondary : .red)
          .accessibilityIdentifier("scriptEvents.result")
      }
      if let problem = error ?? store.loadError ?? store.actions.loadError {
        Text(problem).font(.caption).foregroundStyle(.red).textSelection(.enabled)
      }
      }
      }
      HStack { Spacer(); Button("Done", action: done).keyboardShortcut(.defaultAction) }
    }.padding(20).frame(minWidth: 600, minHeight: 400)
      .onChange(of: actionSet) { _, _ in actionID = nil }
  }
}

@MainActor final class ScriptEventsWindow: NSWindowController {
  init(controller: CraftDocumentController) {
    let window = PhotatoWindow(contentRect: .init(x: 0, y: 0, width: 700, height: 470),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "Script Events Manager"; window.isReleasedWhenClosed = false
    super.init(window: window)
    window.contentView = NSHostingView(rootView: ScriptEventsView(store: controller.scriptEvents,
      dispatcher: controller.scriptEventsDispatcher) { [weak self] in self?.close() })
    window.minSize = .init(width: 640, height: 450); window.center()
  }
  required init?(coder: NSCoder) { nil }
}

@MainActor extension AppDelegate {
  var canShowScriptEvents: Bool { NSApp?.modalWindow == nil && NSApp?.keyWindow?.attachedSheet == nil }
  @objc func showScriptEvents() {
    guard canShowScriptEvents else { return }
    if scriptEventsWindow?.window?.isVisible != true { scriptEventsWindow = ScriptEventsWindow(controller: controller) }
    scriptEventsWindow?.showWindow(nil); scriptEventsWindow?.window?.makeKeyAndOrderFront(nil)
  }
}
