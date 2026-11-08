import AppKit
import PhotoCraftCore

enum ChannelSeparationAPI {
  static let name="channel.split"
  static var stateSchema:[String:Any] {BrushAPI.object(["available":BrushAPI.flag,"unavailableReason":["type":["string","null"]],"outputCount":["type":"integer","minimum":0,"maximum":56]],required:["available","unavailableReason","outputCount"])}
  static var descriptorSchema:[String:Any] {BrushAPI.object([
    "kind":["type":"string","enum":["component","alpha","duotone","plate"]],
    "index":["type":["integer","null"],"minimum":0,"maximum":3],
    "channelID":["type":["string","null"],"format":"uuid"],"name":["type":"string"],"suffix":["type":"string"]
  ],required:["kind","index","channelID","name","suffix"])}
  static var resultSchema:[String:Any] {BrushAPI.object([
    "sourceShareID":["type":"string","format":"uuid"],"sourceDocumentID":["type":"string","format":"uuid"],"sourceClosed":BrushAPI.flag,
    "documents":["type":"array","minItems":2,"maxItems":56,"items":BrushAPI.object(["channel":descriptorSchema,"document":["type":"object","description":"Full shared document state, with its new share id and revision."]],required:["channel","document"])]
  ],required:["sourceShareID","sourceDocumentID","sourceClosed","documents"])}

  static var capabilities:[String:Any] {[
    "command":name,"state":"channelSeparation","stateSchema":stateSchema,"resultSchema":resultSchema,
    "native":"Channels panel > Split Channels. A flat static image is required. Results are grayscale documents named from the source and channel suffix. The original closes without saving only after every result is registered; its file is unchanged.",
    "API":"Requires document transfers and document closing permissions. HTTP201 returns all new shared document states and consumes the original share. Existing eight-document sharing policy applies to the final replacement set; no partial output publication.",
    "samples":"Read native component planes, RGB samples, auxiliary coverage/spot density, Duotone gray or printing plates without a color roundtrip. CMYK/ink density is inverted for grayscale. Retained Float32 spot gray is used when it matches current density. Resolution, selection, paths/guides and source metadata are retained; gray profile follows source Gray or captured working Gray.",
    "history":"Outputs have fresh identities, empty history, no file URL and unsaved change state. Split is a document lifecycle operation, not a source Undo step. Preparation can cancel before publication; stale/revoked/lifecycle changes cannot close the source. Semantic multi-document Actions remain unsupported; native89/Actions58 unchanged.",
    "limits":"Current model/mode/scratch/file/transfer limits apply; no new logical megapixel cap. QuickMask, restricted/temporal/artboard/frame and unflattened/translucent sources reject. Exact Photoshop mode/spot eligibility, naming/profile/default/selection/output/Background/focus behavior, full COL02, dense physical capacity/platform/60fps remain unqualified. No dedicated Adobe HTTP route or unverified action descriptor is invented."]}
  static func descriptor(_ value:SeparatedChannelDescriptor)->[String:Any] {[
    "kind":value.kind.rawValue,"index":value.index as Any? ?? NSNull(),"channelID":value.channelID?.uuidString as Any? ?? NSNull(),"name":value.name,"suffix":value.suffix]}
}

extension AutomationService {
  func splitChannels(_ command:AutomationCommand,document:CraftNSDocument,share:Share)async throws->AutomationResponse {
    guard documentTransfersEnabled,documentClosingEnabled else{throw AutomationFailure(status:403,message:"Enable document transfers and document closing for Split Channels.")}
    guard !documentTransferBusy else{throw AutomationFailure(status:429,message:"Document transfer is busy.")}
    let store=document.store,source=store.document,descriptors=ChannelSeparation.channels(source)
    if let reason=ChannelSeparation.unavailableReason(source){throw AutomationFailure(status:422,message:reason)}
    guard shares.count-1+descriptors.count<=8 else{throw AutomationFailure(status:429,message:"Split Channels needs more than eight shared-document slots.")}
    let token=token,transfer=documentTransferGeneration,closePermission=documentClosingGeneration,settings=controller.colorSettings.value
    let panel=store.layerPanelGeneration,session=store.sessionGeneration,opening=controller.documentOpening.generation,closing=controller.documentClosing.state?.id,maintenance=controller.recoveryMaintenance.generation,discovery=controller.recoveryDiscovery.generation
    guard controller.documentClosing.canStart([document])else{throw AutomationFailure(status:409,message:"Finish the document lifecycle operation first.")}
    let prepare=store.splitChannelsPreparation
    documentTransferBusy=true;store.geometryBusy=true;store.renderTask?.cancel()
    defer{documentTransferBusy=false;if store.layerPanelGeneration==panel{store.geometryBusy=false;store.geometryTask=nil;store.render()}}
    let worker=Task.detached(priority:.userInitiated){try prepare(source,settings.profile(.grayscale,depth:source.depth))}
    store.geometryTask=Task{await withTaskCancellationHandler{_ = try? await worker.value}onCancel:{worker.cancel()}}
    let plan=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
    try Task.checkCancellation();prune()
    guard store.geometryTask?.isCancelled != true,isRunning,self.token==token,documentTransfersEnabled,documentClosingEnabled,
      documentTransferGeneration==transfer,documentClosingGeneration==closePermission,
      shares.contains(where:{$0.id==share.id && $0.document === document}),shares.count-1+plan.outputs.count<=8,
      store.document==source,plan.source==source,revision(store)==command.revision,store.layerPanelGeneration==panel,store.sessionGeneration==session,
      controller.colorSettings.value==settings,NSApp?.modalWindow==nil,
      !controller.documentClosing.isActive,controller.documentClosing.state?.id==closing,
      !controller.documentOpening.isActive,!controller.documentOpening.hasPendingRequests,controller.documentOpening.generation==opening,
      !controller.recoveryIndex.isBusy,controller.recoveryMaintenance.generation==maintenance,controller.recoveryDiscovery.generation==discovery else{throw AutomationFailure(status:409,message:"Split Channels cancelled or sharing/source/lifecycle changed.")}
    for item in plan.outputs{try Self.checkLimits(item.document)}
    store.geometryBusy=false
    let created=try controller.publishChannelSeparation(plan,source:document){try self.replaceSplitChannelShares(share,with:$0)}
    let states=try zip(plan.outputs,created).map{item,doc->[String:Any] in
      guard let lease=shares.first(where:{$0.document === doc})else{throw AutomationFailure(status:409,message:"Channel result sharing ended.")}
      return ["channel":ChannelSeparationAPI.descriptor(item.channel),"document":state(lease,document:doc)]
    }
    return .json(["sourceShareID":share.id.uuidString,"sourceDocumentID":source.id.uuidString,"sourceClosed":document.ownerController==nil,"documents":states],status:201)
  }
}
