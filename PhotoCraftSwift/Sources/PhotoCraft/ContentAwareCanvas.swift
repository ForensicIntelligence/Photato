import AppKit
import SwiftUI

struct ContentAwareCanvas: NSViewRepresentable {
  @Bindable var model: ContentAwareWorkspace
  var preview = false
  func makeNSView(context: Context) -> ContentAwareCanvasView { let v = ContentAwareCanvasView(); v.model = model; v.preview = preview; return v }
  func updateNSView(_ view: ContentAwareCanvasView,context: Context) {
    _ = model.samplingImage; _ = model.previewImage; _ = model.showOriginal; _ = model.zoom; _ = model.pan; _ = model.size; _ = model.stroke
    view.model = model; view.preview = preview; view.needsDisplay = true
  }
}
@MainActor final class ContentAwareCanvasView: NSView {
  weak var model: ContentAwareWorkspace?
  var preview = false
  var image: CGImage? { guard let m = model else { return nil }; return preview ? (m.showOriginal ? m.originalImage:m.previewImage ?? m.originalImage):m.samplingImage }
  private var cursor: CGPoint?
  private var previous: CGPoint?
  private var spaceHeld = false
  private var panning = false
  private var tracking: NSTrackingArea?
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  var imageRect: CGRect {
    guard let m = model,let image = image else { return .zero }
    let fit = min(max(1,bounds.width-24)/Double(image.width),max(1,bounds.height-24)/Double(image.height))*m.zoom
    let size = CGSize(width:Double(image.width)*fit,height:Double(image.height)*fit)
    return CGRect(x:(bounds.width-size.width)/2+m.pan.width,y:(bounds.height-size.height)/2+m.pan.height,width:size.width,height:size.height)
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
    tracking = NSTrackingArea(rect:bounds,options:[.mouseMoved,.mouseEnteredAndExited,.activeInKeyWindow,.inVisibleRect],owner:self); addTrackingArea(tracking!)
  }
  override func draw(_ dirtyRect: NSRect) {
    NSColor(calibratedWhite:0.15,alpha:1).setFill(); bounds.fill()
    guard let m = model,let image = image,let input = m.input else { return }
    let rect = imageRect
    NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height)).draw(in:rect,from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:[.interpolation:NSImageInterpolation.high])
    if let s = m.stroke, s.kind == .lasso {
      let path = NSBezierPath()
      for (i,p) in s.points.enumerated() {
        let point = NSPoint(x:rect.minX+p[0]*rect.width/Double(input.selection.width),y:rect.minY+p[1]*rect.height/Double(input.selection.height))
        if i == 0 { path.move(to:point) } else { path.line(to:point) }
      }
      NSColor.white.setStroke(); path.lineWidth = 1; path.stroke()
    }
    if !preview,let cursor, !spaceHeld, !m.panTool, m.size.isFinite, (1...5000).contains(m.size) {
      let diameter = m.size*rect.width/Double(input.selection.width)
      let path = NSBezierPath(ovalIn:CGRect(x:cursor.x-diameter/2,y:cursor.y-diameter/2,width:diameter,height:diameter))
      NSColor.black.setStroke(); path.lineWidth = 2; path.stroke(); NSColor.white.setStroke(); path.lineWidth = 0.8; path.stroke()
    }
  }
  private func coordinates(_ p: CGPoint) -> CGPoint {
    guard let input = model?.input else { return .zero }; let r = imageRect
    return CGPoint(x:(p.x-r.minX)/max(1,r.width)*Double(input.selection.width),y:(p.y-r.minY)/max(1,r.height)*Double(input.selection.height))
  }
  override func mouseDown(with event: NSEvent) {
    guard let m = model, m.ready else { return }; window?.makeFirstResponder(self)
    let p = convert(event.locationInWindow,from:nil); previous = p; cursor = p; panning = spaceHeld || m.panTool
    if !preview && !panning && imageRect.contains(p) { let q = coordinates(p); m.begin(x:q.x,y:q.y,alternate:event.modifierFlags.contains(.option)) }
  }
  override func mouseDragged(with event: NSEvent) {
    guard let m = model else { return }; let p = convert(event.locationInWindow,from:nil)
    if panning,let previous { m.pan.width += p.x-previous.x; m.pan.height += p.y-previous.y }
    else if !preview { let q = coordinates(p); m.drag(x:q.x,y:q.y) }
    previous = p; cursor = p; needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) { if !preview { model?.end() }; previous = nil; panning = false; needsDisplay = true }
  override func mouseMoved(with event: NSEvent) { cursor = convert(event.locationInWindow,from:nil); needsDisplay = true }
  override func mouseExited(with event: NSEvent) { cursor = nil; needsDisplay = true }
  override func scrollWheel(with event: NSEvent) {
    guard let m = model else { return }
    if event.modifierFlags.contains(.option) { m.zoom = min(16,max(0.125,m.zoom*exp(-event.scrollingDeltaY*0.01))) }
    else { m.pan.width -= event.scrollingDeltaX; m.pan.height -= event.scrollingDeltaY }; needsDisplay = true
  }
  override func magnify(with event: NSEvent) { if let m = model { m.zoom = min(16,max(0.125,m.zoom*(1+event.magnification))) } }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === self,event.modifierFlags.contains(.command),event.charactersIgnoringModifiers?.lowercased() == "z" else { return super.performKeyEquivalent(with:event) }
    if event.modifierFlags.contains(.shift) { model?.redo() } else { model?.undo() }; return true
  }
  override func keyDown(with event: NSEvent) {
    guard let m = model, let key = event.charactersIgnoringModifiers?.lowercased() else { return }
    switch key {
    case " ": spaceHeld = true
    case "h": m.panTool = true
    case "b": m.tool = .sampling; m.kind = .brush; m.panTool = false
    case "e": m.add.toggle()
    case "l": m.tool = .selection; m.kind = .lasso; m.panTool = false
    case "[": m.size = max(1,m.size/1.1)
    case "]": m.size = min(5000,m.size*1.1)
    case "x": m.showOriginal = true
    default: super.keyDown(with:event)
    }; needsDisplay = true
  }
  override func keyUp(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " { spaceHeld = false }
    else if event.charactersIgnoringModifiers?.lowercased() == "x" { model?.showOriginal = false }
    else { super.keyUp(with:event) }; needsDisplay = true
  }
}
