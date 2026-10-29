import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class ProceduralWorkspace:Identifiable {
  let id=UUID()
  let source:CraftDocument
  var request:ProceduralRenderRequest
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var rendering=false
  var committing=false
  var fit=true
  var zoom=1.0
  var error:String?
  var undoStates=[ProceduralRenderRequest]()
  var redoStates=[ProceduralRenderRequest]()
  @ObservationIgnored var task:Task<Void,Never>?
  @ObservationIgnored var commitTask:Task<Void,Never>?
  private var closed=false
  private var generation=0
  private var gestureStart:ProceduralRenderRequest?
  init(document:CraftDocument,request:ProceduralRenderRequest) {
    source=document;var value=request
    if value.settings.kind == .flame {value.path=ProceduralRenderEngine.resolvedPath(request,in:document)}
    self.request=value
  }
  var ready:Bool {image != nil && !rendering && !committing && !closed && error==nil}
  var apiState:[String:Any] {
    ["kind":request.settings.kind.rawValue,"settings":ProceduralAPI.values(request.settings),"newLayer":request.newLayer,"hasPath":request.path != nil,"preview":preview,"zoom":zoom,"fit":fit,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()]
  }
  var paths:[(name:String,path:VectorPath)] {
    var values=(source.paths ?? []).map{(name:$0.name,path:$0.path)}
    if let path=request.path,!values.contains(where:{$0.path==path}) {values.insert(("Selected Path",path),at:0)}
    return values
  }
  func remember(_ value:ProceduralRenderRequest) {undoStates.append(value);if undoStates.count>100{undoStates.removeFirst()};redoStates=[]}
  func change(_ value:ProceduralRenderRequest,remember:Bool=true) {
    guard !closed,!committing else{return}
    do {try value.validate();guard value.settings.kind==request.settings.kind,value.layerID==request.layerID else{throw CraftError.invalid("Cannot change Render kind or target during preview.")}}
    catch {self.error=error.localizedDescription;return}
    guard value != request else{if error != nil{refresh()};return}
    if remember && gestureStart==nil {self.remember(request)};request=value;refresh()
  }
  func update(_ edit:(inout ProceduralRenderRequest)->Void) {var next=request;edit(&next);change(next)}
  func beginGesture() {if !closed,!committing,gestureStart==nil{gestureStart=request}}
  func endGesture() {if let old=gestureStart,old != request {remember(old)};gestureStart=nil}
  func undo() {guard !committing else{return};endGesture();guard let old=undoStates.popLast() else{return};redoStates.append(request);change(old,remember:false)}
  func redo() {guard !committing else{return};endGesture();guard let next=redoStates.popLast() else{return};undoStates.append(request);change(next,remember:false)}
  func refresh() {
    guard !closed,!committing else{return};task?.cancel();generation+=1
    let token=generation,request=request,source=source,needOriginal=originalImage==nil;rendering=true;error=nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { ()throws->(CGImage,CGImage?) in
          var edited=source;try Command.proceduralRender(request).apply(to:&edited)
          return (try ColorManagement.displayImage(Renderer.composite(edited),in:edited),needOriginal ? try ColorManagement.displayImage(Renderer.composite(source),in:source):nil)
        }
        let result=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,!self.closed,self.generation==token else{return};self.image=result.0;if let image=result.1{self.originalImage=image};self.rendering=false
      }catch {guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled{self.error=error.localizedDescription}}
    }
  }
  func setTreeBase(_ point:PathPoint) {
    guard request.settings.kind == .tree,point.x.isFinite,point.y.isFinite else{return}
    update{$0.settings.tree.x=Float(min(1,max(0,point.x)));$0.settings.tree.y=Float(min(1,max(0,point.y)))}
  }
  func close() {closed=true;generation+=1;task?.cancel();commitTask?.cancel();task=nil;commitTask=nil;rendering=false}
}
