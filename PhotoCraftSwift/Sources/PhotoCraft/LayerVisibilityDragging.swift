import AppKit
import PhotoCraftCore
import SwiftUI

struct LayerVisibilityDraft {
  let id = UUID()
  let baseline: CraftDocument
  let visible: Bool
  var values: [UUID: Bool]
}

extension EditorStore {
  @discardableResult
  func beginLayerVisibilityDrag(_ id: UUID) -> UUID? {
    finishLayerName()
    guard canBeginLayerCreation, let layer = document.layers.first(where: { $0.id == id })
    else { return nil }
    let draft = LayerVisibilityDraft(
      baseline: document, visible: !layer.visible, values: [id: !layer.visible])
    layerVisibilityDraft = draft
    render()
    return draft.id
  }

  func extendLayerVisibilityDrag(_ token: UUID, over ids: [UUID]) {
    guard var draft = layerVisibilityDraft, draft.id == token else { return }
    guard document == draft.baseline else {
      finishLayerVisibilityDrag(token, cancel: true)
      return
    }
    let known = Set(document.layers.map(\.id))
    var changed = false
    for id in ids where known.contains(id) && draft.values[id] == nil {
      draft.values[id] = draft.visible
      changed = true
    }
    guard changed else { return }
    layerVisibilityDraft = draft
    render()
  }

  func finishLayerVisibilityDrag(_ token: UUID, cancel: Bool = false) {
    guard let draft = layerVisibilityDraft, draft.id == token else { return }
    layerVisibilityDraft = nil
    guard !cancel, document == draft.baseline else {
      render()
      return
    }
    perform(.layerVisibility(draft.values))
  }

  func layerEyeVisible(_ layer: Layer) -> Bool {
    guard let draft = layerVisibilityDraft, draft.baseline == document else { return layer.visible }
    return draft.values[layer.id] ?? layer.visible
  }
}

/// One tracker belongs to one Layers panel. A row can leave the lazy stack during
/// scrolling without losing the gesture; no app-global layer or window state is used.
@MainActor final class LayerEyeTracking {
  let buttons = NSHashTable<LayerEyeButton>.weakObjects()
  weak var revealView: LayerRevealScrollView?
  private(set) weak var store: EditorStore?
  private(set) weak var window: NSWindow?
  private weak var scrollView: NSScrollView?
  private var origin: NSPoint?
  private var previousPoint: NSPoint?
  private var pressedID: UUID?
  private var baseline: CraftDocument?
  private var modifiers: NSEvent.ModifierFlags = []
  private(set) var token: UUID?
  private var eventMonitor: Any?
  private var observers: [NSObjectProtocol] = []
  private var timer: Timer?

  func press(_ button: LayerEyeButton, event: NSEvent) {
    cancel()
    guard button.isEnabled, let store = button.store, let window = button.window,
      store.canBeginLayerCreation,
      store.document.layers.contains(where: { $0.id == button.layerID })
    else { return }
    self.store = store
    self.window = window
    scrollView = button.enclosingScrollView
    pressedID = button.layerID
    baseline = store.document
    origin = event.locationInWindow
    previousPoint = origin
    modifiers = event.modifierFlags
    eventMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDragged, .leftMouseUp, .keyDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] event in
      let consumed = MainActor.assumeIsolated {
        guard let self, self.origin != nil else { return false }
        switch event.type {
        case .leftMouseDragged:
          self.drag(event)
          return true
        case .leftMouseUp:
          self.release(event)
          return true
        case .keyDown:
          if event.keyCode == 53 { self.cancel() }
          // A pointer gesture owns keyboard input until release or cancellation.
          return true
        default:
          self.cancel()
          return false
        }
      }
      return consumed ? nil : event
    }
    for (name, object) in [
      (NSApplication.didResignActiveNotification, nil),
      (NSWindow.willCloseNotification, window),
      (NSWindow.didResignKeyNotification, window),
    ] as [(Notification.Name, Any?)] {
      observers.append(
        NotificationCenter.default.addObserver(
          forName: name, object: object, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } })
    }
  }

  func drag(_ event: NSEvent) {
    guard let origin, let store, let window, event.window === window,
      let pressedID, let baseline
    else {
      cancel()
      return
    }
    guard store.document == baseline else {
      cancel()
      return
    }
    if token == nil {
      guard hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 4
      else { return }
      token = store.beginLayerVisibilityDrag(pressedID)
      // Finishing an inline name is a separate edit that precedes this gesture.
      self.baseline = store.document
      guard token != nil else {
        cancel()
        return
      }
      let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated { self?.autoscroll() }
      }
      self.timer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
    sweep(to: event.locationInWindow)
  }

  func sweep(to point: NSPoint) {
    guard let store, let token, store.layerVisibilityDraft?.id == token else {
      cancel()
      return
    }
    let prior = previousPoint ?? point
    let low = min(point.y, prior.y)
    let high = max(point.y, prior.y)
    let ids = buttons.allObjects.compactMap { button -> UUID? in
      guard button.tracking === self, button.store === store, button.window === window,
        !button.isHiddenOrHasHiddenAncestor,
        !button.visibleRect.intersection(button.bounds).isEmpty
      else { return nil }
      let rect = button.convert(button.visibleRect.intersection(button.bounds), to: nil)
      return rect.maxY >= low && rect.minY <= high ? button.layerID : nil
    }
    store.extendLayerVisibilityDrag(token, over: ids)
    previousPoint = point
    if store.layerVisibilityDraft?.id != token { cancel() }
  }

  /// Keep revealing rows while the pointer is held at the scroll viewport's edge.
  func autoscroll() {
    guard let token, store?.layerVisibilityDraft?.id == token else {
      cancel()
      return
    }
    guard let point = previousPoint, let scrollView, let documentView = scrollView.documentView,
      let store, store.layerVisibilityDraft?.id == token
    else { return }
    let clip = scrollView.contentView
    let local = clip.convert(point, from: nil)
    let bounds = clip.bounds
    let margin = min(18, bounds.height / 3)
    let delta: CGFloat =
      local.y < bounds.minY + margin
      ? -12
      : (local.y > bounds.maxY - margin ? 12 : 0)
    guard delta != 0 else { return }
    let y = min(
      max(documentView.frame.minY, bounds.minY + delta),
      max(documentView.frame.minY, documentView.frame.maxY - bounds.height))
    guard y != bounds.minY else { return }
    clip.scroll(to: NSPoint(x: bounds.minX, y: y))
    scrollView.reflectScrolledClipView(clip)
    documentView.layoutSubtreeIfNeeded()
    sweep(to: point)
  }

  func release(_ event: NSEvent) {
    guard let store, let window, event.window === window else {
      cancel()
      return
    }
    if let token {
      sweep(to: event.locationInWindow)
      store.finishLayerVisibilityDrag(token)
    } else if let pressedID, let baseline, store.document == baseline,
      let button = buttons.allObjects.first(where: {
        $0.layerID == pressedID && $0.window === window
      }),
      button.bounds.contains(button.convert(event.locationInWindow, from: nil))
    {
      store.toggleLayerVisibility(pressedID, modifiers: modifiers)
    }
    cleanUp()
  }

  func cancel() {
    if let store, let token { store.finishLayerVisibilityDrag(token, cancel: true) }
    cleanUp()
  }

  private func cleanUp() {
    if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    eventMonitor = nil
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
    timer?.invalidate()
    timer = nil
    token = nil
    origin = nil
    previousPoint = nil
    pressedID = nil
    baseline = nil
    scrollView = nil
    store = nil
    window = nil
  }
}

