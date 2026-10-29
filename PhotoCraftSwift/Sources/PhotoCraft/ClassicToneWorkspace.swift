import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class ClassicToneWorkspace:Identifiable {
  let id=UUID()
  let source:CraftDocument
  var request:ClassicToneRequest
  var image:CGImage?
  var originalImage:CGImage?
  var preview=true
  var rendering=false
  var committing=false
  var fit=true
  var zoom=1.0
  var error:String?
  var undoStates=[ClassicToneRequest]()
  var redoStates=[ClassicToneRequest]()
  @ObservationIgnored var task:Task<Void,Never>?
  @ObservationIgnored var commitTask:Task<Void,Never>?
  private var closed=false
  private var generation=0
  private var gestureStart:ClassicToneRequest?
  var filterDraft:FilterDraft?
  var maskImage:CGImage?
  var samplingSurface:Surface?
  var maskPreview=false
  var showMore=false
  var sampleMode="replace"
  var sourceDocumentID:UUID?
  var sourceLayerID:UUID?
  var useSelectionInSource=false
  var sourceBusy=false
  @ObservationIgnored var sourceTask:Task<Void,Never>?
  private var sourceGeneration=0
  var sources:[CraftDocument]=[]
  init(document:CraftDocument,request:ClassicToneRequest,filterDraft:FilterDraft?=nil,sources:[CraftDocument]=[]) {
    source=document;self.request=request;self.filterDraft=filterDraft;self.sources=sources
  }
  var selectedSource:CraftDocument? {sources.first{$0.id==sourceDocumentID}}
  func command(_ request:ClassicToneRequest)throws->Command {
    if var draft=filterDraft {draft.filter.tone=request.settings;return try draft.command(in:source)}
    return try ClassicToneInput.command(request,in:source)
  }
  var ready:Bool {image != nil && !rendering && !committing && !closed && !sourceBusy && error==nil}
  var apiState:[String:Any] {
    ["kind":request.settings.kind.rawValue,"settings":request.settings.apiParameters,"preview":preview,"zoom":zoom,"fit":fit,"canUndo":!undoStates.isEmpty,"canRedo":!redoStates.isEmpty,"error":error as Any? ?? NSNull()]
  }
  func remember(_ value:ClassicToneRequest) {undoStates.append(value);if undoStates.count>100{undoStates.removeFirst()};redoStates=[]}
  func change(_ value:ClassicToneRequest,remember:Bool=true) {
    guard !closed,!committing else{return}
    do {try value.validate();guard value.settings.kind==request.settings.kind,value.layerID==request.layerID else{throw CraftError.invalid("Cannot change adjustment kind or target during preview.")}}
    catch {self.error=error.localizedDescription;return}
    guard value != request else{if error != nil{refresh()};return}
    if remember && gestureStart==nil {self.remember(request)};request=value;refresh()
  }
  func update(_ edit:(inout ClassicToneRequest)->Void) {var next=request;edit(&next);change(next)}
  func beginGesture() {if !closed,!committing,gestureStart==nil{gestureStart=request}}
  func endGesture() {if let old=gestureStart,old != request {remember(old)};gestureStart=nil}
  func undo() {guard !committing else{return};endGesture();guard let old=undoStates.popLast() else{return};redoStates.append(request);change(old,remember:false)}
  func redo() {guard !committing else{return};endGesture();guard let next=redoStates.popLast() else{return};undoStates.append(request);change(next,remember:false)}
  func refresh() {
    guard !closed,!committing else{return};task?.cancel();generation+=1
    let token=generation,request=request,source=source,needOriginal=originalImage==nil,draft=filterDraft;rendering=true;error=nil
    task=Task { [weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { ()throws->(CGImage,CGImage?,CGImage?,Surface?) in
          var edited=source
          if var draft {draft.filter.tone=request.settings;try draft.command(in:source).apply(to:&edited)}
          else {try ClassicToneInput.command(request,in:source).apply(to:&edited)}
          var maskImage:CGImage?,sampling:Surface?
          if request.settings.kind == .replaceColor,let id=request.layerID ?? source.activeLayerID,let layer=source.layers.first(where:{$0.id==id}),case .raster(let pixels)=layer.content {
            let surface=try RasterGeometry.render(pixels,transform:layer.coordinateTransform,bounds:IntRect(x:0,y:0,width:source.width,height:source.height),method:.bicubic,clampEdges:false)
            sampling=surface
            let mask=try ClassicToneEngine.replacementMask(surface,settings:request.settings)
            var image=try Surface(width:source.width,height:source.height)
            for y in 0..<source.height {try Task.checkCancellation();for x in 0..<source.width {let v=mask[y*source.width+x];image.setPixel(x:x,y:y,Pixel(v,v,v))}}
            maskImage=try RasterIO.displayImage(image)
          }
          return (try ColorManagement.displayImage(Renderer.composite(edited),in:edited),needOriginal ? try ColorManagement.displayImage(Renderer.composite(source),in:source):nil,maskImage,sampling)
        }
        let result=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,!self.closed,self.generation==token else{return};self.image=result.0;if let image=result.1{self.originalImage=image};self.maskImage=result.2;self.samplingSurface=result.3;self.rendering=false
      }catch {guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled{self.error=error.localizedDescription}}
    }
  }
  func sample(_ point:PathPoint) {
    guard request.settings.kind == .replaceColor,let surface=samplingSurface,point.x.isFinite,point.y.isFinite else{return}
    let x=min(surface.width-1,max(0,Int(point.x*Double(surface.width)))),y=min(surface.height-1,max(0,Int(point.y*Double(surface.height))))
    var color=surface.pixel(x:x,y:y);color.a=1
    let sample=ToneColorSample(color:color,point:PathPoint(min(1,max(0,point.x)),min(1,max(0,point.y))),subtract:sampleMode=="subtract")
    update {value in if sampleMode=="replace"{value.settings.samples=[sample]}else if value.settings.samples.count<64{value.settings.samples.append(sample)}}
  }
  func calculateSource() {
    sourceTask?.cancel();sourceGeneration+=1;let token=sourceGeneration
    guard let document=selectedSource else{sourceBusy=false;update{$0.settings.sourceStatistics=nil};return}
    let layerID=sourceLayerID,selection=useSelectionInSource;sourceBusy=true;error=nil
    sourceTask=Task {[weak self] in
      do {
        let worker=Task.detached(priority:.userInitiated){try ClassicToneInput.statistics(in:document,layerID:layerID,useSelection:selection)}
        let stats=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,!self.closed,self.sourceGeneration==token else{return};self.sourceBusy=false;self.update{$0.settings.sourceStatistics=stats}
      }catch{guard let self,!self.closed,self.sourceGeneration==token else{return};self.sourceBusy=false;if !Task.isCancelled{self.error=error.localizedDescription}}
    }
  }
  func presetData()throws->Data {
    let body:[String:Any]=["format":"PhotatoTone","version":1,"kind":request.settings.kind.rawValue,"settings":request.settings.apiParameters]
    return try JSONSerialization.data(withJSONObject:body,options:[.prettyPrinted,.sortedKeys])
  }
  func loadPreset(_ data:Data)throws {
    guard data.count<=65536,let p=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(p.keys)==["format","version","kind","settings"],p["format"] as? String=="PhotatoTone",(p["version"] as? NSNumber).map{CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue==1}==true,p["kind"] as? String==request.settings.kind.rawValue,let fields=p["settings"] as? [String:Any] else{throw CraftError.invalid("Choose a matching Photato tone preset.")}
    let settings=try ClassicToneSettings.decodeJSON(JSONSerialization.data(withJSONObject:fields),kind:request.settings.kind);update{$0.settings=settings}
  }
  func close() {closed=true;generation+=1;sourceGeneration+=1;sourceTask?.cancel();task?.cancel();commitTask?.cancel();task=nil;commitTask=nil;sourceTask=nil;rendering=false;sourceBusy=false}
}
