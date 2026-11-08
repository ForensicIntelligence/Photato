import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct ClipboardPlaneContext:Equatable {
  let session:UUID
  let target:ClipboardPlaneTarget?
  let components:[Int]
  let path:PathTarget?
}
extension EditorStore {
  var clipboardPlaneTarget:ClipboardPlaneTarget? {
    if let channel=editingChannel{switch channel{case .alpha(let id):return .alpha(id);case .quickMask:return .quickMask}}
    if let mask=selectedMaskPaintTarget{return mask.smartFilter ? .smartFilterMask(mask.layerID):.layerMask(mask.layerID)}
    return nil
  }
  var clipboardPlaneContext:ClipboardPlaneContext {.init(session:sessionGeneration,target:clipboardPlaneTarget,components:effectiveComponentTargets.sorted(),path:pathTarget)}
  var clipboardPlaneIdle:Bool {!geometryBusy && !aiBusy && !hasToneDraft && transformDraft==nil && !coalescingChanges && eyedropperGesture==nil && pathGesture==nil && unavailableToolID==nil}
  func canUseClipboardPlane(_ target:ClipboardPlaneTarget,writing:Bool=false)->Bool {
    clipboardPlaneIdle && pathTarget==nil && ClipboardPlane.available(document,target:target,writing:writing) && (!writing || target != .quickMask || isQuickMaskVisible)
  }
  func validateClipboardPlane(_ edit:ClipboardPlaneEdit)throws {
    guard edit.source==document,ClipboardPlane.available(document,target:edit.target,writing:true),edit.target != .quickMask || isQuickMaskVisible else{throw CraftError.invalid("The clipboard plane changed, is locked or is hidden.")}
  }
  func commitClipboardPlane(_ prepared:PreparedEdit)throws {
    guard let edit=prepared.clipboardPlaneEdit else{throw CraftError.invalid("Missing targeted clipboard transaction.")}
    try validateClipboardPlane(edit);let before=document
    try session.executePrepared(prepared)
    if document != before{onChange?(.changeDone)}
    else if session.actionRecording != nil{session.recordActionOperation(.unsupported("Mask/channel clipboard recording is not yet supported."),name:prepared.label);actionRevision += 1}
  }
  func copyClipboardPlane(_ target:ClipboardPlaneTarget,cut:Bool) {
    guard canUseClipboardPlane(target,writing:cut)else{return}
    let original=document,context=clipboardPlaneContext,clipboardCount=clipboard.changeCount,background=ClipboardPlaneIO.gray(backgroundColor),settings=workingColorSettings,id=UUID()
    clipboardPlaneOperationID=id;geometryBusy=true;status=cut ? "Cut":"Copy"
    geometryTask=Task{[weak self]in
      do {
        let worker=Task.detached(priority:.userInitiated){
          let profile=try settings.profile(.grayscale,depth:original.depth)
          let content=try ClipboardPlane.copy(original,target:target,grayProfile:profile)
          let representations=try ClipboardRepresentations(content)
          let prepared=try cut ? PreparedEdit(clipboardPlane:ClipboardPlane.cut(original,target:target,background:background)):nil
          return(representations,prepared)
        }
        let (value,prepared)=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
        try Task.checkCancellation();guard let self else{return}
        guard self.clipboardPlaneOperationID==id,self.document==original,self.clipboardPlaneContext==context,self.clipboard.changeCount==clipboardCount else{throw CraftError.invalid("The clipboard source, target or clipboard changed. Try again.")}
        if let prepared{try self.validateClipboardPlane(prepared.clipboardPlaneEdit!)}
        try self.clipboard.write(value)
        if value.tiff==nil{self.status="Copied native channel data; full TIFF/PNG fallbacks exceed the current encoding budget."}
        if let prepared{try self.commitClipboardPlane(prepared)}else if self.session.actionRecording != nil{self.session.recordActionOperation(.unsupported("Copy mask/channel is not yet recordable."),name:"Copy");self.actionRevision += 1}
      }catch is CancellationError{self?.status="Operation cancelled"}catch{self?.error=error.localizedDescription}
      guard let self,self.clipboardPlaneOperationID==id else{return}
      self.clipboardPlaneOperationID=nil;self.geometryBusy=false;self.geometryTask=nil;if cut{self.render()}
    }
  }
  func pasteClipboardPlane(_ target:ClipboardPlaneTarget,placement:PastePlacement) {
    guard canUseClipboardPlane(target,writing:true),placement == .centered || placement == .inPlace else{return}
    do {
      let input=try clipboard.read(),original=document,context=clipboardPlaneContext,clipboardCount=clipboard.changeCount,settings=workingColorSettings,id=UUID()
      let scale=max(0.02,measuredZoom),center=PathPoint(min(Double(document.width),max(0,Double(document.width)/2-pan.width/scale)),min(Double(document.height),max(0,Double(document.height)/2-pan.height/scale)))
      clipboardPlaneOperationID=id;geometryBusy=true;status="Paste"
      geometryTask=Task{[weak self]in
        do {
          let worker=Task.detached(priority:.userInitiated){
            let content=try input.decoded(),image=try ClipboardPlaneIO.image(content,depth:original.depth,settings:settings)
            return try PreparedEdit(clipboardPlane:ClipboardPlane.paste(image,into:original,target:target,placement:placement,center:center))
          }
          let prepared=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
          try Task.checkCancellation();guard let self else{return}
          guard self.clipboardPlaneOperationID==id,self.document==original,self.clipboardPlaneContext==context,self.clipboard.changeCount==clipboardCount else{throw CraftError.invalid("The paste source, destination or clipboard changed. Try again.")}
          try self.commitClipboardPlane(prepared);self.status=prepared.label
        }catch is CancellationError{self?.status="Operation cancelled"}catch{self?.error=error.localizedDescription}
        guard let self,self.clipboardPlaneOperationID==id else{return}
        self.clipboardPlaneOperationID=nil;self.geometryBusy=false;self.geometryTask=nil;self.render()
      }
    }catch{self.error=error.localizedDescription}
  }
}
