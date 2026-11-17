import AppKit
import PhotoCraftCore

/// Pointer-only draft; all accepted coverage still uses the existing command.
@MainActor struct MarqueeCreation {
  let session: UUID
  let panel: UUID
  let tool: EditorTool
  let mode: SelectionMode
  let antiAlias: Bool
  let feather: Double
  var pointer: CGPoint
  func matches(_ store: EditorStore) -> Bool {
    store.sessionGeneration == session && store.layerPanelGeneration == panel
      && store.tool == tool && store.unavailableToolID == nil && store.canManageSelection
      && !store.geometryBusy
  }
}

extension CraftCanvas {
  var creatingMarquee: Bool { marqueeCreation?.matches(store) == true && start != nil && !panningGesture }
  func beginMarqueeCreation(at point: CGPoint) {
    guard [.marquee, .ellipticalMarquee].contains(store.tool), !panningGesture else { return }
    marqueeCreation = .init(session: store.sessionGeneration, panel: store.layerPanelGeneration,
      tool: store.tool, mode: selectionDragMode, antiAlias: store.selectionAntiAlias,
      feather: store.selectionFeather, pointer: point)
  }
  func cancelMarqueeCreation() {
    guard marqueeCreation != nil else { return }
    marqueeCreation = nil; start = nil; end = nil; needsDisplay = true
  }
  @discardableResult func advanceMarqueeCreation(to point: CGPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard var draft = marqueeCreation else { return false }
    guard draft.matches(store), let a = start, let b = end, point.x.isFinite, point.y.isFinite else {
      cancelMarqueeCreation(); return true
    }
    if spaceHeld {
      let dx = point.x - draft.pointer.x, dy = point.y - draft.pointer.y
      start = .init(x: a.x + dx, y: a.y + dy); end = .init(x: b.x + dx, y: b.y + dy)
    } else { end = point }
    draft.pointer = point; marqueeCreation = draft; dragModifiers = modifiers
    needsDisplay = true; refreshToolCursor(); return true
  }
  @discardableResult func finishMarqueeCreation(at point: CGPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard marqueeCreation != nil else { return false }
    advanceMarqueeCreation(to: point, modifiers: modifiers)
    guard let draft = marqueeCreation, let a = start, let b = end else { return true }
    marqueeCreation = nil
    if let rect = Self.dragRect(from: a, to: b, flags: modifiers.subtracting(selectionStartModifiers),
      width: store.document.width, height: store.document.height, clipToCanvas: false) {
      let shape: SelectionShape = draft.tool == .ellipticalMarquee ? .ellipse(rect) : .rectangle(rect)
      store.performGeometry(.selectShape(shape, draft.mode, draft.antiAlias, draft.feather))
    } else if draft.mode == .replace { store.perform(.selection(nil)) }
    return true
  }
}
