import AppKit
import SwiftUI

struct CompactColorWell: NSViewRepresentable {
  @Binding var color: Color
  var label = "Foreground color"
  var supportsOpacity = true
  var closesPanelOnRemoval = false
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> ColorSwatchButton {
    let button = ColorSwatchButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
    button.isBordered = false
    button.target = context.coordinator
    button.action = #selector(Coordinator.showPanel(_:))
    button.setAccessibilityLabel(label)
    return button
  }
  func updateNSView(_ view: ColorSwatchButton, context: Context) {
    context.coordinator.parent = self
    view.swatchColor = NSColor(color)
    view.needsDisplay = true
  }
  static func dismantleNSView(_ view: ColorSwatchButton, coordinator: Coordinator) {
    guard coordinator.parent.closesPanelOnRemoval, Coordinator.panelOwner === coordinator else { return }
    Coordinator.panelOwner = nil
    let panel = NSColorPanel.shared
    panel.setTarget(nil)
    panel.setAction(nil)
    panel.orderOut(nil)
  }
  @MainActor final class Coordinator: NSObject {
    static weak var panelOwner: Coordinator?
    var parent: CompactColorWell
    init(_ parent: CompactColorWell) { self.parent = parent }
    @objc func showPanel(_ sender: NSButton) {
      let panel = NSColorPanel.shared
      Self.panelOwner = self
      panel.setTarget(self)
      panel.setAction(#selector(changed(_:)))
      panel.isContinuous = true
      panel.showsAlpha = parent.supportsOpacity
      panel.color = NSColor(parent.color)
      NSApp.activate()
      panel.makeKeyAndOrderFront(nil)
    }
    @objc func changed(_ sender: NSColorPanel) {
      guard Self.panelOwner === self else { return }
      parent.color = Color(nsColor: sender.color)
    }
  }
}
@MainActor final class ColorSwatchButton: NSButton {
  var swatchColor = NSColor.black
  override var intrinsicContentSize: NSSize { NSSize(width: 22, height: 22) }
  override func draw(_ dirtyRect: NSRect) {
    NSColor(white: 0.12, alpha: 1).setFill()
    bounds.fill()
    swatchColor.setFill()
    bounds.insetBy(dx: 2, dy: 2).fill()
    NSColor(white: 0.85, alpha: 1).setStroke()
    NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
  }
}

struct CanvasScroller: NSViewRepresentable {
  @Bindable var store: EditorStore
  let vertical: Bool
  var activateDocument: () -> Bool = { true }
  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> NSScroller {
    let view = NSScroller(
      frame: NSRect(x: 0, y: 0, width: vertical ? 14 : 100, height: vertical ? 100 : 14))
    view.scrollerStyle = .legacy
    view.knobStyle = .light
    view.controlSize = .small
    view.target = context.coordinator
    view.action = #selector(Coordinator.changed(_:))
    view.setAccessibilityLabel(vertical ? "Canvas vertical scroll" : "Canvas horizontal scroll")
    return view
  }
  var range: Double {
    let size = vertical ? store.viewportSize.height : store.viewportSize.width
    let dimension = vertical ? store.document.height : store.document.width
    return max(1, Double(dimension) * store.viewport.scale + size)
  }
  func updateNSView(_ view: NSScroller, context: Context) {
    context.coordinator.parent = self
    let position = vertical ? store.pan.height : store.pan.width
    view.doubleValue = min(1, max(0, 0.5 - position / range))
    view.knobProportion = min(
      1, max(0.05, (vertical ? store.viewportSize.height : store.viewportSize.width) / range))
  }
  @MainActor final class Coordinator: NSObject {
    var parent: CanvasScroller
    init(_ parent: CanvasScroller) { self.parent = parent }
    @objc func changed(_ sender: NSScroller) {
      guard parent.activateDocument() else { return }
      let old = parent.vertical ? parent.store.pan.height : parent.store.pan.width
      let position: Double
      switch sender.hitPart {
      case .decrementPage: position = old + parent.range * 0.15
      case .incrementPage: position = old - parent.range * 0.15
      case .decrementLine: position = old + 20
      case .incrementLine: position = old - 20
      default: position = (0.5 - sender.doubleValue) * parent.range
      }
      if parent.vertical {
        parent.store.pan.height = position
      } else {
        parent.store.pan.width = position
      }
    }
  }
}
