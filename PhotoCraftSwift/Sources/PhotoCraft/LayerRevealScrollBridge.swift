import AppKit
import SwiftUI

/// A passive native view waits for list attachment/layout, asks SwiftUI to realize a
/// missing row by identity, and acknowledges the request only after native visibility.
struct LayerRevealScrollBridge: NSViewRepresentable {
  let store: EditorStore
  let tracker: LayerRevealTracker
  let eyes: LayerEyeTracking
  let request: LayerRevealTracker.Request?
  let visibleIDs: [UUID]
  let rowHeight: CGFloat
  let approach: (UUID) -> Void
  func makeNSView(context: Context) -> LayerRevealScrollView { LayerRevealScrollView() }
  func updateNSView(_ view: LayerRevealScrollView, context: Context) {
    view.store = store
    view.tracker = tracker
    view.eyes = eyes
    eyes.revealView = view
    view.request = request
    view.visibleIDs = visibleIDs
    view.rowHeight = rowHeight
    view.approach = approach
    view.scheduleReveal()
  }
  static func dismantleNSView(_ view: LayerRevealScrollView, coordinator: ()) {
    view.request = nil
    view.approach = nil
    view.stopObserving()
  }
}

@MainActor final class LayerRevealScrollView: NSView {
  weak var store: EditorStore?
  weak var tracker: LayerRevealTracker?
  weak var eyes: LayerEyeTracking?
  var request: LayerRevealTracker.Request?
  var visibleIDs: [UUID] = []
  var rowHeight: CGFloat = 42
  var approach: ((UUID) -> Void)?
  private var queued = false
  private weak var observedScroll: NSScrollView?
  private weak var observedDocument: NSView?
  private var observers: [NSObjectProtocol] = []
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    scheduleReveal()
  }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { stopObserving() }
    super.viewWillMove(toWindow: newWindow)
  }
  func stopObserving() {
    observers.forEach(NotificationCenter.default.removeObserver)
    observers = []
    observedScroll = nil
    observedDocument = nil
  }
  private func observe(_ scroll: NSScrollView) {
    guard scroll !== observedScroll || scroll.documentView !== observedDocument else { return }
    stopObserving()
    observedScroll = scroll
    observedDocument = scroll.documentView
    for view in [scroll.contentView, scroll.documentView].compactMap({ $0 }) {
      view.postsFrameChangedNotifications = true
      view.postsBoundsChangedNotifications = true
      for name in [NSView.frameDidChangeNotification, NSView.boundsDidChangeNotification] {
        observers.append(
          NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.scheduleReveal() }
          })
      }
    }
  }
  override func layout() {
    super.layout()
    scheduleReveal()
  }
  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    scheduleReveal()
  }
  func scheduleReveal() {
    guard request != nil, !queued else { return }
    queued = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.queued = false
      self.revealIfReady()
    }
  }
  @discardableResult func revealIfReady() -> Bool {
    guard let request, let store, let tracker else { return false }
    guard tracker.canConsume(request, store: store, visibleIDs: visibleIDs) else {
      _ = tracker.consume(request, store: store, visibleIDs: visibleIDs)
      self.request = nil
      stopObserving()
      return false
    }
    guard window != nil, let scroll = enclosingScrollView else { return false }
    observe(scroll)
    let height = CGFloat(visibleIDs.count) * rowHeight + CGFloat(max(0, visibleIDs.count - 1)) + 6
    WorkspaceLayoutDiagnostics.log(
      "reveal.readiness",
      [
        "bounds": WorkspaceLayoutDiagnostics.rect(bounds),
        "expectedHeight": Double(height), "rowHeight": Double(rowHeight),
        "clip": WorkspaceLayoutDiagnostics.rect(scroll.contentView.bounds),
        "document": WorkspaceLayoutDiagnostics.rect(scroll.documentView?.frame ?? .zero),
      ])
    guard bounds.width > 0, rowHeight > 0, bounds.height > 0,
      visibleIDs.contains(request.layerID),
      scroll.contentView.bounds.height > 0, scroll.contentView.bounds.width > 0
    else { return false }
    let clip = scroll.contentView
    // Lazy stacks retain estimates for uninstantiated rows after a thumbnail-size
    // change. SwiftUI owns that geometry; use its identity-based navigation instead
    // of computing distant offsets. Eye controls exist in every row, including groups.
    let eye = eyes?.buttons.allObjects.first {
      $0.layerID == request.layerID && $0.store === store && $0.window === window
        && $0.enclosingScrollView === scroll && $0.bounds.width > 0
        && abs($0.bounds.height - (rowHeight - 6)) < 0.5
    }
    guard let eye else {
      approach?(request.layerID)
      return false
    }
    let target = clip.convert(eye.bounds, from: eye).insetBy(dx: 0, dy: -3)
    let visible = clip.bounds
    var origin = visible.origin
    // Reveal only the nearest missing edge. Already visible rows and horizontal
    // positioning are unchanged; oversized rows retain the largest visible area.
    if target.minY < visible.minY {
      origin.y = target.minY
    } else if target.maxY > visible.maxY {
      origin.y = min(target.minY, target.maxY - visible.height)
    }
    let constrained = clip.constrainBoundsRect(NSRect(origin: origin, size: visible.size))
    clip.scroll(to: constrained.origin)
    scroll.reflectScrolledClipView(clip)
    let shown = clip.convert(eye.bounds, from: eye).insetBy(dx: 0, dy: -3)
      .intersection(clip.bounds)
    let actual = eye.visibleRect.intersection(eye.bounds)
    guard !eye.isHiddenOrHasHiddenAncestor,
      actual.height >= min(eye.bounds.height, clip.bounds.height) - 0.5,
      shown.height >= min(rowHeight, clip.bounds.height) - 0.5
    else {
      // Cached offscreen native controls can retain obsolete ancestor positions.
      // Clip-coordinate intersection alone does not establish that SwiftUI has
      // placed the row in the visible lazy-stack slice.
      approach?(request.layerID)
      return false
    }
    WorkspaceLayoutDiagnostics.log(
      "reveal.native",
      [
        "layer": request.layerID.uuidString,
        "clip": WorkspaceLayoutDiagnostics.rect(clip.bounds),
        "row": WorkspaceLayoutDiagnostics.rect(target),
      ])
    let consumed = tracker.consume(request, store: store, visibleIDs: visibleIDs)
    self.request = nil
    stopObserving()
    return consumed
  }
}
