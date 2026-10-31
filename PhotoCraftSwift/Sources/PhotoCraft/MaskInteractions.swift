import AppKit
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct LayerMaskView: Equatable, Sendable {
  let layerID: UUID
  let generation: UUID
  let mode: MaskViewMode
  var smartFilter = false
}

extension EditorStore {
  var currentMaskView: LayerMaskView? {
    guard let view = layerMaskView, view.generation == layerPanelGeneration,
      view.layerID == document.activeLayerID, editingMask, view.smartFilter == smartFilterMaskEditing
    else { return nil }
    return view
  }
  var displayedMaskImage: CGImage? {
    guard let view = adjustmentBrushMaskView ?? currentMaskView, renderedMaskView == view else { return nil }
    return maskViewImage
  }
  func clearMaskView() {
    layerMaskView = nil
    renderedMaskView = nil
    maskViewImage = nil
    maskViewRegion = nil
  }
  func canUseMaskThumbnail(_ id: UUID, kind: MaskThumbnailKind) -> Bool {
    guard canBeginLayerCreation, let layer = document.layers.first(where: { $0.id == id })
    else { return false }
    return kind == .pixel ? layer.mask != nil : layer.vectorMask != nil
  }
  func useMaskThumbnail(
    _ id: UUID, kind: MaskThumbnailKind, modifiers: NSEvent.ModifierFlags = []
  ) {
    finishLayerName()
    guard canUseMaskThumbnail(id, kind: kind),
      let layer = document.layers.first(where: { $0.id == id })
    else { return }
    // Command takes precedence over both view toggles and enablement.
    if modifiers.contains(.command) {
      let mode: SelectionMode =
        modifiers.contains(.shift)
        ? (modifiers.contains(.option) ? .intersect : .add)
        : (modifiers.contains(.option) ? .subtract : .replace)
      performGeometry(label: "Load Mask Selection") { doc in
        guard let source = doc.layers.first(where: { $0.id == id }) else {
          throw CraftError.invalid("The mask layer is no longer available.")
        }
        return .selectionCoverage(
          try Renderer.maskSelection(source, kind: kind, width: doc.width, height: doc.height), mode
        )
      }
    } else if modifiers.contains(.option), kind == .pixel {
      toggleMaskView(id, mode: modifiers.contains(.shift) ? .overlay : .gray)
    } else if modifiers.contains(.shift), !modifiers.contains(.option) {
      guard !document.isLocked(id) else { return }
      if kind == .pixel {
        updateMask(id) { $0.enabled.toggle() }
      } else if var mask = layer.vectorMask {
        mask.enabled.toggle()
        perform(.vectorMask(id, mask))
      }
    } else if kind == .pixel {
      selectMask(id)
    } else {
      selectPath(.vectorMask(id), revealPanel: false)
      tool = .directSelection
    }
  }
  func toggleMaskView(_ id: UUID, mode: MaskViewMode) {
    guard canUseMaskThumbnail(id, kind: .pixel) else { return }
    let next = LayerMaskView(layerID: id, generation: layerPanelGeneration, mode: mode)
    let turnOff = currentMaskView == next
    selectMask(id)
    displayChannel = nil
    layerMaskView = turnOff ? nil : next
    render()
  }
}

struct MaskThumbnailControl: NSViewRepresentable {
  let store: EditorStore
  let layer: Layer
  let kind: MaskThumbnailKind
  func makeNSView(context: Context) -> MaskThumbnailButton { MaskThumbnailButton() }
  func updateNSView(_ button: MaskThumbnailButton, context: Context) {
    button.store = store
    button.layerID = layer.id
    button.kind = kind
    button.isEnabled = store.canUseMaskThumbnail(layer.id, kind: kind)
    button.setAccessibilityElement(true)
    button.setAccessibilityRole(.button)
    button.setAccessibilityLabel("Edit \(kind == .pixel ? "mask" : "vector mask") of \(layer.name)")
    button.toolTip =
      kind == .pixel
      ? "Click to edit. Shift-click to enable or disable. Option-click to view; Shift-Option-click for overlay. Command-click to load selection."
      : "Click to edit. Shift-click to enable or disable. Command-click to load selection."
  }
}

/// Explicit mouse tracking retains mouse-down modifiers and prevents the row's selection
/// gesture from interpreting Command-click as multi-layer selection.
@MainActor final class MaskThumbnailButton: NSButton {
  weak var store: EditorStore?
  var layerID = UUID()
  var kind: MaskThumbnailKind = .pixel
  private var press:
    (
      point: NSPoint, storeID: UUID, generation: UUID, layer: Layer,
      kind: MaskThumbnailKind, modifiers: NSEvent.ModifierFlags
    )?
  init() {
    super.init(frame: .zero)
    title = ""
    isBordered = false
    target = self
    action = #selector(activateMask)
  }
  required init?(coder: NSCoder) { nil }
  override var alignmentRectInsets: NSEdgeInsets {
    NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }
  override func draw(_ dirtyRect: NSRect) {}
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  @objc private func activateMask() { store?.useMaskThumbnail(layerID, kind: kind) }
  override func mouseDown(with event: NSEvent) {
    press = nil
    guard isEnabled, let store, store.canUseMaskThumbnail(layerID, kind: kind),
      let layer = store.document.layers.first(where: { $0.id == layerID })
    else { return }
    press = (
      event.locationInWindow, store.identity, store.layerPanelGeneration, layer, kind,
      event.modifierFlags
    )
  }
  override func mouseDragged(with event: NSEvent) {
    if let press,
      hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y) >= 4
    {
      self.press = nil
    }
  }
  override func mouseUp(with event: NSEvent) {
    defer { press = nil }
    guard let press, let store, isEnabled, event.window === window,
      store.identity == press.storeID, store.layerPanelGeneration == press.generation,
      layerID == press.layer.id, kind == press.kind,
      store.document.layers.first(where: { $0.id == layerID }) == press.layer,
      bounds.contains(convert(event.locationInWindow, from: nil))
    else { return }
    store.useMaskThumbnail(layerID, kind: kind, modifiers: press.modifiers)
  }
  override func cancelOperation(_ sender: Any?) { press = nil }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    press = nil
    super.viewWillMove(toWindow: newWindow)
  }
}
