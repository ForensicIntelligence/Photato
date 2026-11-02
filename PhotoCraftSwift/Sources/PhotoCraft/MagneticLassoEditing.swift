import AppKit
import PhotoCraftCore
import PhotoCraftImaging

@MainActor final class MagneticLassoDraft {
  let original:CraftDocument
  let initialSettings:MagneticLassoSettings
  let mode:SelectionMode
  var events:[MagneticLassoEvent]=[]
  var trace:MagneticLassoTrace
  var input:MagneticLassoInput?
  var latest:SelectionPoint?
  var loading=true
  var processing=false
  var finishing=false
  var closed=false
  var alternateReady:Bool
  var error:String?
  var task:Task<Void,Never>?
  var commitTask:Task<Void,Never>?
  var feedback:(@MainActor ()->Void)?
  private var processed=0
  init(_ original:CraftDocument,settings:MagneticLassoSettings,mode:SelectionMode,option:Bool)throws {
    self.original=original;initialSettings=settings;trace=try .init(settings:settings);self.mode=mode;alternateReady = !option
  }
  func prepare(using preparation:@escaping @Sendable(CraftDocument)throws->MagneticLassoInput)async {
    let original=original
    do {
      let worker=Task.detached(priority:.userInitiated){try preparation(original)}
      let input=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
      try Task.checkCancellation();guard !closed else{return};self.input=input
    }catch{if !Task.isCancelled && !closed {self.error=error.localizedDescription}}
    loading=false;process();feedback?()
  }
  func append(_ event:MagneticLassoEvent) {
    guard !closed,!finishing else{return}
    guard events.count<100_000 else {error="Magnetic Lasso supports 100,000 trace events.";feedback?();return}
    if event.kind == .move,let p=event.point,let last=latest,hypot(p.x-last.x,p.y-last.y)<0.5{return}
    events.append(event);if let point=event.point {latest=point};process();feedback?()
  }
  func process() {
    guard !closed,!processing,!loading,error==nil,let input,processed<events.count else{return}
    let end=events.count,batch=Array(events[processed..<end]),previous=trace
    processing=true
    task=Task { [weak self] in
      do {
        let worker=Task.detached(priority:.userInitiated) {var trace=previous;for event in batch {try trace.append(event,image:input.image)};return trace}
        let result=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation();if let self,!self.closed {self.trace=result;self.processed=end}
      }catch{if let self,!Task.isCancelled,!self.closed {self.error=error.localizedDescription}}
      guard let self else{return};self.processing=false;self.feedback?();self.process()
    }
  }
  func settle()async {while !closed && error==nil && (loading || processing || processed<events.count) {await task?.value;await Task.yield()}}
  func close(){closed=true;task?.cancel();commitTask?.cancel();feedback?();feedback=nil}
}
@MainActor extension EditorStore {
  var nativeMagneticSettings:MagneticLassoSettings {var value=magneticSettings;value.feather=selectionFeather;value.antiAlias=selectionAntiAlias;return value}
  var canBeginMagneticLasso:Bool {canBeginColorRange && document.depth != .f32}
  func beginMagneticLasso(at point:SelectionPoint,modifiers:NSEvent.ModifierFlags,feedback:@escaping @MainActor ()->Void) {
    guard canBeginMagneticLasso else {status="Magnetic Lasso requires an available RGB8 or RGB16 document target.";return}
    do {
      let draft=try MagneticLassoDraft(document,settings:nativeMagneticSettings,mode:selectionMode(modifiers:modifiers),option:modifiers.contains(.option));draft.feedback=feedback;magneticDraft=draft
      draft.append(.init(.anchor,point:point));let preparation=magneticPreparation;draft.task=Task {await draft.prepare(using:preparation)}
      status="Trace an edge · Click to fasten · Delete removes a point · Return closes · Esc cancels"
    }catch{self.error=error.localizedDescription}
  }
  func cancelMagneticLasso(){magneticDraft?.close();magneticDraft=nil}
  func finishMagneticLasso(straight:Bool=false) {
    guard let draft=magneticDraft,!draft.finishing else{return};draft.finishing=true;draft.feedback?()
    draft.commitTask=Task { [weak self,weak draft] in
      guard let draft else{return};await draft.settle()
      do {
        try Task.checkCancellation();guard !draft.closed,draft.error==nil,let input=draft.input else {throw CraftError.invalid(draft.error ?? "Magnetic Lasso input is unavailable.")}
        let trace=draft.trace,mode=draft.mode
        let worker=Task.detached(priority:.userInitiated) {try PreparedEdit(command:.magneticSelection(trace.mask(image:input.image,straight:straight),mode),document:input.original)}
        let edit=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,self.magneticDraft === draft,self.document == input.original else {throw CraftError.invalid("The document changed. Start Magnetic Lasso again.")}
        try self.executeCompositePreparedEdit(edit);if self.document != input.original {self.onChange?(.changeDone)}
        self.magneticDraft=nil;draft.close();self.status="Magnetic Lasso";self.render()
      }catch{if !Task.isCancelled && !draft.closed {draft.error=error.localizedDescription;self?.status=error.localizedDescription}}
      draft.finishing=false;draft.feedback?()
    }
  }
}
