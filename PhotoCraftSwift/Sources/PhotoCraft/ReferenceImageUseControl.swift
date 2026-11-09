import AppKit
import SwiftUI

/// Match the existing explicit AppKit popup policy: a disabled SwiftUI Text
/// did not reliably disable its native menu item during earlier Remove QA.
@MainActor struct ReferenceImageUseControl: NSViewRepresentable {
  @Binding var selection: ImageReferenceUse
  var editAvailable: Bool
  var enabled: Bool
  static func synchronize(_ popup: NSPopUpButton, selection: ImageReferenceUse, editAvailable: Bool, enabled: Bool) {
    popup.isEnabled = enabled; popup.menu?.autoenablesItems = false
    for (index, use) in ImageReferenceUse.allCases.enumerated() {
      popup.item(at:index)?.isEnabled = use == .inspiration || editAvailable
    }
    if let index = ImageReferenceUse.allCases.firstIndex(of:selection) { popup.selectItem(withTag:index) }
  }
  static func makePopup(_ coordinator: Coordinator, enabled: Bool) -> NSPopUpButton {
    let popup = NSPopUpButton(frame:.zero,pullsDown:false)
    popup.controlSize = .small; popup.font = .systemFont(ofSize:NSFont.smallSystemFontSize)
    popup.addItems(withTitles:ImageReferenceUse.allCases.map(\.title))
    for index in ImageReferenceUse.allCases.indices { popup.item(at:index)?.tag = index }
    popup.target = coordinator; popup.action = #selector(Coordinator.changed(_:))
    popup.setAccessibilityLabel("Use reference image as")
    popup.setAccessibilityHelp("Choose inspiration or request an edit of the selected reference image. Editing requires an image and supported macOS 27 Apple Silicon.")
    synchronize(popup,selection:coordinator.selection.wrappedValue,editAvailable:coordinator.editAvailable,enabled:enabled)
    return popup
  }
  func makeCoordinator() -> Coordinator { Coordinator($selection,editAvailable:editAvailable) }
  func makeNSView(context: Context) -> NSPopUpButton { Self.makePopup(context.coordinator,enabled:enabled && context.environment.isEnabled) }
  func updateNSView(_ popup: NSPopUpButton, context: Context) {
    context.coordinator.selection = $selection; context.coordinator.editAvailable = editAvailable
    Self.synchronize(popup,selection:selection,editAvailable:editAvailable,enabled:enabled && context.environment.isEnabled)
  }
  @MainActor final class Coordinator: NSObject {
    var selection: Binding<ImageReferenceUse>
    var editAvailable: Bool
    init(_ selection: Binding<ImageReferenceUse>, editAvailable: Bool) { self.selection = selection; self.editAvailable = editAvailable; super.init() }
    @objc func changed(_ sender: NSPopUpButton) {
      let index = sender.selectedTag()
      if sender.isEnabled, ImageReferenceUse.allCases.indices.contains(index) {
        let use = ImageReferenceUse.allCases[index]
        if use == .inspiration || editAvailable { selection.wrappedValue = use }
      }
      ReferenceImageUseControl.synchronize(sender,selection:selection.wrappedValue,editAvailable:editAvailable,enabled:sender.isEnabled)
    }
  }
}
