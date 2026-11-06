import AppKit
import Observation
import PhotoCraftCore
import PhotoCraftImaging

@MainActor @Observable final class PathFillDraft:Identifiable {
  let id=UUID(),original:CraftDocument,session:UUID,lifecycle:UUID,layerID:UUID,path:VectorPath,target:PathTarget?,context:PathFillContext
  var options:PathFillOptions
  var error:String?
  init(store:EditorStore,path:VectorPath,layerID:UUID) {
    original=store.document;session=store.sessionGeneration;lifecycle=store.layerPanelGeneration;self.layerID=layerID;self.path=path;target=store.pathTarget
    context=store.pathFillContext;options=store.lastPathFill;options.color=store.brush.color
    if options.contents == .pattern,!context.patterns.contains(where:{$0.id==options.patternID}){options.contents = .foreground;options.patternID=nil}
  }
  var valid:Bool {
    (try? options.validate()) != nil && (!options.clear || original.layers.first(where:{$0.id==layerID})?.isBackground != true)
      && (options.contents != .pattern || !context.patternBusy && context.patterns.contains(where:{$0.id==options.patternID}))
  }
  func choose(_ contents:PathFillOptions.Contents){options.contents=contents;options.patternID=contents == .pattern ? context.patterns.first?.id:nil}
}
@MainActor extension EditorStore {
  var pathFillContext:PathFillContext {.init(foreground:brush.color,background:backgroundColor,patterns:pixelFillPatterns,patternBusy:patterns.busy)}
  var canBeginPathFill:Bool {
    canBeginLayerCreation && !aiBusy && !coalescingChanges && historyOperation==nil && pathGesture==nil && !editingMask && !smartFilterMaskEditing && !editingComponent && isCompositeColorTarget
      && selectedVectorPath?.isEmpty == false && activeLayer.map{PixelFillStroke.available(document,target:.layer($0.id))} == true
  }
  func beginPathFill(){finishNumericField();finishLayerName();guard canBeginPathFill,let path=selectedVectorPath,let id=activeLayer?.id else{return};pathFillEpoch=UUID();pathFillDraft=PathFillDraft(store:self,path:path,layerID:id)}
  func cancelPathFill(){pathFillEpoch=UUID();pathFillDraft=nil}
  func fillPathFooter(modifiers:NSEvent.ModifierFlags = []){if modifiers.contains(.option){beginPathFill()}else{paintSelectedPath(stroke:false)}}
  func commitPathFill(_ draft:PathFillDraft){
    guard pathFillDraft === draft,draft.valid,!geometryBusy else{return}
    guard document==draft.original,sessionGeneration==draft.session,layerPanelGeneration==draft.lifecycle,selectedVectorPath==draft.path,pathTarget==draft.target else{draft.error="The source or path changed. Cancel and reopen Fill Path.";return}
    let path=draft.path,id=draft.layerID,options=draft.options,context=draft.context,epoch=pathFillEpoch,settings=workingColorSettings,prepare=pathFillPreparation
    pathFillDraft=nil
    guard canBeginPathFill else{pathFillDraft=draft;draft.error="Finish the current interaction before filling the path.";return}
    performPreparedGeometry(label:"Fill Path",prepare:{source in try PreparedEdit(command:prepare(path,source,id,options,context),document:source)},validateCommit:{
      guard self.pathFillEpoch==epoch,self.workingColorSettings==settings,self.selectedVectorPath==path,self.pathTarget==draft.target,!self.editingMask,!self.smartFilterMaskEditing,!self.editingComponent else{throw CraftError.invalid("Path Fill was cancelled or its target/settings changed.")}
    },onSuccess:{self.lastPathFill=options})
  }
}
