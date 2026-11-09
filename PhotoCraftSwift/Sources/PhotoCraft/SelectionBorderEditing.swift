import AppKit
import PhotoCraftCore

@MainActor struct SelectionBorderDrag {
  let original: CraftDocument
  let session: UUID
  let panel: UUID
  let tool: EditorTool
  let start: CGPoint
  let contour: SelectionContour?
  var dx = 0, dy = 0
  func matches(_ store: EditorStore) -> Bool {
    store.sessionGeneration == session && store.layerPanelGeneration == panel && store.tool == tool
  }
}
@MainActor final class SelectionBorderNudges {
  var expected: CraftDocument
  var session: UUID
  var panel: UUID
  let tool: EditorTool
  var dx = 0, dy = 0
  var committed = false
  init(_ store: EditorStore) {
    expected = store.document; session = store.sessionGeneration
    panel = store.layerPanelGeneration; tool = store.tool
  }
  func matches(_ store: EditorStore) -> Bool {
    store.sessionGeneration == session && store.layerPanelGeneration == panel
      && store.tool == tool && store.document == expected
  }
}
extension EditorTool {
  var movesSelectionBorder: Bool {
    [.marquee, .ellipticalMarquee, .rowMarquee, .columnMarquee, .lasso, .polygonLasso, .magicWand].contains(self)
  }
}
@MainActor extension EditorStore {
  func canDragSelectionBorder(at point: CGPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard tool.movesSelectionBorder, canModifySelection, selectionMode(modifiers: modifiers) == .replace,
      modifiers.intersection([.shift,.option,.command,.control]).isEmpty,
      point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
      point.x < Double(document.width), point.y < Double(document.height) else { return false }
    return document.selectionCoverage(x: Int(floor(point.x)), y: Int(floor(point.y))) >= 0.5
  }
  @discardableResult func beginSelectionBorderDrag(at point: CGPoint, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard canDragSelectionBorder(at: point, modifiers: modifiers) else { return false }
    selectionBorderDrag = .init(original: document, session: sessionGeneration, panel: layerPanelGeneration,
      tool: tool, start: point, contour: selectionPath.map(SelectionContour.init))
    return true
  }
  func updateSelectionBorderDrag(to point: CGPoint, modifiers: NSEvent.ModifierFlags) {
    guard var drag = selectionBorderDrag else { return }
    guard drag.matches(self) else { selectionBorderDrag = nil; return }
    do {
      let offset = try SelectedPixelMoveRequest(layerID: document.id, dx: point.x-drag.start.x,
        dy: point.y-drag.start.y, constrain: modifiers.contains(.shift)).offset()
      drag.dx = offset.x; drag.dy = offset.y; selectionBorderDrag = drag
    } catch { self.error = error.localizedDescription }
  }
  func finishSelectionBorderDrag() {
    guard let drag = selectionBorderDrag else { return }
    selectionBorderDrag = nil
    guard drag.matches(self), document == drag.original, drag.dx != 0 || drag.dy != 0 else { return }
    let dx = drag.dx, dy = drag.dy, prepare = selectionTransformPreparation
    performGeometry(label: "Move Selection", allowAuxiliary: true, allowModeComponents: true,
      prepare: { try prepare($0, .init(.translation(Double(dx), Double(dy))), .nearest) })
  }
  func cancelSelectionBorderInteraction() {
    selectionBorderDrag = nil
    selectionBorderNudgeTask?.cancel(); selectionBorderNudgeTask = nil; selectionBorderNudges = nil
  }
  @discardableResult func nudgeSelectionBorder(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
    guard tool.movesSelectionBorder, [123,124,125,126].contains(keyCode),
      modifiers.intersection([.command,.option,.control]).isEmpty, document.selection != nil else { return false }
    let context: SelectionBorderNudges
    if let current = selectionBorderNudges {
      guard current.matches(self) else { cancelSelectionBorderInteraction(); return false }
      context = current
    } else {
      guard canModifySelection else { return false }
      context = SelectionBorderNudges(self); selectionBorderNudges = context
    }
    let step = modifiers.contains(.shift) ? 10 : 1
    context.dx = min(1_000_000, max(-1_000_000, context.dx + (keyCode == 123 ? -step : keyCode == 124 ? step : 0)))
    context.dy = min(1_000_000, max(-1_000_000, context.dy + (keyCode == 126 ? -step : keyCode == 125 ? step : 0)))
    guard selectionBorderNudgeTask == nil else { return true }
    selectionBorderNudgeTask = Task { [weak self, weak context] in
      guard let self, let context else { return }
      defer { if self.selectionBorderNudges === context { self.selectionBorderNudges = nil; self.selectionBorderNudgeTask = nil } }
      while !Task.isCancelled, self.selectionBorderNudges === context, context.dx != 0 || context.dy != 0 {
        guard context.matches(self), self.canModifySelection else { break }
        let dx = context.dx, dy = context.dy, prepare = self.selectionTransformPreparation
        context.dx = 0; context.dy = 0; context.committed = false
        self.performGeometry(label: "Move Selection", allowAuxiliary: true, allowModeComponents: true,
          prepare: { try prepare($0, .init(.translation(Double(dx),Double(dy))), .nearest) },
          onSuccess: { [weak self, weak context] in
            guard let self, let context else { return }
            context.expected = self.document; context.session = self.sessionGeneration
            context.panel = self.layerPanelGeneration; context.committed = true
          })
        if let operation = self.geometryTask {
          await withTaskCancellationHandler { await operation.value } onCancel: { operation.cancel() }
        }
        guard context.committed else { break }
      }
    }
    return true
  }
}
