import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class LensCorrectionWorkspace {
  enum Tool:String,CaseIterable { case distortion="Remove Distortion",straighten="Straighten",hand="Hand",grid="Move Grid" }
  var settings=LensCorrectionSettings()
  var tool:Tool = .distortion
  var image:CGImage?
  var originalImage:CGImage?
  var documentSize=CGSize(width:1,height:1)
  var sourceSize=CGSize(width:1,height:1)
  var sourceTransform=Transform2D.identity
  var preview=true
  var showGrid=true
  var gridSize=40.0
  var gridOrigin=CGPoint.zero
  var pan=CGSize.zero
  var zoom=1.0
  var effectiveScale=100.0
  var rendering=false
  var error:String?
  var undoStates=[LensCorrectionSettings]()
  var redoStates=[LensCorrectionSettings]()
  @ObservationIgnored var task:Task<Void,Never>?
  private var document:CraftDocument?
  private var draft:FilterDraft?
  private var gestureStart:LensCorrectionSettings?
  private var generation=0
  private var closed=false
  var ready:Bool { image != nil && !rendering && error == nil }
  func prepare(document:CraftDocument,draft:FilterDraft) async {
    self.document=document;self.draft=draft;settings=draft.filter.lens ?? .init();closed=false
    documentSize=CGSize(width:document.width,height:document.height)
    if let layer=document.layers.first(where:{$0.id==draft.id}),case .raster(let pixels)=layer.content { sourceSize=CGSize(width:pixels.width,height:pixels.height);sourceTransform=layer.coordinateTransform }
    refresh();await task?.value
  }
  func remember(_ s:LensCorrectionSettings) { undoStates.append(s);if undoStates.count>100 { undoStates.removeFirst() };redoStates=[] }
  func change(_ s:LensCorrectionSettings,remember:Bool=true) {
    do { try s.validate() } catch { self.error=error.localizedDescription;return }
    guard s != settings else { error=nil;return }
    if remember && gestureStart == nil { self.remember(settings) };settings=s;refresh()
  }
  func beginGesture() { if gestureStart==nil { gestureStart=settings } }
  func endGesture() { if let before=gestureStart,before != settings { remember(before) };gestureStart=nil }
  func slider(_ active:Bool) { if active { beginGesture() } else { endGesture() } }
  func undo() { endGesture();guard let s=undoStates.popLast() else { return };redoStates.append(settings);change(s,remember:false) }
  func redo() { endGesture();guard let s=redoStates.popLast() else { return };undoStates.append(settings);change(s,remember:false) }
  func straighten(_ a:PathPoint,_ b:PathPoint) {
    guard hypot(a.x-b.x,a.y-b.y)>1e-6 else { return };var s=settings
    let correction=LensCorrectionEngine.straightenAngle(a,b,width:Int(sourceSize.width),height:Int(sourceSize.height));s.angle=min(360,max(-360,s.angle+correction));s.straighten=nil;change(s)
  }
  func distort(from a:PathPoint,to b:PathPoint) {
    var s=gestureStart ?? settings
    s.distortion=min(100,max(-100,s.distortion+(hypot(a.x-0.5,a.y-0.5)-hypot(b.x-0.5,b.y-0.5))*200));change(s)
  }
  func refresh() {
    guard !closed,let document,var draft else { return };task?.cancel();generation+=1;let token=generation,needsOriginal=originalImage==nil,s=settings
    draft.filter.lens=s;let request=draft;rendering=true;error=nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { () throws -> (CGImage,CGImage?,Double,CGSize,Transform2D) in
          let layer=try request.inputLayer(in:document)
          guard case .raster(let input)=layer.content else { throw CraftError.invalid("Lens Correction requires pixels.") }
          let size=CGSize(width:input.width,height:input.height),transform=layer.coordinateTransform
          var edited=document;try request.command(in:document).apply(to:&edited)
          return (try ColorManagement.displayImage(Renderer.composite(edited),in:document),needsOriginal ? try ColorManagement.displayImage(Renderer.composite(document),in:document):nil,try LensCorrectionEngine.resolvedScale(s,width:Int(size.width),height:Int(size.height)),size,transform)
        }
        let result=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation==token else { return };self.image=result.0;if let original=result.1 { self.originalImage=original };self.effectiveScale=result.2;self.sourceSize=result.3;self.sourceTransform=result.4;self.rendering=false
      } catch { guard let self,!self.closed,self.generation==token else { return };self.rendering=false;if !Task.isCancelled { self.error=error.localizedDescription } }
    }
  }
  func close() { closed=true;generation+=1;task?.cancel();task=nil;rendering=false }
}
