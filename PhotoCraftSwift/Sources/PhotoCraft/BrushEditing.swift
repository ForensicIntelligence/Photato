import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct BrushGesture {
  let original:CraftDocument
  let generation:UUID
  let layerID:UUID
  let mask:Bool
  let brush:Brush
  var points:[StrokePoint]
  var selection:SelectionToolRequest?
  var selectionRequest:SelectionToolRequest? {guard var value=selection else{return nil};value.points=points;return value}
  var adjustment:AdjustmentBrushRequest?
  var adjustmentRequest:AdjustmentBrushRequest? {guard var value=adjustment else{return nil};value.points=points;return value}
  var painting:PaintToolRequest?
  var paintingRequest:PaintToolRequest? { guard var value=painting else{return nil};value.points=points;return value }
  var command:Command { mask ? .maskStroke(layerID,points,brush):.stroke(layerID,points,brush) }
}
@MainActor extension EditorStore {
  func beginBrush(_ point:StrokePoint,zoom:Double,alternate:Bool=false,selectionMode:SelectionMode?=nil) {
    guard canUseBrush else { return }; let layer = activeLayer
    guard let layerID = layer?.id ?? (document.inkMode != nil ? document.id : nil) else { return }
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
    brushGesture = .init(original:document,generation:layerPanelGeneration,layerID:layerID,mask:editingMask,brush:value,points:[point],selection:selection,adjustment:adjustment,painting:painting)
    scheduleBrushPreview()
  }
  func extendBrush(_ point:StrokePoint) {
    guard var gesture=brushGesture,gesture.points.count<100_000 else { return }
    guard gesture.original==document,gesture.generation==layerPanelGeneration else { cancelBrush();return }
    gesture.points.append(point);brushGesture=gesture;scheduleBrushPreview()
  }
  func scheduleBrushPreview() {
    guard brushPreviewTask == nil else { return }
    let generation=UUID();brushPreviewGeneration=generation
    // Let each snapshot finish before rendering the newest samples. Cancelling on
    // every pointer event can otherwise starve previews on a large document.
    let initialCount=brushGesture?.points.count ?? 0
    render()
    brushPreviewTask=Task { [weak self] in
      guard let self else { return }
      var count=initialCount
      while !Task.isCancelled,self.brushPreviewGeneration==generation {
        await self.renderTask?.value
        guard !Task.isCancelled,self.brushPreviewGeneration==generation,let gesture=self.brushGesture else { break }
        if gesture.points.count==count { break }
        count=gesture.points.count;self.render()
      }
      if self.brushPreviewGeneration==generation { self.brushPreviewTask=nil }
    }
  }
  func stopBrushPreview() { brushPreviewGeneration=UUID();brushPreviewTask?.cancel();brushPreviewTask=nil }
  var brushPreviewCommand:Command? {
    guard let gesture=brushGesture,gesture.painting==nil,gesture.selection==nil,gesture.original==document,gesture.generation==layerPanelGeneration else { return nil }
    if let request=gesture.adjustmentRequest{return .adjustmentBrush(request)}
    return try? routedMaskCommand(routeInkChannels(routeModeComponents(Self.routeChannel(gesture.command,target:editingChannel))))
  }
  func finishBrush() {
    guard let gesture=brushGesture else { return };stopBrushPreview();brushGesture=nil
    guard gesture.original==document,gesture.generation==layerPanelGeneration else { render();return }
    if let request=gesture.selectionRequest {
      performGeometry(label:request.kind.title,prepare:{original in try await SelectionToolPreparation.command(request,in:original)})
    } else if let request=gesture.adjustmentRequest {
      performGeometry(label:"Adjustment Brush",prepare:{_ in .adjustmentBrush(request)})
    } else if let request=gesture.paintingRequest {
      performGeometry(label:request.tool.title,allowAuxiliary:true,prepare:{original in .painting(try PaintingPreparation.prepare(request,in:original))})
    } else {performGeometry(gesture.command)}
  }
  func cancelBrush() { guard brushGesture != nil else { return };stopBrushPreview();brushGesture=nil;render() }
}
