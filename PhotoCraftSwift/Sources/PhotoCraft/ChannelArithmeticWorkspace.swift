import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class ChannelArithmeticWorkspace: Identifiable {
  let id=UUID()
  let source:CraftDocument
  let sources:[CraftDocument]
  let target:ChannelArithmeticTarget?
  var request:ChannelArithmeticRequest
  var preview=true
  var image:CGImage?
  var originalImage:CGImage?
  var rendering=false
  var committing=false
  var closed=false
  var error:String?
  var prepared:PreparedChannelArithmetic?
  @ObservationIgnored var generation=0
  @ObservationIgnored var task:Task<Void,Never>?
  @ObservationIgnored var commitTask:Task<Void,Never>?
  init(document:CraftDocument,sources:[CraftDocument],target:ChannelArithmeticTarget?,kind:ChannelArithmeticRequest.Kind) {
    self.source=document;self.sources=sources;self.target=target;request = .init(kind)
  }
  var ready:Bool {prepared != nil && !rendering && !committing && !closed && error==nil}
  var documents:[CraftDocument] {[source]+sources.filter{$0.id != source.id}}
  func document(for value:ChannelArithmeticSource)->CraftDocument {documents.first{$0.id==(value.documentID ?? source.id)} ?? source}
  func update(_ body:(inout ChannelArithmeticRequest)->Void) {guard !closed,!committing else{return};body(&request);refresh()}
  func refresh() {
    guard !closed,!committing else{return};task?.cancel();generation+=1
    let token=generation,request=request,source=source,sources=sources,target=target
    rendering=true;error=nil;prepared=nil
    task=Task {[weak self] in
      do {
        try await Task.sleep(for:.milliseconds(80))
        let worker=Task.detached(priority:.userInitiated) { ()throws->(PreparedChannelArithmetic,CGImage,CGImage) in
          let result=try ChannelArithmeticPreparation.prepare(request,target:target,document:source,sources:sources)
          var edited=source
          if let command=result.command {try command.apply(to:&edited)}
          let model=result.newDocument ?? edited
          let surface:Surface
          if request.kind == .calculations,request.result == .newChannel,let id=result.channelID {surface=try model.channel(.alpha(id)).pixels}
          else if request.kind == .calculations,request.result == .selection {surface=try AlphaChannel.coverage(model.coverageSelection(),width:model.width,height:model.height,depth:.u8)}
          else if request.kind == .applyImage,let target {
            switch target {
            case .alpha(let id):surface=try model.channel(.alpha(id)).pixels
            case .quickMask:surface=try model.channel(.quickMask).pixels
            case .layerMask(let id):surface=try model.layers.first{$0.id==id}?.mask ?? Renderer.composite(model)
            case .ink(let ink):surface=try model.inkChannel(ink).surface()
            case .pixels:surface=try Renderer.composite(model)
            }
          } else {surface=try Renderer.composite(model)}
          func bounded(_ surface:Surface)throws->Surface {
            let scale=min(1,900/Double(max(surface.width,surface.height)))
            return try surface.reducedPreview(in:.init(x:0,y:0,width:surface.width,height:surface.height),width:max(1,Int(Double(surface.width)*scale)),height:max(1,Int(Double(surface.height)*scale)))
          }
          let before:Surface
          if request.kind == .applyImage,let target {
            switch target {
            case .alpha(let id):before=try source.channel(.alpha(id)).pixels
            case .quickMask:before=try source.channel(.quickMask).pixels
            case .layerMask(let id):before=try source.layers.first{$0.id==id}?.mask ?? Renderer.composite(source)
            case .ink(let ink):before=try source.inkChannel(ink).surface()
            case .pixels:before=try Renderer.composite(source)
            }
          }else{before=try Renderer.composite(source)}
          return (result,try ColorManagement.displayImage(bounded(surface),in:model),try ColorManagement.displayImage(bounded(before),in:source))
        }
        let value=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self,!self.closed,self.generation==token else{return}
        self.prepared=value.0;self.image=value.1;self.originalImage=value.2;self.rendering=false
      }catch {guard let self,!self.closed,self.generation==token else{return};self.rendering=false;if !Task.isCancelled{self.error=error.localizedDescription}}
    }
  }
  func close() {closed=true;generation+=1;task?.cancel();commitTask?.cancel();task=nil;commitTask=nil;prepared=nil;rendering=false}
}
