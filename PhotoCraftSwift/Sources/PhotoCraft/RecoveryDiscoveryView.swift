import AppKit
import SwiftUI

struct RecoveryDiscoveryView: View {
  @Bindable var discovery: RecoveryDiscovery
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(discovery.state?.active == true ? "Recovering Documents" : "Recovery Results").font(.headline)
      if let state = discovery.state {
        ProgressView(value: Double(state.completedEntries), total: Double(max(1, state.totalEntries)))
        Text(state.active && state.cancellationRequested ? "Finishing the current operation…" :
          "\(state.completedEntries) of \(state.totalEntries) recovery records checked")
          .font(.caption)
        if discovery.controller.recoveryIndex.lastDeferred > 0 {
          Text("\(discovery.controller.recoveryIndex.lastDeferred) backups deferred to keep recovery within its memory allowance.")
            .font(.caption)
          Text("Their files are preserved. Close documents, then use Retry Recovery in File Handling. Review Backups also lets you choose an individual copy.")
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        Text("Recovered documents stay open. Remaining backups are available for Retry Recovery.")
          .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        HStack {
          Spacer()
          if state.active {
            Button("Cancel") { discovery.cancel(state.id) }
              .disabled(state.cancellationRequested).keyboardShortcut(.cancelAction)
          } else {
            Button("Done") { discovery.dismissProgress() }.keyboardShortcut(.defaultAction)
          }
        }
      }
    }.padding(20).frame(width: 380)
  }
}
@MainActor final class RecoveryDiscoveryWindowController: NSWindowController {
  init(discovery: RecoveryDiscovery) {
    let window = PhotatoWindow(contentRect: .init(x: 0, y: 0, width: 420, height: 320),
      styleMask: [.titled], backing: .buffered, defer: false)
    window.title = "Photato — Recovering Documents"
    window.isReleasedWhenClosed = false
    super.init(window: window)
    window.contentView = NSHostingView(rootView: RecoveryDiscoveryView(discovery: discovery))
    window.center()
  }
  required init?(coder: NSCoder) { nil }
}
