import AppKit
import Combine
import PhotoCraftCore
import PhotoCraftImaging
import SwiftUI

struct CanvasHost: NSViewRepresentable {
  var store: EditorStore
  var image: CGImage?
  var revision: Int
  var zoom: Double
  var pan: CGSize
  var selection: IntRect?
  var showRulers: Bool
  var showLayerBounds: Bool
  var activateDocument: () -> Bool = { true }
  func makeNSView(context: Context) -> CraftCanvas { CraftCanvas(store: store) }
  func updateNSView(_ view: CraftCanvas, context: Context) {
    _ = store.shapeGesture; _ = store.frameGesture; _ = store.frameTarget; _ = store.artboardGesture; _ = store.showArtboardNames; _ = store.showArtboardGuides
    view.store = store
    view.activateDocument = activateDocument
    view.synchronizeTool()
    view.synchronizeFrameProbe()
    if store.brushGesture == nil && store.cloneDraft == nil { view.drawingEvents.end() }
    _ = store.typeEditingDraft?.content
    view.synchronizeTypeEditor()
    _ = store.peopleWorkspace.image
    _ = store.objectFinder.image
    store.refreshObjectFinderIfNeeded()
    _ = store.canvasRasterPreview
    _ = store.selectionOverlayImage
    _ = store.displayedMaskImage
    _ = store.cloneOverlay
    _ = store.gradientGesture
    _ = store.gradientSelectedStop
    _ = store.gradientOptions.mode
    _ = store.cloneState.slot
    _ = store.cloneState.showOverlay
    _ = store.cloneState.overlayOpacity
    _ = store.cloneState.clippedOverlay
    _ = store.cloneState.autoHideOverlay
    _ = store.cloneState.overlayBlend
    store.refreshCloneOverlay()
    view.needsDisplay = true
    view.window?.invalidateCursorRects(for: view)
  }
}
@MainActor final class CraftCanvas: NSView {
  var store: EditorStore
  var typeOverlay: CanvasTypeEditor?
  var activateDocument: () -> Bool = { true }
  var viewportUpdateQueued = false
  var cloneHover: CGPoint?
  var cloneTracking: NSTrackingArea?
  let checkerboard = CanvasCheckerboard()
  let drawingEvents = DrawingEventCapture()
  var frameProbe: CanvasFrameProbe?
  var drawingFocusObservation: AnyCancellable?
  var samples: [StrokePoint] = []
  var brushStartTime: TimeInterval = 0
  var airbrushTimer: Timer?
  var start: CGPoint?
  var end: CGPoint?
  var dragLayerOrigin = CGPoint.zero
  var dragPanOrigin = CGSize.zero
  var spaceHeld = false
  var panningGesture = false
  var dragModifiers: NSEvent.ModifierFlags = []
  var cropStart: CropDraft?
  var cropHandle = -1
  var cropLineGesture = false
  var transformStart: TransformDraft?
  var gradientDragStart: GradientFill?
  var patternDragStart: PatternFill?
  var transformHandle = -1
  var regionRetouchStart: RegionRetouchDraft?
  var regionRetouchHandle = -1
  var regionRetouchSelecting = false
  var lassoPoints: [SelectionPoint] = []
  var polygonPoints: [SelectionPoint] = []
  var selectionDragMode = SelectionMode.replace
  var selectionStartModifiers: NSEvent.ModifierFlags = []
  var gestureToolID: String
  init(store: EditorStore) {
    self.store = store
    gestureToolID = store.selectedTool.id
    super.init(frame: .zero)
    wantsLayer = true
    clipsToBounds = true
    layer?.masksToBounds = true
    registerForDraggedTypes([.string])
  }
  isolated deinit { frameProbe?.invalidate(); airbrushTimer?.invalidate() }
  required init?(coder: NSCoder) { return nil }
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    synchronizeFrameProbe()
    if window == nil { drawingEvents.end(); airbrushTimer?.invalidate();airbrushTimer=nil;store.cancelBrush() }
    drawingFocusObservation = window.map { target in
      NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
        .sink { [weak self, weak target] note in
          guard let target, note.object as? NSWindow === target else { return }
          MainActor.assumeIsolated {
            self?.drawingEvents.end()
            self?.airbrushTimer?.invalidate(); self?.airbrushTimer = nil
            self?.store.cancelBrush(); self?.store.cancelClone()
          }
        }
    }
    WorkspaceLayoutDiagnostics.log("canvas.attached", ["hasWindow": window != nil])
    window?.makeFirstResponder(self)
  }
  func synchronizeTool() {
    guard gestureToolID != store.selectedTool.id else { return }
    gestureToolID = store.selectedTool.id
    drawingEvents.end()
    store.cancelClone()
    airbrushTimer?.invalidate();airbrushTimer=nil;store.cancelBrush()
    store.cancelGradientGesture()
    cloneHover = nil
    store.resetPathGesture()
    polygonPoints = []
    lassoPoints = []
    samples = []
    start = nil
    end = nil
    panningGesture = false
    cropStart = nil; cropLineGesture = false
    regionRetouchStart = nil;regionRetouchSelecting = false
  }
  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { true }
  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    guard let value = sender.draggingPasteboard.string(forType: .string),
      store.gradientCanvasDrop(value) != nil
    else { return [] }
    return .copy
  }
  override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
    draggingEntered(sender)
  }
  override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    draggingEntered(sender) == .copy
  }
  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let value = sender.draggingPasteboard.string(forType: .string),
      let id = store.gradientCanvasDrop(value)
    else { return false }
    guard activateDocument() else { return false }
    store.activateGradientPreset(id)
    return true
  }
  override func layout() {
    super.layout()
    queueViewportUpdate()
    synchronizeTypeEditor()
  }
  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    queueViewportUpdate()
    needsDisplay = true
  }
  func queueViewportUpdate() {
    guard !viewportUpdateQueued else { return }
    viewportUpdateQueued = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      viewportUpdateQueued = false
      guard window != nil else { return }
      synchronizeViewport()
    }
  }
  func synchronizeViewport() {
    guard bounds.width > 0, bounds.height > 0 else { return }
    store.updateViewport(size: bounds.size, backingScale: Double(window?.backingScaleFactor ?? 1))
  }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let cloneTracking { removeTrackingArea(cloneTracking) }
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
      owner: self)
    addTrackingArea(area)
    cloneTracking = area
  }
  override func mouseMoved(with event: NSEvent) {
    if store.tool == .objectSelection {let p=docPoint(event);store.hoverObject(at:.init(p.x,p.y));needsDisplay=true;return}
    guard store.tool.usesRetouchStroke else { return }
    let previous = cloneHover
    cloneHover = docPoint(event)
    store.refreshCloneOverlay()
    invalidateRetouchFeedback(from: previous)
  }
  override func mouseExited(with event: NSEvent) {
    let previous = cloneHover
    store.clearObjectHover()
    cloneHover = nil
    if store.tool.usesRetouchStroke { invalidateRetouchFeedback(from: previous) }
    else { needsDisplay = true }
  }
  func drawCloneOverlay(in c: CGContext) {
    guard store.tool.usesRetouchStroke, let hover = cloneHover else { return }
    let state = store.cloneState
    let mapping =
      store.tool.samplesRetouchSource
      ? (store.cloneDraft?.mapping
        ?? (try? state.slot.mapping(
          at: PathPoint(hover.x, hover.y), target: store, aligned: store.retouchSettings.aligned)))
      : nil
    let center = viewPoint(hover)
    let radius = store.retouchSettings.brush.size * scale / 2
    c.saveGState()
    c.clip(to: imageRect)
    if store.tool.samplesRetouchSource, state.showOverlay,
      !(state.autoHideOverlay && store.cloneDraft != nil),
      let overlay = store.cloneOverlay, let mapping,
      let inverse = try? mapping.transform().inverted()
    {
      c.saveGState()
      if state.clippedOverlay {
        c.addEllipse(
          in: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        c.clip()
      }
      c.setAlpha(CGFloat(state.overlayOpacity))
      c.setBlendMode(state.overlayBlend.cgMode)
      let t = inverse * overlay.transform
      if overlay.outside.a > 0 {
        // Draw the mask's implicit outside coverage only outside its stored rectangle.
        // Filling beneath the image as well would apply overlay opacity twice.
        c.saveGState()
        c.addRect(imageRect)
        let corners = [
          t.point(0, 0), t.point(Double(overlay.image.width), 0),
          t.point(Double(overlay.image.width), Double(overlay.image.height)),
          t.point(0, Double(overlay.image.height)),
        ].map { viewPoint(CGPoint(x: $0.x, y: $0.y)) }
        c.move(to: corners[0])
        for corner in corners.dropFirst() { c.addLine(to: corner) }
        c.closePath()
        c.clip(using: .evenOdd)
        let p = overlay.outside
        c.setFillColor(
          NSColor(
            srgbRed: CGFloat(p.r), green: CGFloat(p.g), blue: CGFloat(p.b), alpha: CGFloat(p.a)
          ).cgColor)
        c.fill(imageRect)
        c.restoreGState()
      }
      c.translateBy(x: imageRect.minX, y: imageRect.minY)
      c.scaleBy(x: scale, y: scale)
      c.concatenate(CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty))
      c.translateBy(x: 0, y: CGFloat(overlay.image.height))
      c.scaleBy(x: 1, y: -1)
      c.draw(
        overlay.image,
        in: CGRect(x: 0, y: 0, width: overlay.image.width, height: overlay.image.height))
      c.restoreGState()
    }
    c.setLineWidth(1)
    c.setStrokeColor(NSColor.white.cgColor)
    c.strokeEllipse(
      in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    c.setStrokeColor(NSColor.black.cgColor)
    c.strokeEllipse(
      in: CGRect(
        x: center.x - radius - 1, y: center.y - radius - 1, width: radius * 2 + 2,
        height: radius * 2 + 2))
    if state.slot.store === store, let mapping, let t = try? mapping.transform() {
      let point = t.point(hover.x, hover.y)
      let p = viewPoint(CGPoint(x: point.x, y: point.y))
      c.setStrokeColor(NSColor.white.cgColor)
      c.setLineWidth(3)
      for width in [3.0, 1.0] {
        c.setLineWidth(width)
        c.setStrokeColor(width == 3 ? NSColor.black.cgColor : NSColor.white.cgColor)
        c.move(to: CGPoint(x: p.x - 6, y: p.y))
        c.addLine(to: CGPoint(x: p.x + 6, y: p.y))
        c.move(to: CGPoint(x: p.x, y: p.y - 6))
        c.addLine(to: CGPoint(x: p.x, y: p.y + 6))
        c.strokePath()
      }
    }
    c.restoreGState()
  }
  override func resetCursorRects() {
    let cursor: NSCursor =
      store.unavailableToolID != nil
      ? .operationNotAllowed
      : (spaceHeld || store.tool == .hand)
        ? .openHand : store.tool == .move ? .arrow : [.text,.verticalText].contains(store.tool) ? .iBeam : .crosshair
    addCursorRect(bounds, cursor: cursor)
  }
  var viewport: CanvasViewport {
    CanvasViewport(
      documentSize: CGSize(width: store.document.width, height: store.document.height),
      size: bounds.size, backingScale: Double(window?.backingScaleFactor ?? 1), zoom: store.zoom,
      pan: store.pan)
  }
  var scale: CGFloat { viewport.scale }
  var imageRect: CGRect { viewport.imageRect }
  func docPoint(_ event: NSEvent) -> CGPoint {
    viewport.documentPoint(at: convert(event.locationInWindow, from: nil))
  }
  override func draw(_ dirtyRect: NSRect) {
    guard let c = NSGraphicsContext.current?.cgContext else { return }
    // Zoomed/panned image bounds, shadows and tool overlays may exceed the viewport.
    let drawTrace = store.canvasFrameTrace?.beginDraw()
    defer { store.canvasFrameTrace?.drew(drawTrace) }
    c.saveGState()
    defer { c.restoreGState() }
    c.clip(to: bounds)
    NSColor(srgbRed: 0.17, green: 0.17, blue: 0.17, alpha: 1).setFill()
    bounds.fill()
    let r = imageRect
    c.saveGState()
    c.setShadow(
      offset: CGSize(width: 0, height: 6), blur: 22,
      color: NSColor.black.withAlphaComponent(0.35).cgColor)
    c.setFillColor(NSColor.white.cgColor)
    c.fill(r)
    c.restoreGState()
    c.saveGState()
    c.clip(to: r)
    let cell: CGFloat = max(2, 8 * scale)
    checkerboard.draw(in: c, viewport: bounds, imageRect: r, cell: cell,
      backing: CGFloat(window?.backingScaleFactor ?? 1))
    if let preview = store.canvasRasterPreview {
      c.saveGState(); c.translateBy(x: r.minX, y: r.minY); c.scaleBy(x: scale, y: scale)
      c.interpolationQuality = viewport.resolvedZoom >= 1 ? .none : .high
      preview.draw(in: c); c.restoreGState()
    } else if let image = store.image {
      c.saveGState()
      c.translateBy(x: r.minX, y: r.maxY)
      c.scaleBy(x: 1, y: -1)
      c.interpolationQuality = viewport.resolvedZoom >= 1 ? .none : .high
      c.draw(image, in: CGRect(origin: .zero, size: r.size))
      c.restoreGState()
    }
    if let maskImage = store.tool == .selectionBrush ? store.selectionOverlayImage:store.displayedMaskImage {
      c.saveGState()
      c.translateBy(x: r.minX, y: r.maxY)
      c.scaleBy(x: 1, y: -1)
      c.interpolationQuality = viewport.resolvedZoom >= 1 ? .none : .high
      c.draw(maskImage, in: CGRect(origin: .zero, size: r.size))
      c.restoreGState()
    }
    if store.tool == .objectSelection, store.canFindObjects, let overlay = store.peopleWorkspace.image ?? (store.objectFinderEnabled ? store.objectFinder.image:nil) {
      c.saveGState();c.translateBy(x:r.minX,y:r.maxY);c.scaleBy(x:1,y:-1)
      c.draw(overlay,in:CGRect(origin:.zero,size:r.size));c.restoreGState()
    }
    c.restoreGState()
    drawCloneOverlay(in: c)
    drawGradientOverlay(in: c)
    drawVectorPath(in: c)
    if store.selectionPath != nil && store.tool != .selectionBrush {
      if let path = store.selectionPath {
        c.saveGState()
        c.translateBy(x: r.minX, y: r.minY)
        c.scaleBy(x: scale, y: scale)
        c.setLineWidth(1 / scale)
        c.setStrokeColor(NSColor.white.cgColor)
        c.addPath(path)
        c.strokePath()
        c.setStrokeColor(NSColor.black.cgColor)
        c.setLineDash(phase: 0, lengths: [4 / scale, 4 / scale])
        c.addPath(path)
        c.strokePath()
        c.restoreGState()
      }
    } else if let s = store.document.selection,store.tool != .selectionBrush {
      outline(
        CGRect(
          x: r.minX + CGFloat(s.x) * scale, y: r.minY + CGFloat(s.y) * scale,
          width: CGFloat(s.width) * scale, height: CGFloat(s.height) * scale), in: c)
    }
    if let a = start, let b = end,
      ([.marquee, .ellipticalMarquee].contains(store.tool) || (store.tool == .objectSelection && store.objectSelectionMode == .rectangle)),
      !panningGesture
    {
      if let rect = Self.dragRect(
        from: a, to: b,
        flags: [.marquee, .ellipticalMarquee].contains(store.tool)
          ? dragModifiers.subtracting(selectionStartModifiers) : dragModifiers,
        width: store.document.width, height: store.document.height,
        clipToCanvas: store.tool != .ellipticalMarquee)
      {
        let q = CGRect(
          x: r.minX + CGFloat(rect.x) * scale, y: r.minY + CGFloat(rect.y) * scale,
          width: CGFloat(rect.width) * scale, height: CGFloat(rect.height) * scale)
        if store.tool == .ellipticalMarquee {
          c.saveGState()
          c.clip(to: imageRect)
          c.setStrokeColor(NSColor.white.cgColor)
          c.setLineWidth(1)
          c.strokeEllipse(in: q)
          c.setStrokeColor(NSColor.black.cgColor)
          c.setLineDash(phase: 0, lengths: [4, 4])
          c.strokeEllipse(in: q)
          c.restoreGState()
        } else {
          outline(q, in: c)
        }
      }
    }
    let pathPoints =
      (store.tool == .lasso || store.tool.isRetouchSelectionTool || (store.tool == .objectSelection && store.objectSelectionMode == .lasso)) ? lassoPoints : store.tool == .polygonLasso ? polygonPoints : []
    if !pathPoints.isEmpty {
      c.saveGState()
      c.clip(to: imageRect)
      c.setStrokeColor(NSColor.systemBlue.cgColor)
      c.setLineWidth(1)
      for (index, point) in pathPoints.enumerated() {
        let p = viewPoint(CGPoint(x: point.x, y: point.y))
        if index == 0 { c.move(to: p) } else { c.addLine(to: p) }
      }
      if let end, store.tool == .polygonLasso { c.addLine(to: viewPoint(end)) }
      c.strokePath()
      c.restoreGState()
    }
    drawArtboards(in: c)
    drawShapeGesture(in:c)
    drawFrames(in: c)
    drawCrop(in:c)
    drawRegionRetouch(in:c)
    if let draft = store.transformDraft {
      drawTransform(draft, in: c)
    } else if store.showLayerBounds, store.tool == .move,
      let boxInDocument = store.activeLayerBounds
    {
      let box = CGRect(
        x: r.minX + CGFloat(boxInDocument.x) * scale, y: r.minY + CGFloat(boxInDocument.y) * scale,
        width: CGFloat(boxInDocument.width) * scale, height: CGFloat(boxInDocument.height) * scale)
      c.setStrokeColor(NSColor.systemBlue.cgColor)
      c.setLineWidth(1)
      c.stroke(box)
    }
    if store.showRulers { drawRulers(in: c, imageRect: r) }
  }
  func viewPoint(_ p: CGPoint) -> CGPoint {
    CGPoint(x: imageRect.minX + p.x * scale, y: imageRect.minY + p.y * scale)
  }
  func drawTransform(_ draft: TransformDraft, in c: CGContext) {
    let points = draft.handles.map(viewPoint)
    c.setLineDash(phase: 0, lengths: [])
    c.setStrokeColor(NSColor.systemBlue.cgColor)
    c.setLineWidth(1)
    c.move(to: points[0])
    for index in [2, 4, 6] { c.addLine(to: points[index]) }
    c.closePath()
    c.strokePath()
    for p in points {
      let box = CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)
      c.setFillColor(NSColor.white.cgColor)
      c.fill(box)
      c.stroke(box)
    }
    let center = viewPoint(CGPoint(x: draft.centerX, y: draft.centerY))
    c.move(to: CGPoint(x: center.x - 5, y: center.y))
    c.addLine(to: CGPoint(x: center.x + 5, y: center.y))
    c.move(to: CGPoint(x: center.x, y: center.y - 5))
    c.addLine(to: CGPoint(x: center.x, y: center.y + 5))
    c.strokePath()
  }
  func drawRulers(in c: CGContext, imageRect r: CGRect) {
    c.setFillColor(NSColor(calibratedWhite: 0.28, alpha: 1).cgColor)
    c.fill(CGRect(x: 0, y: 0, width: bounds.width, height: 18))
    c.fill(CGRect(x: 0, y: 0, width: 18, height: bounds.height))
    let step = pow(10, floor(log10(max(1, 80 / scale))))
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.lightGray,
    ]
    c.setStrokeColor(NSColor.lightGray.cgColor)
    c.setLineWidth(0.5)
    for value in stride(
      from: floor(-r.minX / scale / step) * step, through: (bounds.width - r.minX) / scale, by: step
    ) {
      let x = r.minX + value * scale
      c.move(to: CGPoint(x: x, y: 13))
      c.addLine(to: CGPoint(x: x, y: 18))
      c.strokePath()
      "\(Int(value))".draw(at: CGPoint(x: x + 2, y: 1), withAttributes: attrs)
    }
    for value in stride(
      from: floor(-r.minY / scale / step) * step, through: (bounds.height - r.minY) / scale,
      by: step)
    {
      let y = r.minY + value * scale
      c.move(to: CGPoint(x: 13, y: y))
      c.addLine(to: CGPoint(x: 18, y: y))
      c.strokePath()
      c.saveGState()
      c.translateBy(x: 2, y: y + 2)
      c.rotate(by: -.pi / 2)
      "\(Int(value))".draw(at: .zero, withAttributes: attrs)
      c.restoreGState()
    }
  }
  func outline(_ rect: CGRect, in c: CGContext) {
    c.setLineWidth(1)
    c.setStrokeColor(NSColor.white.cgColor)
    c.setLineDash(phase: 0, lengths: [])
    c.stroke(rect)
    c.setStrokeColor(NSColor.black.cgColor)
    c.setLineDash(phase: 0, lengths: [4, 4])
    c.stroke(rect)
    c.setLineDash(phase: 0, lengths: [])
  }
  func drawVectorPath(in c: CGContext) {
    guard store.usesPathTool || store.layersTab == .paths,
      let path = store.displayedVectorPath, let outline = try? VectorRasterizer.outline(path)
    else { return }
    c.saveGState()
    c.translateBy(x: imageRect.minX, y: imageRect.minY)
    c.scaleBy(x: scale, y: scale)
    c.setStrokeColor(NSColor.systemBlue.cgColor)
    c.setLineWidth(1.5 / scale)
    c.addPath(outline)
    c.strokePath()
    for (i, component) in path.components.enumerated() {
      for (j, knot) in component.knots.enumerated() {
        let selected = store.pathAnchor == PathAnchorSelection(component: i, knot: j)
        if selected {
          c.setLineWidth(1 / scale)
          for handle in [knot.incoming, knot.outgoing] where handle != knot.anchor {
            c.move(to: CGPoint(x: knot.anchor.x, y: knot.anchor.y))
            c.addLine(to: CGPoint(x: handle.x, y: handle.y))
            c.strokePath()
            c.setFillColor(NSColor.systemBlue.cgColor)
            c.fillEllipse(
              in: CGRect(
                x: handle.x - 2.5 / scale, y: handle.y - 2.5 / scale,
                width: 5 / scale, height: 5 / scale))
          }
        }
        let box = CGRect(
          x: knot.anchor.x - 3 / scale, y: knot.anchor.y - 3 / scale,
          width: 6 / scale, height: 6 / scale)
        c.setFillColor((selected ? NSColor.systemBlue : NSColor.white).cgColor)
        c.fill(box)
        c.stroke(box)
      }
    }
    c.restoreGState()
  }
  override func mouseDown(with event: NSEvent) {
    guard activateDocument() else { return }
    synchronizeTool()
    if store.typeEditingDraft != nil, !store.finishType() { return }
    synchronizeTypeEditor()
    window?.makeFirstResponder(self)
    guard !store.geometryBusy else { return }
    guard spaceHeld || store.canUseComponentCanvasTool else {
      store.status = "This tool is not available for individual channels yet. Select RGB to use it."
      return
    }
    if let draft = store.gradientFillDraft {
      start = docPoint(event)
      gradientDragStart = draft.fill
      return
    }
    if let draft = store.patternFillDraft {
      start = docPoint(event)
      patternDragStart = draft.fill.linked ? draft.fill : nil
      return
    }
    guard store.unavailableToolID == nil else { return }
    let p = docPoint(event)
    if beginShapeGesture(event,at:p) { return }
    if beginFrameGesture(event, at: p) { return }
    if beginArtboardGesture(event, at: p) { return }
    if beginCropGesture(event,at:p) { return }
    if beginRegionRetouchGesture(event,at:p) { return }
    if let draft = store.transformDraft, !spaceHeld {
      transformStart = draft
      start = p
      let nearest = draft.handles.enumerated().min {
        hypot($0.element.x - p.x, $0.element.y - p.y)
          < hypot($1.element.x - p.x, $1.element.y - p.y)
      }
      if let nearest, hypot(nearest.element.x - p.x, nearest.element.y - p.y) * scale < 10 {
        transformHandle = nearest.offset
      } else {
        let inverse = try? draft.delta.inverted()
        let local = inverse?.point(p.x, p.y)
        let inside =
          local.map {
            $0.x >= Double(draft.bounds.x) && $0.y >= Double(draft.bounds.y)
              && $0.x <= Double(draft.bounds.x + draft.bounds.width)
              && $0.y <= Double(draft.bounds.y + draft.bounds.height)
          } ?? false
        transformHandle = inside ? -1 : 8
      }
      return
    }
    if (store.tool == .magicWand || store.tool == .paintBucket) && !spaceHeld {
      store.colorRegionClick(at: PathPoint(p.x, p.y), modifiers: event.modifierFlags)
      return
    }
    if store.tool == .objectSelection && store.objectSelectionMode == .point && !spaceHeld {
      store.selectObject(point:.init(p.x,p.y),mode:store.selectionToolMode(modifiers:event.modifierFlags));return
    }
    if store.tool == .mixerBrush && !spaceHeld && event.modifierFlags.contains(.option) {
      store.sampleMixer(at:PathPoint(p.x,p.y));return
    }
    if store.tool == .adjustmentBrush && store.adjustmentBrushObject && !spaceHeld {
      store.applyAdjustmentObject(at:PathPoint(p.x,p.y),alternate:event.modifierFlags.contains(.option));return
    }
    if store.tool == .magicEraser && !spaceHeld {
      brushStartTime=event.timestamp;samples=[];store.beginBrush(brushSample(event),zoom:viewport.resolvedZoom);store.finishBrush();return
    }
    if store.tool == .gradient && !spaceHeld {
      store.beginGradient(at: PathPoint(p.x, p.y), zoom: scale, clickCount: event.clickCount)
      needsDisplay = true
      return
    }
    if store.tool.usesRetouchStroke && !spaceHeld {
      cloneHover = p
      if store.tool.samplesRetouchSource && event.modifierFlags.contains(.option) {
        store.setCloneSource(at: PathPoint(p.x, p.y))
      } else {
        start = p
        store.beginClone(
          StrokePoint(
            x: p.x, y: p.y, pressure: event.subtype == .tabletPoint ? unit(event.pressure) : 1),
          alternate: event.modifierFlags.contains(.option), eventTimestamp: event.timestamp)
        if store.cloneDraft != nil { drawingEvents.begin(); synchronizeFrameProbe() }
      }
      needsDisplay = true
      return
    }
    if store.usesPathTool && !spaceHeld {
      store.beginPath(
        at: PathPoint(p.x, p.y), tolerance: 6 / scale,
        option: event.modifierFlags.contains(.option), clickCount:event.clickCount)
      needsDisplay = true
      return
    }
    dragModifiers = event.modifierFlags
    if store.tool != .polygonLasso { polygonPoints = [] }
    if !spaceHeld && store.tool == .polygonLasso {
      if polygonPoints.isEmpty {
        selectionDragMode = store.selectionMode(modifiers: event.modifierFlags)
      }
      let closesPath =
        polygonPoints.count >= 3
        && polygonPoints.first.map {
          hypot($0.x - p.x, $0.y - p.y) * scale < 6
        } == true
      if event.clickCount >= 2 || closesPath {
        finishPolygon()
      } else {
        polygonPoints.append(SelectionPoint(p.x, p.y))
      }
      needsDisplay = true
      return
    }
    selectionStartModifiers = event.modifierFlags.intersection([.shift, .option])
    selectionDragMode = store.selectionMode(modifiers: selectionStartModifiers)
    lassoPoints = []
    if (store.tool == .lasso || (store.tool == .objectSelection && store.objectSelectionMode == .lasso)) && !spaceHeld { lassoPoints.append(SelectionPoint(p.x, p.y)) }
    panningGesture = spaceHeld || store.tool == .hand
    if store.tool == .move && store.autoSelect && !store.editingMask && !panningGesture {
      store.autoSelectLayer(at: p)
    }
    start = p
    end = p
    samples = []
    dragPanOrigin = store.pan
    if let l = store.activeLayer { dragLayerOrigin = CGPoint(x: l.x, y: l.y) }
    if panningGesture { return }
    if store.tool.usesPaintingStroke {
      brushStartTime=event.timestamp
      let point=brushSample(event);samples=[point];store.beginBrush(point,zoom:viewport.resolvedZoom,alternate:event.modifierFlags.contains(.option),selectionMode:store.selectionToolMode(modifiers:event.modifierFlags),eventTimestamp:event.timestamp)
      if store.brushGesture != nil { drawingEvents.begin(); synchronizeFrameProbe() }
      synchronizeBrushClock()
    }
    if store.tool == .eyedropper, let s = store.surface {
      let x = Int(p.x)
      let y = Int(p.y)
      if x >= 0, y >= 0, x < s.width, y < s.height { store.brush.color = s.pixel(x: x, y: y) }
    }
    needsDisplay = true
  }
  func brushSample(_ e:NSEvent)->StrokePoint {
    let p=docPoint(e),tablet=e.subtype == .tabletPoint
    return .init(x:p.x,y:p.y,pressure:tablet ? unit(e.pressure):1,
      tiltX:tablet ? Double(e.tilt.x)*90:nil,tiltY:tablet ? Double(e.tilt.y)*90:nil,
      rotation:tablet ? Double(e.rotation):nil,wheel:tablet ? (Double(e.tangentialPressure)+1)/2:nil,
      time:max(samples.last?.time ?? 0,(e.timestamp-brushStartTime)*1000))
  }
  func addSample(_ e:NSEvent) {
    guard store.brushGesture != nil,samples.count<100_000 else { return }
    let point=brushSample(e);samples.append(point);store.extendBrush(point,eventTimestamp:e.timestamp)
    if e.type == .leftMouseDragged { synchronizeBrushClock() }
  }
  func synchronizeBrushClock() {
    guard store.brushGesture?.needsStationarySample == true else {
      airbrushTimer?.invalidate(); airbrushTimer = nil; return
    }
    guard airbrushTimer == nil else { return }
    let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.advanceBrushClock() }
    }
    airbrushTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }
  func advanceBrushClock() {
    guard window?.isVisible == true, store.selectedTool.id == gestureToolID,
      samples.count < 100_000 else {
      airbrushTimer?.invalidate(); airbrushTimer = nil; store.cancelBrush(); return
    }
    let time = (ProcessInfo.processInfo.systemUptime - brushStartTime) * 1000
    guard time <= 3_600_000 else { airbrushTimer?.invalidate(); airbrushTimer = nil; return }
    if let point = store.advanceStationaryBrush(time: time) { samples.append(point) }
    synchronizeBrushClock()
  }
  override func mouseDragged(with event: NSEvent) {
    if dragShapeGesture(event) { return }
    if dragFrameGesture(event) { return }
    if dragArtboardGesture(event) { return }
    if dragCropGesture(event) { return }
    if dragRegionRetouchGesture(event) { return }
    if store.gradientGesture != nil {
      let p = docPoint(event)
      store.dragGradient(to: PathPoint(p.x, p.y), shift: event.modifierFlags.contains(.shift))
      needsDisplay = true
      return
    }
    if store.gradientFillDraft != nil {
      if let initial = gradientDragStart, let start {
        let p = docPoint(event)
        store.dragGradientFill(from: initial, x: p.x - start.x, y: p.y - start.y)
      }
      return
    }
    if store.patternFillDraft != nil {
      if let initial = patternDragStart, let start {
        let p = docPoint(event)
        store.dragPatternFill(from: initial, x: p.x - start.x, y: p.y - start.y)
      }
      return
    }
    if store.cloneDraft != nil {
      let previous = cloneHover
      let p = docPoint(event)
      cloneHover = p
      store.extendClone(
        StrokePoint(
          x: p.x, y: p.y, pressure: event.subtype == .tabletPoint ? unit(event.pressure) : 1), eventTimestamp: event.timestamp)
      invalidateRetouchFeedback(from: previous)
      return
    }
    if store.freeformGesture != nil {let p=docPoint(event);store.extendFreeform(to:.init(p.x,p.y));needsDisplay=true;return}
    if store.pathGesture != nil {
      let p = docPoint(event)
      store.dragPath(to: PathPoint(p.x, p.y), option: event.modifierFlags.contains(.option))
      needsDisplay = true
      return
    }
    if let original = transformStart, let start {
      store.updateTransform(
        original.dragging(
          handle: transformHandle, from: start, to: docPoint(event),
          shift: event.modifierFlags.contains(.shift), option: event.modifierFlags.contains(.option)
        ))
      needsDisplay = true
      return
    }
    guard store.unavailableToolID == nil else { return }
    end = docPoint(event)
    dragModifiers = event.modifierFlags
    if !panningGesture && store.tool.usesPaintingStroke {
      addSample(event)
      // CanvasHost invalidates when a prepared preview is published. Input alone
      // does not change the displayed pixels or a painting gesture overlay.
      return
    }
    if !panningGesture && (store.tool == .lasso || (store.tool == .objectSelection && store.objectSelectionMode == .lasso)), let end, lassoPoints.count < 100_000 {
      lassoPoints.append(SelectionPoint(end.x, end.y))
    }
    if panningGesture {
      store.pan.width += event.deltaX
      store.pan.height += event.deltaY
    }
    needsDisplay = true
  }
  override func mouseUp(with event: NSEvent) {
    defer { synchronizeFrameProbe() }
    drawingEvents.end()
    airbrushTimer?.invalidate();airbrushTimer=nil
    defer {
      start = nil
      end = nil
      samples = []
      lassoPoints = []
      panningGesture = false
      transformStart = nil
      cropStart = nil; cropLineGesture = false
      patternDragStart = nil
      gradientDragStart = nil
      needsDisplay = true
    }
    if endShapeGesture(event) { return }
    if endFrameGesture(event) { return }
    if endArtboardGesture(event) { return }
    if endCropGesture(event) { return }
    if endRegionRetouchGesture(event) { return }
    if store.gradientGesture != nil {
      let p = docPoint(event)
      store.dragGradient(to: PathPoint(p.x, p.y), shift: event.modifierFlags.contains(.shift))
      store.finishGradient()
      return
    }
    if store.gradientFillDraft != nil {
      if let initial = gradientDragStart, let start {
        let p = docPoint(event)
        store.dragGradientFill(from: initial, x: p.x - start.x, y: p.y - start.y)
      }
      return
    }
    if store.patternFillDraft != nil {
      if let initial = patternDragStart, let start {
        let p = docPoint(event)
        store.dragPatternFill(from: initial, x: p.x - start.x, y: p.y - start.y)
      }
      return
    }
    if store.cloneDraft != nil {
      let p = docPoint(event)
      cloneHover = p
      store.extendClone(
        StrokePoint(
          x: p.x, y: p.y, pressure: event.subtype == .tabletPoint ? unit(event.pressure) : 1), eventTimestamp: event.timestamp)
      store.finishClone()
      return
    }
    if store.freeformGesture != nil {let p=docPoint(event);store.extendFreeform(to:.init(p.x,p.y));store.finishFreeform();return}
    if store.pathGesture != nil {
      store.endPathGesture()
      return
    }
    if transformStart != nil { return }
    guard let a = start, store.unavailableToolID == nil, !panningGesture else { return }
    let b = docPoint(event)
    switch store.tool {
    case .quickSelection,.selectionBrush,.adjustmentBrush, .brush, .eraser, .pencil, .colorReplacement, .mixerBrush, .patternStamp, .backgroundEraser:
      addSample(event);store.finishBrush()
    case .move:
      if let l = store.activeLayer {
        if store.editingMask && !l.effectiveMaskProperties.linked {
          let delta = Transform2D.translation((b.x - a.x).rounded(), (b.y - a.y).rounded())
          if let inverse = try? l.coordinateTransform.inverted() {
            store.updateMask(l.id) { $0.transform = inverse * delta * l.maskCoordinateTransform }
          }
        } else {
          store.perform(
            .move(l.id, Int(dragLayerOrigin.x + b.x - a.x), Int(dragLayerOrigin.y + b.y - a.y)))
        }
      }
    case .objectSelection:
      if hypot(b.x-a.x,b.y-a.y)*scale<3 {store.selectObject(point:.init(b.x,b.y),mode:selectionDragMode)}
      else if store.objectSelectionMode == .lasso {
        lassoPoints.append(.init(b.x,b.y));if lassoPoints.count>=3{store.selectObject(shape:.polygon(lassoPoints),mode:selectionDragMode)}
      } else if let rect=Self.dragRect(from:a,to:b,flags:[],width:store.document.width,height:store.document.height) {store.selectObject(shape:.rectangle(rect),mode:selectionDragMode)}
    case .lasso:
      lassoPoints.append(SelectionPoint(b.x, b.y))
      if lassoPoints.count >= 3 {
        store.selectShape(.polygon(lassoPoints), mode: selectionDragMode)
      }
    case .marquee, .ellipticalMarquee:
      if let rect = Self.dragRect(
        from: a, to: b,
        flags: event.modifierFlags.subtracting(selectionStartModifiers),
        width: store.document.width, height: store.document.height, clipToCanvas: false)
      {
        store.selectShape(
          store.tool == .ellipticalMarquee ? .ellipse(rect) : .rectangle(rect),
          mode: selectionDragMode)
      } else if selectionDragMode == .replace {
        store.perform(.selection(nil))
      }
    case .crop: break
    case .text, .verticalText:
      store.beginType(at: a, end: b)
      synchronizeTypeEditor()
    case .zoom:
      synchronizeViewport()
      store.stepZoom(
        inward: !event.modifierFlags.contains(.option),
        anchoredAt: convert(event.locationInWindow, from: nil))
    default: break
    }
  }
  override func scrollWheel(with event: NSEvent) {
    guard activateDocument() else { return }
    synchronizeViewport()
    if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
      store.setZoom(
        store.effectiveZoom * exp(-event.scrollingDeltaY * 0.015),
        anchoredAt: convert(event.locationInWindow, from: nil))
    } else {
      store.pan.width -= event.scrollingDeltaX
      store.pan.height -= event.scrollingDeltaY
    }
    needsDisplay = true
  }
  override func magnify(with event: NSEvent) {
    guard activateDocument() else { return }
    synchronizeViewport()
    store.setZoom(
      store.effectiveZoom * (1 + event.magnification),
      anchoredAt: convert(event.locationInWindow, from: nil))
    needsDisplay = true
  }
  func finishPolygon() {
    if polygonPoints.count >= 3 {
      store.selectShape(.polygon(polygonPoints), mode: selectionDragMode)
    }
    polygonPoints = []
    start = nil
    end = nil
    needsDisplay = true
  }
  override func keyDown(with event: NSEvent) {
    guard activateDocument() else { return }
    if store.handleWorkspaceKey(event) { return }
    if store.gradientFillDraft != nil {
      if event.keyCode == 53 {
        store.cancelGradientFill()
      } else if [36, 76].contains(event.keyCode) {
        store.commitGradientFill()
      } else {
        super.keyDown(with: event)
      }
      return
    }
    if store.patternFillDraft != nil {
      if event.keyCode == 53 {
        store.cancelPatternFill()
      } else if [36, 76].contains(event.keyCode) {
        store.commitPatternFill()
      } else {
        super.keyDown(with: event)
      }
      return
    }
    synchronizeTool()
    if cropKey(event) { needsDisplay = true; return }
    if regionRetouchKey(event) { needsDisplay = true; return }
    if event.keyCode == 53 && store.shapeGesture != nil { store.shapeGesture=nil;needsDisplay=true;return }
    if event.keyCode == 53 && store.frameGesture != nil { store.frameGesture = nil; needsDisplay = true; return }
    if event.keyCode == 53 && store.artboardGesture != nil { store.artboardGesture = nil; needsDisplay = true; return }
    if event.keyCode == 53 && store.gradientGesture != nil {
      store.cancelGradientGesture()
      needsDisplay = true
      return
    }
    if [51, 117].contains(event.keyCode), !event.modifierFlags.contains(.command),
      store.deleteGradientStop()
    {
      needsDisplay = true
      return
    }
    if event.keyCode == 53 && store.brushGesture != nil {
      drawingEvents.end()
      airbrushTimer?.invalidate();airbrushTimer=nil;store.cancelBrush();start=nil;samples=[];needsDisplay=true;return
    }
    if event.keyCode == 53 && (store.peopleWorkspace.busy || store.peopleWorkspace.presented) {
      store.peopleWorkspace.close(); needsDisplay = true; return
    }
    if event.keyCode == 53 && store.objectFinder.busy {
      store.stopObjectFinder(); needsDisplay = true; return
    }
    if event.keyCode == 53 && store.geometryBusy {
      store.cancelActiveOperation()
      return
    }
    if event.keyCode == 53 && store.cloneDraft != nil {
      drawingEvents.end()
      store.cancelClone()
      start = nil
      needsDisplay = true
      return
    }
    if store.usesPathTool && !event.modifierFlags.contains(.command) {
      switch event.keyCode {
      case 36, 76:
        store.finishPath()
        needsDisplay = true
        return
      case 53:
        store.finishPath(cancelGesture: true)
        needsDisplay = true
        return
      case 51:
        store.deletePathAnchor()
        needsDisplay = true
        return
      default: break
      }
    }
    if event.keyCode == 53, start != nil,
      [.lasso, .marquee, .ellipticalMarquee, .crop].contains(store.tool)
    {
      lassoPoints = []
      start = nil
      end = nil
      needsDisplay = true
      return
    }
    if store.tool == .polygonLasso && !polygonPoints.isEmpty {
      switch event.keyCode {
      case 36, 76:
        finishPolygon()
        return
      case 53:
        polygonPoints = []
        needsDisplay = true
        return
      case 51:
        polygonPoints.removeLast()
        needsDisplay = true
        return
      default: break
      }
    }
    if store.transformDraft != nil {
      switch event.keyCode {
      case 36, 76:
        store.commitTransform()
        return
      case 53:
        store.cancelTransform()
        return
      case 123, 124, 125, 126:
        if var draft = store.transformDraft {
          let step = event.modifierFlags.contains(.shift) ? 10.0 : 1.0
          if event.keyCode == 123 { draft.centerX -= step }
          if event.keyCode == 124 { draft.centerX += step }
          if event.keyCode == 125 { draft.centerY += step }
          if event.keyCode == 126 { draft.centerY -= step }
          store.updateTransform(draft)
        }
        return
      default: break
      }
    }
    guard !event.modifierFlags.contains(.command),
      let key = event.charactersIgnoringModifiers?.lowercased()
    else {
      super.keyDown(with: event)
      return
    }
    if store.chooseShortcut(key, cycle: event.modifierFlags.contains(.shift)) {
      return
    }
    switch key {
    case " ":
      spaceHeld = true
      window?.invalidateCursorRects(for: self)
    case "x": store.swapColors()
    case "d": store.resetColors()
    case "\r": if store.tool == .crop && store.unavailableToolID == nil { store.cropToSelection() }
    case "[":
      if store.tool.usesRetouchStroke {
        store.retouchSettings.brush.size = max(1, store.retouchSettings.brush.size - 5)
      } else {
        store.brush.size = max(1, store.brush.size - 5)
      }
    case "]":
      if store.tool.usesRetouchStroke {
        store.retouchSettings.brush.size = min(2048, store.retouchSettings.brush.size + 5)
      } else {
        store.brush.size = min(2048, store.brush.size + 5)
      }
    case "\u{1b}": store.perform(.selection(nil))
    case "\u{7f}": store.clear()
    default: super.keyDown(with: event)
    }
  }
  override func keyUp(with event: NSEvent) {
    if event.charactersIgnoringModifiers == " " {
      spaceHeld = false
      window?.invalidateCursorRects(for: self)
    } else {
      super.keyUp(with: event)
    }
  }
  static func dragRect(
    from a: CGPoint, to b: CGPoint, flags: NSEvent.ModifierFlags, width: Int, height: Int,
    clipToCanvas: Bool = true
  ) -> IntRect? {
    var dx = b.x - a.x
    var dy = b.y - a.y
    if flags.contains(.shift) {
      let side = max(abs(dx), abs(dy))
      dx = dx < 0 ? -side : side
      dy = dy < 0 ? -side : side
    }
    let opposite = flags.contains(.option) ? CGPoint(x: a.x - dx, y: a.y - dy) : a
    let end = CGPoint(x: a.x + dx, y: a.y + dy)
    if !clipToCanvas {
      let x = Int(floor(min(opposite.x, end.x)))
      let y = Int(floor(min(opposite.y, end.y)))
      let w = Int(ceil(max(opposite.x, end.x))) - x
      let h = Int(ceil(max(opposite.y, end.y))) - y
      return w > 0 && h > 0 ? IntRect(x: x, y: y, width: w, height: h) : nil
    }
    let x = max(0, min(width, Int(floor(min(opposite.x, end.x)))))
    let y = max(0, min(height, Int(floor(min(opposite.y, end.y)))))
    let x1 = max(x, min(width, Int(ceil(max(opposite.x, end.x)))))
    let y1 = max(y, min(height, Int(ceil(max(opposite.y, end.y)))))
    return x1 > x && y1 > y ? IntRect(x: x, y: y, width: x1 - x, height: y1 - y) : nil
  }
}
