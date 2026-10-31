import AppKit
import PhotoCraftCore
import SwiftUI

struct LiquifyCanvas: NSViewRepresentable {
  @Bindable var model: LiquifyWorkspace
  func makeNSView(context: Context) -> LiquifyCanvasView { let v = LiquifyCanvasView(); v.model = model; return v }
  func updateNSView(_ view: LiquifyCanvasView,context: Context) {
    // Read observable values here so mesh/preview/view changes invalidate AppKit drawing.
    _ = model.image; _ = model.originalImage; _ = model.field; _ = model.preview
    _ = model.showMask; _ = model.showMesh; _ = model.showBackdrop; _ = model.backdropOpacity
    _ = model.zoom; _ = model.pan; _ = model.size; _ = model.selectedFace; _ = model.settings
    _ = model.tool; _ = model.panTool
    view.model = model; view.needsDisplay = true; view.refreshToolCursor()
  }
  static func dismantleNSView(_ view: LiquifyCanvasView,coordinator: ()) { view.stopDabs() }
}
@MainActor final class LiquifyCanvasView: ModifierCursorView {
  override var toolCursor: ToolCursor {
    guard let model else { return .unavailable }
    if (panning && cursorPointerDown) || (!cursorPointerDown && (spaceHeld || model.panTool)) { return cursorPointerDown ? .closedHand : .openHand }
    let tool = model.stroke?.tool ?? model.resolvedTool(alternate:cursorModifiers.contains(.option))
    switch tool {
    case .freeze: return .symbol("snowflake",.add)
    case .thaw: return .symbol("snowflake",.subtract)
    case .twirlCw: return .symbol("arrow.clockwise")
    case .twirlCcw: return .symbol("arrow.counterclockwise")
    case .pucker: return .symbol("arrow.down.right.and.arrow.up.left")
    case .bloat: return .symbol("arrow.up.left.and.arrow.down.right")
    case .lassoMask:
      let subtract = model.stroke.map { ($0.amount ?? 1) == 0 } ?? cursorModifiers.contains(.option)
      return .symbol("lasso",subtract ? .subtract:.add)
    case .forwardWarp: return .symbol("hand.draw")
    case .reconstruct: return .symbol("arrow.uturn.backward")
    case .smooth: return .symbol("drop")
    case .pushLeft: return .symbol("arrow.left")
    case .reconstructAll,.freezeAll,.thawAll,.invertFreeze: return .unavailable
    }
  }

