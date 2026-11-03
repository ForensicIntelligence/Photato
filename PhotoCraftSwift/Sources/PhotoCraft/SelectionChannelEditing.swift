import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  func cancelChannelDialog() {channelDialog?.task?.cancel();channelDialog=nil}
  func commitSelectionChannelDialog(_ draft:ChannelDialog) {
    guard channelDialog === draft,!draft.committing,document==draft.source else {
      draft.error="The document changed. Cancel and reopen the selection dialog.";return
    }
    let selected=draft.selectedDocument,createsDocument=draft.createsDocument,foreign=selected.id != document.id && !draft.createsDocument
    if createsDocument,documentController == nil {draft.error="No document workspace is available.";return}
    let foreignDocument=documentController?.documents.compactMap {$0 as? CraftNSDocument}.first {$0.store.document==selected}
    guard !foreign || foreignDocument != nil else {draft.error="The other document changed or closed. Reopen this dialog.";return}
    let targetStore=draft.kind == .save && foreign ? foreignDocument!.store:self
    let available=targetStore === self ? !document.colorMode.isRestricted && canSelectComponentTarget(excludingChannelDialog:true) && historyOperation == nil:targetStore.canEditChannels
    guard available else {draft.error="Finish the destination interaction first.";return}
    let original=document,target=targetStore.document,kind=draft.kind,id=draft.channelID,name=draft.name,
      mode=draft.kind == .save && draft.channelID == nil ? SelectionMode.replace:draft.mode,invert=draft.invert
    let selectedSource=draft.selectionSource,colorSettings=draft.colorSettings
    guard workingColorSettings==colorSettings else{draft.error="Color Settings changed. Cancel and reopen the selection dialog.";return}
    let lifecycle=documentController
    let closing=lifecycle?.documentClosing.state?.id,opening=lifecycle?.documentOpening.generation
    let maintenance=lifecycle?.recoveryMaintenance.generation,discovery=lifecycle?.recoveryDiscovery.generation
    let ownGeneration=layerPanelGeneration,targetGeneration=targetStore.layerPanelGeneration
    draft.committing=true;draft.error=nil;geometryBusy=true;targetStore.geometryBusy=true
    draft.task=Task {[weak self,weak draft,weak targetStore,weak foreignDocument] in
      guard let self,let draft,let targetStore else{return}
      defer {
        draft.committing=false
        if self.layerPanelGeneration==ownGeneration {self.geometryBusy=false;self.geometryTask=nil;self.render()}
        if targetStore !== self && targetStore.layerPanelGeneration==targetGeneration {targetStore.geometryBusy=false;targetStore.render()}
      }
      do {
        let worker=Task.detached(priority:.userInitiated) { ()throws->(PreparedEdit?,CraftDocument?) in
          if createsDocument {return (nil,try original.selectionDocument(channelName:name))}
          let command:Command
          if kind == .save {
            let coverage=try AlphaChannel.coverage(original.coverageSelection(),width:original.width,height:original.height,depth:target.depth)
            command = .channel(.storeSelection(coverage,id,id == nil ? name:nil,mode))
          } else {
            guard let selectedSource else {throw CraftError.invalid("Choose a selection source.")}
            command = .channel(.loadCoverage(try selectedSource.selection(in:selected,invert:invert,colorSettings:colorSettings),mode))
          }
          return (try PreparedEdit(command:command,document:target),nil)
        }
        let (prepared,created)=try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard self.channelDialog === draft,self.document==original,targetStore.document==target,
          self.layerPanelGeneration==ownGeneration,targetStore.layerPanelGeneration==targetGeneration else {
          throw CraftError.invalid("A document changed during the selection operation.")
        }
        guard self.workingColorSettings==colorSettings else{throw CraftError.invalid("Color Settings changed during the selection operation.")}
        if foreign {
          guard let foreignDocument,foreignDocument.store.document==selected,
            self.documentController?.documents.contains(where:{$0 === foreignDocument})==true else {throw CraftError.invalid("The other document changed or closed.")}
        }
        if let created {
          guard let controller=self.documentController,controller === lifecycle,
            controller.documentClosing.state?.id==closing,controller.documentOpening.generation==opening,
            controller.recoveryMaintenance.generation==maintenance,controller.recoveryDiscovery.generation==discovery,
            !controller.documentClosing.isActive,!controller.documentOpening.isActive,
            !controller.documentOpening.hasPendingRequests,!controller.recoveryIndex.isBusy else{throw CraftError.invalid("Finish the document lifecycle operation first.")}
          let document=CraftNSDocument(model:created);controller.addDocument(document);document.updateChangeCount(.changeDone)
          self.channelDialog=nil;controller.documentWindows.presentAfterCurrentSheet(document)
        } else if let prepared {
          try targetStore.executeCompositePreparedEdit(prepared,allowAuxiliary:true)
          if targetStore.document != target {targetStore.onChange?(.changeDone)}
          self.channelDialog=nil
        }
        targetStore.status=kind == .save ? "Save Selection":"Load Selection"
      } catch {if !Task.isCancelled && self.channelDialog === draft {draft.error=error.localizedDescription}}
    }
    geometryTask=draft.task
  }
}
