import AppKit
import SwiftUI
import PhotoCraftCore

/// Explicit AppKit availability: SwiftUI's per-Text disabled environment did
/// not disable the unavailable row in the native macOS popup during live QA.
@MainActor struct RemoveModeControl: NSViewRepresentable {
  @Binding var selection: RemoveToolSettings.Mode
  var enabled: Bool
  var localAvailable: Bool

  static func synchronize(_ popup: NSPopUpButton, selection: RemoveToolSettings.Mode, enabled: Bool, localAvailable: Bool) {
    popup.isEnabled = enabled
    popup.menu?.autoenablesItems = false
    for (index, mode) in RemoveToolSettings.Mode.allCases.enumerated() {
      popup.item(at:index)?.isEnabled = mode != .generativeOn || localAvailable
    }
    if let index = RemoveToolSettings.Mode.allCases.firstIndex(of:selection) {
      popup.selectItem(withTag:index)
    }
    popup.setAccessibilityHelp(localAvailable ? "Device processing is available for this document."
      : "Generative AI on requires an eligible document and a local model.")
  }
  static func makePopup(_ coordinator: Coordinator, enabled: Bool) -> NSPopUpButton {
    let popup = NSPopUpButton(frame:.zero,pullsDown:false)
    popup.controlSize = .small
    popup.font = .systemFont(ofSize:NSFont.smallSystemFontSize)
    popup.addItems(withTitles:RemoveToolSettings.Mode.allCases.map(\.title))
    for index in RemoveToolSettings.Mode.allCases.indices { popup.item(at:index)?.tag = index }
    popup.target = coordinator; popup.action = #selector(Coordinator.changed(_:))
    popup.setAccessibilityLabel("Remove processing mode")
    synchronize(popup,selection:coordinator.selection.wrappedValue,enabled:enabled,localAvailable:coordinator.localAvailable)
    return popup
  }
  func makeCoordinator() -> Coordinator { Coordinator($selection, localAvailable: localAvailable) }
  func makeNSView(context: Context) -> NSPopUpButton {
    Self.makePopup(context.coordinator,enabled:enabled && context.environment.isEnabled)
  }
  func updateNSView(_ popup: NSPopUpButton, context: Context) {
    context.coordinator.selection = $selection
    context.coordinator.localAvailable = localAvailable
    Self.synchronize(popup,selection:selection,enabled:enabled && context.environment.isEnabled,localAvailable:localAvailable)
  }
  @MainActor final class Coordinator: NSObject {
    var selection: Binding<RemoveToolSettings.Mode>
    var localAvailable: Bool
    init(_ selection: Binding<RemoveToolSettings.Mode>, localAvailable: Bool = false) {
      self.selection = selection; self.localAvailable = localAvailable; super.init()
    }
    @objc func changed(_ sender: NSPopUpButton) {
      let index = sender.selectedTag()
      if sender.isEnabled, RemoveToolSettings.Mode.allCases.indices.contains(index) {
        let mode = RemoveToolSettings.Mode.allCases[index]
        if mode != .generativeOn || localAvailable { selection.wrappedValue = mode }
      }
      // A rejected binding update must not leave a different visible selection.
      RemoveModeControl.synchronize(sender,selection:selection.wrappedValue,enabled:sender.isEnabled,localAvailable:localAvailable)
    }
  }
}
