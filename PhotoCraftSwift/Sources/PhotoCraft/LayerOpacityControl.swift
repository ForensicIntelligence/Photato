import AppKit
import Observation
import PhotoCraftCore
import SwiftUI

@MainActor @Observable final class LayerOpacityDraft: Identifiable {
  let id = UUID()
  let layerID: UUID
  let lifecycle: UUID
  let session: UUID
  var value: Float

  init(store: EditorStore, layer: Layer) {
    layerID = layer.id
    lifecycle = store.layerPanelGeneration
    session = store.sessionGeneration
    value = layer.opacity
  }

  func matches(_ store: EditorStore) -> Bool {
    lifecycle == store.layerPanelGeneration && session == store.sessionGeneration
      && layerID == store.document.activeLayerID && !store.document.isLocked(layerID)
  }
}

extension EditorStore {
  var canBeginLayerOpacity: Bool {
    !geometryBusy && !aiBusy && !hasToneDraft && !coalescingChanges
      && historyOperation == nil && transformDraft == nil
      && activeLayer.map { !document.isLocked($0.id) } == true
  }

  func beginLayerOpacity() {
    finishNumericField()
    finishLayerName()
    guard canBeginLayerOpacity, let layer = activeLayer else { return }
    stopTimelinePlayback(render: false)
    layerOpacityDraft = LayerOpacityDraft(store: self, layer: layer)
  }

  func previewLayerOpacity(_ value: Double, draftID: UUID) {
    guard let draft = layerOpacityDraft, draft.id == draftID, draft.matches(self),
      value.isFinite, (0...100).contains(value), !geometryBusy, !aiBusy
    else { return }
    let opacity = Float(value / 100)
    guard draft.value != opacity else { return }
    draft.value = opacity
    render()
  }

  func finishLayerOpacity(_ expected: UUID? = nil, cancel: Bool = false) {
    guard let draft = layerOpacityDraft, expected == nil || expected == draft.id else { return }
    layerOpacityDraft = nil
    if !cancel, draft.matches(self), canBeginLayerOpacity,
      activeLayer?.opacity != draft.value {
      perform(.opacity(draft.layerID, draft.value))
    } else {
      render()
    }
  }
}

/// Numeric entry and the pop-up share the existing opacity command. The slider
/// previews a draft so Escape leaves both the document and its history intact.
struct LayerOpacityControl: View {
  @Bindable var store: EditorStore
  var body: some View {
    HStack(spacing: 4) {
      Text("Opacity:")
      HStack(spacing: 1) {
        NativeNumericField(
          store: store, label: "Layer opacity",
          value: Binding(
            get: { Double((store.layerOpacityDraft?.value ?? store.activeLayer?.opacity ?? 1) * 100) },
            set: { value in
              guard value.isFinite, store.canBeginLayerOpacity, let layer = store.activeLayer else { return }
              store.perform(.opacity(layer.id, Float(min(100, max(0, value)) / 100)))
            }), range: 0...100, alignment: .right
        ).frame(width: 30, height: 13).padding(3)
          .disabled(!store.canBeginLayerOpacity)
        Text("%")
        LayerOpacityPopup(store: store).frame(width: 15, height: 19)
      }.background(StudioTheme.field)
    }
    .onDisappear { store.finishLayerOpacity(cancel: true) }
  }
}

