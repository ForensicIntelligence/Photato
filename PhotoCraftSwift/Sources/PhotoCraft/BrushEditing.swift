import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Pending digit for the next key on a focused canvas.
struct BrushNumberPrefix {
  enum Setting { case opacity, flow, smoothing }
  static let interval: TimeInterval = 0.5
  let setting: Setting
  let digit: Int
  let timestamp: TimeInterval
  let tool: EditorTool
  let revision: Int

  static func digit(in event: NSEvent) -> Int? {
    func digit(_ characters: String?) -> Int? {
      guard let bytes = characters?.utf8, bytes.count == 1, let key = bytes.first,
        (48...57).contains(key) else { return nil }
      return Int(key - 48)
    }
    // On shifted layouts the reported character can be punctuation. The
    // unshifted character uses the current input source, including the keypad.
    return digit(event.charactersIgnoringModifiers) ?? digit(event.characters(byApplyingModifiers: []))
  }

  static func help(_ setting: Setting, airbrush: Bool = false) -> String {
    if setting == .smoothing {
      return "Press Option and a number key for tens, or two digits quickly for an exact percentage."
    }
    let shifted = (setting == .flow) != airbrush
    let keys = shifted ? "Shift and a number key" : "a number key"
    return "Press \(keys) for tens, or two digits quickly for an exact percentage."
  }
}

enum BrushTipShortcuts {
  static let hardnessStep: Float = 0.25
  static let angleStep: Double = 1
  static let largeAngleStep: Double = 15
  static let hardnessHelp = "Press { or } to soften or harden the brush tip."
  static let angleHelp = "Press Left or Right to rotate the tip by 1°. Hold Shift for 15°."
}

struct BrushStrokeTarget: Equatable {
  let tool: EditorTool
  let layer: UUID
  let mask: Bool
}