  weak var model: LiquifyWorkspace?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  private var tracking: NSTrackingArea?
  private var cursorPoint: CGPoint?, previous: CGPoint?
  var panning = false
  private var dabTask: Task<Void,Never>?
  var imageRect: CGRect {
    guard let m = model, let image = m.originalImage else { return .zero }
    let fit = min(max(1,bounds.width-24)/Double(image.width),max(1,bounds.height-24)/Double(image.height))*m.zoom
    let size = CGSize(width:Double(image.width)*fit,height:Double(image.height)*fit)
    return CGRect(x:(bounds.width-size.width)/2+m.pan.width,y:(bounds.height-size.height)/2+m.pan.height,width:size.width,height:size.height)
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(rect:bounds,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self)
    addTrackingArea(tracking!)
  }
  override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { stopDabs() }; super.viewWillMove(toWindow:newWindow) }
  override func draw(_ dirtyRect: NSRect) {
    NSColor(calibratedWhite:0.16,alpha:1).setFill(); bounds.fill()
    guard let m = model, let original = m.originalImage else { return }
    let rect = imageRect
    NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:rect).addClip()
    NSColor(calibratedWhite:0.8,alpha:1).setFill(); rect.fill()
    NSColor(calibratedWhite:0.65,alpha:1).setFill()
    for y in stride(from:max(rect.minY,bounds.minY),to:min(rect.maxY,bounds.maxY),by:12) {
      for x in stride(from:max(rect.minX,bounds.minX),to:min(rect.maxX,bounds.maxX),by:12) {
        if (Int((x-rect.minX)/12)+Int((y-rect.minY)/12))%2 == 0 { CGRect(x:x,y:y,width:12,height:12).fill() }
      }
    }
    func drawImage(_ image: CGImage,alpha: Double = 1) {
      NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:rect,from:.zero,operation:.sourceOver,fraction:alpha,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
    }
    drawImage(m.preview ? m.image ?? original : original)
    if m.showBackdrop { drawImage(original,alpha:m.backdropOpacity) }
    if let field = m.field {
      let sx = rect.width/Double(field.width), sy = rect.height/Double(field.height)
      if m.showMask {
        // Bounded overlay grid; mask data remains full resolution in the deformation field.
        let step = max(1,Int(ceil(Double(max(field.width,field.height))/200)))
        for y in stride(from:0,to:field.height,by:step) { for x in stride(from:0,to:field.width,by:step) {
          let alpha = field.frozen(x:Double(x)+0.5,y:Double(y)+0.5)
          if alpha > 0 { NSColor.systemRed.withAlphaComponent(Double(alpha)*0.45).setFill(); CGRect(x:rect.minX+Double(x)*sx,y:rect.minY+Double(y)*sy,width:Double(step)*sx+0.5,height:Double(step)*sy+0.5).fill() }
        } }
      }
      if m.showMesh {
        let step = max(8,Int(ceil(Double(max(field.width,field.height))/32)))
        let path = NSBezierPath(); path.lineWidth = 0.6
        func point(_ x: Int,_ y: Int) -> NSPoint {
          let d = field.sample(x:Double(x),y:Double(y))
          return NSPoint(x:rect.minX+(Double(x)+d.x)*sx,y:rect.minY+(Double(y)+d.y)*sy)
        }
        for y in stride(from:0,through:field.height,by:step) {
          path.move(to:point(0,y)); for x in stride(from:step,through:field.width,by:step) { path.line(to:point(x,y)) }
        }
        for x in stride(from:0,through:field.width,by:step) {
          path.move(to:point(x,0)); for y in stride(from:step,through:field.height,by:step) { path.line(to:point(x,y)) }
        }
        NSColor.white.withAlphaComponent(0.65).setStroke(); path.stroke()
      }
    }
    if m.settings.faces.indices.contains(m.selectedFace) {
      let face = m.settings.faces[m.selectedFace].geometry.bounds
      NSColor.systemCyan.setStroke()
      NSBezierPath(rect:CGRect(x:rect.minX+face[0]*rect.width,y:rect.minY+face[1]*rect.height,width:face[2]*rect.width,height:face[3]*rect.height)).stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    if let point = cursorPoint, !m.panTool, !spaceHeld, m.settings.width > 0, m.size.isFinite, (1...15000).contains(m.size) {
      let diameter = m.size*rect.width/Double(m.settings.width)
      let ring = NSBezierPath(ovalIn:CGRect(x:point.x-diameter/2,y:point.y-diameter/2,width:diameter,height:diameter))
      NSColor.black.setStroke(); ring.lineWidth = 2; ring.stroke(); NSColor.white.setStroke(); ring.lineWidth = 0.8; ring.stroke()
    }
  }
  private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow,from:nil) }
  private func coordinates(_ point: CGPoint) -> CGPoint {
    guard let m = model else { return .zero }; let r = imageRect
    return CGPoint(x:(point.x-r.minX)/max(1,r.width)*Double(m.settings.width),y:(point.y-r.minY)/max(1,r.height)*Double(m.settings.height))
  }
  private func pressure(_ event: NSEvent) -> Double { event.subtype == .tabletPoint ? max(0,Double(event.pressure)) : 1 }
  override func mouseDown(with event: NSEvent) {
    beginCursorGesture(event); defer { refreshToolCursor() }
    guard let m = model, m.ready else { return }; window?.makeFirstResponder(self)
    let p = point(event); previous = p; cursorPoint = p; panning = m.panTool || spaceHeld
    guard !panning, imageRect.contains(p) else { return }
    let q = coordinates(p); m.begin(x:q.x,y:q.y,pressure:pressure(event),alternate:event.modifierFlags.contains(.option)); startDabs()
  }
  override func mouseDragged(with event: NSEvent) {
    updateCursorModifiers(event.modifierFlags)
    guard let m = model else { return }; let p = point(event); cursorPoint = p
    if panning, let previous { m.pan.width += p.x-previous.x; m.pan.height += p.y-previous.y }
    else { let q = coordinates(p); m.drag(x:q.x,y:q.y,pressure:pressure(event)) }
    previous = p; needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) { defer { endCursorGesture(event) }; stopDabs(); model?.end(); previous = nil; panning = false; needsDisplay = true }
  override func mouseMoved(with event: NSEvent) { super.mouseMoved(with:event); cursorPoint = point(event); needsDisplay = true }
  override func mouseExited(with event: NSEvent) { super.mouseExited(with:event); cursorPoint = nil; needsDisplay = true }
  override func scrollWheel(with event: NSEvent) {
    guard let m = model else { return }
    if event.modifierFlags.contains(.option) { m.zoom = min(16,max(0.125,m.zoom*exp(-event.scrollingDeltaY*0.01))) }
    else { m.pan.width -= event.scrollingDeltaX; m.pan.height -= event.scrollingDeltaY }
    needsDisplay = true
  }
  override func magnify(with event: NSEvent) { if let m = model { m.zoom = min(16,max(0.125,m.zoom*(1+event.magnification))) } }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === self, event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" else { return super.performKeyEquivalent(with:event) }
    stopDabs(); if event.modifierFlags.contains(.shift) { model?.redo() } else { model?.undo() }; return true
  }
  override func keyDown(with event: NSEvent) {
    updateCursorModifiers(event.modifierFlags); defer { refreshToolCursor() }
    guard let m = model, let key = event.charactersIgnoringModifiers?.lowercased() else { return }
    let map: [String:LiquifyTool] = ["w":.forwardWarp,"r":.reconstruct,"e":.smooth,"c":.twirlCw,"s":.pucker,"b":.bloat,"o":.pushLeft,"f":.freeze,"d":.thaw,"l":.lassoMask]
    if key == " " { spaceHeld = true }
    else if key == "h" { m.panTool = true }
    else if key == "[" { m.size = max(1,m.size/1.1) }
    else if key == "]" { m.size = min(15000,m.size*1.1) }
    else if let tool = map[key] { stopDabs(); m.end(); m.tool = tool; m.panTool = false }
    else { super.keyDown(with:event) }
    needsDisplay = true
  }
  override func keyUp(with event: NSEvent) { if event.charactersIgnoringModifiers == " " { spaceHeld = false; needsDisplay = true } else { super.keyUp(with:event) } }
  private func startDabs() {
    stopDabs()
    guard model?.stroke?.tool.stationary == true else { return }
    dabTask = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(for:.milliseconds(80)) } catch { return }
        guard let self, let m = self.model, let p = m.stroke?.points.last else { return }
        m.drag(x:p[0],y:p[1],pressure:p.count > 2 ? p[2] : 1)
      }
    }
  }
  func stopDabs() { dabTask?.cancel(); dabTask = nil }
}
