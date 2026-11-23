import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class VanishingWorkspace:Identifiable {
  enum Tool:String,CaseIterable { case create="Create Plane",edit="Edit Plane",stamp="Stamp",brush="Brush",transform="Transform",hand="Hand" }
  let id=UUID()
  let original:CraftDocument
  let layerID:UUID
  private(set) var program=VanishingProgram()
  var tool:Tool = .create
  var selected=0
  var selectedCorner=0
  var selectedPaste:Int?
  var pending=[PathPoint]()
  var cloneSource:PathPoint?
  var diameter=40.0
  var hardness=50.0
  var opacity=100.0
  var color=Pixel.black
  var clip=true
  var aligned=true
  var image:CGImage?
  var originalImage:CGImage?
  var showGrid=true
  var gridSize=10.0
  var preview=true
  var rendering=false
  var zoom=1.0
  var pan=CGSize.zero
  var error:String?
  var undoStates=[VanishingProgram]()
  var redoStates=[VanishingProgram]()
  @ObservationIgnored var task:Task<Void,Never>?
  @ObservationIgnored private var seedSnapshot: RenderSnapshot?
  @ObservationIgnored private var seedDisplay: CanvasRasterPreview?
  @ObservationIgnored private var sourcePreview: SourcePreview?
  private(set) var preparedEdit: VanishingEdit?
  private var generation=0
  private var closed=false
  private var gestureStart:VanishingProgram?
  private var cloneAnchor:PathPoint?
  private var clonePlane:Int?
  var size:CGSize { .init(width:original.width,height:original.height) }
  var scene:VanishingScene? { try? VanishingScene(program.settings,width:original.width,height:original.height) }
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
  func remember(_ p:VanishingProgram) { undoStates.append(p);if undoStates.count>40 { undoStates.removeFirst() };redoStates=[] }
  func change(_ p:VanishingProgram,remember:Bool=true) {
    do { try p.validate();_ = try VanishingScene(p.settings,width:original.width,height:original.height) } catch { self.error=error.localizedDescription;return }
    guard p != program else { error=nil;return };if remember && gestureStart==nil { self.remember(program) };program=p;selected=max(0,min(selected,p.settings.planes.count-1));if let i=selectedPaste,!p.operations.indices.contains(i) { selectedPaste=nil };refresh()
  }
  func beginGesture() { if gestureStart==nil { gestureStart=program } }
  func endGesture() { if let start=gestureStart,start != program { remember(start) };gestureStart=nil }
  func undo() { if !pending.isEmpty { pending.removeLast();return };endGesture();guard let p=undoStates.popLast() else { return };redoStates.append(program);change(p,remember:false) }
  func redo() { endGesture();guard let p=redoStates.popLast() else { return };undoStates.append(program);change(p,remember:false) }
  func addPoint(_ p:PathPoint) {
    pending.append(p);guard pending.count==4 else { return };var next=program;next.settings.planes.append(.init(corners:pending))
    do { try next.validate();_ = try VanishingScene(next.settings,width:original.width,height:original.height);pending=[];selected=next.settings.planes.count-1;change(next);tool = .edit } catch { pending.removeLast();self.error=error.localizedDescription }
  }
  func moveCorner(_ plane:Int,_ corner:Int,to p:PathPoint) {
    guard program.settings.planes.indices.contains(plane),program.settings.planes[plane].parent==nil else { return };var next=program;next.settings.planes[plane].corners[corner]=p;selected=plane;selectedCorner=corner;change(next)
  }
  func movePlane(_ plane:Int,dx:Double,dy:Double) {
    var next=gestureStart ?? program;guard next.settings.planes.indices.contains(plane),next.settings.planes[plane].parent==nil else { return };next.settings.planes[plane].corners=next.settings.planes[plane].corners.map{.init($0.x+dx,$0.y+dy)};change(next)
  }
  func tear(_ edge:VanishingPlane.Edge) { guard program.settings.planes.indices.contains(selected) else { return };var p=program;p.settings.planes.append(.init(parent:selected,edge:edge));let count=p.settings.planes.count;change(p);if program.settings.planes.count==count { selected=count-1 } }
  func detach() { guard let scene,scene.frames.indices.contains(selected) else { return };var p=program;p.settings.planes[selected] = .init(corners:scene.frames[selected].corners);change(p) }
  func removePlane() {
    guard program.settings.planes.indices.contains(selected) else { return };var removed:Set<Int>=[selected]
    for i in program.settings.planes.indices { if let parent=program.settings.planes[i].parent,removed.contains(parent) { removed.insert(i) } }
    let remaining=program.settings.planes.indices.filter{!removed.contains($0)},map=Dictionary(uniqueKeysWithValues:remaining.enumerated().map{($0.element,$0.offset)})
    var p=program;p.settings.planes=remaining.map { i in var plane=program.settings.planes[i];plane.parent=plane.parent.flatMap{map[$0]};return plane };p.operations=p.operations.compactMap { op in guard let index=map[op.plane] else { return nil };var op=op;op.plane=index;return op };selectedPaste=nil;change(p)
  }
  func setSource(_ p:PathPoint) { guard scene?.plane(at:p) != nil else { error="Choose a source inside a plane.";return };cloneSource=p;cloneAnchor=nil;clonePlane=nil;error=nil }
  func stroke(_ points:[PathPoint]) {
    guard let first=points.first,let scene,let plane=scene.plane(at:first) else { error="Start inside a perspective plane.";return }
    var op=VanishingOperation(tool == .stamp ? .clone:.brush);op.plane=plane;op.points=points;op.diameter=diameter;op.hardness=hardness;op.opacity=opacity;op.color=color;op.clip=clip
    if op.kind == .clone {
      guard let source=cloneSource,let sourcePlane=scene.plane(at:source) else { error="Option-click inside a plane to choose a clone source.";return }
      if aligned,let anchor=cloneAnchor,clonePlane==plane {
        let a=scene.frames[plane].metric(anchor),b=scene.frames[plane].metric(first),s=scene.frames[sourcePlane].metric(source)
        op.sourcePoint=scene.frames[sourcePlane].projected(.init(s.x+b.x-a.x,s.y+b.y-a.y))
      } else { op.sourcePoint=source;cloneAnchor=first;clonePlane=plane }
    }
    var p=program;p.operations.append(op);selected=plane;change(p)
  }
  func paste(_ source:Surface) {
    guard scene?.frames.indices.contains(selected)==true else { error="Create or select a plane before pasting.";return }
    var p=program,op=VanishingOperation(.paste);op.plane=selected;op.source=source;op.opacity=opacity;op.clip=clip;p.operations.append(op);selectedPaste=p.operations.count-1;change(p);tool = .transform
  }
  func movePaste(to point:PathPoint) {
    guard let i=selectedPaste,program.operations.indices.contains(i),let scene,let plane=scene.plane(at:point) else { return };var p=program;p.operations[i].plane=plane;p.operations[i].at=scene.frames[plane].uv(point);selected=plane;change(p)
  }
  func pasteLayer(_ id:UUID) { do { guard let layer=original.layers.first(where:{$0.id==id}) else { return };paste(try Renderer.layerSurface(layer,in:original)) } catch { self.error=error.localizedDescription } }
  func pasteClipboard(_ input:ClipboardInput) async {
    do {
      let original=original
      let worker=Task.detached { let content=try ColorManagement.converted(input.decoded(),to:original);return try ClipboardRenderer.preview(content) }
      let pixels=try await worker.value;guard !closed else { return };paste(pixels)
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
  func close() {
    closed = true
    generation += 1
    task?.cancel()
    task = nil
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
    draft.close()
    vanishingWorkspace = nil
    performGeometry(label: "Vanishing Point") { _ in .vanishingPoint(edit) }
  }
}
@MainActor extension AppDelegate { @objc func vanishingPoint() { store?.beginVanishingPoint() } }
