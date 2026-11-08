import AppKit
import SwiftUI
import PhotoCraftCore

/// Explicit AppKit availability: SwiftUI's per-Text disabled environment did
/// not disable the unavailable row in the native macOS popup during live QA.
@MainActor struct RemoveModeControl: NSViewRepresentable {
  @Binding var selection: RemoveToolSettings.Mode
  var enabled: Bool

  static func available(_ mode: RemoveToolSettings.Mode) -> Bool {
    switch mode {
    case .auto, .generativeOff: true
    case .generativeOn: false
    }
  }
  static func synchronize(_ popup: NSPopUpButton, selection: RemoveToolSettings.Mode, enabled: Bool) {
    popup.isEnabled = enabled
    popup.menu?.autoenablesItems = false
    for (index, mode) in RemoveToolSettings.Mode.allCases.enumerated() {
      popup.item(at:index)?.isEnabled = available(mode)
    }
    if let index = RemoveToolSettings.Mode.allCases.firstIndex(of:selection) {
      popup.selectItem(withTag:index)
    }
  }
  static func makePopup(_ coordinator: Coordinator, enabled: Bool) -> NSPopUpButton {
    let popup = NSPopUpButton(frame:.zero,pullsDown:false)
    popup.controlSize = .small
    popup.font = .systemFont(ofSize:NSFont.smallSystemFontSize)
    popup.addItems(withTitles:RemoveToolSettings.Mode.allCases.map(\.title))
    for index in RemoveToolSettings.Mode.allCases.indices { popup.item(at:index)?.tag = index }
    popup.target = coordinator; popup.action = #selector(Coordinator.changed(_:))
    popup.setAccessibilityLabel("Remove processing mode")
    popup.setAccessibilityHelp("Auto currently uses traditional processing. Generative Remove is not available.")
    synchronize(popup,selection:coordinator.selection.wrappedValue,enabled:enabled)
    return popup
  }
  func makeCoordinator() -> Coordinator { Coordinator($selection) }
  func makeNSView(context: Context) -> NSPopUpButton {
    Self.makePopup(context.coordinator,enabled:enabled && context.environment.isEnabled)
  }
  func updateNSView(_ popup: NSPopUpButton, context: Context) {
    context.coordinator.selection = $selection
    Self.synchronize(popup,selection:selection,enabled:enabled && context.environment.isEnabled)
  }
  @MainActor final class Coordinator: NSObject {
    var selection: Binding<RemoveToolSettings.Mode>
    init(_ selection: Binding<RemoveToolSettings.Mode>) { self.selection = selection; super.init() }
    @objc func changed(_ sender: NSPopUpButton) {
      let index = sender.selectedTag()
      if sender.isEnabled, RemoveToolSettings.Mode.allCases.indices.contains(index) {
        let mode = RemoveToolSettings.Mode.allCases[index]
        if RemoveModeControl.available(mode) { selection.wrappedValue = mode }
      }
      // A rejected binding update must not leave a different visible selection.
      RemoveModeControl.synchronize(sender,selection:selection.wrappedValue,enabled:sender.isEnabled)
    }
  }
}
