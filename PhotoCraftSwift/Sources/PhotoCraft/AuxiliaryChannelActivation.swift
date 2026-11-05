import AppKit
import PhotoCraftCore
import SwiftUI

/// A displayed thumbnail cannot open options for a replacement document or channel.
@MainActor struct AuxiliaryChannelActivation {
  let owner: UUID
  let documentID: UUID
  let session: UUID
  let channelID: UUID
  let target: ChannelPlaneTarget

  init(store: EditorStore, channel: AlphaChannel, quick: Bool) {
    owner = store.identity; documentID = store.document.id
    session = store.sessionGeneration; channelID = channel.id
    target = quick ? .quickMask : .alpha(channel.id)
  }

  private func current(_ store: EditorStore) -> Bool {
    guard owner == store.identity, documentID == store.document.id,
      session == store.sessionGeneration, store.canEditChannels,
      (try? store.document.channel(target).id) == channelID else { return false }
    if let controller = store.documentController,
      !controller.documents.contains(where: { ($0 as? CraftNSDocument)?.store === store }) { return false }
    return true
  }

  static func opensOptions(clickCount: Int, modifiers: NSEvent.ModifierFlags) -> Bool {
    clickCount == 2 && modifiers.intersection([.command, .option, .shift, .control]).isEmpty
  }

  @discardableResult func openOptions(in store: EditorStore) -> Bool {
    guard current(store) else { return false }
    do {
      if target == .quickMask { try store.selectQuickMaskChannel() }
      else { try store.selectAlphaChannel(channelID) }
      store.beginChannelDialog(target == .quickMask ? .quickOptions : .options)
      return store.channelDialog != nil
    } catch { store.error = error.localizedDescription; return false }
  }

  func activate(in store: EditorStore, clickCount: Int, modifiers: NSEvent.ModifierFlags) {
    guard current(store) else { return }
    if Self.opensOptions(clickCount: clickCount, modifiers: modifiers) {
      _ = openOptions(in: store)
    } else if target == .quickMask {
      do { try store.selectQuickMaskChannel() } catch { store.error = error.localizedDescription }
    } else { store.channelThumbnail(channelID, modifiers: modifiers) }
  }
}

/// Native click counts avoid competing SwiftUI single/double tap recognizers.
struct AuxiliaryChannelThumbnail: NSViewRepresentable {
  let store: EditorStore
  let activation: AuxiliaryChannelActivation
  let image: CGImage?
  let name: String
  func makeNSView(context: Context) -> AuxiliaryChannelThumbnailButton {
    AuxiliaryChannelThumbnailButton()
  }
  func updateNSView(_ button: AuxiliaryChannelThumbnailButton, context: Context) {
    button.store = store; button.activation = activation; button.isEnabled = store.canEditChannels
    button.image = image.map { NSImage(cgImage: $0, size: .zero) }
    button.setAccessibilityLabel("Select \(name) channel thumbnail")
    button.setAccessibilityIdentifier("channels.thumbnail.\(activation.target == .quickMask ? "quickMask" : activation.channelID.uuidString)")
    button.toolTip = "Select \(name) channel. Double-click for options."
  }
}

@MainActor final class AuxiliaryChannelThumbnailButton: NSButton {
  weak var store: EditorStore?
  var activation: AuxiliaryChannelActivation?
  init() {
    super.init(frame: .zero)
    title = ""; isBordered = false; imagePosition = .imageOnly
    imageScaling = .scaleProportionallyUpOrDown
    wantsLayer = true; layer?.backgroundColor = NSColor.black.cgColor
    layer?.borderWidth = 1; layer?.borderColor = NSColor.black.cgColor
    target = self; action = #selector(activate)
  }
  required init?(coder: NSCoder) { nil }
  @objc private func activate() { dispatch(NSApp.currentEvent) }
  func dispatch(_ event: NSEvent?) {
    guard isEnabled, let store else { return }
    activation?.activate(in: store, clickCount: event?.clickCount ?? 1, modifiers: event?.modifierFlags ?? [])
  }
  override func mouseDown(with event: NSEvent) {
    if AuxiliaryChannelActivation.opensOptions(clickCount: event.clickCount, modifiers: event.modifierFlags) {
      dispatch(event)
    } else { super.mouseDown(with: event) }
  }
}
