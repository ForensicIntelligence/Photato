import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum ChannelArithmeticAPI {
  static let commands:Set<String>=["image.applyImage","image.calculations"]
  static var sourceSchema:[String:Any] {BrushAPI.object([
    "documentID":["type":"string","format":"uuid"],"revision":["type":"string"],
    "layerID":["type":"string","format":"uuid"],"channel":BrushAPI.enumeration(["composite","gray","component","alpha","quickMask","selection","transparency","layerMask","vectorMask","duotone","plate"]),
    "component":BrushAPI.number(0,3,integer:true),"channelID":["type":"string","format":"uuid"],"invert":BrushAPI.flag])}
  static var targetSchema:[String:Any] {BrushAPI.object([
    "kind":BrushAPI.enumeration(["pixels","layerMask","alpha","quickMask","duotone","plate"]),
    "layerID":["type":"string","format":"uuid"],"channelID":["type":"string","format":"uuid"],
    "components":["type":"array","uniqueItems":true,"maxItems":4,"items":BrushAPI.number(0,3,integer:true)]],required:["kind"])}
  static func schema(_ key:String)->[String:Any] {switch key {
    case "source","source1","source2","mask":return sourceSchema
    case "target":return targetSchema
    case "blending":return BrushAPI.enumeration(ChannelArithmeticOptions.modes)
    case "opacity":return BrushAPI.number(0,100)
    case "scale":return BrushAPI.number(1,2)
    case "offset":return BrushAPI.number(-255,255)
    case "preserveTransparency":return BrushAPI.flag
    case "result":return BrushAPI.enumeration(ChannelCalculationResult.allCases.map(\.rawValue))
    default:return ["type":"string","minLength":1,"maxLength":256]
  }}
  static var stateSchema:[String:Any] {BrushAPI.object(["applyImageAvailable":BrushAPI.flag,"calculationsAvailable":BrushAPI.flag,"workspaceOpen":BrushAPI.flag,"previewBusy":BrushAPI.flag,"ready":BrushAPI.flag],required:["applyImageAvailable","calculationsAvailable","workspaceOpen","previewBusy","ready"])}
  static var capabilities:[String:Any] {["commands":commands.sorted(),"sourceSchema":sourceSchema,"targetSchema":targetSchema,"stateSchema":stateSchema,
    "opacityUnit":"percent,0–100","defaults":["blending":"multiply","opacity":100,"scale":1,"offset":0,"preserveTransparency":false,"result":"newChannel"],
    "sources":"Current document or explicitly shared matching-size/depth document. External documentID is a share UUID and requires its current revision. Merged is default; layerID selects a retained layer snapshot.",
    "history":"Apply Image and Calculations channel/selection results commit one shared native Undo. newDocument requires document transfers and returns201 with a new shared grayscale document; source history remains unchanged.",
    "limits":"Existing shared document/layer/resident limits apply. Native mode/ink and grayscale new-document storage retains its8MP bound; paged RGB and coverage math accepts the native300000-side limit.",
    "qualification":"Licensed PhotoCraft-derived native arithmetic. Photoshop exact kernels/ICC, Actions semantic recording, larger mode storage and published Adobe actionJSON descriptors remain unqualified. No invented Adobe endpoint or descriptor."]}
}
@MainActor extension EditorStore {
  var channelArithmeticState:[String:Any] {["applyImageAvailable":canBeginChannelArithmetic(.applyImage),"calculationsAvailable":canBeginChannelArithmetic(.calculations),"workspaceOpen":channelArithmeticWorkspace != nil,"previewBusy":channelArithmeticWorkspace?.rendering ?? false,"ready":channelArithmeticWorkspace?.ready ?? false]}
}
extension AutomationService {
  struct ChannelSourceLease {
    let shareID:UUID
    let document:CraftNSDocument
    let revision:String
    let model:CraftDocument
  }
  func executeChannelArithmetic(_ command:AutomationCommand,document:CraftNSDocument,share:Share)async throws->AutomationResponse {
    let store=document.store,original=store.document
    var leases:[ChannelSourceLease]=[]
    func fields(_ key:String,_ schema:[String:Any])throws->[String:Any]? {
      guard let value=command.parameters[key] else{return nil}
      return try BrushAPI.merge(value,schema:schema,path:key) as? [String:Any]
    }
    func uuid(_ fields:[String:Any],_ key:String)throws->UUID? {
      guard let raw=fields[key] else{return nil}
      guard let text=raw as? String,let id=UUID(uuidString:text) else{throw AutomationFailure(status:400,message:"Invalid \(key).")};return id
    }
    func requiredID(_ fields:[String:Any],_ key:String)throws->UUID {guard let id=try uuid(fields,key) else{throw AutomationFailure(status:400,message:"Missing \(key).")};return id}
    func source(_ key:String,_ fallback:ChannelArithmeticSource)throws->ChannelArithmeticSource {
      guard let raw=try fields(key,ChannelArithmeticAPI.sourceSchema) else{return fallback}
      var model=original
      if let id=try uuid(raw,"documentID"),id != share.id {
        guard let entry=shares.first(where:{$0.id==id}),let doc=entry.document else{throw AutomationFailure(status:404,message:"Shared source document not found.")}
        try preflight(doc)
        guard let expected=raw["revision"] as? String,expected==revision(doc.store) else{throw AutomationFailure(status:409,message:"An external source requires its current revision.")}
        model=doc.store.document
        guard model.id != original.id else{throw AutomationFailure(status:422,message:"Source and destination snapshots must have distinct native document identities.")}
        leases.append(.init(shareID:id,document:doc,revision:expected,model:model))
      } else if let expected=raw["revision"] as? String,expected != command.revision {throw AutomationFailure(status:409,message:"The source revision changed.")}
      let channel:ChannelArithmeticChannel
      let name=raw["channel"] as? String ?? (fallback.channel == .gray ? "gray":fallback.channel == .composite ? "composite":"component")
      switch name {
      case "composite":channel = .composite
      case "gray":channel = .gray
      case "component":channel = .component((raw["component"] as? NSNumber)?.intValue ?? 0)
      case "alpha":channel = .alpha(try requiredID(raw,"channelID"))
      case "quickMask":channel = .quickMask
      case "selection":channel = .selection
      case "transparency":channel = .transparency
      case "layerMask":channel = .layerMask
      case "vectorMask":channel = .vectorMask
      case "duotone":channel = .ink(.duotone)
      case "plate":channel = .ink(.plate(try requiredID(raw,"channelID")))
      default:throw AutomationFailure(status:400,message:"Unknown source channel.")
      }
      guard (name=="component" || raw["component"]==nil),(["alpha","plate"].contains(name) || raw["channelID"]==nil) else{throw AutomationFailure(status:400,message:"Channel-specific fields do not match the source channel.")}
      return .init(documentID:model.id,layerID:try uuid(raw,"layerID"),channel:channel,invert:raw["invert"] as? Bool ?? false)
    }
    var request=ChannelArithmeticRequest(command.name == "image.applyImage" ? .applyImage:.calculations)
    request.source1=try source(request.kind == .applyImage ? "source":"source1",request.source1)
    if request.kind == .calculations {request.source2=try source("source2",request.source2)}
    if command.parameters["mask"] != nil {request.mask=try source("mask",.init(channel:.gray))}
    for key in ["blending","opacity","scale","offset","preserveTransparency","result","name"] where command.parameters[key] != nil {
      let value=try BrushAPI.merge(command.parameters[key]!,schema:ChannelArithmeticAPI.schema(key),path:key)
      switch key {
      case "blending":request.options.blending=value as! String
      case "opacity":request.options.opacity=(value as! NSNumber).floatValue/100
      case "scale":request.options.scale=(value as! NSNumber).floatValue
      case "offset":request.options.offset=(value as! NSNumber).floatValue
      case "preserveTransparency":request.options.preserveTransparency=value as! Bool
      case "result":request.result=ChannelCalculationResult(rawValue:value as! String)!
      default:request.name=value as? String
      }
    }
    try request.validate()
    var target=store.channelArithmeticTarget
    if let raw=try fields("target",ChannelArithmeticAPI.targetSchema) {
      let kind=raw["kind"] as! String
      if let values=raw["components"] as? [NSNumber],Set(values.map(\.intValue)).count != values.count {throw AutomationFailure(status:400,message:"Duplicate destination components.")}
      guard (kind=="pixels" || raw["components"]==nil),(["pixels","layerMask"].contains(kind) || raw["layerID"]==nil),(["alpha","plate"].contains(kind) || raw["channelID"]==nil) else{throw AutomationFailure(status:400,message:"Target-specific fields do not match its kind.")}
      switch kind {
      case "pixels":target = .pixels(try uuid(raw,"layerID") ?? original.activeLayerID ?? requiredID(raw,"layerID"),(raw["components"] as? [NSNumber] ?? []).map(\.intValue))
      case "layerMask":target = .layerMask(try requiredID(raw,"layerID"))
      case "alpha":target = .alpha(try requiredID(raw,"channelID"))
      case "quickMask":target = .quickMask
      case "duotone":target = .ink(.duotone)
      default:target = .ink(.plate(try requiredID(raw,"channelID")))
      }
    }
    let creating=request.kind == .calculations && request.result == .newDocument
    guard !creating || documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Enable document transfers to create a Calculations document.")}
    guard !creating || (!documentTransferBusy && shares.count<8) else{throw AutomationFailure(status:429,message:"Document transfer busy or sharing limit reached.")}
    let expectedToken=token,panel=store.layerPanelGeneration,transferGeneration=documentTransferGeneration
    let closing=controller.documentClosing.state?.id,opening=controller.documentOpening.generation
    let maintenance=controller.recoveryMaintenance.generation,discovery=controller.recoveryDiscovery.generation
    if creating,controller.documentClosing.isActive || controller.documentOpening.isActive || controller.documentOpening.hasPendingRequests || controller.recoveryIndex.isBusy {throw AutomationFailure(status:409,message:"Finish the document lifecycle operation first.")}
    let snapshots=leases.map(\.model),capturedRequest=request,capturedTarget=target,prepare=channelArithmeticPrepare
    if creating {documentTransferBusy=true};store.geometryBusy=true;store.renderTask?.cancel()
    defer {if creating{documentTransferBusy=false};if store.layerPanelGeneration==panel {store.geometryBusy=false;store.geometryTask=nil;store.render()}}
    let worker=Task.detached(priority:.userInitiated) { ()async throws->(PreparedChannelArithmetic,PreparedEdit?) in
      let result=try await prepare(capturedRequest,capturedTarget,original,snapshots)
      return (result,try result.command.map{try PreparedEdit(command:$0,document:original)})
    }
    store.geometryTask=Task {await withTaskCancellationHandler{_ = try? await worker.value}onCancel:{worker.cancel()}}
    let (result,prepared)=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
    try Task.checkCancellation();prune()
    guard store.geometryTask?.isCancelled != true,isRunning,token==expectedToken,shares.contains(where:{$0.id==share.id && $0.document === document}),store.document==original,revision(store)==command.revision,store.layerPanelGeneration==panel else{throw AutomationFailure(status:409,message:"Channel blending was cancelled, changed or sharing was revoked.")}
    for lease in leases {
      guard shares.contains(where:{$0.id==lease.shareID && $0.document === lease.document}),revision(lease.document.store)==lease.revision,lease.document.store.document==lease.model else{throw AutomationFailure(status:409,message:"A source changed, closed or sharing was revoked.")};try preflight(lease.document)
    }
    if let model=result.newDocument {
      guard documentTransfersEnabled,documentTransferGeneration==transferGeneration,shares.count<8,controller.documentClosing.state?.id==closing,controller.documentOpening.generation==opening,controller.recoveryMaintenance.generation==maintenance,controller.recoveryDiscovery.generation==discovery,!controller.documentClosing.isActive,!controller.documentOpening.isActive,!controller.documentOpening.hasPendingRequests,!controller.recoveryIndex.isBusy,NSApp?.modalWindow==nil else{throw AutomationFailure(status:409,message:"Document lifecycle or transfer permission changed.")}
      try Self.checkLimits(model);let created=CraftNSDocument(model:model);controller.addDocument(created)
      do{try self.share(created)}catch{controller.removeDocument(created);throw error}
      created.updateChangeCount(.changeDone)
      guard let added=shares.first(where:{$0.document === created}) else{throw AutomationFailure(status:409,message:"Document sharing ended.")}
      return .json(state(added,document:created),status:201)
    }
    if let prepared {
      var candidate=store.session;try candidate.executePrepared(prepared);try Self.checkLimits(candidate.document)
      try store.executeCompositePreparedEdit(prepared,allowChannelArithmetic:true)
      if store.document != original {store.onChange?(.changeDone)}
      store.status=request.title
    }
    store.geometryBusy=false
    return .json(state(share,document:document))
  }
}