struct LayerOpacityPopup: NSViewRepresentable {
  let store: EditorStore
  func makeCoordinator() -> Coordinator { Coordinator(store: store) }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton()
    button.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
    button.imageScaling = .scaleProportionallyDown
    button.isBordered = false
    button.toolTip = "Show layer opacity slider"
    button.setAccessibilityLabel("Layer opacity slider")
    button.target = context.coordinator
    button.action = #selector(Coordinator.toggle(_:))
    return button
  }
  func updateNSView(_ button: NSButton, context: Context) {
    let coordinator = context.coordinator
    if coordinator.store !== store {
      coordinator.close(cancel: true)
      coordinator.store = store
    }
    button.isEnabled = context.environment.isEnabled
      && (store.canBeginLayerOpacity || store.layerOpacityDraft != nil)
    if let draft = store.layerOpacityDraft, draft.id == coordinator.draftID {
      coordinator.slider?.doubleValue = Double(draft.value * 100)
    } else if coordinator.popover.isShown { coordinator.close(cancel: true) }
  }
  static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
    coordinator.close(cancel: true)
    button.target = nil
  }

  @MainActor final class Coordinator: NSObject, NSPopoverDelegate {
    var store: EditorStore
    let popover = NSPopover()
    var draftID: UUID?
    var slider: LayerOpacitySlider.OpacitySlider?
    var sliderCoordinator: LayerOpacitySlider.Coordinator?
    init(store: EditorStore) {
      self.store = store
      super.init()
      popover.behavior = .transient
      popover.animates = false
      popover.delegate = self
      popover.appearance = NSAppearance(named: .darkAqua)
    }
    @objc func toggle(_ button: NSButton) {
      if popover.isShown { close(cancel: false); return }
      store.beginLayerOpacity()
      guard let draft = store.layerOpacityDraft else { return }
      draftID = draft.id
      let slider = LayerOpacitySlider.OpacitySlider(frame: NSRect(x: 10, y: 10, width: 180, height: 22))
      slider.minValue = 0; slider.maxValue = 100
      slider.doubleValue = Double(draft.value * 100)
      slider.isContinuous = true
      slider.controlSize = .small
      slider.setAccessibilityLabel("Layer opacity")
      let target = LayerOpacitySlider.Coordinator(store: store, draft: draft)
      slider.target = target
      slider.action = #selector(LayerOpacitySlider.Coordinator.change(_:))
      slider.finish = { [weak self] cancel in self?.close(cancel: cancel) }
      self.slider = slider; sliderCoordinator = target
      let controller = NSViewController()
      controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 42))
      controller.view.addSubview(slider)
      popover.contentViewController = controller
      popover.contentSize = controller.view.frame.size
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func popoverDidShow(_ notification: Notification) {
      guard let slider, let window = slider.window else { return }
      window.makeKey()
      window.makeFirstResponder(slider)
    }
    func close(cancel: Bool) {
      if let draftID { store.finishLayerOpacity(draftID, cancel: cancel) }
      popover.performClose(nil)
    }
    func popoverWillClose(_ notification: Notification) {
      if let draftID { store.finishLayerOpacity(draftID) }
      draftID = nil
    }
  }
}

struct LayerOpacitySlider: NSViewRepresentable {
  let store: EditorStore
  let draft: LayerOpacityDraft
  func makeCoordinator() -> Coordinator { Coordinator(store: store, draft: draft) }
  func makeNSView(context: Context) -> OpacitySlider {
    let slider = OpacitySlider()
    slider.minValue = 0
    slider.maxValue = 100
    slider.isContinuous = true
    slider.controlSize = .small
    slider.setAccessibilityLabel("Layer opacity")
    slider.target = context.coordinator
    slider.action = #selector(Coordinator.change(_:))
    slider.finish = { [weak store] cancel in store?.finishLayerOpacity(draft.id, cancel: cancel) }
    return slider
  }
  func updateNSView(_ slider: OpacitySlider, context: Context) {
    slider.doubleValue = Double(draft.value * 100)
    slider.isEnabled = draft.matches(store)
  }
  @MainActor final class Coordinator: NSObject {
    let store: EditorStore
    let draft: LayerOpacityDraft
    init(store: EditorStore, draft: LayerOpacityDraft) { self.store = store; self.draft = draft }
    @objc func change(_ slider: NSSlider) {
      store.previewLayerOpacity(slider.doubleValue.rounded(), draftID: draft.id)
    }
  }
  final class OpacitySlider: NSSlider {
    var finish: ((Bool) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
      switch event.keyCode {
      case 53: finish?(true)
      case 36, 76: finish?(false)
      case 123, 124, 125, 126:
        let direction = event.keyCode == 123 || event.keyCode == 125 ? -1.0 : 1.0
        let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
        doubleValue = min(maxValue, max(minValue, doubleValue + direction * step))
        sendAction(action, to: target)
      default: super.keyDown(with: event)
      }
    }
  }
}
