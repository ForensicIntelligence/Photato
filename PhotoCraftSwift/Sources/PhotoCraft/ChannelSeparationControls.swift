import AppKit
import PhotoCraftCore

@MainActor extension CraftDocumentController {
  /// Publish every result before retiring the source, with no suspension between
  /// registration and close. The caller installs API leases inside registration.
  func publishChannelSeparation(_ plan:PreparedChannelSeparation,source:CraftNSDocument,
    register:([CraftNSDocument])throws->Void = {_ in})throws->[CraftNSDocument] {
    guard source.ownerController === self,source.store.document==plan.source,
      !source.recoveryWriteBusy,documentClosing.canStart([source]),
      plan.outputs.count==ChannelSeparation.channels(plan.source).count,
      Set(plan.outputs.map{$0.document.id}).count==plan.outputs.count,
      !plan.outputs.contains(where:{$0.document.id==plan.source.id}) else{throw CraftError.invalid("Split Channels source or document lifecycle changed.")}
    for output in plan.outputs {try output.document.validate();guard output.document.colorMode == .grayscale,output.document.width==plan.source.width,output.document.height==plan.source.height,output.document.depth==plan.source.depth else{throw CraftError.invalid("Invalid prepared channel document.")}}
    let created=plan.outputs.map{CraftNSDocument(model:$0.document)}
    do {
      for doc in created{addDocument(doc)}
      try register(created)
    }catch{
      for doc in created{doc.close()}
      throw error
    }
    for doc in created{doc.updateChangeCount(.changeDone)}
    source.close()
    // Closing is synchronous after the recovery/lifecycle admission above.
    assert(source.ownerController==nil)
    for doc in created{documentWindows.presentAfterCurrentSheet(doc)}
    return created
  }
}

@MainActor extension EditorStore {
  var canSplitChannels:Bool {
    guard canBeginLayerCreation,!aiBusy,
      let controller=documentController,let file=controller.documents.compactMap({$0 as? CraftNSDocument}).first(where:{$0.store === self}),
      controller.documentClosing.canStart([file]) else{return false}
    return ChannelSeparation.unavailableReason(document)==nil
  }
  func splitChannels() {
    finishNumericField();finishLayerName()
    guard canSplitChannels,let controller=documentController,
      let file=controller.documents.compactMap({$0 as? CraftNSDocument}).first(where:{$0.store === self})else{return}
    let source=document,generation=layerPanelGeneration,session=sessionGeneration,settings=workingColorSettings,prepare=splitChannelsPreparation
    let opening=controller.documentOpening.generation,closing=controller.documentClosing.state?.id,maintenance=controller.recoveryMaintenance.generation,discovery=controller.recoveryDiscovery.generation
    geometryBusy=true;renderTask?.cancel();status="Split Channels"
    geometryTask=Task{[weak self,weak controller,weak file]in
      do {
        let worker=Task.detached(priority:.userInitiated){try prepare(source,settings.profile(.grayscale,depth:source.depth))}
        let plan=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
        try Task.checkCancellation()
        guard let self,let controller,let file,self.document==source,plan.source==source,
          self.layerPanelGeneration==generation,self.sessionGeneration==session,self.workingColorSettings==settings,
          !controller.documentClosing.isActive,controller.documentClosing.state?.id==closing,
          !controller.documentOpening.isActive,!controller.documentOpening.hasPendingRequests,controller.documentOpening.generation==opening,
          !controller.recoveryIndex.isBusy,controller.recoveryMaintenance.generation==maintenance,controller.recoveryDiscovery.generation==discovery else{throw CraftError.invalid("Split Channels source or lifecycle changed.")}
        self.geometryBusy=false
        _ = try controller.publishChannelSeparation(plan,source:file)
      }catch is CancellationError {if self?.layerPanelGeneration==generation{self?.status="Operation cancelled"}}
      catch{if self?.layerPanelGeneration==generation{self?.error=error.localizedDescription}}
      if self?.layerPanelGeneration==generation{self?.geometryBusy=false;self?.geometryTask=nil;self?.render()}
    }
  }
  var channelSeparationState:[String:Any] {
    ["available":canSplitChannels,"unavailableReason":ChannelSeparation.unavailableReason(document)as Any? ?? NSNull(),"outputCount":ChannelSeparation.channels(document).count]
  }
}
