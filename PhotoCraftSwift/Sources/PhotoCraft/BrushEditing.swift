import Foundation
import PhotoCraftCore
import PhotoCraftImaging

final class BrushGesture {
  let sessionGeneration: UUID
  init(original: CraftDocument, generation: UUID, sessionGeneration: UUID, layerID: UUID, mask: Bool, brush: Brush, points: [StrokePoint], selection: SelectionToolRequest?, adjustment: AdjustmentBrushRequest?, painting: PaintToolRequest?) {
    self.original=original; self.generation=generation; self.sessionGeneration=sessionGeneration; self.layerID=layerID; self.mask=mask; self.brush=brush; self.points=points; self.selection=selection; self.adjustment=adjustment; self.painting=painting
    smoothingCursor = BrushSmoothingCursor(settings: brush.settings?.smoothing ?? .init(), zoom: brush.settings?.zoom ?? 1)
    for point in points { smoothingCursor.append(point) }
  }
  let original:CraftDocument
  let generation:UUID
  let layerID:UUID
  let mask:Bool
  let brush:Brush
  var points:[StrokePoint]
  private var smoothingCursor: BrushSmoothingCursor
  var supportsHeldSmoothing: Bool {
    selection == nil && adjustment == nil && (painting == nil || [.brush, .pencil, .mixerBrush].contains(painting!.tool))
  }
  var needsStationarySample: Bool {
    points.count < 100_000 && (brush.settings?.buildUp == true && painting?.tool != .pencil
      || supportsHeldSmoothing && smoothingCursor.needsStationarySample)
  }
  func append(_ point: StrokePoint) { points.append(point); smoothingCursor.append(point) }
  var heldBrush: Brush {
    var value = brush
    if supportsHeldSmoothing { value.settings?.smoothing.catchUpOnEnd = false }
    return value
  }
  var selection:SelectionToolRequest?
  var selectionRequest:SelectionToolRequest? {guard var value=selection else{return nil};value.points=points;return value}
  var adjustment:AdjustmentBrushRequest?
  var adjustmentRequest:AdjustmentBrushRequest? {guard var value=adjustment else{return nil};value.points=points;return value}
  var painting:PaintToolRequest?
  var paintingRequest:PaintToolRequest? { guard var value=painting else{return nil};value.points=points;return value }
  var paintingPreviewRequest: PaintToolRequest? {
    guard var value = paintingRequest else { return nil }; value.brush = heldBrush; return value
  }
  var command:Command { mask ? .maskStroke(layerID,points,brush):.stroke(layerID,points,brush) }
  var heldCommand: Command { mask ? .maskStroke(layerID, points, heldBrush) : .stroke(layerID, points, heldBrush) }
}
@MainActor extension EditorStore {
  func beginBrush(_ point:StrokePoint,zoom:Double,alternate:Bool=false,selectionMode:SelectionMode?=nil,eventTimestamp:TimeInterval?=nil) {
    if hasHiddenQuickMaskEditingTarget { error = Self.hiddenQuickMaskBrushMessage; return }
    guard canUseBrush else { return }; let layer = activeLayer
    guard let layerID = layer?.id ?? (document.inkMode != nil || editingChannel != nil ? document.id : nil) else { return }
    var value=brush;value.settings=value.settings ?? .init();value.settings!.seed=UInt64.random(in:1...9_007_199_254_740_991);value.settings!.zoom=min(64,max(0.01,zoom))
    value.erase=tool == .eraser;value.backgroundColor=backgroundColor
    if editingMask && value.erase { value.color=backgroundColor;value.erase=false }
    let selection=tool.usesSelectionStroke && canUseSelectionTools ? selectionToolRequest(tool.selectionToolKind!,points:[point],brush:value,mode:selectionMode ?? (alternate ? .subtract:selectionPaintMode)):nil
    if tool.usesSelectionStroke && selection==nil{return}
    var painting:PaintToolRequest?
    let adjustment=tool == .adjustmentBrush && canUseAdjustmentBrush ? adjustmentBrushRequest(points:[point],brush:value,alternate:alternate):nil
    if tool == .adjustmentBrush && adjustment==nil {return}
    if let kind=tool.paintTool {
      let ordinary:Bool;if let layer, case .raster=layer.content {ordinary=layer.smartObject==nil}else{ordinary=document.inkMode != nil}
      if kind != .brush || (!editingMask && editingChannel==nil && !ordinary) {
        do {painting=try paintingRequest(kind,points:[point],brush:value)} catch {self.error=error.localizedDescription;return}
      }
    }
    canvasFrameTrace?.begin(tool: tool.rawValue, eventTimestamp: eventTimestamp)
    brushPreviewLastStart = 0; brushPreviewFrameCount = 0; brushPreviewSampleCount = 0; brushPreviewRenderMS = 0
    brushGesture = .init(original:document,generation:layerPanelGeneration,sessionGeneration:sessionGeneration,layerID:layerID,mask:editingMask,brush:value,points:[point],selection:selection,adjustment:adjustment,painting:painting)
    if let command = brushCommand(preview: false) { interactiveBrushPreview = InteractiveBrushPreview(document: document, command: command) }
    scheduleBrushPreview()
  }
  func extendBrush(_ point:StrokePoint,eventTimestamp:TimeInterval?=nil) {
    guard let gesture=brushGesture,gesture.points.count<100_000 else { return }
    guard gesture.sessionGeneration==sessionGeneration,gesture.generation==layerPanelGeneration else { cancelBrush();return }
    gesture.append(point);canvasFrameTrace?.input(samples:gesture.points.count,eventTimestamp:eventTimestamp);scheduleBrushPreview()
  }
  /// Elapsed stroke time, not a fabricated pointer event. Retain the last tablet
  /// attributes and route generated samples through the ordinary commit path.
  @discardableResult func advanceStationaryBrush(time: Double) -> StrokePoint? {
    guard let gesture = brushGesture else { return nil }
    guard gesture.sessionGeneration == sessionGeneration, gesture.generation == layerPanelGeneration
    else { cancelBrush(); return nil }
    guard gesture.needsStationarySample, time.isFinite, time <= 3_600_000,
      var point = gesture.points.last, time > (point.time ?? 0) else { return nil }
    point.time = time; extendBrush(point); return point
  }
  func scheduleBrushPreview() {
    guard brushPreviewTask == nil else { return }
    let generation=UUID();brushPreviewGeneration=generation
    // Collect every sample, but publish at most60 previews/second. One worker runs
    // at a time; slow frames consume the newest batch instead of building a queue.
    brushPreviewTask=Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled,self.brushPreviewGeneration==generation {
        let delay = self.brushPreviewLastStart - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        guard !Task.isCancelled,self.brushPreviewGeneration==generation,let gesture=self.brushGesture else { break }
        let count=gesture.points.count
        let now = ProcessInfo.processInfo.systemUptime
        let interval = self.brushPreviewFrameInterval
        self.brushPreviewLastStart = self.brushPreviewLastStart > 0 && now < self.brushPreviewLastStart + interval
          ? self.brushPreviewLastStart + interval : now + interval
        self.render()
        await self.renderTask?.value
        guard !Task.isCancelled,self.brushPreviewGeneration==generation else { break }
        if self.brushGesture?.points.count==count { break }
      }
      if self.brushPreviewGeneration==generation { self.brushPreviewTask=nil }
    }
  }
  func stopBrushPreview() { brushPreviewGeneration=UUID();brushPreviewTask?.cancel();brushPreviewTask=nil;interactiveBrushPreview=nil }
  var brushPreviewCommand:Command? { brushCommand(preview: true) }
  private func brushCommand(preview: Bool) -> Command? {
    guard let gesture=brushGesture,gesture.painting==nil,gesture.selection==nil,gesture.sessionGeneration==sessionGeneration,gesture.generation==layerPanelGeneration else { return nil }
    if let request=gesture.adjustmentRequest{return .adjustmentBrush(request)}
    return try? routedMaskCommand(routeInkChannels(routeModeComponents(Self.routeChannel(preview ? gesture.heldCommand : gesture.command,target:editingChannel))))
  }
  func finishBrush() {
    guard let gesture=brushGesture else { return }
    let retained = interactiveBrushPreview, command = brushCommand(preview: false), points = gesture.points
    canvasFrameTrace?.end(cancelled:false);stopBrushPreview();brushGesture=nil
    guard gesture.sessionGeneration==sessionGeneration,gesture.generation==layerPanelGeneration else { render();return }
    if let request=gesture.selectionRequest {
      performGeometry(label:request.kind.title,prepare:{original in try await SelectionToolPreparation.command(request,in:original)})
    } else if let request=gesture.adjustmentRequest {
      performGeometry(label:"Adjustment Brush",prepare:{_ in .adjustmentBrush(request)})
    } else if let request=gesture.paintingRequest {
      performGeometry(label:request.tool.title,allowAuxiliary:true,prepare:{original in .painting(try PaintingPreparation.prepare(request,in:original))})
    } else if let retained, let command {
      performPreparedGeometry(label: command.label, cancelPreview: false) { original in
        if let prepared = try await retained.prepareCommit(base: original, points: points) { return prepared }
        return try PreparedEdit(command: command, document: original)
      }
    } else {performGeometry(gesture.command)}
  }
  func cancelBrush() { guard brushGesture != nil else { return };canvasFrameTrace?.end(cancelled:true);stopBrushPreview();brushGesture=nil;render() }
}
