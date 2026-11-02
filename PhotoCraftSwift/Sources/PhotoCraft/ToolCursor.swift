import AppKit
import PhotoCraftCore
import SwiftUI

/// Cursor semantics follow the operation actually dispatched, including the mode captured at stroke start.
enum ToolCursor: Hashable {
  enum Badge: String { case add, subtract, intersect, constrain, center, constrainCenter, copy, constrainCopy }
  case arrow, text, crosshair, openHand, closedHand, unavailable
  case symbol(String, Badge? = nil)
  case selectedPixels(copy:Bool,constrained:Bool,unsnapped:Bool)

  static func selection(_ symbol: String, _ mode: SelectionMode) -> Self {
    .symbol(symbol, mode == .add ? .add : mode == .subtract ? .subtract : mode == .intersect ? .intersect : nil)
  }
  static func geometry(_ flags: NSEvent.ModifierFlags) -> Badge? {
    flags.contains(.shift) ? (flags.contains(.option) ? .constrainCenter : .constrain) : flags.contains(.option) ? .center : nil
  }
  @MainActor private static var cache: [Self: NSCursor] = [:]
  @MainActor var native: NSCursor {
    switch self {
    case .arrow: return .arrow
    case .text: return .iBeam
    case .crosshair: return .crosshair
    case .openHand: return .openHand
    case .closedHand: return .closedHand
    case .unavailable: return .operationNotAllowed
    case .selectedPixels(let copy,let constrained,let unsnapped):
      let badge:Badge?=copy ? (constrained ? .constrainCopy:.copy):constrained ? .constrain:nil
      let base=ToolCursor.symbol("arrow.up.and.down.and.arrow.left.and.right",badge).native
      guard unsnapped else{return base};if let cached=Self.cache[self]{return cached}
      let image=base.image.copy() as! NSImage;image.lockFocus()
      let grid=NSBezierPath();grid.lineWidth=1
      for i in [3.0,6.0,9.0]{grid.move(to:.init(x:i,y:1));grid.line(to:.init(x:i,y:10));grid.move(to:.init(x:1,y:i));grid.line(to:.init(x:10,y:i))}
      NSColor.black.setStroke();grid.lineWidth=3;grid.stroke();NSColor.white.setStroke();grid.lineWidth=1;grid.stroke()
      let slash=NSBezierPath();slash.move(to:.init(x:1,y:1));slash.line(to:.init(x:10,y:10));NSColor.black.setStroke();slash.lineWidth=3;slash.stroke();NSColor.white.setStroke();slash.lineWidth=1;slash.stroke();image.unlockFocus()
      let value=NSCursor(image:image,hotSpot:base.hotSpot);if Self.cache.count>=128{Self.cache.removeAll(keepingCapacity:true)};Self.cache[self]=value;return value
    case .symbol(let name, let badge):
      if let cached = Self.cache[self] { return cached }
      let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { _ in
        let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)
          ?? NSImage(systemSymbolName: "plus", accessibilityDescription: nil)!
        let rect = NSRect(x: 2, y: 10, width: 20, height: 20)
        // A dark silhouette and white inset remain readable on light and dark pixels.
        func draw(_ color: NSColor, dx: CGFloat, dy: CGFloat) {
          let tinted = symbol.copy() as! NSImage
          tinted.lockFocus(); color.set(); NSRect(origin: .zero, size: tinted.size).fill(using: .sourceIn); tinted.unlockFocus()
          tinted.draw(in: rect.offsetBy(dx: dx, dy: dy), from: .zero, operation: .sourceOver, fraction: 1)
        }
        for d: CGPoint in [.init(x:-1,y:0),.init(x:1,y:0),.init(x:0,y:-1),.init(x:0,y:1)] { draw(.black, dx: d.x, dy: d.y) }
        draw(.white, dx: 0, dy: 0)
        if let badge {
          let circle = NSBezierPath(ovalIn: NSRect(x: 17, y: 0, width: 15, height: 15))
          NSColor.black.setFill(); circle.fill(); NSColor.white.setStroke(); circle.lineWidth = 1; circle.stroke()
          let path = NSBezierPath(); path.lineWidth = 1.5
          switch badge {
          case .add, .subtract:
            path.move(to: .init(x:20,y:7.5)); path.line(to: .init(x:29,y:7.5))
            if badge == .add { path.move(to: .init(x:24.5,y:3)); path.line(to: .init(x:24.5,y:12)) }
          case .copy,.constrainCopy:
            path.appendRect(.init(x:20,y:6,width:6,height:6));path.appendRect(.init(x:23,y:3,width:6,height:6))
            if badge == .constrainCopy{path.move(to:.init(x:20,y:2));path.line(to:.init(x:29,y:2))}
          case .intersect:
            path.appendRect(.init(x:20,y:6,width:6,height:6)); path.appendRect(.init(x:23,y:3,width:6,height:6))
          case .constrain, .constrainCenter:
            path.appendRect(.init(x:20.5,y:3.5,width:8,height:8))
            if badge == .constrainCenter { path.appendOval(in:.init(x:23.5,y:6.5,width:2,height:2)) }
          case .center:
            path.appendOval(in:.init(x:20.5,y:3.5,width:8,height:8))
            path.move(to:.init(x:24.5,y:2)); path.line(to:.init(x:24.5,y:13))
            path.move(to:.init(x:19,y:7.5)); path.line(to:.init(x:30,y:7.5))
          }
          path.stroke()
        }
        return true
      }
      let result = NSCursor(image: image, hotSpot: .init(x: 12, y: 12))
      if Self.cache.count >= 128 { Self.cache.removeAll(keepingCapacity: true) }
      Self.cache[self] = result
      return result
    }
  }
}

