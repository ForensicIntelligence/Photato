import AppKit
import QuartzCore
import PhotoCraftCore

enum SelectionAntsShape {
  case contour(CGPath, CGAffineTransform)
  case rectangle(CGRect)
  case ellipse(CGRect)
  func matches(_ other: Self?) -> Bool {
    switch (self, other) {
    case (.contour(let a, let t), .contour(let b, let u)): a === b && t == u
    case (.rectangle(let a), .rectangle(let b)), (.ellipse(let a), .ellipse(let b)): a == b
    default: false
    }
  }
  var path: CGPath {
    switch self {
    case .contour(let path, var transform): return path.copy(using: &transform)!
    case .rectangle(let rect): return CGPath(rect: rect, transform: nil)
    case .ellipse(let rect): return CGPath(ellipseIn: rect, transform: nil)
    }
  }
}
struct SelectionAntsEnvironment {
  var attached = true
  var applicationActive = true
  var keyWindow = true
  var windowVisible = true
  var unoccluded = true
  var minimized = false
  var hidden = false
  var reduceMotion = false
  var animates: Bool {
    attached && applicationActive && keyWindow && windowVisible && unoccluded
      && !minimized && !hidden && !reduceMotion
  }
}
@MainActor final class SelectionAntsStroke {
  static let animationKey = "Photato.selectionAnts"
  nonisolated static let period = 8.0
  nonisolated static let duration = 0.8
  let layer = CALayer()
  let white = CAShapeLayer()
  let black = CAShapeLayer()
  let clip = CAShapeLayer()
  private(set) var shape: SelectionAntsShape?
  private(set) var pathUpdates = 0
  var isAnimating: Bool { black.animation(forKey: Self.animationKey) != nil }
  init() {
    layer.name = "Photato selection border"
    layer.mask = clip
    for stroke in [white, black] {
      stroke.fillColor = nil; stroke.lineWidth = 1
      stroke.lineCap = .butt; stroke.lineJoin = .miter
      layer.addSublayer(stroke)
    }
    white.strokeColor = NSColor.white.cgColor
    black.strokeColor = NSColor.black.cgColor; black.lineDashPattern = [4, 4]
    clip.fillColor = NSColor.white.cgColor
    layer.isHidden = true
  }
  func update(_ next: SelectionAntsShape?, bounds: CGRect, visible: CGRect, backing: CGFloat, animate: Bool) {
    CATransaction.begin(); CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }
    layer.frame = bounds; layer.bounds = bounds
    for stroke in [white, black, clip] { stroke.frame = bounds; stroke.bounds = bounds; stroke.contentsScale = backing }
    clip.path = visible.isEmpty || visible.isNull || visible.isInfinite ? nil : CGPath(rect: visible, transform: nil)
    if let next {
      if !next.matches(shape) { let path = next.path; white.path = path; black.path = path; pathUpdates += 1 }
      shape = next
    } else {
      shape = nil; white.path = nil; black.path = nil
    }
    layer.isHidden = next == nil || visible.isEmpty || black.path?.isEmpty != false
    setAnimating(animate && !layer.isHidden)
  }
  func setAnimating(_ active: Bool) {
    guard active != isAnimating else { return }
    if active {
      let motion = CABasicAnimation(keyPath: "lineDashPhase")
      motion.fromValue = black.lineDashPhase; motion.toValue = black.lineDashPhase + CGFloat(Self.period)
      motion.duration = Self.duration; motion.repeatCount = .infinity
      motion.timingFunction = CAMediaTimingFunction(name: .linear)
      black.add(motion, forKey: Self.animationKey)
    } else {
      if let phase = black.presentation()?.lineDashPhase, phase.isFinite {
        black.lineDashPhase = phase.truncatingRemainder(dividingBy: CGFloat(Self.period))
      }
      black.removeAnimation(forKey: Self.animationKey)
    }
  }
}
@MainActor final class SelectionAntsOverlay {
  weak var canvas: CraftCanvas?
  let committed = SelectionAntsStroke()
  let preview = SelectionAntsStroke()
  private var observations: [(NotificationCenter, NSObjectProtocol)] = []
  init(_ canvas: CraftCanvas) {
    self.canvas = canvas
    canvas.layer?.addSublayer(committed.layer); canvas.layer?.addSublayer(preview.layer)
  }
  isolated deinit { removeObservers() }
  private func removeObservers() {
    for (center, token) in observations { center.removeObserver(token) }
    observations.removeAll()
  }
  func observeWindow() {
    removeObservers()
    guard let canvas, let window = canvas.window else { synchronize(); return }
    let center = NotificationCenter.default
    for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
      observe(center, name: name, object: window)
    }
    for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] { observe(center, name: name, object: nil) }
    observe(NSWorkspace.shared.notificationCenter, name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    synchronize()
  }
  private func observe(_ center: NotificationCenter, name: Notification.Name, object: AnyObject?) {
    let token = center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.synchronize() }
    }
    observations.append((center, token))
  }
  func synchronize(environment supplied: SelectionAntsEnvironment? = nil) {
    guard let canvas else { committed.setAnimating(false); preview.setAnimating(false); return }
    let window = canvas.window
    let environment = supplied ?? SelectionAntsEnvironment(attached: window != nil,
      applicationActive: NSApp?.isActive == true, keyWindow: window?.isKeyWindow == true,
      windowVisible: window?.isVisible == true, unoccluded: window?.occlusionState.contains(.visible) == true,
      minimized: window?.isMiniaturized == true, hidden: canvas.isHiddenOrHasHiddenAncestor,
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    let backing = window?.backingScaleFactor ?? 1
    committed.update(canvas.committedSelectionAnts, bounds: canvas.bounds, visible: canvas.visibleRect,
      backing: backing, animate: environment.animates)
    preview.update(canvas.previewSelectionAnts, bounds: canvas.bounds,
      visible: canvas.visibleRect.intersection(canvas.imageRect), backing: backing, animate: environment.animates)
  }
}
extension CraftCanvas {
  var committedSelectionAnts: SelectionAntsShape? {
    guard store.tool != .selectionBrush else { return nil }
    if let drag = store.selectionBorderDrag, drag.matches(store) {
      if let contour = drag.contour {
        return .contour(contour.path, .init(a: scale, b: 0, c: 0, d: scale,
          tx: imageRect.minX + Double(drag.dx) * scale, ty: imageRect.minY + Double(drag.dy) * scale))
      }
      if let rect = drag.original.selection {
        return .rectangle(selectionViewRect(.init(x: rect.x + drag.dx, y: rect.y + drag.dy, width: rect.width, height: rect.height)))
      }
    }
    let replacing = selectionDragMode == .replace && !panningGesture && (
      start != nil && ([.marquee,.ellipticalMarquee,.rowMarquee,.columnMarquee,.lasso].contains(store.tool)
        || store.tool == .objectSelection) || store.tool == .polygonLasso && !polygonPoints.isEmpty)
    if replacing { return nil }
    let draft = store.transformDraft
    let path = draft?.collectionLayerIDs != nil || draft?.pixelMask == true || (draft?.channelTarget != nil && store.document.selection == nil)
      ? nil : draft?.selection == true ? (store.selectionTransform?.previewPath ?? store.selectionPath) : store.selectionPath
    if let path {
      return .contour(path, .init(a: scale, b: 0, c: 0, d: scale, tx: imageRect.minX, ty: imageRect.minY))
    }
    if let rect = store.document.selection, draft?.selection != true { return .rectangle(selectionViewRect(rect)) }
    return nil
  }
  func selectionViewRect(_ rect: IntRect) -> CGRect {
    let p = viewPoint(.init(x: rect.x, y: rect.y))
    return CGRect(x: p.x, y: p.y, width: CGFloat(rect.width) * scale, height: CGFloat(rect.height) * scale)
  }
  var previewSelectionAnts: SelectionAntsShape? {
    guard store.selectionBorderDrag == nil, let start, let end, !panningGesture else { return nil }
    if let axis = store.tool.singlePixelMarquee,
      let rect = axis.rectangle(at: axis == .row ? end.y : end.x, width: store.document.width, height: store.document.height) {
      return .rectangle(selectionViewRect(rect))
    }
    guard [.marquee, .ellipticalMarquee].contains(store.tool) || (store.tool == .objectSelection && store.objectSelectionMode == .rectangle),
      let rect = Self.dragRect(from: start, to: end,
        flags: [.marquee, .ellipticalMarquee].contains(store.tool) ? dragModifiers.subtracting(selectionStartModifiers) : dragModifiers,
        width: store.document.width, height: store.document.height, clipToCanvas: store.tool != .ellipticalMarquee)
    else { return nil }
    return store.tool == .ellipticalMarquee ? .ellipse(selectionViewRect(rect)) : .rectangle(selectionViewRect(rect))
  }
  func synchronizeSelectionAnts() { selectionAnts?.synchronize() }
}
