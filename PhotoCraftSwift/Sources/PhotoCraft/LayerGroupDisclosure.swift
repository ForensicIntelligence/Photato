import AppKit
import PhotoCraftCore
import SwiftUI

extension EditorStore {
  func layersInPanel(search: String = "", kind: String = "All") -> [Layer] {
    let document = layerPanelDocument
    let hierarchy = LayerHierarchyIndex(document)
    return document.layers.reversed().filter { layer in
      layer.id == layerNameDraft?.layerID
        || ((search.isEmpty && kind == "All"
          ? !hierarchy.ancestors(of: layer.id).contains { $0.group?.expanded == false } : true)
          && (search.isEmpty || layer.name.localizedCaseInsensitiveContains(search))
          && (kind == "All" || layer.content.label == kind))
    }
  }

  func canChangeGroupDisclosure(_ id: UUID? = nil) -> Bool {
    canBeginLayerCreation && document.layers.contains { $0.isGroup && (id == nil || $0.id == id) }
  }

  func toggleGroupDisclosure(_ id: UUID, modifiers: NSEvent.ModifierFlags = []) {
    finishLayerName()
    guard canChangeGroupDisclosure(id),
      let group = document.layers.first(where: { $0.id == id })?.group
    else { return }
    let ids = modifiers.contains(.option) ? Set(document.layers.filter(\.isGroup).map(\.id)) : [id]
    setLayerGroupsExpanded(ids, expanded: !group.expanded)
  }

  func collapseAllLayerGroups() {
    finishLayerName()
    guard canChangeGroupDisclosure() else { return }
    setLayerGroupsExpanded(Set(document.layers.filter(\.isGroup).map(\.id)), expanded: false)
  }

  private func setLayerGroupsExpanded(_ ids: Set<UUID>, expanded: Bool) {
    do {
      // Observation refreshes panel rows. Do not call perform(), render(), or onChange:
      // this cannot alter composited pixels, edit history, selection, or dirty state.
      try session.setGroupExpansion(ids, expanded: expanded)
    } catch { self.error = error.localizedDescription }
  }
}

struct LayerGroupDisclosureControl: NSViewRepresentable {
  let store: EditorStore
  let layer: Layer
  var height: CGFloat = 36
  func makeNSView(context: Context) -> LayerGroupDisclosureButton { LayerGroupDisclosureButton() }
  func updateNSView(_ button: LayerGroupDisclosureButton, context: Context) {
    button.store = store
    button.controlHeight = height
    button.layerID = layer.id
    button.isEnabled = store.canChangeGroupDisclosure(layer.id)
    let expanded = layer.group?.expanded == true
    button.expanded = expanded
    button.needsDisplay = true
    button.setAccessibilityLabel("\(expanded ? "Collapse" : "Expand") group \(layer.name)")
    button.setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
    button.toolTip =
      "\(expanded ? "Collapse" : "Expand") group. Option-click to \(expanded ? "collapse" : "expand") all groups."
  }
}

/// A disclosure click must not select or drag-reorder the group row behind it.
@MainActor final class LayerGroupDisclosureButton: NSButton {
  weak var store: EditorStore?
  var layerID = UUID()
  var expanded = true
  var controlHeight: CGFloat = 36 {
    didSet { if oldValue != controlHeight { invalidateIntrinsicContentSize() } }
  }
  private var press:
    (
      point: NSPoint, storeID: UUID, documentID: UUID, layerID: UUID, expanded: Bool,
      modifiers: NSEvent.ModifierFlags
    )?
  init() {
    super.init(frame: .zero)
    title = ""
    isBordered = false
    imagePosition = .imageOnly
    contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
    target = self
    action = #selector(toggleGroup)
  }
  required init?(coder: NSCoder) { nil }
  override var alignmentRectInsets: NSEdgeInsets {
    NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }
  override var intrinsicContentSize: NSSize { NSSize(width: 14, height: controlHeight) }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var isFlipped: Bool { true }
  override func draw(_ dirtyRect: NSRect) {
    let center = NSPoint(x: bounds.midX, y: bounds.midY)
    let path = NSBezierPath()
    if expanded {
      path.move(to: NSPoint(x: center.x - 3.5, y: center.y - 2.1))
      path.line(to: NSPoint(x: center.x + 3.5, y: center.y - 2.1))
      path.line(to: NSPoint(x: center.x, y: center.y + 2.1))
    } else {
      path.move(to: NSPoint(x: center.x - 2.1, y: center.y - 3.5))
      path.line(to: NSPoint(x: center.x - 2.1, y: center.y + 3.5))
      path.line(to: NSPoint(x: center.x + 2.1, y: center.y))
    }
    path.close()
    NSColor(calibratedWhite: 0.88, alpha: isEnabled ? 1 : 0.45).setFill()
    path.fill()
  }
  @objc private func toggleGroup() { store?.toggleGroupDisclosure(layerID) }
  override func mouseDown(with event: NSEvent) {
    press = nil
    guard isEnabled, let store, store.canChangeGroupDisclosure(layerID),
      let group = store.document.layers.first(where: { $0.id == layerID })?.group
    else { return }
    press = (
      event.locationInWindow, store.identity, store.document.id, layerID, group.expanded,
      event.modifierFlags
    )
  }
  override func mouseDragged(with event: NSEvent) {
    guard let press else { return }
    if hypot(event.locationInWindow.x - press.point.x, event.locationInWindow.y - press.point.y)
      >= 4
    {
      self.press = nil
    }
  }
  override func mouseUp(with event: NSEvent) {
    defer { press = nil }
    guard let press, let store, isEnabled, event.window === window,
      press.storeID == store.identity, press.documentID == store.document.id,
      press.layerID == layerID,
      store.document.layers.first(where: { $0.id == layerID })?.group?.expanded == press.expanded,
      bounds.contains(convert(event.locationInWindow, from: nil))
    else { return }
    store.toggleGroupDisclosure(layerID, modifiers: press.modifiers)
  }
  override func cancelOperation(_ sender: Any?) { press = nil }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    press = nil
    super.viewWillMove(toWindow: newWindow)
  }
}
