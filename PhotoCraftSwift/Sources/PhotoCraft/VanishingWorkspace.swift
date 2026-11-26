import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class VanishingWorkspace:Identifiable {
  enum Tool:String,CaseIterable { case create="Create Plane",edit="Edit Plane",marquee="Marquee",stamp="Stamp",brush="Brush",transform="Transform",eyedropper="Eyedropper",measure="Measure",hand="Hand",zoom="Zoom" }
  enum NavigationAction: Equatable {
    case pan
    case zoom(outward: Bool)

    init?(tool: Tool, temporaryHand: Bool, modifiers: NSEvent.ModifierFlags) {
      if temporaryHand || tool == .hand { self = .pan }
      else if tool == .zoom { self = .zoom(outward:modifiers.contains(.option)) }
      else { return nil }
    }

    func cursor(dragging: Bool) -> ToolCursor {
      switch self {
      case .pan: return dragging ? .closedHand : .openHand
      case .zoom(let outward): return .symbol(outward ? "minus.magnifyingglass" : "plus.magnifyingglass")
      }
    }
  }
  enum MarqueeMoveMode: String, CaseIterable { case destination = "Destination", source = "Source" }
  let id=UUID()
  let original:CraftDocument
  let layerID:UUID
  private(set) var program=VanishingProgram()
  var tool:Tool = .create {
    didSet { if tool != .measure { pendingMeasurement = nil } }
  }
  var selected=0
  var selectedCorner=0
  var selectedPaste:Int?
  var selectedMeasurement: Int?
  var pendingMeasurement: (plane: Int, point: PathPoint)?
  var marquee: VanishingMarquee?
  var selectedMarqueePatch: Int?
  var marqueeMoveMode: MarqueeMoveMode = .destination
  var allowMultiSurfaceOperations = true
  var marqueeFeather = 1.0
  var marqueeOpacity = 100.0
  var marqueeHeal: VanishingOperation.Heal = .off
  /// Session choice. The preview remains editable until Apply.
  var renderMeasurements = false
  var showMeasurements = true
  var measurements: [VanishingMeasurement] { program.settings.measurements ?? [] }
  var selectedMeasurementLength: Double? {
    guard let index = selectedMeasurement, measurements.indices.contains(index) else { return nil }
    return scene?.measurementLength(measurements[index],settings:program.settings)
  }
  var measurementsLinked: Bool {
    get {
      guard let scene, scene.frames.indices.contains(selected) else { return false }
      return program.settings.measurementScale(for:scene.measurementRoot(for:selected)).linkedToGrid
    }
    set {
      guard let scene, scene.frames.indices.contains(selected) else { return }
      var settings = program.settings
      var scale = settings.measurementScale(for:scene.measurementRoot(for:selected))
      scale.linkedToGrid = newValue
      settings.setMeasurementScale(scale)
      var draft = program
      draft.settings = settings
      change(draft)
    }
  }
  var pending=[PathPoint]()
  var cloneSource:PathPoint?
  var diameter=40.0
  var hardness=50.0
  var opacity=100.0
  var heal: VanishingOperation.Heal = .off
  var color=Pixel.black
  var clip=true
  var aligned=true
  var image:CGImage?
  var originalImage:CGImage?
  var showGrid=true
  var gridSize: Double {
    get { program.settings.effectiveGridSize }
    set {
      guard newValue.isFinite else { return }
      let range = VanishingSettings.gridSizeRange
      let size = min(range.upperBound, max(range.lowerBound, newValue))
      var draft = program
      draft.settings.gridSize = size == VanishingSettings.defaultGridSize ? nil : size
      change(draft)
    }
  }
  var preview=true
  var rendering=false
  var zoom=1.0
  var pan=CGSize.zero
  private static let previewZoomRange = 0.25...8.0

  func previewScale(in viewport: CGSize, temporary: Bool = false) -> CGFloat {
    let fit = min((viewport.width-32)/size.width,(viewport.height-32)/size.height)
    return max(0.001,fit*zoom*(temporary ? 2 : 1))
  }

  func changePreviewZoom(by factor: Double, about anchor: CGPoint? = nil,
    in viewport: CGSize = .zero, centerAnchor: Bool = false)
  {
    guard factor.isFinite, factor > 0 else { return }
    let previous = zoom
    let scale = previewScale(in:viewport)
    let range = Self.previewZoomRange
    zoom = min(range.upperBound,max(range.lowerBound,zoom*factor))
    guard let anchor, anchor.x.isFinite, anchor.y.isFinite, viewport.width > 0, viewport.height > 0,
      zoom != previous || centerAnchor else { return }
    let ratio = previewScale(in:viewport)/scale
    let dx = anchor.x-viewport.width/2, dy = anchor.y-viewport.height/2
    let targetX = centerAnchor ? 0 : dx
    let targetY = centerAnchor ? 0 : dy
    pan = .init(width:targetX+(pan.width-dx)*ratio,height:targetY+(pan.height-dy)*ratio)
  }

  func fitPreview() {
    zoom = 1
    pan = .zero
  }

  var error:String?
  private(set) var brushColorError: String?
  private struct StampAnchor: Equatable {
    let source: PathPoint
    let start: PathPoint
    let plane: Int
  }
  private struct EditState: Equatable {
    var program: VanishingProgram
    var marquee: VanishingMarquee?
    var floating: Int?
    var paste: Int?
    var stampAnchor: StampAnchor?

    static func == (lhs: Self, rhs: Self) -> Bool {
      // A source pick alone does not add a workspace undo step.
      lhs.program == rhs.program && lhs.marquee == rhs.marquee && lhs.floating == rhs.floating
    }
  }
  private var undoStates=[EditState]()
  private var redoStates=[EditState]()
  var canUndo: Bool { !undoStates.isEmpty || !pending.isEmpty || pendingMeasurement != nil }
  var canRedo: Bool { !redoStates.isEmpty }
  private var editState: EditState { .init(program:program,marquee:marquee,floating:selectedMarqueePatch,paste:selectedPaste,stampAnchor:cloneAnchor) }
  @ObservationIgnored var task:Task<Void,Never>?
  @ObservationIgnored private(set) var brushColorTask: Task<Void,Never>?
  @ObservationIgnored private var seedSnapshot: RenderSnapshot?
  @ObservationIgnored private var seedDisplay: CanvasRasterPreview?
  @ObservationIgnored private var sourcePreview: SourcePreview?
  private(set) var preparedEdit: VanishingEdit?
  private var generation=0
  private var closed=false
  private var gestureStart:EditState?
  private var cloneAnchor: StampAnchor?
  var size:CGSize { .init(width:original.width,height:original.height) }
  var scene:VanishingScene? { try? VanishingScene(program.settings,width:original.width,height:original.height) }
  var exportingScene = false
  var sceneExportMessage: String?
  var sceneExportError: String?
  @ObservationIgnored private var sceneExportTask: Task<Void,Never>?
  @ObservationIgnored private var sceneExportPanel: NSOpenPanel?
  var canExportScene: Bool {
    !closed && !rendering && !exportingScene && preparedEdit != nil && !program.settings.planes.isEmpty
  }
  var ready:Bool { preparedEdit != nil && image != nil && !rendering && error == nil && pending.isEmpty }
  init(document: CraftDocument, layerID: UUID, snapshot: RenderSnapshot? = nil,
    display: CanvasRasterPreview? = nil) {
    original = document
    self.layerID = layerID
    seedSnapshot = snapshot
    seedDisplay = display
    program.settings = document.vanishingPoint ?? .init()
    tool = program.settings.planes.isEmpty ? .create : .edit
  }
  func prepare() async { refresh();await task?.value }
  private func remember(_ state: EditState) { undoStates.append(state);if undoStates.count>40 { undoStates.removeFirst() };redoStates=[] }
  func change(_ p:VanishingProgram,remember:Bool=true) {
    do { try p.validate();_ = try VanishingScene(p.settings,width:original.width,height:original.height) } catch { self.error=error.localizedDescription;return }
    guard p != program else { error=nil;return }
    var previous = program
    previous.settings = previous.settings.withDisplayMetadata(from:p.settings)
    if remember && gestureStart == nil { self.remember(editState) }
    program = p
    selected = max(0,min(selected,p.settings.planes.count-1))
    if let i = selectedPaste, !p.operations.indices.contains(i) || p.operations[i].kind != .paste { selectedPaste = nil }
    if let i = selectedMarqueePatch, !p.operations.indices.contains(i) || p.operations[i].marquee == nil { selectedMarqueePatch = nil }
    if let i = selectedMeasurement, !measurements.indices.contains(i) { selectedMeasurement = nil }
    if p == previous, let edit = preparedEdit, let updated = try? edit.updatingDisplayMetadata(p.settings) {
      preparedEdit = updated
      error = nil
    } else {
      refresh()
    }
  }
  func beginGesture() { if gestureStart==nil { gestureStart=editState } }
  func endGesture() { if let start=gestureStart,start != editState { remember(start) };gestureStart=nil }
  private func restore(_ state: EditState) {
    change(state.program,remember:false)
    marquee = state.marquee
    selectedMarqueePatch = state.floating
    selectedPaste = state.paste
    if let operation = selectedPasteOperation,operation.canvasPaste == nil { selected = operation.plane }
    cloneAnchor = state.stampAnchor?.source == cloneSource ? state.stampAnchor : nil
  }
  func undo() { if pendingMeasurement != nil { pendingMeasurement=nil;return };if !pending.isEmpty { pending.removeLast();return };endGesture();guard let state=undoStates.popLast() else { return };redoStates.append(editState);restore(state) }
  func redo() { endGesture();guard let state=redoStates.popLast() else { return };undoStates.append(editState);restore(state) }
  func addPoint(_ p:PathPoint) {
    pending.append(p);guard pending.count==4 else { return };var next=program;next.settings.planes.append(.init(corners:pending))
    do { try next.validate();_ = try VanishingScene(next.settings,width:original.width,height:original.height);pending=[];selected=next.settings.planes.count-1;change(next);tool = .edit } catch { pending.removeLast();self.error=error.localizedDescription }
  }
  func moveCorner(_ plane:Int,_ corner:Int,to p:PathPoint) {
    guard program.settings.planes.indices.contains(plane),program.settings.planes[plane].parent==nil else { return };var next=program;next.settings.planes[plane].corners[corner]=p;selected=plane;selectedCorner=corner;change(next)
  }
  func movePlane(_ plane:Int,dx:Double,dy:Double) {
    var next=gestureStart?.program ?? program;guard next.settings.planes.indices.contains(plane),next.settings.planes[plane].parent==nil else { return };next.settings.planes[plane].corners=next.settings.planes[plane].corners.map{.init($0.x+dx,$0.y+dy)};change(next)
  }
  func tear(_ edge:VanishingPlane.Edge) { guard program.settings.planes.indices.contains(selected) else { return };var p=program;p.settings.planes.append(.init(parent:selected,edge:edge));let count=p.settings.planes.count;change(p);if program.settings.planes.count==count { selected=count-1 } }
  func detach() { guard let scene,scene.frames.indices.contains(selected) else { return };var p=program;p.settings.planes[selected] = .init(corners:scene.frames[selected].corners);change(p) }
  func removePlane() {
    guard program.settings.planes.indices.contains(selected) else { return };var removed:Set<Int>=[selected]
    for i in program.settings.planes.indices { if let parent=program.settings.planes[i].parent,removed.contains(parent) { removed.insert(i) } }
    let remaining=program.settings.planes.indices.filter{!removed.contains($0)},map=Dictionary(uniqueKeysWithValues:remaining.enumerated().map{($0.element,$0.offset)})
    var p=program;p.settings.planes=remaining.map { i in var plane=program.settings.planes[i];plane.parent=plane.parent.flatMap{map[$0]};return plane }
    p.operations = p.operations.compactMap { operation in
      if operation.canvasPaste != nil { return operation }
      guard let destination = map[operation.plane] else { return nil }
      var operation = operation
      operation.plane = destination
      if var patch = operation.marquee {
        guard let donor = map[patch.source.plane] else { return nil }
        patch.source.plane = donor
        patch.destination.plane = destination
        operation.marquee = patch
      }
      return operation
    }
    let lines = measurements.compactMap { line -> VanishingMeasurement? in
      guard let index = map[line.plane] else { return nil }
      return .init(plane:index,start:line.start,end:line.end)
    }
    let scales = (p.settings.measurementScales ?? []).compactMap { scale -> VanishingMeasurementScale? in
      guard let root = map[scale.root] else { return nil }
      return .init(root:root,pixelsPerUnit:scale.pixelsPerUnit,linkedToGrid:scale.linkedToGrid)
    }
    p.settings.measurements = lines.isEmpty ? nil : lines
    p.settings.measurementScales = scales.isEmpty ? nil : scales
    beginGesture()
    selectedPaste = nil
    selectedMarqueePatch = nil
    if var selection = marquee,let index = map[selection.plane] {
      selection.plane = index
      marquee = selection
    } else { marquee = nil }
    selectedMeasurement = nil
    pendingMeasurement = nil
    change(p)
    endGesture()
  }
  enum MeasurementTarget: Equatable {
    case start(Int), end(Int), body(Int)

    var index: Int {
      switch self { case .start(let index), .end(let index), .body(let index): index }
    }
  }

  func measurementTarget(at point: PathPoint, radius: Double, scene: VanishingScene) -> MeasurementTarget? {
    guard showMeasurements else { return nil }
    var best: (hit: MeasurementTarget, distance: Double)?
    for index in measurements.indices.reversed() {
      let line = measurements[index], frame = scene.frames[line.plane]
      let a = frame.point(line.start), b = frame.point(line.end)
      let da = hypot(point.x-a.x,point.y-a.y), db = hypot(point.x-b.x,point.y-b.y)
      let endpoint: MeasurementTarget = da < db ? .start(index) : .end(index)
      let endpointDistance = min(da,db)
      if endpointDistance <= radius {
        if best.map({ endpointDistance < $0.distance || $0.hit == .body($0.hit.index) }) ?? true {
          best = (endpoint,endpointDistance)
        }
        continue
      }
      let dx = b.x-a.x, dy = b.y-a.y
      let t = ((point.x-a.x)*dx+(point.y-a.y)*dy)/(dx*dx+dy*dy)
      guard t > 0, t < 1 else { continue }
      let distance = hypot(point.x-a.x-t*dx,point.y-a.y-t*dy)
      if distance <= radius/2, best.map({ $0.hit == .body($0.hit.index) && distance < $0.distance }) ?? true {
        best = (.body(index),distance)
      }
    }
    return best?.hit
  }

  func editedMeasurement(_ line: VanishingMeasurement, target: MeasurementTarget,
    from: PathPoint, to: PathPoint, constraint: ToolCursor.MeasurementConstraint, scene: VanishingScene) -> VanishingMeasurement?
  {
    let frame = scene.frames[line.plane]
    let start = frame.uv(from), end = frame.uv(to)
    let dx = end.x-start.x, dy = end.y-start.y
    var result = line
    switch target {
    case .body:
      result.start = .init(line.start.x+dx,line.start.y+dy)
      result.end = .init(line.end.x+dx,line.end.y+dy)
    case .start, .end:
      if constraint.keepAngle && constraint.keepLength { return line }
      let isStart = target == .start(target.index)
      let fixed = isStart ? line.end : line.start
      let moving = isStart ? line.start : line.end
      let metric = scene.measurementMetric(for:line.plane)
      let original = PathPoint((moving.x-fixed.x)*metric.x,(moving.y-fixed.y)*metric.y)
      let proposed = PathPoint(original.x+dx*metric.x,original.y+dy*metric.y)
      let vector = constraint.vector(from:original,proposed:proposed)
      let point = PathPoint(fixed.x+vector.x/metric.x,fixed.y+vector.y/metric.y)
      if isStart { result.start = point } else { result.end = point }
    }
    return scene.measurementDistance(result) == nil ? nil : result
  }

  func selectMeasurement(_ index: Int?) {
    selectedMeasurement = index
    if let index, measurements.indices.contains(index) { selected = measurements[index].plane }
  }

  func updateMeasurement(_ line: VanishingMeasurement, at index: Int? = nil) {
    var lines = measurements
    if let index {
      guard lines.indices.contains(index) else { return }
      lines[index] = line
    } else {
      lines.append(line)
    }
    setMeasurements(lines)
    if measurements == lines { selectMeasurement(index ?? lines.count-1) }
  }

  func measurePlaneDimensions(_ index: Int) {
    let lines = measurements + [
      VanishingMeasurement(plane:index,start:.init(1,1),end:.init(1,0)),
      VanishingMeasurement(plane:index,start:.init(1,1),end:.init(0,1))]
    pendingMeasurement = nil
    setMeasurements(lines)
    if measurements == lines { selectMeasurement(lines.count-2) }
  }

  func removeMeasurement() {
    if pendingMeasurement != nil { pendingMeasurement = nil; return }
    guard let index = selectedMeasurement, measurements.indices.contains(index) else { return }
    var lines = measurements
    lines.remove(at:index)
    setMeasurements(lines)
    selectedMeasurement = nil
  }

  private func setMeasurements(_ lines: [VanishingMeasurement]) {
    var draft = program
    draft.settings.measurements = lines.isEmpty ? nil : lines
    change(draft)
  }

  func calibrateMeasurement(length: Double) {
    guard let index = selectedMeasurement, let scene else { return }
    var draft = program
    do {
      let scale = try scene.measurementScale(calibrating:index,to:length,settings:draft.settings)
      draft.settings.setMeasurementScale(scale)
      change(draft)
    } catch {
      self.error = error.localizedDescription
    }
  }
  func setSource(_ p:PathPoint) { guard scene?.plane(at:p) != nil else { error="Choose a source inside a plane.";return };cloneSource=p;cloneAnchor=nil;error=nil }

  func canSampleBrushColor(at point: PathPoint) -> Bool {
    !closed && (!preview || preparedEdit != nil) && point.x >= 0 && point.y >= 0
      && point.x < Double(original.width) && point.y < Double(original.height)
  }

  func sampleBrushColor(at point: PathPoint) {
    guard canSampleBrushColor(at:point) else { return }
    let document = preview ? preparedEdit?.result ?? original : original
    let samplingPreview = preview, token = generation, previousColor = color
    brushColorError = nil
    brushColorTask?.cancel()
    brushColorTask = Task { [weak self] in
      let worker = Task.detached(priority:.userInitiated) {
        try ColorSampling.sample(document,x:point.x,y:point.y,settings:.init())
      }
      do {
        let sample = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard let self, !Task.isCancelled, !self.closed, self.color == previousColor,
          self.preview == samplingPreview, self.generation == token else { return }
        self.color = sample.color
      } catch {
        guard let self, !Task.isCancelled, !self.closed, self.tool == .eyedropper,
          self.preview == samplingPreview, self.generation == token else { return }
        self.brushColorError = error.localizedDescription
      }
    }
  }

  func stroke(_ points:[PathPoint], straight: Bool = false, connect: Bool = false) {
    guard let eventStart=points.first,let scene,let eventPlane=scene.plane(at:eventStart) else { error="Start inside a perspective plane.";return }
    let kind: VanishingOperation.Kind = tool == .stamp ? .clone : .brush
    var first = eventStart
    var plane = eventPlane
    var samples = points
    if straight && connect, kind != .clone || cloneAnchor != nil,
      let previous = program.operations.last, previous.kind == kind,
      let end = previous.points.last, let endpoint = points.last, let previousPlane = scene.plane(at:end),
      previousPlane == eventPlane || (allowMultiSurfaceOperations && scene.measurementRoot(for:previousPlane) == scene.measurementRoot(for:eventPlane)) {
      first = end
      plane = previousPlane
      samples = [end,endpoint]
    }
    var op=VanishingOperation(kind);op.plane=plane;op.points=samples;op.diameter=diameter;op.hardness=hardness;op.opacity=opacity;op.color=color;op.clip=clip
    op.straightStroke = straight ? true : nil
    op.heal = heal == .off ? nil : heal
    op.strokeSelection = marquee
    let canWrap = allowMultiSurfaceOperations && scene.hasMarqueeNeighbors(plane)
    op.wrap = canWrap ? true : nil
    var nextAnchor = cloneAnchor
    if op.kind == .clone {
      guard let source=cloneSource,let sourcePlane=scene.plane(at:source) else { error="Option-click inside a plane to choose a clone source.";return }
      let wraps = canWrap || (allowMultiSurfaceOperations && scene.hasMarqueeNeighbors(sourcePlane))
      op.wrap = wraps ? true : nil
      if aligned,let anchor=cloneAnchor,scene.frames.indices.contains(anchor.plane),
        anchor.plane == plane || (wraps && scene.measurementRoot(for:anchor.plane) == scene.measurementRoot(for:plane)) {
        if wraps {
          guard let donor = scene.linkedStampSource(source,plane:sourcePlane,from:anchor.start,on:anchor.plane,
            to:first,on:plane) else { error = "The aligned Stamp source crosses the perspective horizon."; return }
          op.sourcePoint = donor.point
          op.sourcePlane = donor.plane
        } else {
          let a=scene.frames[plane].metric(anchor.start),b=scene.frames[plane].metric(first),s=scene.frames[sourcePlane].metric(source)
          op.sourcePoint=scene.frames[sourcePlane].projected(.init(s.x+b.x-a.x,s.y+b.y-a.y))
        }
      } else {
        op.sourcePoint=source
        nextAnchor = .init(source:source,start:first,plane:plane)
      }
    }
    var p=program;p.operations.append(op);selected=plane;change(p)
    if program == p { cloneAnchor = nextAnchor }
  }
  func paste(_ source:Surface, tool selectionTool: Tool = .transform, onCanvas: Bool = false) {
    guard onCanvas || scene?.frames.indices.contains(selected)==true else { error="Create or select a plane before pasting.";return }
    var draft = program, operation = VanishingOperation(.paste)
    operation.plane = selected
    operation.source = source
    operation.opacity = opacity
    operation.clip = clip
    if onCanvas {
      operation.canvasPaste = .init(origin:.init(0,0),width:Double(source.width),height:Double(source.height))
    }
    draft.operations.append(operation)
    change(draft)
    guard draft == program else { return }
    selectPaste(draft.operations.count-1)
    tool = selectionTool
  }
  func selectPaste(_ index: Int?) {
    guard let index else { selectedPaste = nil; return }
    guard program.operations.indices.contains(index), program.operations[index].kind == .paste else { return }
    selectedPaste = index
    if program.operations[index].canvasPaste == nil { selected = program.operations[index].plane }
    selectedMarqueePatch = nil
    marquee = nil
  }
  var selectedPasteHeal: VanishingOperation.Heal? {
    guard let i = selectedPaste, program.operations.indices.contains(i),
      program.operations[i].kind == .paste else { return nil }
    return program.operations[i].heal ?? .off
  }
  func setSelectedPasteHeal(_ heal: VanishingOperation.Heal) {
    guard let i = selectedPaste, let current = selectedPasteHeal, heal != current else { return }
    var draft = program
    draft.operations[i].heal = heal == .off ? nil : heal
    change(draft)
  }
  func movePaste(to point:PathPoint) {
    guard let i=selectedPaste,program.operations.indices.contains(i),let scene,let plane=scene.plane(at:point) else { return };var p=program;p.operations[i].plane=plane;p.operations[i].at=scene.frames[plane].uv(point);selected=plane;change(p)
  }
  func pasteLayer(_ id:UUID) { do { guard let layer=original.layers.first(where:{$0.id==id}) else { return };paste(try Renderer.layerSurface(layer,in:original)) } catch { self.error=error.localizedDescription } }
  func pasteClipboard(_ input:ClipboardInput) async {
    do {
      let original=original
      let worker=Task.detached { let content=try ColorManagement.converted(input.decoded(),to:original);return try ClipboardRenderer.preview(content) }
      let pixels=try await worker.value;guard !closed else { return };paste(pixels,tool:.marquee,onCanvas:true)
    } catch { if !closed { self.error=error.localizedDescription } }
  }
  private struct SourcePreview: Sendable {
    let snapshot: RenderSnapshot
    let display: CanvasRasterPreview?
    let overview: RasterPreviewRequest?
    let image: CGImage
    var sample: Surface?

    init(snapshot: RenderSnapshot, display: CanvasRasterPreview?) throws {
      self.snapshot = snapshot
      let original = snapshot.document
      if original.width > Surface.maximumDensePixels / original.height {
        self.display = nil
        let request = try RasterPreviewRequest.overview(width: original.width, height: original.height)
        overview = request
        image = try ColorManagement.displayImage(request.reducing(snapshot.surface), in: original)
      } else if let display {
        self.display = display
        overview = nil
        image = display.base
      } else {
        overview = nil
        image = try ColorManagement.displayImage(snapshot.surface, in: original)
        self.display = CanvasRasterPreview(base: image)
      }
    }

    mutating func samples(for program: VanishingProgram) throws -> Surface {
      guard !program.operations.isEmpty else { return snapshot.surface }
      if let sample { return sample }
      let converted = try snapshot.surface.converted(to: snapshot.document.depth)
      sample = converted
      return converted
    }

    func image(for edit: VanishingEdit) throws -> CGImage {
      guard !edit.program.operations.isEmpty else { return image }
      let rendered = try Renderer.render(edit.result, reusing: snapshot)
      if rendered.update == .unchanged { return image }
      if let overview {
        return try ColorManagement.displayImage(overview.reducing(rendered.surface), in: edit.result)
      }
      return try display?.updating(rendered).base
        ?? ColorManagement.displayImage(rendered.surface, in: edit.result)
    }
  }

  func refresh() {
    guard !closed else { return }
    let debounce = rendering || gestureStart != nil
    task?.cancel()
    generation += 1
    let token = generation, original = original, id = layerID, p = program
    let cached = sourcePreview, snapshot = seedSnapshot, display = seedDisplay
    rendering = true
    error = nil
    preparedEdit = nil
    task=Task { [weak self] in
      do {
        if debounce { try await Task.sleep(for: .milliseconds(70)) }
        let worker = Task.detached(priority: .userInitiated) { () throws -> (SourcePreview, VanishingEdit, CGImage) in
          var source = try cached ?? SourcePreview(snapshot: snapshot ?? Renderer.render(original), display: display)
          let samples = try source.samples(for: p)
          let edit = try VanishingEdit.prepare(original, layerID: id, program: p, sample: samples)
          return (source, edit, try source.image(for: edit))
        }
        let (source, edit, image) = try await withTaskCancellationHandler {
          try await worker.value
        } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        guard let self, !self.closed, self.generation == token else { return }
        self.seedSnapshot = nil
        self.seedDisplay = nil
        self.sourcePreview = source
        self.originalImage = source.image
        self.image = image
        self.preparedEdit = edit
        self.rendering = false
      } catch { guard let self,!self.closed,self.generation==token else { return };self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func measurementRenderRequest() -> (program: VanishingProgram, sample: Surface)? {
    guard renderMeasurements, !measurements.isEmpty, let sourcePreview else { return nil }
    var output = program
    output.renderMeasurements = true
    return (output,sourcePreview.sample ?? sourcePreview.snapshot.surface)
  }
  func presentSceneExport(_ format: VanishingSceneExport.Format) {
    guard canExportScene, sceneExportPanel == nil else { return }
    let revision = generation
    let panel = NSOpenPanel()
    sceneExportPanel = panel
    panel.title = format == .studio ? "Export to 3DS" : "Export for After Effects"
    panel.message = "Choose where to create a folder for the scene and its PNG textures."
    panel.prompt = "Export"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.begin { [weak self, weak panel] response in
      guard let self, let panel, self.sceneExportPanel === panel else { return }
      self.sceneExportPanel = nil
      guard response == .OK, let parent = panel.url, !self.closed, self.generation == revision else { return }
      self.exportScene(format,to:parent)
    }
  }

  func exportScene(_ format: VanishingSceneExport.Format, to parent: URL) {
    guard canExportScene, let source = preparedEdit?.result else { return }
    let revision = generation
    sceneExportMessage = nil
    sceneExportError = nil
    exportingScene = true
    sceneExportTask = Task { @MainActor [weak self] in
      guard let self else { return }
      let scoped = parent.startAccessingSecurityScopedResource()
      defer {
        if scoped { parent.stopAccessingSecurityScopedResource() }
        self.sceneExportTask = nil
        self.exportingScene = false
      }
      do {
        let worker = Task.detached(priority:.userInitiated) {
          let output = try VanishingSceneExport.render(source,format:format)
          let destination = parent.appendingPathComponent(output.name+"-scene",isDirectory:true)
          return try PreparedSequenceFolder.prepare(files:output.files,destination:destination,
            maximumBytes:VanishingSceneExport.maximumBytes)
        }
        let prepared = try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        defer { prepared.discard() }
        try Task.checkCancellation()
        guard !self.closed, self.generation == revision else { throw CancellationError() }
        try prepared.commit()
        self.sceneExportMessage = "Exported "+prepared.destination.lastPathComponent
      } catch is CancellationError {
        if !self.closed { self.sceneExportMessage = "Scene export cancelled" }
      } catch {
        if !self.closed { self.sceneExportError = error.localizedDescription }
      }
    }
  }

  func cancelSceneExport() { sceneExportTask?.cancel() }
  func close() {
    closed = true
    sceneExportPanel?.cancel(nil)
    sceneExportPanel = nil
    cancelSceneExport()
    generation += 1
    task?.cancel()
    task = nil
    brushColorTask?.cancel()
    brushColorTask = nil
    seedSnapshot = nil
    seedDisplay = nil
    sourcePreview = nil
    preparedEdit = nil
    rendering = false
  }
}
extension EditorStore {
  var canBeginVanishingPoint:Bool { !geometryBusy && !hasToneDraft && transformDraft==nil && !editingComponent && !editingMask && activeLayer.map{(try? VanishingEdit.target(document,layerID:$0.id)) != nil} == true }
  func beginVanishingPoint() {
    guard canBeginVanishingPoint, let id = activeLayer?.id else { return }
    let original = document
    let snapshot = renderSnapshotSourceGeneration == sessionGeneration && renderSnapshot?.document == original
      ? renderSnapshot : nil
    let display = snapshot != nil && ordinaryCanvasImage
      && canvasRasterPreview?.base.width == original.width && canvasRasterPreview?.base.height == original.height
      ? canvasRasterPreview : nil
    vanishingWorkspace = VanishingWorkspace(document: original, layerID: id, snapshot: snapshot, display: display)
  }
  func cancelVanishingPoint() { vanishingWorkspace?.close();vanishingWorkspace=nil }
  func commitVanishingPoint() {
    guard let draft = vanishingWorkspace, draft.ready, let edit = draft.preparedEdit, document == edit.source else { return }
    let request = draft.measurementRenderRequest()
    draft.close()
    vanishingWorkspace = nil
    performGeometry(label: "Vanishing Point") { source in
      if let request {
        return .vanishingPoint(try VanishingEdit.prepare(source,layerID:edit.layerID,
          program:request.program,sample:request.sample))
      }
      return .vanishingPoint(edit)
    }
  }
}
@MainActor extension AppDelegate { @objc func vanishingPoint() { store?.beginVanishingPoint() } }
