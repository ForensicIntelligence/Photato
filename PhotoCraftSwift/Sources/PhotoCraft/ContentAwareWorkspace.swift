import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct ContentAwareState: Equatable, Sendable {
  var settings = ContentAwareSettings()
  var output: ContentAwareOutput = .new
  var strokes: [ContentAwareStroke] = []
  var samplingID: UUID?
}
@MainActor @Observable final class ContentAwareWorkspace: Identifiable {
  let id = UUID()
  var state = ContentAwareState()
  var input: ContentAwareInput?
  var tool: ContentAwareStroke.Target = .sampling
  var kind: ContentAwareStroke.Kind = .brush
  var add = false
  var size = 30.0
  var panTool = false
  var zoom = 1.0
  var pan = CGSize.zero
  var showSampling = true
  var excludedOverlay = false
  var overlayOpacity = 0.5
  var overlayColor = Pixel(0,1,0)
  var showOriginal = false
  var originalImage: CGImage?
  var samplingImage: CGImage?
  var previewImage: CGImage?
  var edit: ContentAwareEdit?
  var sampled: SelectionMask?
  var selected: SelectionMask?
  var error: String?
  var loading = false
  var rendering = false
  var committing = false
  var task: Task<Void,Never>?
  var overlayTask: Task<Void,Never>?
  var commitTask: Task<Void,Never>?
  var stroke: ContentAwareStroke?
  var undoStates: [ContentAwareState] = []
  var redoStates: [ContentAwareState] = []
  private var generation = 0
  private var closed = false
  var ready: Bool { input != nil && !loading && !committing && !closed }
  var canCommit: Bool { ready && !rendering && edit != nil && error == nil }
  func prepare(_ document: CraftDocument,layerID: UUID) async {
    loading = true
    do {
      let worker = Task.detached(priority:.userInitiated) {
        let input = try ContentAwareInput.prepare(document,layerID:layerID)
        return (input,try ColorManagement.displayImage(input.composite,in:document))
      }
      let input = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation(); guard !closed else { return }; self.input = input.0; originalImage = input.1; samplingImage = input.1
      loading = false; refresh()
    } catch { if !closed && !Task.isCancelled { self.error = error.localizedDescription }; loading = false }
  }
  func change(_ next: ContentAwareState,remember: Bool = true) {
    guard !closed && !committing else { return }
    do { try next.settings.validate() } catch { self.error = error.localizedDescription; return }
    if remember && next != state { undoStates.append(state); if undoStates.count > 24 { undoStates.removeFirst() }; redoStates = [] }
    state = next; refresh()
  }
  func begin(x: Double,y: Double,alternate: Bool) {
    guard ready, stroke == nil else { return }
    var s = ContentAwareStroke(); s.target = tool; s.kind = kind; s.add = alternate ? !add:add; s.size = size; s.points = [[x,y]]
    do { try s.validate(); stroke = s } catch { self.error = error.localizedDescription }
  }
  func drag(x: Double,y: Double) { guard ready, let s = stroke, s.points.count < 4096 else { return }; stroke?.points.append([x,y]) }
  func end() { guard let stroke else { return }; self.stroke = nil; var next = state; next.strokes.append(stroke); change(next) }
  func undo() { stroke = nil; guard let old = undoStates.popLast() else { return }; redoStates.append(state); change(old,remember:false) }
  func redo() { guard let next = redoStates.popLast() else { return }; undoStates.append(state); change(next,remember:false) }
  func reset() { change(ContentAwareState()) }
  func resetSampling() { var next = state; next.strokes.removeAll { $0.target == .sampling }; next.samplingID = nil; next.settings.sampling = .auto; change(next) }
  func refresh() {
    guard !closed, let input else { return }
    generation += 1; let request = generation, state = state
    task?.cancel(); rendering = true; edit = nil; error = nil
    task = Task { [weak self] in
      do {
        let worker = Task.detached(priority:.userInitiated) { () throws -> (SelectionMask,SelectionMask,ContentAwareEdit?,CGImage?,String?) in
          let sampling = try state.samplingID.map { try input.original.channel(.alpha($0)).selection() }
          let masks = try input.masks(settings:state.settings,strokes:state.strokes,sampling:sampling)
          do {
            let edit = try input.edit(settings:state.settings,output:state.output,strokes:state.strokes,sampling:sampling)
            let result = try edit.applied(to:input.original)
            return (masks.selection,masks.sampling,edit,try ColorManagement.displayImage(Renderer.composite(result),in:result),nil)
          } catch is CancellationError { throw CancellationError() }
          catch { return (masks.selection,masks.sampling,nil,nil,error.localizedDescription) }
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation(); guard let self,!self.closed,self.generation == request else { return }
        self.selected = result.0; self.sampled = result.1; self.edit = result.2; self.previewImage = result.3; self.error = result.4; self.refreshOverlay()
      } catch { if let self,!self.closed,self.generation == request,!Task.isCancelled { self.error = error.localizedDescription } }
      if let self,self.generation == request { self.rendering = false }
    }
    // Show the source immediately, even while synthesis is running or a custom sampling region is empty.
    refreshOverlay()
  }
  func refreshOverlay() {
    guard let input,!closed else { return }; overlayTask?.cancel()
    let sample = sampled, selection = selected ?? input.selection, visible = showSampling, excluded = excludedOverlay, opacity = overlayOpacity, color = overlayColor
    overlayTask = Task { [weak self] in
      do {
        let worker = Task.detached(priority:.utility) { try Self.overlay(input.composite,document:input.original,sampling:sample,selection:selection,visible:visible,excluded:excluded,opacity:opacity,color:color) }
        let image = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation(); if self?.closed == false { self?.samplingImage = image }
      } catch {}
    }
  }
  nonisolated static func overlay(_ image: Surface,document: CraftDocument,sampling: SelectionMask?,selection: SelectionMask,visible: Bool,excluded: Bool,opacity: Double,color: Pixel) throws -> CGImage {
    let factor = min(1,1024/Double(max(image.width,image.height))),w = max(1,Int(Double(image.width)*factor)),h = max(1,Int(Double(image.height)*factor))
    var out = try Surface(width:w,height:h)
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let sx = min(image.width-1,Int(Double(x)/factor)),sy = min(image.height-1,Int(Double(y)/factor)),i = sy*image.width+sx,p = image.pixel(x:sx,y:sy)
      let checker: Float = (x/12+y/12)%2 == 0 ? 0.75:0.6
      let a = Float(sampling?.byte(at:i) ?? 0)/255,k = visible ? (excluded ? 1-a:a)*Float(opacity):0
      var rgb = (p.rgb*p.a+SIMD3(repeating:checker*(1-p.a)))*(1-k)+color.rgb*k
      if selection.byte(at:i) > 0 && (sx == 0 || sy == 0 || sx+1 == image.width || sy+1 == image.height || selection.byte(at:i-1) == 0 || selection.byte(at:i+1) == 0 || selection.byte(at:i-image.width) == 0 || selection.byte(at:i+image.width) == 0) { rgb = SIMD3(repeating:(x+y)%8 < 4 ? 1:0) }
      out.setPixel(x:x,y:y,Pixel(rgb.x,rgb.y,rgb.z))
    } }
    return try ColorManagement.displayImage(out,in:document)
  }
  func close() { closed = true; generation += 1; task?.cancel(); overlayTask?.cancel(); commitTask?.cancel() }
}
