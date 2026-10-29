import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct SelectMaskState: Equatable, Sendable {
  var focus:FocusAreaSettings?
  var settings = SelectionRefinement()
  var strokes: [SelectionRefinementStroke] = []
  var initial: SelectionMask?
  var output: SelectionRefinementOutput = .selection
}
enum SelectMaskView: String, CaseIterable, Sendable { case onion = "Onion Skin", overlay = "Overlay", black = "On Black", white = "On White", mask = "Black & White", layers = "On Layers" }
@MainActor @Observable final class SelectMaskWorkspace: Identifiable {
  let id = UUID()
  var state = SelectMaskState()
  var tool: SelectionRefinementStroke.Tool = .add
  var size = 30.0
  var hardness = 0.8
  var view: SelectMaskView = .overlay
  var opacity = 0.5
  var showOriginal = false
  var zoom = 1.0
  var pan = CGSize.zero
  var panTool = false
  var image: CGImage?
  var input: SelectionRefinementInput?
  var focusInput:FocusAreaInput?
  var refinedMask: SelectionMask?
  var error: String?
  var loading = false
  var rendering = false
  var detecting = false
  var committing = false
  var task: Task<Void,Never>?
  var detectionTask: Task<Void,Never>?
  var commitTask: Task<Void,Never>?
  var stroke: SelectionRefinementStroke?
  var undoStates: [SelectMaskState] = []
  var redoStates: [SelectMaskState] = []
  private var generation = 0
  private var closed = false
  private var sliderStart: SelectMaskState?
  var ready: Bool { input != nil && !loading && !detecting && !committing && !closed }
  var isFocus:Bool{state.focus != nil}
  var title:String{isFocus ? "Focus Area":"Select and Mask"}
  var effectiveFocus:FocusAreaSettings?
  var canCommit:Bool{ready && !rendering && error==nil && refinedMask != nil && stroke==nil}
  var effectiveOutput: SelectionRefinementOutput { state.output.allowingDecontamination(state.settings.decontaminate) }
  func prepare(_ original: CraftDocument,layerID: UUID,fromMask: Bool,focus:Bool=false) async {
    loading = true
    do {
      let worker = Task.detached(priority:.userInitiated) { ()throws->(SelectionRefinementInput,FocusAreaInput?) in
        if focus{let value=try FocusAreaInput.prepare(original,layerID:layerID);return (value.refinement,value)}
        return (try SelectionRefinementInput.prepare(original,layerID:layerID,fromLayerMask:fromMask),nil)
      }
      let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
      try Task.checkCancellation(); guard !closed else { return }; input = value.0;focusInput=value.1;state.focus=focus ? .init():nil
      state.output = fromMask ? .layerMask : .selection; refresh()
    } catch { if !closed && !Task.isCancelled { self.error = error.localizedDescription } }
    loading = false
  }
  func remember(_ old: SelectMaskState) {
    guard old != state else { return }; undoStates.append(old); redoStates.removeAll()
    let limit = min(24,max(2,64*1024*1024/max(1,(input?.mask.bytes.count ?? 1))))
    if undoStates.count > limit { undoStates.removeFirst(undoStates.count-limit) }
  }
  func change(_ next: SelectMaskState,remember save: Bool = true) {
    guard !closed && !committing else { return }
    do { try next.settings.validate();try next.focus?.validate() } catch { self.error = error.localizedDescription; return }
    let old = state; state = next; if save { remember(old) }; error = nil; refresh()
  }
  func slider(_ editing: Bool) { if editing { sliderStart = state } else if let old = sliderStart { remember(old); sliderStart = nil } }
  func update(_ key: WritableKeyPath<SelectionRefinement,Double>,_ value: Double) {
    var next = state; next.settings[keyPath:key] = value; change(next,remember:sliderStart == nil)
  }
  func begin(x: Double,y: Double,alternate: Bool) {
    guard ready, stroke == nil else { return }
    let alternateTool: [SelectionRefinementStroke.Tool:SelectionRefinementStroke.Tool] = [.add:.subtract,.subtract:.add,.refine:.eraseRefinement,.eraseRefinement:.refine,.lassoAdd:.lassoSubtract,.lassoSubtract:.lassoAdd]
    let value = SelectionRefinementStroke(tool:alternate ? alternateTool[tool] ?? tool : tool,size:size,hardness:hardness,points:[[x,y]])
    do { try value.validate(); stroke = value; refresh() } catch { self.error = error.localizedDescription }
  }
  func drag(x: Double,y: Double) {
    guard ready, let current = stroke, current.points.count < 4096 else { return }
    stroke?.points.append([x,y]); if tool != .lassoAdd && tool != .lassoSubtract { refresh() }
  }
  func end() {
    guard let stroke else { return }; self.stroke = nil
    var next = state; next.strokes.append(stroke); change(next)
  }
  func undo() { stroke = nil; guard let old = undoStates.popLast() else { return }; redoStates.append(state); change(old,remember:false) }
  func redo() { guard let next = redoStates.popLast() else { return }; undoStates.append(state); change(next,remember:false) }
  func reset() { var next = SelectMaskState(); next.output = state.output;if isFocus{next.focus = .init()}; change(next) }
  func refineFocusEdges(){guard isFocus,canCommit,let mask=refinedMask else{return};var next=state;next.focus=nil;next.initial=mask;next.strokes=[];next.settings = .init();change(next);tool = .add}
  nonisolated static func preparedEdit(input:SelectionRefinementInput,focus:FocusAreaInput?,state:SelectMaskState)throws->SelectionRefinementEdit {
    if let settings=state.focus {guard let focus else{throw CraftError.invalid("Focus analysis is not ready.")};return try focus.edit(settings:settings,output:state.output,strokes:state.strokes)}
    return try input.edit(settings:state.settings,output:state.output,strokes:state.strokes,initial:state.initial)
  }
  func detect(using detector: any ForegroundDetecting) {
    guard ready, let input else { return }; detecting = true
    detectionTask = Task { [weak self] in
      do {
        let worker = Task.detached(priority:.userInitiated) {
          let proxy = try ColorManagement.converted(input.guide,from:input.original,to:CraftDocument(width:1,height:1))
          return try await detector.mask(for:proxy)
        }
        let mask = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        guard let self, !self.closed else { return }; var next = self.state; next.initial = mask; next.strokes = []; self.change(next)
      } catch { if !Task.isCancelled { self?.error = error.localizedDescription } }
      self?.detecting = false
    }
  }
  func refresh() {
    generation += 1
    guard !closed, !rendering, let input else { return }
    let currentGeneration = generation, view = view, opacity = opacity, original = showOriginal,focus = focusInput
    var staged = state; if let stroke { staged.strokes.append(stroke) }
    let state = staged
    rendering = true
    task = Task { [weak self] in
      do {
        let worker = Task.detached(priority:.userInitiated) {
          let mask:SelectionMask
          if state.focus != nil{mask=try Self.preparedEdit(input:input,focus:focus,state:state).mask}
          else{mask=try input.refined(settings:state.settings,strokes:state.strokes,initial:state.initial)}
          let guide = original ? input.guide : try input.previewGuide(mask:mask,settings:state.settings)
          let image = try original && state.focus != nil ? ColorManagement.displayImage(input.guide,in:input.original):Self.preview(input:input,mask:original ? state.initial ?? input.mask : mask,view:view,opacity:opacity,guide:guide)
          return (mask,image,try state.focus.map{try focus?.analysis.effectiveSettings($0)})
        }
        let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        if let self, !self.closed { self.refinedMask = result.0; self.image = result.1; self.effectiveFocus = result.2 ?? nil; self.error = nil }
      } catch { if !Task.isCancelled { self?.error = error.localizedDescription } }
      guard let self else { return }; self.rendering = false
      if !self.closed && self.generation != currentGeneration { self.refresh() }
    }
  }
  nonisolated static func preview(input: SelectionRefinementInput,mask: SelectionMask,view: SelectMaskView,opacity: Double,guide: Surface) throws -> CGImage {
    let factor = min(1,1024/Double(max(mask.width,mask.height)))
    let w = max(1,Int(Double(mask.width)*factor)), h = max(1,Int(Double(mask.height)*factor))
    var out = try Surface(width:w,height:h)
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let sx = min(mask.width-1,Int(Double(x)/factor)), sy = min(mask.height-1,Int(Double(y)/factor))
      let a = Float(mask.bytes[sy*mask.width+sx])/255, p = guide.pixel(x:sx,y:sy)
      let checker: Float = (x/12+y/12)%2 == 0 ? 0.75:0.6
      var rgb: SIMD3<Float>
      switch view {
      case .mask: rgb = SIMD3(repeating:a)
      case .black: rgb = p.rgb*p.a*a
      case .white: rgb = p.rgb*p.a*a+SIMD3(repeating:1-p.a*a)
      case .overlay:
        let base = p.rgb*p.a+SIMD3(repeating:checker*(1-p.a)), k = (1-a)*Float(opacity)
        rgb = base*(1-k)+SIMD3(1,0,0)*k
      case .onion, .layers:
        let alpha = p.a*(view == .onion ? a+(1-a)*(1-Float(opacity)) : a)
        rgb = p.rgb*alpha+SIMD3(repeating:checker*(1-alpha))
      }
      out.setPixel(x:x,y:y,Pixel(rgb.x,rgb.y,rgb.z))
    } }
    return try ColorManagement.displayImage(out,in:input.original)
  }
  func close() { closed = true; task?.cancel(); detectionTask?.cancel(); commitTask?.cancel() }
}
