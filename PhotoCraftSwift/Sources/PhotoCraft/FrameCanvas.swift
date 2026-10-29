import AppKit
import PhotoCraftCore
import PhotoCraftImaging

@MainActor struct FrameGesture {
  var geometry: ArtboardGesture
  let target: FrameTarget
  let definition: FrameDefinition
  let sourceIDs: Set<UUID>
}
extension EditorStore {
  func finishFrameGesture() {
    guard let gesture = frameGesture else { return }; frameGesture = nil
    let geometry = gesture.geometry
    guard geometry.changed, geometry.original == document else { return }
    let old = geometry.bounds, rect = geometry.current, target = gesture.target, ids = gesture.sourceIDs
    var resized = gesture.definition; resized.width = rect.width; resized.height = rect.height
    let definition = resized
    performGeometry(label: geometry.layerID == nil ? "New Frame" : "Transform Frame", prepare: { original in
      if let id = geometry.layerID {
        let delta = Transform2D.translation(Double(rect.x), Double(rect.y)) * .scale(Double(rect.width) / Double(old.width), Double(rect.height) / Double(old.height)) * .translation(-Double(old.x), -Double(old.y))
        return .frame(target == .contents ? .transformContents(id, delta) : .transform(id, delta, contents: target == .both))
      }
      if !ids.isEmpty, case .embedSmartObject(let selected, let layer) = try SmartObjectIO.convert(in: original, selected: ids) {
        return .frame(.wrap(name: "Frame", bounds: rect, definition: definition, sourceIDs: selected, embedded: layer))
      }
      return .frame(.create(name: "Frame", bounds: rect, definition: definition, children: []))
    }, onSuccess: { [weak self] in self?.selectActiveFrame() })
  }
}
extension CraftCanvas {
  func beginFrameGesture(_ event: NSEvent, at p: CGPoint) -> Bool {
    guard store.tool == .frame, !spaceHeld else { return false }
    guard store.canEditFrames else { return true }
    var target: Layer?, corner: Int?
    if let selected = store.selectedFrame, let r = selected.frameBounds {
      corner = artboardCorners(r).firstIndex { hypot($0.x - p.x, $0.y - p.y) * scale < 9 }
      if corner != nil { target = selected }
    }
    if target == nil, !event.modifierFlags.contains(.option) {
      target = store.document.layers.reversed().first { layer in
        guard let path = try? layer.framePath(), let cg = try? VectorRasterizer.filledPath(path) else { return false }
        return cg.contains(p)
      }
    }
    if let target { store.selectFrameTarget(target, target: store.frameTarget); if store.document.isLocked(target.id) { return true } }
    let rect = target?.frameBounds ?? IntRect(x: Int(p.x), y: Int(p.y), width: 1, height: 1)
    var definition = target?.frame ?? .init(width: 1, height: 1, shape: store.frameShape, sides: store.frameSides)
    if target == nil, definition.shape == .custom {
      do {
        guard let path = store.selectedVectorPath else { throw CraftError.invalid("Select a closed path in the Paths panel for a custom frame.") }
        definition.customPath = try FrameRenderer.normalized(VectorRasterizer.filledPath(path)).0
      } catch { store.error = error.localizedDescription; return true }
    }
    let source = target == nil && store.activeLayer?.frame == nil && store.activeLayer?.isGroup == false ? store.groupSelectionIDs : []
    store.frameGesture = .init(geometry: .init(original: store.document, layerID: target?.id, start: p, bounds: rect, corner: corner, current: rect), target: store.frameTarget, definition: definition, sourceIDs: source)
    needsDisplay = true; return true
  }
  func dragFrameGesture(_ event: NSEvent) -> Bool {
    guard store.frameGesture != nil else { return false }
    store.frameGesture?.geometry.drag(to: docPoint(event), square: event.modifierFlags.contains(.shift)); needsDisplay = true; return true
  }
  func endFrameGesture(_ event: NSEvent) -> Bool {
    guard dragFrameGesture(event) else { return false }; store.finishFrameGesture(); needsDisplay = true; return true
  }
  func drawFrames(in c: CGContext) {
    c.saveGState(); defer { c.restoreGState() }
    for layer in store.document.layers where layer.frame != nil && layer.visible {
      let selected = store.tool == .frame && store.selectedFrame?.id == layer.id
      guard selected || store.document.children(of: layer.id).isEmpty, let rect = layer.frameBounds, let path = try? layer.framePath(), let cg = try? VectorRasterizer.filledPath(path) else { continue }
      let origin = viewPoint(.zero)
      var transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: origin.x, ty: origin.y)
      c.setStrokeColor((selected ? NSColor.controlAccentColor : .gray).cgColor); c.setLineWidth(selected ? 2 : 1)
      if let outline = cg.copy(using: &transform) { c.addPath(outline); c.strokePath() }
      let corners = artboardCorners(rect).map(viewPoint)
      if store.document.children(of: layer.id).isEmpty {
        c.saveGState(); if let outline = cg.copy(using: &transform) { c.addPath(outline); c.clip() }
        for (a,b) in [(0,2),(1,3)] { c.move(to: corners[a]); c.addLine(to: corners[b]); c.strokePath() }; c.restoreGState()
      }
      if selected { for p in corners { c.setFillColor(NSColor.white.cgColor); c.fill(CGRect(x: p.x-3,y:p.y-3,width:6,height:6)); c.stroke(CGRect(x:p.x-3,y:p.y-3,width:6,height:6)) } }
    }
    if let gesture = store.frameGesture, gesture.geometry.changed {
      let r = gesture.geometry.current, p = viewPoint(.init(x:r.x,y:r.y))
      c.setStrokeColor(NSColor.controlAccentColor.cgColor); c.setLineWidth(2); c.setLineDash(phase:0,lengths:[5,3]); c.stroke(CGRect(x:p.x,y:p.y,width:Double(r.width)*scale,height:Double(r.height)*scale))
    }
  }
}