struct LayerEyeControl: NSViewRepresentable {
  let store: EditorStore
  let layer: Layer
  let tracking: LayerEyeTracking
  var height: CGFloat = 36

  func makeNSView(context: Context) -> LayerEyeButton { LayerEyeButton() }
  func updateNSView(_ button: LayerEyeButton, context: Context) {
    button.store = store
    button.controlHeight = height
    button.layerID = layer.id
    button.tracking = tracking
    tracking.buttons.add(button)
    tracking.revealView?.scheduleReveal()
    button.isEnabled = store.canBeginLayerCreation || store.layerVisibilityDraft != nil
    button.image =
      store.layerEyeVisible(layer)
      ? NSImage(systemSymbolName: "eye", accessibilityDescription: nil)?.withSymbolConfiguration(
        .init(pointSize: 11, weight: .regular)) : nil
    button.setAccessibilityLabel("Visibility of \(layer.name)")
    button.setAccessibilityValue(
      "\(store.layerEyeVisible(layer) ? "Visible" : "Hidden"). Layer color: \(layer.colorLabel?.title ?? "Unknown")"
    )
    button.toolTip =
      "Toggle \(layer.name). Drag to show or hide rows. Option-click to isolate or restore visibility."
  }
}

@MainActor final class LayerEyeButton: NSButton {
  weak var store: EditorStore?
  weak var tracking: LayerEyeTracking?
  var layerID = UUID()
  var controlHeight: CGFloat = 36 {
    didSet { if oldValue != controlHeight { invalidateIntrinsicContentSize() } }
  }
  init() {
    super.init(frame: .zero)
    title = ""
    isBordered = false
    imagePosition = .imageOnly
    contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
    target = self
    action = #selector(toggleVisibility)
  }
  required init?(coder: NSCoder) { nil }
  override var alignmentRectInsets: NSEdgeInsets {
    NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
  }
  override var intrinsicContentSize: NSSize { NSSize(width: 22, height: controlHeight) }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    tracking?.revealView?.scheduleReveal()
  }
  override func setFrameSize(_ newSize: NSSize) {
    let changed = frame.size != newSize
    super.setFrameSize(newSize)
    if changed { tracking?.revealView?.scheduleReveal() }
  }
  override func setFrameOrigin(_ newOrigin: NSPoint) {
    let changed = frame.origin != newOrigin
    super.setFrameOrigin(newOrigin)
    if changed { tracking?.revealView?.scheduleReveal() }
  }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  @objc private func toggleVisibility() { store?.toggleLayerVisibility(layerID) }
  override func mouseDown(with event: NSEvent) { tracking?.press(self, event: event) }
  override func mouseDragged(with event: NSEvent) { tracking?.drag(event) }
  override func mouseUp(with event: NSEvent) { tracking?.release(event) }
  override func cancelOperation(_ sender: Any?) { tracking?.cancel() }
}
