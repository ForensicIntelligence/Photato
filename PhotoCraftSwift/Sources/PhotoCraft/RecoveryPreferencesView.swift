import AppKit
import SwiftUI

struct RecoveryPreferencesView: View {
  @Bindable var draft: RecoveryPreferencesDraft
  let dismiss: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      GroupBox("File Saving Options") {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Toggle("Automatically Save Recovery Information Every:", isOn: $draft.value.enabled)
            Picker("Recovery interval", selection: $draft.value.intervalMinutes) {
              ForEach(RecoveryPreferences.intervals, id: \.self) { minutes in
                Text(minutes == 60 ? "1 Hour" : "\(minutes) Minutes").tag(minutes)
              }
            }
            .labelsHidden().frame(width: 125).disabled(!draft.value.enabled)
          }
          Text("Recovery backups preserve committed edits for reopening after a crash.")
            .font(.caption).foregroundStyle(.secondary)
        }.padding(10)
      }
      GroupBox("File Compatibility") {
        VStack(alignment: .leading, spacing: 8) {
          Toggle("Disable Compression of PSD and PSB Files",
            isOn: $draft.value.disablePSDCompression)
          Text("Use uncompressed data by default when saving 16-bit and 32-bit Photoshop files. Files may be larger. Explicit compression choices in Save As or Save a Copy take precedence.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
      }
      GroupBox("Recovery Backups") {
        VStack(alignment: .leading, spacing: 8) {
          let index = draft.controller.recoveryIndex
          Text(index.isDiscovering ? "Looking for recovery backups…" :
            "\(index.lastDiscovered) recovered · \(index.lastAlreadyOpen) already open · \(index.lastDeferred) deferred · \(index.lastUnavailable + index.lastInvalid) need attention")
            .font(.caption)
          Text("Backups are kept in Photato’s private recovery folder, independently of the original files.")
            .font(.caption).foregroundStyle(.secondary)
          if let message = index.loadError ?? index.writeError ?? index.discoveryError {
            Text(message).font(.caption).foregroundStyle(.red)
          }
          if index.lastDeferred > 0 {
            Text("Some backups exceeded the automatic recovery memory allowance. Their files are preserved. Close documents and retry, or use Review Backups to choose an individual copy.")
              .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
          }
          if let operation = draft.controller.recoveryDiscovery.state, operation.active {
            Text("\(operation.completedEntries) of \(operation.totalEntries) recovery records checked")
              .font(.caption)
            Button(operation.cancellationRequested ? "Cancelling…" : "Cancel Recovery") {
              draft.controller.recoveryDiscovery.cancel(operation.id)
            }.disabled(operation.cancellationRequested)
          }
          Button("Retry Recovery") {
            Task { try? await draft.controller.discoverIndexedRecovery(display: true) }
          }.disabled(!draft.controller.recoveryDiscovery.canStart)
          Button("Review Backups…") { draft.controller.showRecoveryMaintenance() }
          Button("Find Recovery Copies…") { draft.controller.showRecoverySalvage() }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
      }
      HStack {
        Text("Recent File List Contains:")
        TextField("Recent file count", text: $draft.recentLimitText)
          .textFieldStyle(.roundedBorder).frame(width: 65)
          .accessibilityLabel("Recent File List Contains")
        Text("files")
      }
      if let error = draft.controller.recoveryPreferences.recentWriteError {
        Text(error).font(.caption).foregroundStyle(.red)
      }
      if let error = draft.error {
        Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Spacer()
        Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
        Button("OK") { if draft.apply() { dismiss() } }.keyboardShortcut(.defaultAction)
      }
    }.padding(20).frame(width: 600)
  }
}

@MainActor final class RecoveryPreferencesWindowController: NSWindowController {
  init(controller: CraftDocumentController) {
    let window = PhotatoWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 230),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Settings — File Handling"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.contentView = NSHostingView(
      rootView: RecoveryPreferencesView(draft: .init(controller: controller)) { [weak self] in
        self?.close()
      })
    window.center()
  }
  required init?(coder: NSCoder) { nil }
}

extension AppDelegate {
  @objc func fileHandlingPreferences() {
    if recoverySettingsWindow?.window?.isVisible != true {
      recoverySettingsWindow = RecoveryPreferencesWindowController(controller: controller)
    }
    recoverySettingsWindow?.showWindow(nil)
    recoverySettingsWindow?.window?.makeKeyAndOrderFront(nil)
  }
}
