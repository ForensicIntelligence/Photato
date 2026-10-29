import AppKit
import PhotoCraftCore

extension CraftCanvas {
  func beginRegionRetouchGesture(_ event: NSEvent,at p: CGPoint) -> Bool {
    guard let kind = store.tool.regionRetouchKind,!spaceHeld else { return false }
    start = p;end = p;regionRetouchSelecting = false;regionRetouchStart = nil
    if kind == .redEye { regionRetouchSelecting = true;return true }
    if let draft = store.regionRetouchDraft {
      regionRetouchStart = draft
      let nearest = draft.frame.handles.enumerated().min { hypot($0.element.x-p.x,$0.element.y-p.y) < hypot($1.element.x-p.x,$1.element.y-p.y) }
      if kind == .move,let nearest,hypot(nearest.element.x-p.x,nearest.element.y-p.y)*scale < 10 { regionRetouchHandle = nearest.offset }
      else {
        let q = try? draft.frame.delta.inverted().point(p.x,p.y),b = draft.frame.bounds
        let inside = q.map { $0.x >= Double(b.x) && $0.y >= Double(b.y) && $0.x <= Double(b.x+b.width) && $0.y <= Double(b.y+b.height) } ?? false
        regionRetouchHandle = kind == .move && !inside ? 8:-1
      }
      return true
    }
    guard store.canBeginRegionRetouch else { store.status = "Select an unlocked raster layer for retouching.";return true }
    let modified = !event.modifierFlags.intersection([.shift,.option]).isEmpty
    if !modified,store.document.selection != nil,store.document.selectionCoverage(x:Int(floor(p.x)),y:Int(floor(p.y))) > 0 {
      store.beginRegionRetouch(kind:kind);regionRetouchStart = store.regionRetouchDraft;regionRetouchHandle = -1
    } else {
      regionRetouchSelecting = true;selectionDragMode = store.selectionMode(modifiers:event.modifierFlags)
      lassoPoints = [SelectionPoint(p.x,p.y)]
    }
    needsDisplay = true;return true
  }
  func dragRegionRetouchGesture(_ event: NSEvent) -> Bool {
    guard store.tool.regionRetouchKind != nil,start != nil,!panningGesture else { return false }
    let p = docPoint(event);end = p
    if var d = regionRetouchStart,let start {
      d.frame = d.frame.dragging(handle:regionRetouchHandle,from:start,to:p,shift:event.modifierFlags.contains(.shift),option:event.modifierFlags.contains(.option))
      store.updateRegionRetouch(d)
    } else if regionRetouchSelecting,store.tool != .redEye,lassoPoints.count < 4096 { lassoPoints.append(SelectionPoint(p.x,p.y)) }
    needsDisplay = true;return true
  }
  func endRegionRetouchGesture(_ event: NSEvent) -> Bool {
    guard let kind = store.tool.regionRetouchKind,let a = start,!panningGesture else { return false }
    defer { regionRetouchSelecting = false;regionRetouchStart = nil }
    let b = docPoint(event)
    if kind == .redEye {
      if store.regionRetouchDraft != nil { store.cancelRegionRetouch() }
      let box = Self.dragRect(from:a,to:b,flags:[],width:store.document.width,height:store.document.height)
        ?? IntRect(x:Int(a.x)-30,y:Int(a.y)-30,width:60,height:60).clipped(toWidth:store.document.width,height:store.document.height)
      guard box.width > 0,box.height > 0 else { return true }
      store.beginRegionRetouch(kind:kind,region:box);store.commitRegionRetouch();return true
    }
    if regionRetouchSelecting {
      lassoPoints.append(SelectionPoint(b.x,b.y))
      if lassoPoints.count >= 3 { store.selectShape(.polygon(lassoPoints),mode:selectionDragMode) }
      return true
    }
    if regionRetouchStart != nil {
      _ = dragRegionRetouchGesture(event)
      if kind == .patch || !store.regionRetouchTransformOnDrop { store.commitRegionRetouch() }
    }
    return true
  }
  func drawRegionRetouch(in c: CGContext) {
    if let d = store.regionRetouchDraft { drawTransform(d.frame,in:c) }
    if store.tool == .redEye,regionRetouchSelecting,let a = start,let b = end {
      let p = viewPoint(a),q = viewPoint(b)
      outline(CGRect(x:min(p.x,q.x),y:min(p.y,q.y),width:abs(q.x-p.x),height:abs(q.y-p.y)),in:c)
    }
  }
  func regionRetouchKey(_ event: NSEvent) -> Bool {
    if event.keyCode == 53,regionRetouchSelecting || store.regionRetouchDraft != nil {
      store.cancelRegionRetouch();regionRetouchStart = nil;regionRetouchSelecting = false;start = nil;end = nil;lassoPoints = [];return true
    }
    guard var d = store.regionRetouchDraft else { return false }
    if [36,76].contains(event.keyCode) { store.commitRegionRetouch();return true }
    let amount = event.modifierFlags.contains(.shift) ? 10.0:1.0
    switch event.keyCode {
    case 123:d.frame.centerX -= amount
    case 124:d.frame.centerX += amount
    case 125:d.frame.centerY += amount
    case 126:d.frame.centerY -= amount
    default:return false
    }
    store.updateRegionRetouch(d);return true
  }
}
