import AppKit
import PhotoCraftCore

@MainActor struct ArtboardGesture {
  let original: CraftDocument
  let layerID: UUID?
  let start: CGPoint
  let bounds: IntRect
  let corner: Int?
  var current: IntRect
  var changed = false
  mutating func drag(to p: CGPoint, square: Bool) {
    let dx = Int((p.x - start.x).rounded()), dy = Int((p.y - start.y).rounded())
    changed = changed || abs(dx) + abs(dy) > 1
    if layerID == nil {
      current = CraftCanvas.dragRect(from: start, to: p, flags: square ? [.shift] : [], width: original.width, height: original.height, clipToCanvas: false) ?? bounds
    } else if let corner {
      var x0 = bounds.x, y0 = bounds.y, x1 = bounds.x + bounds.width, y1 = bounds.y + bounds.height
      if corner == 0 || corner == 3 { x0 = min(x1 - 1, x0 + dx) } else { x1 = max(x0 + 1, x1 + dx) }
      if corner < 2 { y0 = min(y1 - 1, y0 + dy) } else { y1 = max(y0 + 1, y1 + dy) }
      current = .init(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    } else { current = .init(x: bounds.x + dx, y: bounds.y + dy, width: bounds.width, height: bounds.height) }
  }
  var command: Command {
    let logical = IntRect(x: current.x + (original.artboardOrigin?.x ?? 0), y: current.y + (original.artboardOrigin?.y ?? 0), width: current.width, height: current.height)
    if let layerID { return .artboard(.resize(layerID, bounds: logical, moveContents: corner == nil)) }
    return .artboard(.create(name: "Artboard \(original.artboards.count + 1)", bounds: logical, background: .white, children: []))
  }
}
extension EditorStore {
  func fitArtboard(_ rect: IntRect) {
    let next = CanvasViewport.bounded(min(max(1, viewportSize.width - 60) / Double(rect.width), max(1, viewportSize.height - 60) / Double(rect.height)) * viewport.backing)
    setZoom(next, center: true)
    pan = CGSize(width: (Double(document.width) / 2 - Double(rect.x) - Double(rect.width) / 2) * next / viewport.backing, height: (Double(document.height) / 2 - Double(rect.y) - Double(rect.height) / 2) * next / viewport.backing)
  }
  func finishArtboardGesture() {
    guard let gesture = artboardGesture else { return }
    artboardGesture = nil
    guard gesture.changed, gesture.original == document else { return }
    perform(gesture.command)
  }
}
extension CraftCanvas {
  func artboardCorners(_ r: IntRect) -> [CGPoint] {
    [CGPoint(x: r.x, y: r.y), CGPoint(x: r.x + r.width, y: r.y), CGPoint(x: r.x + r.width, y: r.y + r.height), CGPoint(x: r.x, y: r.y + r.height)]
  }
  func beginArtboardGesture(_ event: NSEvent, at p: CGPoint) -> Bool {
    guard store.tool == .artboard, !spaceHeld else { return false }
    guard store.canEditArtboards else { return true }
    var target: Layer?
    var corner: Int?
    if let selected = store.selectedArtboard, let rect = selected.artboardBounds {
      corner = artboardCorners(rect).firstIndex { hypot($0.x - p.x, $0.y - p.y) * scale < 9 }
      if corner != nil { target = selected }
    }
    if target == nil {
      target = store.document.artboards.reversed().first { board in
        guard let r = board.artboardBounds else { return false }
        return p.x >= Double(r.x) && p.x <= Double(r.x + r.width) && p.y >= Double(r.y) - (store.showArtboardNames ? 23 / scale : 0) && p.y <= Double(r.y + r.height)
      }
    }
    if let target { store.select(target.id); if store.document.isLocked(target.id) { return true } }
    let r = target?.artboardBounds ?? .init(x: Int(p.x), y: Int(p.y), width: 1, height: 1)
    store.artboardGesture = .init(original: store.document, layerID: target?.id, start: p, bounds: r, corner: corner, current: r)
    needsDisplay = true; return true
  }
  func dragArtboardGesture(_ event: NSEvent) -> Bool {
    guard store.artboardGesture != nil else { return false }
    store.artboardGesture?.drag(to: docPoint(event), square: event.modifierFlags.contains(.shift))
    needsDisplay = true; return true
  }
  func endArtboardGesture(_ event: NSEvent) -> Bool {
    guard dragArtboardGesture(event) else { return false }
    store.finishArtboardGesture(); needsDisplay = true; return true
  }
  func drawArtboards(in c: CGContext) {
    c.saveGState(); defer { c.restoreGState() }
    for layer in store.document.artboards {
      guard let board = layer.artboard, let r = layer.artboardBounds else { continue }
      let point = viewPoint(.init(x: r.x, y: r.y))
      let box = CGRect(x: point.x, y: point.y, width: Double(r.width) * scale, height: Double(r.height) * scale)
      let selected = store.selectedArtboard?.id == layer.id && store.tool == .artboard
      c.setStrokeColor((selected ? NSColor.controlAccentColor : .gray).cgColor); c.setLineWidth(selected ? 2 : 1); c.stroke(box)
      if store.showArtboardNames {
        (layer.name as NSString).draw(at: .init(x: point.x, y: point.y - 20), withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: selected ? NSColor.controlAccentColor : NSColor.lightGray])
      }
      if selected { for p in artboardCorners(r).map(viewPoint) { c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)); c.stroke(CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)) } }
      if store.showArtboardGuides {
        c.setStrokeColor(NSColor.cyan.withAlphaComponent(0.65).cgColor); c.setLineWidth(1)
        for guide in board.guides {
          let vertical = guide.axis == .vertical
          guard guide.position >= 0, guide.position <= Double(vertical ? r.width : r.height) else { continue }
          let g = guide.position * scale
          c.move(to: CGPoint(x: box.minX + (vertical ? g : 0), y: box.minY + (vertical ? 0 : g)))
          c.addLine(to: CGPoint(x: vertical ? box.minX + g : box.maxX, y: vertical ? box.maxY : box.minY + g)); c.strokePath()
        }
      }
    }
    if let gesture = store.artboardGesture, gesture.changed {
      let r = gesture.current, p = viewPoint(.init(x: r.x, y: r.y))
      c.setStrokeColor(NSColor.controlAccentColor.cgColor); c.setLineDash(phase: 0, lengths: [5, 3]); c.setLineWidth(2)
      c.stroke(CGRect(x: p.x, y: p.y, width: Double(r.width) * scale, height: Double(r.height) * scale))
    }
  }
}
@MainActor extension AppDelegate {
  func validateArtboardMenu(_ item: NSMenuItem) -> Bool? {
    switch item.action {
    case #selector(newArtboard): return store?.canEditArtboards == true
    case #selector(artboardFromLayers): return store?.canEditArtboards == true && store?.groupSelectionIDs.isEmpty == false
    case #selector(artboardFromGroup): return store?.canEditArtboards == true && store?.activeLayer?.isGroup == true && store?.activeLayer?.parentID == nil && store?.activeLayer?.artboard == nil
    case #selector(clearArtboardGuides): return store?.canEditArtboards == true && store?.selectedArtboard != nil
    case #selector(fitArtboard): return store?.selectedArtboard != nil
    case #selector(toggleArtboardNames): item.state = store?.showArtboardNames == true ? .on : .off; return store != nil
    case #selector(toggleArtboardGuides): item.state = store?.showArtboardGuides == true ? .on : .off; return store != nil
    case #selector(exportArtboardFiles), #selector(exportArtboardPDF): return store?.canEditArtboards == true && store?.document.hasArtboards == true
    default: return nil
    }
  }
}
