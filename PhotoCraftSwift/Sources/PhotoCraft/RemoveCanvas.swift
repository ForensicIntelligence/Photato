import AppKit
import PhotoCraftCore

extension CraftCanvas {
  func beginRemoveGesture(_ event: NSEvent, at point: CGPoint) -> Bool {
    guard store.tool == .remove, !spaceHeld else { return false }
    _ = store.beginRemoveStroke(at:point,alternate:event.modifierFlags.contains(.option))
    needsDisplay = true; return true
  }
  func dragRemoveGesture(_ event: NSEvent) -> Bool {
    guard store.removeStroke != nil else { return false }
    store.extendRemoveStroke(to:docPoint(event)); needsDisplay = true; return true
  }
  func endRemoveGesture(_ event: NSEvent) -> Bool {
    guard store.removeStroke != nil else { return false }
    store.finishRemoveStroke(at:docPoint(event)); needsDisplay = true; return true
  }
  func removeKey(_ event: NSEvent) -> Bool {
    guard store.tool == .remove else { return false }
    if event.keyCode == 53, store.removeDraft != nil || store.removeApplying != nil {
      store.cancelRemove(); return true
    }
    if [36,76].contains(event.keyCode), store.removeDraft != nil {
      store.applyRemove(); return true
    }
    if ["[","]"].contains(event.charactersIgnoringModifiers ?? ""), store.removeStroke == nil {
      var settings = store.removeSettings
      settings.size = min(5000,max(1,settings.size+(event.charactersIgnoringModifiers == "[" ? -5:5)))
      try? store.updateRemoveSettings(settings); return true
    }
    return false
  }
  func drawRemoveOverlay(in context: CGContext) {
    guard store.tool == .remove else { return }
    let draft = store.removeDraft ?? store.removeApplying
    guard draft.map({ $0.original == store.document }) ?? false else { return }
    var strokes = draft?.strokes ?? []
    if let stroke = store.removeStroke { strokes.append(stroke) }
    context.saveGState(); context.clip(to:imageRect)
    // Isolate subtract's Clear blend so it only erases the marking overlay.
    context.setAlpha(0.45); context.beginTransparencyLayer(auxiliaryInfo:nil)
    for stroke in strokes {
      let points = stroke.points.map { viewPoint(CGPoint(x:$0[0],y:$0[1])) }
      guard let first = points.first else { continue }
      context.setBlendMode(stroke.subtract ? .clear:.normal)
      context.setFillColor(NSColor.systemPink.cgColor); context.setStrokeColor(NSColor.systemPink.cgColor)
      if stroke.closesLoop {
        context.beginPath(); context.move(to:first)
        for point in points.dropFirst() { context.addLine(to:point) }
        context.closePath(); context.fillPath(using:.evenOdd)
      }
      let diameter = stroke.size*scale
      if points.count == 1 { context.fillEllipse(in:CGRect(x:first.x-diameter/2,y:first.y-diameter/2,width:diameter,height:diameter)) }
      else {
        context.beginPath(); context.move(to:first)
        for point in points.dropFirst() { context.addLine(to:point) }
        context.setLineWidth(diameter); context.setLineCap(.round); context.setLineJoin(.round); context.strokePath()
      }
    }
    context.endTransparencyLayer(); context.restoreGState()
  }
}
