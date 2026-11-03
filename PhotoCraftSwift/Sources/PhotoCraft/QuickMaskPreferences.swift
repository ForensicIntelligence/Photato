import AppKit
import Observation
import SwiftUI
import PhotoCraftCore

@MainActor @Observable final class QuickMaskPreferences {
  static let shared = QuickMaskPreferences(defaults:.standard)
  static let key = "Photato.QuickMaskOptions"
  private let defaults: UserDefaults?
  private(set) var value: ChannelDisplayOptions
  init(defaults:UserDefaults? = nil) {
    self.defaults=defaults
    if let data=defaults?.data(forKey:Self.key),let decoded=try? JSONDecoder().decode(ChannelDisplayOptions.self,from:data),
      (try? decoded.validate()) != nil {value=decoded} else {value = .init()}
  }
  func set(_ options:ChannelDisplayOptions) throws {
    try options.validate(); let data=try JSONEncoder().encode(options)
    value=options;defaults?.set(data,forKey:Self.key)
  }
}

struct QuickMaskModeButton: NSViewRepresentable {
  let store:EditorStore
  func makeNSView(context:Context)->Control {
    let button=Control();button.bezelStyle = .inline;button.isBordered=false
    button.imagePosition = .imageOnly;button.setAccessibilityLabel("Quick Mask Mode")
    button.target=button;button.action=#selector(Control.activate)
    return button
  }
  func updateNSView(_ button:Control,context:Context) {
    button.store=store;button.isEnabled=store.canEditChannels
    let options=store.document.quickMask?.options ?? store.quickMaskOptions
    button.image=NSImage(systemSymbolName:options.indicates == .maskedAreas ? "rectangle.inset.filled":"rectangle.center.inset.filled",accessibilityDescription:nil)
    button.contentTintColor=store.document.quickMask == nil ? .labelColor:.systemRed
    button.toolTip="Quick Mask Mode (Q). Double-click for options; Option-click to reverse Color Indicates."
  }
  final class Control:NSButton {
    weak var store:EditorStore?
    @objc func activate() {
      guard let store else{return}
      let event=NSApp.currentEvent
      if (event?.clickCount ?? 1)>1 {store.beginChannelDialog(.quickOptions)}
      else if event?.modifierFlags.contains(.option)==true {store.reverseQuickMaskIndication()}
      else {store.toggleQuickMask()}
    }
  }
}