extension EditorTool {
  /// Exhaustive by design: adding a tool must include its effective cursor policy.
  func cursor(modifiers flags: NSEvent.ModifierFlags, selection: SelectionMode = .replace,
              adjustmentSubtract: Bool = false, fingerPainting: Bool = false) -> ToolCursor {
    let option = flags.contains(.option)
    switch self {
    case .zoom: return .symbol(option ? "minus.magnifyingglass" : "plus.magnifyingglass")
    case .hand: return .openHand
    case .move, .pathSelection: return .arrow
    case .directSelection: return .symbol(option ? "arrow.triangle.branch" : "cursorarrow")
    case .text, .verticalText: return .text
    case .marquee: return .selection("rectangle.dashed", selection)
    case .ellipticalMarquee: return .selection("circle.dashed", selection)
    case .magneticLasso:return ToolCursor.magnetic(modifiers:flags,mode:selection,active:false)
    case .lasso, .polygonLasso: return .selection("lasso", selection)
    case .objectSelection: return .selection("viewfinder", selection)
    case .quickSelection, .selectionBrush: return .selection("paintbrush.pointed", selection)
    case .magicWand: return .selection("wand.and.stars", selection)
    case .cloneStamp, .healingBrush:
      return .symbol(option ? "scope" : self == .cloneStamp ? "paintbrush.pointed" : "bandage")
    case .mixerBrush: return .symbol(option ? "eyedropper" : "paintbrush.pointed")
    case .dodge: return .symbol(option ? "flame" : "sun.max")
    case .burn: return .symbol(option ? "sun.max" : "flame")
    case .smudge: return .symbol(fingerPainting != option ? "hand.draw.fill" : "hand.draw")
    case .adjustmentBrush: return .symbol("paintbrush.pointed", adjustmentSubtract != option ? .subtract : .add)
    case .rectangle, .ellipse, .triangle, .polygon, .star, .line, .customShape:
      return .symbol("plus", ToolCursor.geometry(flags))
    case .frame, .artboard: return .symbol("viewfinder", flags.contains(.shift) ? .constrain : nil)
    case .crop: return .symbol("crop", ToolCursor.geometry(flags))
    case .blur: return .symbol("drop")
    case .sharpen: return .symbol("triangle")
    case .sponge: return .symbol("circle.lefthalf.filled")
    case .patch, .contentAwareMove: return .selection("lasso", selection)
    case .redEye: return .symbol("eye")
    case .spotHealing: return .symbol("bandage")
    case .pencil: return .symbol("pencil.tip")
    case .colorReplacement: return .symbol("paintbrush.pointed.fill")
    case .patternStamp: return .symbol("square.grid.2x2")
    case .backgroundEraser, .magicEraser, .eraser: return .symbol("eraser")
    case .brush: return .crosshair
    case .paintBucket: return .symbol("drop.fill")
    case .gradient: return .symbol("rectangle.lefthalf.filled", flags.contains(.shift) ? .constrain : nil)
    case .eyedropper: return .symbol("eyedropper")
    case .pen, .freeformPen, .curvaturePen: return .symbol("pencil.tip")
    }
  }
}

