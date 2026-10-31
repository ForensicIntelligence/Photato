import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var channelArithmeticTarget:ChannelArithmeticTarget? {
    if let channel=editingChannel {switch channel {case .alpha(let id):return .alpha(id);case .quickMask:return .quickMask}}
    if let id=maskEditingLayerID {return .layerMask(id)}
    if document.inkMode != nil {return effectiveInkTargets.count==1 ? effectiveInkTargets.first.map{.ink($0)}:nil}
    guard let layer=activeLayer,!layer.isGroup,!document.isImageLocked(layer.id),layer.smartObject==nil,layer.smartFilters==nil,case .raster=layer.content else{return nil}
    let components:[Int]
    if !modeComponentTargets.isEmpty {components=modeComponentTargets.sorted()}
    else if let selected=componentTarget.editComponents {components=[(0,RGBComponents.red),(1,.green),(2,.blue)].filter{selected.contains($0.1)}.map(\.0)}
    else {components=[]}
    return .pixels(layer.id,components)
  }
  func canBeginChannelArithmetic(_ kind:ChannelArithmeticRequest.Kind)->Bool {
    !document.colorMode.isRestricted && canSelectComponentTarget && !smartFilterMaskEditing && historyOperation==nil
      && (kind == .calculations || channelArithmeticTarget != nil)
  }
  func beginChannelArithmetic(_ kind:ChannelArithmeticRequest.Kind) {
    guard canBeginChannelArithmetic(kind) else{return}
    let sources=documentController?.documents.compactMap{($0 as? CraftNSDocument)?.store.document} ?? []
    let model=ChannelArithmeticWorkspace(document:document,sources:sources,target:channelArithmeticTarget,kind:kind)
    channelArithmeticWorkspace=model;model.refresh()
  }
  func cancelChannelArithmetic() {channelArithmeticWorkspace?.close();channelArithmeticWorkspace=nil;render()}
  func commitChannelArithmetic() {
    guard let draft=channelArithmeticWorkspace,draft.ready,let result=draft.prepared else{return}
    draft.committing=true;let original=draft.source,request=draft.request
    draft.commitTask=Task {[weak self,weak draft] in
      do {
        let command=result.command
        let worker=Task.detached(priority:.userInitiated) {try command.map{try PreparedEdit(command:$0,document:original)}}
        let prepared=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard let self,let draft,self.channelArithmeticWorkspace === draft,self.document==original else{throw CraftError.invalid("The destination changed during channel blending.")}
        let ids=Set(([request.source1]+(request.kind == .calculations ? [request.source2]:[])+(request.mask.map{[$0]} ?? [])).compactMap(\.documentID)).subtracting([original.id])
        for id in ids {
          guard let saved=draft.sources.first(where:{$0.id==id}),self.documentController?.documents.contains(where:{($0 as? CraftNSDocument)?.store.document==saved})==true else{throw CraftError.invalid("A source document changed or closed. Reopen this dialog.")}
        }
        if let created=result.newDocument {
          guard let controller=self.documentController else{throw CraftError.invalid("No document workspace is available.")}
          let document=CraftNSDocument(model:created);controller.addDocument(document);document.updateChangeCount(.changeDone);document.makeWindowControllers();document.showWindows()
        } else if let prepared {
          try self.executeCompositePreparedEdit(prepared,allowChannelArithmetic:true)
          if self.document != original {self.onChange?(.changeDone)}
        }
        self.channelArithmeticWorkspace=nil;draft.close();self.status=request.title
        if let id=result.channelID {try self.selectAlphaChannel(id)}
        self.render()
      }catch {if !Task.isCancelled{draft?.error=error.localizedDescription};draft?.committing=false}
    }
  }
}
extension AppDelegate {
  @objc func applyImageDialog(_ sender:Any?) {store?.beginChannelArithmetic(.applyImage)}
  @objc func calculationsDialog(_ sender:Any?) {store?.beginChannelArithmetic(.calculations)}
}