struct BrushStrokeEndpoint {
  let target: BrushStrokeTarget
  let session: UUID
  let lifecycle: UUID
  let point: PathPoint
}

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
  var connectsToPrevious = false
  var endpointTarget: BrushStrokeTarget?
  var eraserMode: EraserMode?
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
  /// Updates the same values as the Options bar. An in-progress gesture has
  /// already captured its Brush and retains those settings through release.
  func applyBrushNumber(_ event: NSEvent, following prefix: BrushNumberPrefix?)
    -> (handled: Bool, prefix: BrushNumberPrefix?) {
    guard canConfigureCanvasBrush, unavailableToolID == nil,
      event.modifierFlags.intersection([.command, .control, .function]).isEmpty,
      let digit = BrushNumberPrefix.digit(in: event) else { return (false, nil) }

    let shift = event.modifierFlags.contains(.shift)
    let setting: BrushNumberPrefix.Setting
    if event.modifierFlags.contains(.option) {
      guard !shift,
        tool == .brush || tool == .pencil || tool == .mixerBrush || (tool == .eraser && eraserMode != .block)
      else { return (false, nil) }
      setting = .smoothing
    } else {
      switch tool {
      case .brush:
        setting = shift != brushOptions.buildUp ? .flow : .opacity
      case .pencil where !shift, .eraser where eraserMode == .pencil && !shift:
        setting = .opacity
      case .eraser where eraserMode == .brush:
        setting = shift != brushOptions.buildUp ? .flow : .opacity
      default:
        return (false, nil)
      }
    }

    if event.isARepeat { return (true, prefix) }
    let previous = prefix.flatMap {
      $0.setting == setting && $0.tool == tool && $0.revision == brushRevision
        && (0...BrushNumberPrefix.interval).contains(event.timestamp - $0.timestamp) ? $0.digit : nil
    }
    let value = previous.map { 10 * $0 + digit } ?? (digit == 0 ? 100 : digit * 10)
    switch setting {
    case .opacity: brush.opacity = Float(value) / 100
    case .flow: brushOptions.flow = Double(value) / 100
    case .smoothing: brushOptions.smoothing.amount = Double(value) / 100
    }
    return (true, previous == nil
      ? BrushNumberPrefix(setting: setting, digit: digit, timestamp: event.timestamp, tool: tool, revision: brushRevision)
      : nil)
  }

  func applyBrushTipKey(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags
    guard canConfigureCanvasBrush, unavailableToolID == nil,
      flags.intersection([.command, .control]).isEmpty else { return false }
    switch tool {
    case .brush, .mixerBrush, .patternStamp, .colorReplacement, .backgroundEraser: break
    case .eraser where eraserMode == .brush: break
    default: return false
    }

    let character = event.charactersIgnoringModifiers?.unicodeScalars.first?.value
    // AppKit marks real arrow events as function keys. A translated Home or
    // End event from Fn-arrow still has its own distinct character.
    if !flags.contains(.option),
      character == UInt32(NSLeftArrowFunctionKey) || character == UInt32(NSRightArrowFunctionKey) {
      let direction = character == UInt32(NSLeftArrowFunctionKey) ? 1.0 : -1.0
      let step = flags.contains(.shift) ? BrushTipShortcuts.largeAngleStep : BrushTipShortcuts.angleStep
      // The painter measures positive angles counterclockwise in image space.
      brushOptions.angle = (brushOptions.angle + direction * step).remainder(dividingBy: 360)
      return true
    }
    guard !flags.contains(.function), brushOptions.tip == nil, !brushOptions.aliased,
      tool != .colorReplacement || currentPaintOptions.antiAlias else { return false }
    let shiftedBracket = flags.contains(.shift) && !flags.contains(.option) ? event.charactersIgnoringModifiers : nil
    let direction: Float
    if event.characters == "{" || shiftedBracket == "[" { direction = -1 }
    else if event.characters == "}" || shiftedBracket == "]" { direction = 1 }
    else { return false }
    brush.hardness = min(1, max(0, brush.hardness + direction * BrushTipShortcuts.hardnessStep))
    return true
  }

  private var brushStrokeTarget: BrushStrokeTarget? {
    guard tool == .brush || tool == .pencil, !editingComponent, !smartFilterMaskEditing,
      document.inkMode == nil, let layer = activeLayer, layer.smartObject == nil,
      case .raster = layer.content else { return nil }
    return .init(tool: tool, layer: layer.id, mask: editingMask)
  }

  var canConnectBrushStroke: Bool {
    guard let endpoint = brushStrokeEndpoint, let target = brushStrokeTarget, canUseBrush else { return false }
    return endpoint.target == target && endpoint.session == sessionGeneration && endpoint.lifecycle == layerPanelGeneration
  }

  func retainBrushEndpointAfterRecordingChange(previousSession: UUID) {
    guard let endpoint = brushStrokeEndpoint, endpoint.session == previousSession,
      endpoint.lifecycle == layerPanelGeneration else { return }
    brushStrokeEndpoint = .init(target: endpoint.target, session: sessionGeneration,
      lifecycle: endpoint.lifecycle, point: endpoint.point)
  }

  func beginBrush(_ point:StrokePoint,zoom:Double,alternate:Bool=false,selectionMode:SelectionMode?=nil,eventTimestamp:TimeInterval?=nil,connectToPrevious:Bool=false,temporaryClear:Bool=false) {
    if hasHiddenQuickMaskEditingTarget { error = Self.hiddenQuickMaskBrushMessage; return }
    guard canUseBrush else { return }; let layer = activeLayer
    guard let layerID = layer?.id ?? (document.inkMode != nil || editingChannel != nil ? document.id : nil) else { return }
    var value=brush;value.settings=value.settings ?? .init();value.settings!.seed=UInt64.random(in:1...9_007_199_254_740_991);value.settings!.zoom=min(64,max(0.01,zoom))
    if temporaryClear, tool == .brush { value.settings?.paintMode = .clear }
    if let mode = value.settings?.paintMode {
      if let paintTool = tool.paintTool, mode.supports(paintTool) {
        do { try validateBrushPaintDestination() } catch { self.error = error.localizedDescription; return }
      } else {
        value.settings?.paintMode = nil
      }
    }
    value.erase=tool == .eraser;value.backgroundColor=backgroundColor
    if editingMask && value.erase { value.color=backgroundColor;value.erase=false }
    if tool == .eraser {
      if alternate { status = "Erase to History requires a history source and is not available yet."; return }
      do {
        guard let resolved = try EraserBrush.resolve(value, mode: eraserMode, zoom: value.settings!.zoom) else { return }
        value = resolved
      } catch { self.error = error.localizedDescription; return }
    }
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
    var points = [point]
    if connectToPrevious, canConnectBrushStroke, let endpoint = brushStrokeEndpoint {
      var first = point
      first.x = endpoint.point.x; first.y = endpoint.point.y
      points.insert(first, at: 0)
    }
    canvasFrameTrace?.begin(tool: tool.rawValue, eventTimestamp: eventTimestamp, samples: points.count)
    brushPreviewLastStart = 0; brushPreviewFrameCount = 0; brushPreviewSampleCount = 0; brushPreviewRenderMS = 0
    brushGesture = .init(original:document,generation:layerPanelGeneration,sessionGeneration:sessionGeneration,layerID:layerID,mask:editingMask,brush:value,points:points,selection:selection,adjustment:adjustment,painting:painting)
    brushGesture?.connectsToPrevious = points.count > 1
    brushGesture?.endpointTarget = brushStrokeTarget
    brushGesture?.eraserMode = tool == .eraser ? eraserMode : nil
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
    guard brushPreviewTask == nil, let gesture = brushGesture else { return }
    let generation=UUID();brushPreviewGeneration=generation
    // The ready ordinary canvas can capture the first input immediately. The
    // renderer still prepares its pixels off the main actor.
    let firstFrame: (samples: Int, render: CanvasRenderRequest?)?
    if brushPreviewLastStart == 0, tool == .brush, ordinaryCanvasImage, !rendering,
      case .stroke? = brushPreviewCommand {
      firstFrame = startBrushPreviewFrame(samples: gesture.points.count, startWorkerImmediately: true)
    } else {
      firstFrame = nil
    }
    brushPreviewTask=Task { [weak self] in
      guard let self else { return }
      var frame = firstFrame
      // One preview runs at a time. Keep all input and render the latest batch
      // when the previous preview and the pacing deadline allow it.
      while !Task.isCancelled,self.brushPreviewGeneration==generation {
        if let frame {
          await frame.render?.value
          guard !Task.isCancelled, self.brushPreviewGeneration == generation,
            self.brushGesture?.points.count != frame.samples else { break }
        }
        let delay = self.brushPreviewLastStart - ProcessInfo.processInfo.systemUptime
        if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
        guard !Task.isCancelled,self.brushPreviewGeneration==generation,let gesture=self.brushGesture else { break }
        frame = self.startBrushPreviewFrame(samples: gesture.points.count)
      }
      if self.brushPreviewGeneration==generation { self.brushPreviewTask=nil }
    }
  }
  private func startBrushPreviewFrame(samples: Int, startWorkerImmediately: Bool = false) -> (samples: Int, render: CanvasRenderRequest?) {
    let now = ProcessInfo.processInfo.systemUptime
    let interval = brushPreviewFrameInterval
    brushPreviewLastStart = brushPreviewLastStart > 0 && now < brushPreviewLastStart + interval
      ? brushPreviewLastStart + interval : now + interval
    render(startWorkerImmediately: startWorkerImmediately)
    return (samples, renderTask)
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
    let rememberEndpoint: (() -> Void)?
    if let target = gesture.endpointTarget, let point = points.last {
      rememberEndpoint = { [weak self] in
        guard let self, self.brushStrokeTarget == target else { return }
        self.brushStrokeEndpoint = .init(target: target, session: self.sessionGeneration,
          lifecycle: self.layerPanelGeneration, point: .init(point.x, point.y))
      }
    } else { rememberEndpoint = nil }
    if let request=gesture.selectionRequest {
      performGeometry(label:request.kind.title,prepare:{original in try await SelectionToolPreparation.command(request,in:original)})
    } else if let request=gesture.adjustmentRequest {
      if let retained {
        performPreparedGeometry(label: "Adjustment Brush", cancelPreview: false) { original in
          if let prepared = try await retained.prepareCommit(base: original, points: points) { return prepared }
          return try PreparedEdit(command: .adjustmentBrush(request), document: original)
        }
      } else { performGeometry(label:"Adjustment Brush",prepare:{_ in .adjustmentBrush(request)}) }
    } else if let request=gesture.paintingRequest {
      performGeometry(label:request.tool.title,allowAuxiliary:true,prepare:{original in .painting(try PaintingPreparation.prepare(request,in:original))},onSuccess:rememberEndpoint)
    } else if let retained, let command {
      performPreparedGeometry(label: command.label, cancelPreview: false, prepare: { original in
        if let prepared = try await retained.prepareCommit(base: original, points: points) { return prepared }
        return try PreparedEdit(command: command, document: original)
      }, onSuccess: rememberEndpoint)
    } else {performGeometry(gesture.command,onSuccess:rememberEndpoint)}
  }
  func cancelBrush() { guard brushGesture != nil else { return };canvasFrameTrace?.end(cancelled:true);stopBrushPreview();brushGesture=nil;render() }
}