/// One AppKit lifecycle for every editing canvas. Modifier events are observed without consuming them,
/// including when a control elsewhere in the same window has keyboard focus.
@MainActor class ModifierCursorView: NSView {
  private(set) var cursorModifiers: NSEvent.ModifierFlags = []
  private(set) var cursorGestureModifiers: NSEvent.ModifierFlags?
  private(set) var cursorPointerDown = false
  var spaceHeld = false { didSet { if oldValue != spaceHeld { refreshToolCursor() } } }
  private var modifierMonitor: Any?
  private var windowObservers: [NSObjectProtocol] = []
  private var cursorTracking: NSTrackingArea?
  private var registeredCursor: ToolCursor?
  var toolCursor: ToolCursor { .crosshair }
  var cursorAllowsChildHit: Bool { false }
  var hasCursorMonitor: Bool { modifierMonitor != nil }
  isolated deinit { removeCursorObservers() }
  private func removeCursorObservers() {
    if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }; modifierMonitor = nil
    for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }; windowObservers = []
  }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow(); removeCursorObservers(); registeredCursor = nil; clearCursorInput()
    guard let target = window else { return }
    cursorModifiers = NSEvent.modifierFlags
    modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged,.keyUp]) { [weak self, weak target] event in
      MainActor.assumeIsolated {
        if let self, let target, self.window === target { self.observeCursorModifiers(event) }
      }
      return event
    }
    for name in [NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification] {
      let resigned = name == NSWindow.didResignKeyNotification
      windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: target, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          if resigned { self.clearCursorInput() }
          else { self.updateCursorModifiers(NSEvent.modifierFlags) }
        }
      })
    }
    refreshToolCursor()
  }
  func clearCursorInput() {
    spaceHeld = false; cursorPointerDown = false; cursorGestureModifiers = nil; cursorModifiers = []
    refreshToolCursor()
  }
  func updateCursorModifiers(_ flags: NSEvent.ModifierFlags) {
    cursorModifiers = flags.intersection([.control,.command,.option,.shift]); refreshToolCursor()
  }
  func beginCursorGesture(_ event: NSEvent) {
    cursorPointerDown = true; cursorGestureModifiers = event.modifierFlags
    updateCursorModifiers(event.modifierFlags)
  }
  func endCursorGesture(_ event: NSEvent) {
    cursorPointerDown = false; cursorGestureModifiers = nil; updateCursorModifiers(event.modifierFlags)
  }
  func observeCursorModifiers(_ event: NSEvent) {
    guard let window, window.isKeyWindow, event.window == nil || event.window === window else { return }
    if event.type == .keyUp {
      if event.keyCode == 49 { spaceHeld = false }
      return
    }
    updateCursorModifiers(event.modifierFlags)
  }
  func ownsToolCursor(atWindowPoint pointInWindow: NSPoint) -> Bool {
    guard let window, !isHiddenOrHasHiddenAncestor, visibleRect.contains(convert(pointInWindow,from:nil)) else { return false }
    if !cursorAllowsChildHit, let content = window.contentView {
      let point = content.superview?.convert(pointInWindow,from:nil) ?? pointInWindow
      if content.hitTest(point) !== self { return false }
    }
    return true
  }
  func refreshToolCursor() {
    let descriptor = toolCursor
    if registeredCursor != descriptor { window?.invalidateCursorRects(for: self); registeredCursor = descriptor }
    guard let window, window.isKeyWindow, window.attachedSheet == nil,
          !isHiddenOrHasHiddenAncestor else { return }
    guard ownsToolCursor(atWindowPoint:window.mouseLocationOutsideOfEventStream) else { return }
    let cursor = descriptor.native
    if NSCursor.current !== cursor { cursor.set() }
  }
  override func resetCursorRects() { addCursorRect(visibleRect, cursor: toolCursor.native) }
  override func flagsChanged(with event: NSEvent) { updateCursorModifiers(event.modifierFlags) }
  override func cursorUpdate(with event: NSEvent) { updateCursorModifiers(event.modifierFlags) }
  override func mouseEntered(with event: NSEvent) { updateCursorModifiers(event.modifierFlags) }
  override func mouseMoved(with event: NSEvent) { updateCursorModifiers(event.modifierFlags) }
  override func mouseExited(with event: NSEvent) { window?.invalidateCursorRects(for: self) }
  override func updateTrackingAreas() {
    super.updateTrackingAreas(); if let cursorTracking { removeTrackingArea(cursorTracking) }
    let area = NSTrackingArea(rect: .zero, options: [.cursorUpdate,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect], owner: self)
    addTrackingArea(area); cursorTracking = area
  }
}

/// Non-hit-testing cursor region for native SwiftUI previews; gestures remain owned by SwiftUI.
struct ToolCursorRegion: NSViewRepresentable {
  var descriptor: (NSEvent.ModifierFlags) -> ToolCursor
  func makeNSView(context: Context) -> Region { Region() }
  func updateNSView(_ view: Region, context: Context) { view.descriptor = descriptor; view.refreshToolCursor() }
  final class Region: ModifierCursorView {
    var descriptor: (NSEvent.ModifierFlags) -> ToolCursor = { _ in .crosshair }
    override var toolCursor: ToolCursor { descriptor(cursorModifiers) }
    override var cursorAllowsChildHit: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
  }
}
extension View {
  func toolCursor(_ descriptor: @escaping (NSEvent.ModifierFlags) -> ToolCursor) -> some View {
    background(ToolCursorRegion(descriptor: descriptor))
  }
}
