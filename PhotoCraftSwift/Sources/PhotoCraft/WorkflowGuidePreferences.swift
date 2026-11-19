import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class WorkflowGuidePreferences {
  static let limits = 1...8
  static let defaultLimit = 4
  private static let limitKey = "workflowGuide.maximumSuggestions"
  private static let launchKey = "workflowGuide.opensAtLaunch"

  @ObservationIgnored private let defaults: UserDefaults?
  private(set) var maximumSuggestions: Int
  private(set) var isShown = false
  var opensAtLaunch: Bool {
    didSet { defaults?.set(opensAtLaunch, forKey: Self.launchKey) }
  }

  init(defaults: UserDefaults? = nil) {
    self.defaults = defaults
    let storedLimit = defaults?.object(forKey: Self.limitKey) as? Int
    maximumSuggestions = storedLimit.flatMap { Self.limits.contains($0) ? $0 : nil } ?? Self.defaultLimit
    opensAtLaunch = defaults?.bool(forKey: Self.launchKey) ?? false
  }

  func setMaximumSuggestions(_ value: Int) {
    guard Self.limits.contains(value), value != maximumSuggestions else { return }
    maximumSuggestions = value
    defaults?.set(value, forKey: Self.limitKey)
  }

  func setShown(_ value: Bool) { isShown = value }

  var capability: [String: Any] {
    ["maximumSuggestions": maximumSuggestions, "defaultMaximumSuggestions": Self.defaultLimit,
     "allowedMaximumSuggestions": Array(Self.limits), "opensAtLaunch": opensAtLaunch,
     "isShown": isShown, "menu": "Photato > Settings… > Workflow Guide…"]
  }
}

struct WorkflowGuidePreferencesView: View {
  @Bindable var preferences: WorkflowGuidePreferences
  let setVisible: @MainActor @Sendable (Bool) -> Void

  var body: some View {
    Form {
      Toggle("Show Workflow Guide", isOn: Binding(get: { preferences.isShown }, set: setVisible))
      Toggle("Open Workflow Guide at launch", isOn: $preferences.opensAtLaunch)
      Picker("Maximum suggestions", selection: Binding(get: { preferences.maximumSuggestions },
        set: preferences.setMaximumSuggestions)) {
        ForEach(WorkflowGuidePreferences.limits, id: \.self) { count in
          Text(count.formatted()).tag(count)
        }
      }
      .pickerStyle(.menu)
    }
    .formStyle(.grouped)
    .frame(width: 390, height: 170)
  }
}

@MainActor extension AppDelegate {
  @objc func showWorkflowGuidePreferences() {
    if workflowGuidePreferencesWindow == nil {
      let window = PhotatoWindow(contentRect: NSRect(x: 0, y: 0, width: 390, height: 170),
        styleMask: [.titled, .closable], backing: .buffered, defer: false)
      window.title = "Settings — Workflow Guide"
      window.isReleasedWhenClosed = false
      window.contentViewController = NSHostingController(rootView: WorkflowGuidePreferencesView(
        preferences: controller.workflowGuidePreferences) { [weak self] visible in
          self?.setWorkflowGuideVisible(visible, takesFocus: false)
        })
      window.center()
      workflowGuidePreferencesWindow = NSWindowController(window: window)
    }
    workflowGuidePreferencesWindow?.window?.makeKeyAndOrderFront(nil)
  }
}
