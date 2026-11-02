import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Photato-only file authorization. Adobe resource jobs continue using their published URL contract.
enum LinkedArtworkAPI {
  static let commands:Set<String>=["smartObject.linked.place","smartObject.linked.relink","smartObject.linked.update","smartObject.linked.embed","smartObject.linked.convert","smartObject.linked.embedAll","smartObject.linked.package"]
  static let definitions:[AutomationCommand.Definition]=[
    .init(name:"smartObject.linked.embedAll",parameters:[:],description:"Embed all linked originals through one atomic native history transaction."),
    .init(name:"smartObject.linked.package",parameters:["name":"Package folder name","format":"photato, psd or psb","replace":"Update an existing package folder, preserving unrelated files"],description:"Collect a saved shared document and approved originals inside the native-approved output folder. Explicit replacement updates the packaged document/inventory while preserving other files.",optionalParameters:["replace"]),
    .init(name:"smartObject.linked.place",parameters:["assetID":"Session-approved artwork UUID","fingerprint":"Current approved artwork SHA256","fit":"Fit to canvas","placement":"PDF selection, RAW settings, transform or frame options"],description:"Place approved linked artwork with retained original bytes and one Undo.",optionalParameters:["fit","placement"]),
    .init(name:"smartObject.linked.relink",parameters:["layerID":"Smart Object UUID","assetID":"Session-approved artwork UUID","fingerprint":"Current approved artwork SHA256"],description:"Relink shared instances, preserving transforms, masks and filters."),
    .init(name:"smartObject.linked.update",parameters:["layerID":"Optional linked layer; omit for all linked sources"],description:"Update linked artwork from session-approved files in one transaction.",optionalParameters:["layerID"]),
    .init(name:"smartObject.linked.embed",parameters:["layerID":"Linked Smart Object UUID"],description:"Embed retained matching source bytes, or resolve an approved original, in one Undo."),
    .init(name:"smartObject.linked.convert",parameters:["layerID":"Embedded Smart Object UUID","assetID":"Session-approved identical original file","fingerprint":"Current approved artwork SHA256"],description:"Convert embedded shared instances to an approved identical source file without writing arbitrary paths.")
  ]
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "layerID","assetID":return ["type":"string","format":"uuid"]
    case "fingerprint":return ["type":"string","pattern":"^[a-f0-9]{64}$","minLength":64,"maxLength":64]
    case "name":return ["type":"string","minLength":1,"maxLength":150]
    case "format":return ["type":"string","enum":["photato","psd","psb"]]
    case "placement":return LinkedArtworkPlacementAPI.schema
    case "fit","replace":return ["type":"boolean"]
    default:return [:]
    }
  }
  static var capabilities:[String:Any] {[
    "commands":commands.sorted(),"assets":"/v1/linked-artwork","nativeArchiveVersion":66,
    "authorization":"Native API window approves individual files each session. Opaque asset UUIDs expire on API stop. Document links and imported PSD paths never authorize file access.",
    "package":["localSavingRequired":true,"approvedOutputFolderRequired":true,"approvedSourceFilesRequired":true,"streamsDocument":true,"replacesExistingFolders":false,"mergesExistingFolders":true,"explicitReplaceRequired":true,"reusesIdenticalAssets":true,"formats":["photato","psd","psb"],"relativeReferences":"Links/<filename>; opening never grants filesystem access. Native Locate Packaged Sources explicitly authorizes that package folder."],
    "stateSchema":["type":"object","properties":["hasLinks":["type":"boolean"],"canEmbedAll":["type":"boolean"],"canPackage":["type":"boolean"],"hasRelativePackageLinks":["type":"boolean"]]],
    "packageResultSchema":["type":"object","required":["folder","document","sourceCount","originalDocumentUnchanged"],"properties":["folder":["type":"string"],"document":["type":"string"],"manifest":["type":"string"],"updatedExisting":["type":"boolean"],"sourceCount":["type":"integer"],"originalDocumentUnchanged":["const":true]]],
    "photoshopLinkedFileTypes":"Byte/MIME signatures retain PNG, JPEG, TIFF, GIF, PSD and PSB/PDF declarations; unknown types are untyped. Linked Photato originals require native output or prior conversion. Other format/live interoperability remains unqualified.",
    "placement":["schema":LinkedArtworkPlacementAPI.schema,"pdf":"Page/image/crop/resolution/antialias; original whole PDF retained.","raw":"Supported camera RAW settings retain original sensor bytes.","geometry":"Initial new-layer transform or frameID/frameFit; one shared native transaction.","authorization":"Existing session-approved assetID/current fingerprint, stale/busy/revocation guards."],
    "originalEditing":LinkedSourceFileAPI.capabilities,
    "history":"Shared source changes are one native transaction; retained byte-cache hydration has no history or revision effect.",
    "conversion":"API convert links an approved identical existing file. Desktop Convert to Linked can also save source bytes through a native Save panel. Package writes a new folder through the existing local-saving/output-folder permission. Linked originals can be edited through the separately approved linked-source route; converting to a newly created file still uses the native Save panel.",
    "limits":"64MiB original source; supported native raster/PSD/RAW/PDF preparation budgets apply. Full PSD cache fidelity, nested monitoring, semantic Actions, media sidecars, platform and Photoshop parity remain open."
  ]}
}
extension AutomationService {
  func authorizeLinkedArtwork(_ url:URL,registry:LinkedSourceRegistry = .shared)throws->UUID {
    guard isRunning else{throw AutomationFailure(status:409,message:"Start the API before authorizing artwork.")}
    guard linkedArtworkAssets.count<8 else{throw AutomationFailure(status:422,message:"Remove an artwork authorization before adding another.")}
    let grant=try registry.authorize(url),id=UUID();linkedArtworkAssets[id]=grant;linkedArtworkRegistries[id]=registry;return id
  }
  func clearLinkedArtwork(){for share in shares where layerCompFileShares.contains(share.id) {cancelSharedLayerCompEdit(share);share.document?.store.layerCompExportWorker?.cancel()};for share in shares where smartObjectCompFileShares.contains(share.id) {cancelSharedSmartObjectComp(share)};clearLinkedSourceWrites();linkedArtworkAssets.removeAll();linkedArtworkRegistries.removeAll()}
  func chooseLinkedArtwork() {
    let panel=NSOpenPanel();panel.title="Authorize Linked Artwork for API";panel.canChooseDirectories=false;panel.allowsMultipleSelection=false
    let expected=token
    panel.begin{[weak self] response in
      guard response == .OK,let url=panel.url,let self,self.isRunning,self.token==expected else{return}
      do{_ = try self.authorizeLinkedArtwork(url)}catch{self.message=error.localizedDescription}
    }
  }
  func linkedArtworkGrant(_ id:UUID,store:EditorStore)throws->LinkedArtworkGrant {
    guard let grant=linkedArtworkAssets[id],store.linkedSourceRegistry.stillAuthorizes(grant)else{throw AutomationFailure(status:403,message:"Authorize this artwork file in the native API window for this session.")};return grant
  }
  func linkedArtworkGrant(_ link:LinkedSmartObjectSource,store:EditorStore)throws->LinkedArtworkGrant {
    guard let grant=try? store.linkedSourceRegistry.resolve(link,documentID:store.document.id,documentURL:store.linkedArtworkDocumentURL),
      linkedArtworkAssets.values.contains(where:{$0.id==grant.id && $0.generation==grant.generation}) else{throw AutomationFailure(status:403,message:"The linked file is not approved for this API session.")}
    return grant
  }
  func handleLinkedArtwork(_ request:AutomationRequest)async throws->AutomationResponse? {
    guard request.path=="/v1/linked-artwork" else{return nil}
    guard request.method=="GET" else{throw AutomationFailure(status:405,message:"Artwork authorization requires the native API window.")}
    let assets=linkedArtworkAssets,expected=token,writable=linkedArtworkWritableAssets
    guard assets.allSatisfy({linkedArtworkRegistries[$0.key]?.stillAuthorizes($0.value)==true})else{throw AutomationFailure(status:403,message:"Artwork authorization was revoked. Clear and authorize the file again.")}
    let worker=Task.detached(priority:.utility){()throws->Data in
      var values:[[String:Any]]=[]
      for (id,grant)in assets {
        try Task.checkCancellation()
        do{let file=try LinkedArtworkRead.read(grant);values.append(["assetID":id.uuidString,"fileName":file.fileName,"fingerprint":file.fingerprint,"byteLength":file.data.count,"available":true,"canWrite":writable.contains(id)])}
        catch is CancellationError{throw CancellationError()}
        catch{values.append(["assetID":id.uuidString,"fileName":grant.url.lastPathComponent,"available":false,"canWrite":writable.contains(id)])}
      }
      return try JSONSerialization.data(withJSONObject:["assets":values.sorted{($0["assetID"]as?String ?? "")<($1["assetID"]as?String ?? "")}])
    }
    let body=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
    guard isRunning,token==expected,assets.count==linkedArtworkAssets.count,assets.allSatisfy({linkedArtworkAssets[$0.key]?.generation==$0.value.generation && linkedArtworkRegistries[$0.key]?.stillAuthorizes($0.value)==true})else{throw AutomationFailure(status:409,message:"Artwork authorization changed.")}
    return .init(status:200,contentType:"application/json",body:body)
  }
  func executeLinkedArtwork(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID)async throws {
    for (key,value)in command.parameters {_ = try BrushAPI.merge(value,schema:LinkedArtworkAPI.schema(key),path:key)}
    let store=document.store
    let layerID:UUID?=try command.parameters["layerID"].map{_ in try command.actionUUID("layerID")}
    let object=layerID.flatMap{id in store.document.layers.first{$0.id==id}?.smartObject}
    if layerID != nil,object==nil{throw AutomationFailure(status:404,message:"Smart Object not found.")}
    var grants:[UUID:LinkedArtworkGrant]=[:]
    if command.name=="smartObject.linked.embedAll" {
      for layer in store.document.layers {
        guard let source=layer.smartObject,let link=source.linkedSource,grants[source.sourceID]==nil else{continue}
        if !source.data.isEmpty,try layer.linkedSmartObjectPreview()==nil{continue}
        grants[source.sourceID]=try linkedArtworkGrant(link,store:store)
      }
    } else if command.name=="smartObject.linked.update" {
      for layer in store.document.layers {
        guard let source=layer.smartObject,let link=source.linkedSource,layerID==nil || source.sourceID==object?.sourceID else{continue}
        grants[source.sourceID]=try linkedArtworkGrant(link,store:store)
      }
      guard !grants.isEmpty else{throw AutomationFailure(status:422,message:"Choose linked artwork to update.")}
    } else if command.name=="smartObject.linked.embed" {
      guard let object,let link=object.linkedSource else{throw AutomationFailure(status:422,message:"Choose a linked Smart Object.")}
      let unresolved=try store.document.layers.first{$0.id==layerID}?.linkedSmartObjectPreview() != nil
      if object.data.isEmpty || unresolved {grants[object.sourceID]=try linkedArtworkGrant(link,store:store)}
    } else {
      let grant=try linkedArtworkGrant(command.actionUUID("assetID"),store:store);grants[grant.id]=grant
    }
    if let value=command.parameters["fingerprint"] {
      guard case .string(let hash)=value,hash.utf8.count==64,hash.allSatisfy({"0123456789abcdef".contains($0)})else{throw AutomationFailure(status:400,message:"fingerprint must be a lowercase SHA256.")}
    }
    let captured=grants,name=command.name,expectedFingerprint=command.parameters["fingerprint"],fit=try command.adjustmentBrushFlag("fit",true)
    let placement=command.name=="smartObject.linked.place" ? try LinkedArtworkPlacementAPI.options(command.parameters["placement"],fit:fit,fitExplicit:command.parameters["fit"] != nil):nil
    let placePreparation=linkedArtworkPlacementPreparation
    let hydrated:[UUID:LinkedArtworkRead]=try await executePreparedResult(document:document,shareID:shareID,revision:command.revision,allowLinkedSmartObject:true,
      validatePreparedOutput:{files in for file in files.values {guard try LinkedArtworkRead.signature(file.grant)==file.signature else{throw DocumentPersistenceConflict.changed}}},
      validateCommit:{[weak self,weak store]in
        guard let self,let store,captured.values.allSatisfy({grant in store.linkedSourceRegistry.stillAuthorizes(grant) && self.linkedArtworkAssets.values.contains{$0.id==grant.id && $0.generation==grant.generation}})else{throw AutomationFailure(status:409,message:"Artwork authorization was revoked.")}
      }){original in
        var reads:[UUID:LinkedArtworkRead]=[:]
        for(id,grant)in captured{reads[id]=try LinkedArtworkRead.read(grant)}
        if case .string(let expected)=expectedFingerprint,reads.values.first?.fingerprint != expected{throw AutomationFailure(status:409,message:"Artwork changed. Refresh its fingerprint before placement or relinking.")}
        let result:Command
        switch name {
        case "smartObject.linked.embedAll":result=try LinkedSmartObjectIO.embed(original,originals:reads.mapValues(\.data))
        case "smartObject.linked.place":
          let file=reads.values.first!
          result=try await placePreparation(file,original,placement!)
        case "smartObject.linked.relink":
          let file=reads.values.first!;result=try LinkedSmartObjectIO.replacement(file.data,fileName:file.fileName,reference:file.reference,in:original,layerID:layerID!)
        case "smartObject.linked.update":
          var target=original
          for(sourceID,file)in reads {
            guard let layer=target.layers.first(where:{$0.smartObject?.sourceID==sourceID})else{throw CraftError.invalid("Linked source changed.")}
            if layer.smartObject?.linkedSource?.contentHash==file.fingerprint,try layer.linkedSmartObjectPreview()==nil{continue}
            try LinkedSmartObjectIO.replacement(file.data,fileName:file.fileName,reference:file.reference,in:target,layerID:layer.id).apply(to:&target)
          }
          result = .linkedSmartObject(try .init(source:original,result:target,title:"Update Linked Smart Objects"))
        case "smartObject.linked.embed":
          let current=object!,id=layerID!
          if !current.data.isEmpty,try original.layers.first(where:{$0.id==id})?.linkedSmartObjectPreview()==nil {
            result=try LinkedSmartObjectIO.retag(original,layerID:id,source:current.embedding(),title:"Convert to Embedded")
          } else {
            let file=reads.values.first!
            if current.linkedSource?.contentHash==file.fingerprint,try original.layers.first(where:{$0.id==id})?.linkedSmartObjectPreview()==nil {
              result=try LinkedSmartObjectIO.retag(original,layerID:id,source:current.hydrating(file.data).embedding(),title:"Convert to Embedded")
            }else{result=try LinkedSmartObjectIO.replacement(file.data,fileName:file.fileName,reference:nil,in:original,layerID:id,title:"Convert to Embedded")}
          }
        case "smartObject.linked.convert":
          let current=object!,file=reads.values.first!;guard current.linkedSource==nil else{throw AutomationFailure(status:422,message:"Choose an embedded Smart Object.")}
          var linked=try current.linked(to:file.reference);linked.fileName=file.fileName
          result=try LinkedSmartObjectIO.retag(original,layerID:layerID!,source:linked,title:"Convert to Linked")
        default:throw AutomationFailure(status:422,message:"Unknown linked artwork operation.")
        }
        for file in reads.values {guard try LinkedArtworkRead.signature(file.grant)==file.signature else{throw DocumentPersistenceConflict.changed}}
        return (result,reads)
      }
    for file in hydrated.values {
      let ids=Set(store.document.layers.compactMap {layer -> UUID? in
        guard let source=layer.smartObject,source.linkedSource?.reference==file.grant.reference,source.linkedSource?.contentHash==file.fingerprint,source.data.isEmpty else{return nil};return source.sourceID
      })
      for id in ids {try store.session.hydrateLinkedSmartObject(id,bytes:file.data)}
    }
    if command.name=="smartObject.linked.place" {store.selectedLayerIDs=Set(store.document.activeLayerID.map{[$0]} ?? [])}
    store.synchronizeLinkedArtwork()
  }
}
