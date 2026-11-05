import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

struct SkyState:Equatable,Sendable {
  var settings=SkyReplacementSettings()
  var strokes:[SkyMaskStroke]=[]
  var skyID:UUID?
  var sourceLayerID:UUID?
  var useSelection=false
}
enum SkyTool:String,CaseIterable {case move="Sky Move",brush="Sky Brush",hand="Hand",zoom="Zoom"}
@MainActor @Observable final class SkyWorkspace:Identifiable {
  let id=UUID()
  let original:CraftDocument
  let library:SkyLibrary
  var state=SkyState()
  var input:SkyReplacementInput?
  var originalImage:CGImage?
  var previewImage:CGImage?
  var maskImage:CGImage?
  var mask:SelectionMask?
  var edit:SkyReplacementEdit?
  var tool=SkyTool.move
  var add=true
  var size=40.0
  var hardness=0.5
  var opacity=1.0
  var zoom=1.0
  var pan=CGSize.zero
  var showOriginal=false
  var showMask=false
  var loading=false
  var rendering=false
  var committing=false
  var error:String?
  var task:Task<Void,Never>?
  var commitTask:Task<Void,Never>?
  var importTask:Task<Void,Never>?
  var undoStates:[SkyState]=[]
  var redoStates:[SkyState]=[]
  var renameDraft:SkyRenameDraft?
  var stroke:SkyMaskStroke?
  private var generation=0
  private var closed=false
  private var detection:(SkySelectionSettings,SelectionMask)?
  private var dragStart:SkyState?
  var hasRasterSource:Bool{if let layer=original.layers.first(where:{$0.id==original.activeLayerID}),case .raster=layer.content{return true};return false}
  var ready:Bool{input != nil && !loading && !committing && !closed}
  var canRenameSky:Bool{ready && renameDraft==nil && stroke==nil && dragStart==nil && library.loadError==nil && state.sourceLayerID==nil && library.skies.contains{$0.id==state.skyID}}
  var canCommit:Bool{ready && renameDraft==nil && !rendering && edit != nil && error==nil && stroke==nil && dragStart==nil}
  init(document:CraftDocument,library:SkyLibrary){original=document;self.library=library;state.skyID=library.skies.first?.id}
  func prepare()async {
    loading=true
    do{
      let original=original,worker=Task.detached(priority:.userInitiated){let input=try SkyReplacementInput.prepare(original);return (input,try ColorManagement.displayImage(input.composite,in:original))}
      let result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation();guard !closed else{return}
      input=result.0;originalImage=result.1;loading=false;refresh()
    }catch{if !closed && !Task.isCancelled{self.error=error.localizedDescription};loading=false}
  }
  func change(_ next:SkyState,remember:Bool=true){guard !closed,!committing else{return};do{try next.settings.validate()}catch{self.error=error.localizedDescription;return};if next != state && remember{undoStates.append(state);if undoStates.count>24{undoStates.removeFirst()};redoStates=[]};state=next;refresh()}
  func undo(){guard ready else{return};stroke=nil;dragStart=nil;guard let old=undoStates.popLast() else{return};redoStates.append(state);change(old,remember:false)}
  func redo(){guard ready,let next=redoStates.popLast() else{return};undoStates.append(state);change(next,remember:false)}
  func reset(){var next=SkyState();next.skyID=state.skyID;next.sourceLayerID=state.sourceLayerID;change(next)}
  func chooseSky(_ id:UUID?){var next=state;next.skyID=id;next.sourceLayerID=nil;change(next)}
  func useLayer(_ id:UUID){var next=state;next.sourceLayerID=id;next.skyID=nil;change(next)}
  nonisolated static func sourceLayer(_ id:UUID,in d:CraftDocument)throws->CraftDocument {
    guard let layer=d.layers.first(where:{$0.id==id}),case .raster(let pixels)=layer.content else{throw CraftError.invalid("Choose a raster layer as the replacement sky.")}
    var source=try CraftDocument(width:pixels.width,height:pixels.height,depth:d.depth);source.workingICC=d.workingICC;source.layers[0].content = .raster(pixels);source.name=layer.name;return source
  }
  func refresh(){
    guard let input,!closed else{return};generation+=1;let request=generation,state=state,previous=detection
    task?.cancel();edit=nil;error=nil;rendering=false
    guard state.skyID != nil || state.sourceLayerID != nil else{previewImage=originalImage;return}
    let preset:SkyPreset?
    do{preset=try state.skyID.map{try library.preset($0)}}catch{self.error=error.localizedDescription;return}
    rendering=true
    task=Task{[weak self] in
      do{
        let worker=Task.detached(priority:.userInitiated){()throws->(SkyReplacementEdit,SelectionMask,CGImage,CGImage?,SelectionMask) in
          let sky=try preset?.document() ?? Self.sourceLayer(state.sourceLayerID!,in:input.original)
          let detected:SelectionMask
          if state.useSelection{guard let value=try input.original.coverageSelection() else{throw CraftError.invalid("Create a selection before using it as the sky mask.")};detected=value}
          else if let previous,previous.0==state.settings.selection{detected=previous.1}
          else{guard let value=try SkySelection.mask(input.guide,settings:state.settings.selection) else{throw CraftError.invalid("No sky was detected. Use a manual selection or another photo.")};detected=value}
          let result=try input.edit(sky:sky,name:preset?.name ?? sky.name,settings:state.settings,strokes:state.strokes,detected:detected)
          return (result.edit,result.mask,try ColorManagement.displayImage(Renderer.composite(result.edit.result),in:result.edit.result),try SelectionToolPreparation.overlay(result.mask,color:Pixel(1,0,0,0.55)),detected)
        }
        let result=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,!self.closed,self.generation==request else{return}
        self.edit=result.0;self.mask=result.1;self.previewImage=result.2;self.maskImage=result.3;if !state.useSelection{self.detection=(state.settings.selection,result.4)}
      }catch{if let self,!self.closed,self.generation==request,!Task.isCancelled{self.error=error.localizedDescription}}
      if let self,self.generation==request{self.rendering=false}
    }
  }
  func beginStroke(_ point:PathPoint,alternate:Bool){guard ready else{return};let value=SkyMaskStroke(points:[.init(x:point.x,y:point.y)],size:size,hardness:Float(hardness),opacity:Float(opacity),add:alternate ? !add:add);do{try value.validate();stroke=value}catch{self.error=error.localizedDescription}}
  func dragStroke(_ p:PathPoint){guard var s=stroke,s.points.count<4096 else{return};s.points.append(.init(x:p.x,y:p.y));stroke=s}
  func endStroke(){guard let stroke else{return};self.stroke=nil;var next=state;next.strokes.append(stroke);change(next)}
  func beginMove(){guard ready else{return};dragStart=state}
  func move(_ delta:CGSize){guard let start=dragStart else{return};var next=start;next.settings.offsetX+=delta.width;next.settings.offsetY+=delta.height;change(next,remember:false)}
  func endMove(){guard let start=dragStart else{return};dragStart=nil;if start != state{undoStates.append(start);if undoStates.count>24{undoStates.removeFirst()};redoStates=[]}}
  func importSky(){
    guard ready else{return};let panel=NSOpenPanel();panel.allowedContentTypes=[.image];panel.allowsMultipleSelection=false;panel.message="Choose a sky image to add to your library."
    panel.begin{[weak self] response in guard response == .OK,let url=panel.url,let self,!self.closed else{return};self.loadSky(url)}
  }
  func loadSky(_ url:URL){
    importTask?.cancel();loading=true
    importTask=Task{[weak self] in
      do{let worker=Task.detached(priority:.userInitiated){
        let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}}
        guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0)<=16*1024*1024 else{throw CraftError.invalid("Sky image exceeds16MiB.")}
        let preset=SkyPreset(name:url.deletingPathExtension().lastPathComponent,data:try Data(contentsOf:url));_=try preset.document();return preset
      };let preset=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation();guard let self,!self.closed else{return};try self.library.add(preset);self.loading=false;self.chooseSky(preset.id)
      }catch{if let self,!self.closed,!Task.isCancelled{self.error=error.localizedDescription};self?.loading=false}
    }
  }
  func removeSky(){guard ready,let id=state.skyID else{return};do{try library.remove(id);chooseSky(library.skies.first?.id)}catch{self.error=error.localizedDescription}}
  func close(){renameDraft=nil;closed=true;generation+=1;task?.cancel();commitTask?.cancel();importTask?.cancel()}
}
@MainActor extension EditorStore {
  var canSelectSky:Bool{canUseSelectionTools && !editingMask}
  var canReplaceSky:Bool{canSelectSky && document.width<=SkyReplacement.maximumPixels/document.height}
  func selectSky(){guard canSelectSky else{return};let id=activeLayer?.id;performGeometry(label:"Select Sky",prepare:{original in try SkyReplacementInput.selection(original,layerID:id)})}
  func beginSkyReplacement(){guard canReplaceSky else{return};let draft=SkyWorkspace(document:document,library:skies);skyWorkspace=draft;draft.task=Task{await draft.prepare()}}
  func cancelSkyReplacement(){skyWorkspace?.close();skyWorkspace=nil}
  func commitSkyReplacement(){
    guard let draft=skyWorkspace,draft.canCommit,let edit=draft.edit else{return};draft.committing=true
    draft.commitTask=Task{[weak self,weak draft] in
      do{let worker=Task.detached(priority:.userInitiated){try PreparedEdit(command:.skyReplacement(edit),document:edit.source)}
        let prepared=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
        guard let self,let draft,self.skyWorkspace === draft,self.document==edit.source else{throw CraftError.invalid("Sky Replacement source changed.")}
        try self.executeCompositePreparedEdit(prepared);self.selectedLayerIDs=Set(self.document.activeLayerID.map{[$0]} ?? []);self.onChange?(.changeDone);self.skyWorkspace=nil;draft.close();self.status="Sky Replacement";self.render()
      }catch{if !Task.isCancelled{draft?.error=error.localizedDescription}};draft?.committing=false
    }
  }
}
extension AppDelegate {
  @objc func selectSky(){store?.selectSky()}
  @objc func skyReplacement(){store?.beginSkyReplacement()}
}
