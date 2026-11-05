import AppKit
import PhotoCraftCore
import SwiftUI

@MainActor extension EditorStore {
  var canChangeLayerSelection: Bool { canChangeLayerFilter && numericEditor == nil && layerNameDraft == nil }
  var hasLayerSelection: Bool { document.activeLayerID != nil || !selectedLayerIDs.isEmpty }
  var canDeselectLayers: Bool { canChangeLayerSelection && hasLayerSelection }
  @discardableResult func deselectLayers() -> Bool {
    finishNumericField(); finishLayerName()
    guard canChangeLayerSelection, hasLayerSelection else { return false }
    let wasMask = editingMask || smartFilterMaskEditing || currentMaskView != nil
    selectedLayerIDs = []
    session.deselectLayers()
    maskEditingLayerID = nil; smartFilterMaskEditing = false
    temporaryMaskChannelVisibility = nil
    clearMaskView()
    if case .shape = pathTarget { selectPath(nil) }
    if case .vectorMask = pathTarget { selectPath(nil) }
    if wasMask { render() }
    invalidatePeopleIfNeeded(); refreshObjectFinderIfNeeded()
    return true
  }
  /// Validate every named target before publishing a selection-only recipe.
  /// Generic prepared document playback would otherwise create a spurious Undo.
  func applyLayerSelectionAction(_ action: RecordedAction) throws -> Bool {
    guard action.isLayerSelectionOnly else { return false }
    guard canChangeLayerSelection, session.actionRecording == nil else {
      throw CraftError.invalid("Finish the interaction and stop recording before selection playback.")
    }
    if let target = try action.layerSelection(in: document) { select(target) }
    else { _ = deselectLayers() }
    return true
  }
  func clickEmptyLayerPanel(modifiers: NSEvent.ModifierFlags) {
    guard modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return }
    _ = deselectLayers()
  }
}

/// A sibling of the rows, never an overlay that can swallow thumbnail/eye events.
struct LayerPanelEmptySelectionArea: NSViewRepresentable {
  let store: EditorStore
  func makeNSView(context: Context) -> LayerPanelEmptySelectionButton { LayerPanelEmptySelectionButton() }
  func updateNSView(_ button: LayerPanelEmptySelectionButton, context: Context) {
    button.store = store
    button.isEnabled = store.canDeselectLayers
  }
}

@MainActor final class LayerPanelEmptySelectionButton: NSButton {
  weak var store: EditorStore?
  private var press: (point: NSPoint, storeID: UUID, documentID: UUID, modifiers: NSEvent.ModifierFlags)?
  init() {
    super.init(frame: .zero)
    title = ""; isBordered = false; target = self; action = #selector(deselect)
    setAccessibilityLabel("Deselect layers in empty panel area")
    setAccessibilityIdentifier("layers.deselectEmptyArea")
    setContentHuggingPriority(.defaultLow, for: .vertical)
  }
  required init?(coder: NSCoder) { nil }
  override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 18) }
  override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
  override func draw(_ dirtyRect: NSRect) {}
  override func isAccessibilityElement() -> Bool { true }
  override func accessibilityRole() -> NSAccessibility.Role? { .button }
  override func accessibilityPerformPress() -> Bool {
    guard isEnabled, let store, store.canDeselectLayers else { return false }
    return store.deselectLayers()
  }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  @objc private func deselect() { _ = store?.deselectLayers() }
  override func mouseDown(with event: NSEvent) {
    press = nil
    guard isEnabled, let store, store.canDeselectLayers else { return }
    press = (event.locationInWindow, store.identity, store.document.id, event.modifierFlags)
  }
  override func mouseDragged(with event: NSEvent) {
    guard let press else { return }
    if hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y) >= 4 {
      self.press = nil
    }
  }
  override func mouseUp(with event: NSEvent) {
    defer { press = nil }
    guard let press, let store, isEnabled, event.window === window,
      press.storeID == store.identity, press.documentID == store.document.id,
      bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
    store.clickEmptyLayerPanel(modifiers: press.modifiers)
  }
  override func cancelOperation(_ sender: Any?) { press = nil }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    press = nil; super.viewWillMove(toWindow: newWindow)
  }
}

@MainActor extension AppDelegate {
  @objc func deselectLayers() { _ = store?.deselectLayers() }
}
