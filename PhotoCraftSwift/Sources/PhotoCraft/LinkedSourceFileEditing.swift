import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

struct LinkedSourceWriteOperation {
  let id:UUID
  let layerID:UUID
  let assetID:UUID
  var stage:String
}

/// One task owns this staged file at a time; publication is separate from parent history.
final class PreparedLinkedSourceWrite:@unchecked Sendable {
  let original:CraftDocument
  let result:CraftDocument
  let grants:[UUID:LinkedArtworkGrant]
  let before:LinkedArtworkRead
  let fingerprint:String
  private let output:LinkedArtworkExport?
  private let scoped:Bool
  private(set) var fileWritten=false
  private init(original:CraftDocument,result:CraftDocument,grants:[UUID:LinkedArtworkGrant],before:LinkedArtworkRead,
    fingerprint:String,output:LinkedArtworkExport?,scoped:Bool) {
    self.original=original;self.result=result;self.grants=grants;self.before=before;self.fingerprint=fingerprint;self.output=output;self.scoped=scoped
  }
  deinit{output?.discard();if scoped{before.grant.scopeURL.stopAccessingSecurityScopedResource()}}
  static func prepare(_ bytes:Data,in original:CraftDocument,grants:[UUID:LinkedArtworkGrant],
    target:LinkedArtworkGrant,expectedFingerprint:String)throws->PreparedLinkedSourceWrite {
    guard !bytes.isEmpty,bytes.count<=SmartObject.maximumSourceBytes else{throw AutomationFailure(status:413,message:"Send1 byte through64MiB of original artwork.")}
    let scoped=target.scopeURL.startAccessingSecurityScopedResource();var output:LinkedArtworkExport?
    do {
      let before:LinkedArtworkRead
      do{before=try LinkedArtworkRead.read(target)}catch{throw AutomationFailure(status:409,message:"The approved source is missing or changed location. Relink it before writing.")}
      guard before.fingerprint==expectedFingerprint else{throw AutomationFailure(status:412,message:"The original file changed. Download it again before saving.")}
      let hash=LinkedSmartObjectSource.fingerprint(bytes)
      if before.data.starts(with:Data("8BPS".utf8)),bytes.starts(with:Data("8BPS".utf8)),before.data.count>=6,bytes.count>=6 {
        guard before.data[4..<6]==bytes[4..<6]else{throw AutomationFailure(status:415,message:"Preserve the original PSD or PSB container when editing its source.")}
      }
      var result=original
      for (sourceID,grant)in grants {
        try Task.checkCancellation()
        guard grant.id==target.id,let layer=result.layers.first(where:{$0.smartObject?.sourceID==sourceID}),
          let old=layer.smartObject,old.linkedSource != nil else{throw AutomationFailure(status:409,message:"The linked source changed.")}
        if old.linkedSource?.contentHash==hash,try layer.linkedSmartObjectPreview()==nil{continue}
        let reference=try LinkedSmartObjectSource(reference:grant.sourceReference ?? grant.reference,
          authorizationID:grant.sourceReference==nil ? grant.id:nil,contentHash:hash,byteLength:UInt64(bytes.count),
          modificationDate:hash==before.fingerprint ? before.modified:nil)
        try LinkedSmartObjectIO.replacement(bytes,fileName:before.fileName,reference:reference,in:result,layerID:layer.id).apply(to:&result)
        guard result.layers.first(where:{$0.id==layer.id})?.smartObject?.mediaType==old.mediaType else {
          throw AutomationFailure(status:415,message:"Preserve the original source format. Use Relink to change file types.")
        }
      }
      guard !grants.isEmpty else{throw AutomationFailure(status:409,message:"No matching linked source remains in this document.")}
      _ = try PreparedEdit(command:.linkedSmartObject(.init(source:original,result:result,title:"Update Linked Smart Objects")),document:original)
      try AutomationService.checkLimits(result)
      if hash != before.fingerprint {output=try LinkedArtworkExport(url:target.url,data:bytes,followSymbolicLinks:false)}
      guard (try? LinkedArtworkRead.signature(target))==before.signature else{throw AutomationFailure(status:412,message:"The original file changed while preparing its save.")}
      return .init(original:original,result:result,grants:grants,before:before,fingerprint:hash,output:output,scoped:scoped)
    }catch{output?.discard();if scoped{target.scopeURL.stopAccessingSecurityScopedResource()};throw error}
  }
  func initialEdit()throws->PreparedEdit {
    try .init(command:.linkedSmartObject(.init(source:original,result:result,title:"Update Linked Smart Objects")),document:original)
  }
  func publish()throws {
    try Task.checkCancellation()
    guard (try? LinkedArtworkRead.signature(before.grant))==before.signature else{throw AutomationFailure(status:412,message:"The original file changed before publication.")}
    if let output {try output.commit();fileWritten=true}
  }
  func finalized()throws->(PreparedEdit,[UUID:LinkedArtworkRead]) {
    let saved=try LinkedArtworkRead.read(before.grant)
    guard saved.fingerprint==fingerprint else{throw AutomationFailure(status:409,message:"The source changed again after saving; the parent was not updated.")}
    var result=result,files:[UUID:LinkedArtworkRead]=[:]
    for (id,grant)in grants {
      let file=LinkedArtworkRead(data:saved.data,fingerprint:saved.fingerprint,signature:saved.signature,modified:saved.modified,fileName:saved.fileName,grant:grant)
      files[id]=file
      for i in result.layers.indices where result.layers[i].smartObject?.sourceID==id {
        if result != original {result.layers[i].smartObject?.linkedSource=try file.reference}
      }
    }
    let edit=try PreparedEdit(command:.linkedSmartObject(.init(source:original,result:result,title:"Update Linked Smart Objects")),document:original)
    return(edit,files)
  }
}

enum LinkedSourceFileAPI {
  static func etag(_ hash:String)->String{"\""+hash+"\""}
  static func fingerprint(_ value:String?)throws->String {
    guard let value else{throw AutomationFailure(status:428,message:"Download the original and provide its ETag in If-Match.")}
    guard value.utf8.count==66,value.first=="\"",value.last=="\"" else{throw AutomationFailure(status:400,message:"If-Match must contain one quoted lowercase SHA256 ETag.")}
    let hash=String(value.dropFirst().dropLast());guard hash.allSatisfy({"0123456789abcdef".contains($0)})else{throw AutomationFailure(status:400,message:"Invalid original source ETag.")};return hash
  }
  static var capabilities:[String:Any] {[
    "path":"/v1/documents/{id}/smart-objects/{layerID}/linked-source","methods":["GET","POST"],"contentType":"application/octet-stream",
    "maximumBytes":SmartObject.maximumSourceBytes,"read":"Requires an individually approved file for this API session; downloads current original bytes and a strong ETag. Existing source extraction remains unchanged.",
    "write":"Native per-file source-update switch, current X-Photato-Revision, If-Match ETag and same-format validated original bytes. All source IDs using this approval in the shared document update in one Undo step.",
    "cancel":["method":"POST","path":"/v1/documents/{id}/smart-objects/{layerID}/linked-source/cancel","schema":BrushAPI.object(["operationID":["type":"string","format":"uuid"]],required:["operationID"])],
    "operations":"capabilities.linkedSourceWriteOperations lists operationID/layerID/stage by shared document UUID.",
    "resultSchema":["type":"object","required":["fileWritten","documentUpdated","sourceFingerprint","state"],"properties":["fileWritten":["type":"boolean"],"documentUpdated":["type":"boolean"],"sourceFingerprint":["type":"string","pattern":"^[a-f0-9]{64}$"],"state":["type":"object"]]],
    "history":"Parent Undo/Redo restores cached artwork, not the external original. Acknowledged file versions are not automatically reapplied after Undo.",
    "lateFailure":"After publication, conflict/cancellation/revocation reports409 with fileWritten:true/documentUpdated:false/sourceFingerprint. The saved original remains; no filesystem rollback is claimed.",
    "permission":"Per-file switches default off, cannot be enabled by HTTP, and reset on stop/clear. No arbitrary paths or file-type conversion.",
    "adobe":"Photato file authorization/editing extension; no published Adobe original-file-write endpoint is invented.",
    "limits":"64MiB original, native source/format/decoder and shared-document budgets. Full source/editor/sidecar/Photoshop/platform qualification remains open."
  ]}
}

extension AutomationService {
  func setLinkedArtworkWritable(_ assetID:UUID,enabled:Bool) {
    guard isRunning,let grant=linkedArtworkAssets[assetID],linkedArtworkRegistries[assetID]?.stillAuthorizes(grant)==true else{return}
    linkedSourceWriteGeneration=UUID()
    if enabled{linkedArtworkWritableAssets.insert(assetID)}else{
      linkedArtworkWritableAssets.remove(assetID)
      for (id,op)in linkedSourceWriteOperations where op.assetID==assetID{linkedSourceWriteTasks[id]?.cancel()}
    }
  }
  func clearLinkedSourceWrites() {
    linkedSourceWriteGeneration=UUID();linkedArtworkWritableAssets.removeAll()
    for task in linkedSourceWriteTasks.values{task.cancel()};linkedSourceWriteTasks.removeAll();linkedSourceWriteOperations.removeAll()
  }
  func handleLinkedSourceFile(_ request:AutomationRequest)async throws->AutomationResponse? {
    let parts=request.path.split(separator:"/")
    guard [6,7].contains(parts.count),parts[0]=="v1",parts[1]=="documents",parts[3]=="smart-objects",parts[5]=="linked-source",
      request.path=="/"+parts.joined(separator:"/"),parts.count==6 || parts[6]=="cancel"else{return nil}
    guard let shareID=UUID(uuidString:String(parts[2])),let layerID=UUID(uuidString:String(parts[4])),
      let share=shares.first(where:{$0.id==shareID}),let document=share.document else{throw AutomationFailure(status:404,message:"Shared document or layer not found.")}
    let store=document.store
    if parts.count==7 {
      guard request.method=="POST"else{throw AutomationFailure(status:405,message:"Use POST to cancel a linked source update.")}
      guard request.body.count<=4096,let fields=try? JSONSerialization.jsonObject(with:request.body)as?[String:Any],Set(fields.keys)==["operationID"],
        let value=fields["operationID"]as?String,let id=UUID(uuidString:value)else{throw AutomationFailure(status:400,message:"Provide one linked source operationID.")}
      guard let op=linkedSourceWriteOperations[shareID],op.id==id,op.layerID==layerID else{throw AutomationFailure(status:409,message:"The linked source operation changed.")}
      linkedSourceWriteTasks[shareID]?.cancel();return .json(["operationID":id.uuidString,"cancellationRequested":true])
    }
    guard let source=store.document.layers.first(where:{$0.id==layerID})?.smartObject,let link=source.linkedSource else{throw AutomationFailure(status:404,message:"Linked Smart Object not found.")}
    let grant=try linkedArtworkGrant(link,store:store)
    guard let assetID=linkedArtworkAssets.first(where:{$0.value.id==grant.id && $0.value.generation==grant.generation})?.key else{throw AutomationFailure(status:403,message:"Approve this source file in the native API window.")}
    if request.method=="GET" {
      let expected=token,revision=source.revision
      let worker=Task.detached(priority:.utility){try LinkedArtworkRead.read(grant)}
      let file=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};try Task.checkCancellation()
      guard isRunning,token==expected,shares.contains(where:{$0.id==shareID && $0.document === document}),
        store.document.layers.first(where:{$0.id==layerID})?.smartObject?.revision==revision,
        linkedArtworkAssets[assetID]?.generation==grant.generation,store.linkedSourceRegistry.stillAuthorizes(grant)else{throw AutomationFailure(status:409,message:"Source sharing or authorization changed.")}
      return .init(status:200,contentType:"application/octet-stream",body:file.data,headers:["ETag":LinkedSourceFileAPI.etag(file.fingerprint)])
    }
    guard request.method=="POST"else{throw AutomationFailure(status:405,message:"Use GET or POST for linked source files.")}
    guard linkedArtworkWritableAssets.contains(assetID)else{throw AutomationFailure(status:403,message:"Enable source updates for this file in the native API window.")}
    guard linkedSourceWriteLeases[grant.id]==nil else{throw AutomationFailure(status:429,message:"Another save of this original is still finishing. Retry shortly.")}
    try preflight(document)
    guard store.canManageLinkedArtwork else{throw AutomationFailure(status:422,message:"Finish the current editing context before updating the original.")}
    guard let expected=request.headers["x-photato-revision"],expected==revision(store)else{throw AutomationFailure(status:409,message:"Stale or missing parent document revision.")}
    let expectedFile=try LinkedSourceFileAPI.fingerprint(request.headers["if-match"])
    guard request.headers["content-type"]?.split(separator:";").first?.lowercased()=="application/octet-stream"else{throw AutomationFailure(status:415,message:"Send application/octet-stream original source bytes.")}
    guard !request.body.isEmpty,request.body.count<=SmartObject.maximumSourceBytes else{throw AutomationFailure(status:413,message:"Send1 byte through64MiB of original artwork.")}
    let original=store.document,session=store.sessionGeneration,panel=store.layerPanelGeneration,expectedToken=token,permission=linkedSourceWriteGeneration
    var grants:[UUID:LinkedArtworkGrant]=[:]
    for layer in original.layers {
      guard let object=layer.smartObject,let link=object.linkedSource,grants[object.sourceID]==nil,
        let candidate=try? store.linkedSourceRegistry.resolve(link,documentID:original.id,documentURL:store.linkedArtworkDocumentURL),candidate.id==grant.id else{continue}
      grants[object.sourceID]=candidate
    }
    let captured=grants,operation=UUID(),prepare=linkedSourceWritePreparation,after=linkedSourceWriteAfterPublication,bytes=request.body
    @MainActor func validate()throws {
      guard isRunning,token==expectedToken,linkedSourceWriteGeneration==permission,linkedArtworkWritableAssets.contains(assetID),
        linkedArtworkAssets[assetID]?.generation==grant.generation,shares.contains(where:{$0.id==shareID && $0.document === document}),
        store.document==original,store.sessionGeneration==session,store.layerPanelGeneration==panel,revision(store)==expected,
        document.closeWorkflowID==nil,!document.fileOperationBusy,!document.recoveryWriteBusy,
        captured.values.allSatisfy({store.linkedSourceRegistry.stillAuthorizes($0)}) else{throw AutomationFailure(status:409,message:"The source update was cancelled, changed or its permission was revoked.")}
    }
    linkedSourceWriteLeases[grant.id]=operation
    linkedSourceWriteOperations[shareID] = .init(id:operation,layerID:layerID,assetID:assetID,stage:"preparing")
    var reported=false
    store.linkedArtworkOperationID=operation;store.geometryBusy=true;store.renderTask?.cancel();store.status="Saving linked source…"
    defer {
      if linkedSourceWriteLeases[grant.id]==operation{linkedSourceWriteLeases.removeValue(forKey:grant.id)}
      if linkedSourceWriteOperations[shareID]?.id==operation{linkedSourceWriteOperations.removeValue(forKey:shareID);linkedSourceWriteTasks.removeValue(forKey:shareID)}
      if store.linkedArtworkOperationID==operation && store.layerPanelGeneration==panel{store.linkedArtworkOperationID=nil;store.geometryBusy=false;store.geometryTask=nil;if !reported{store.status="Linked source update stopped"};store.render()}
    }
    var staged:PreparedLinkedSourceWrite?
    do {
      let worker=Task.detached(priority:.userInitiated){try await prepare(bytes,original,captured,grant,expectedFile)}
      let observer=Task{await withTaskCancellationHandler{_ = try? await worker.value}onCancel:{worker.cancel()}};store.geometryTask=observer;linkedSourceWriteTasks[shareID]=observer
      let prepared=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()};staged=prepared
      try Task.checkCancellation();guard !observer.isCancelled else{throw CancellationError()};try validate()
      var candidate=store.session;try candidate.executePrepared(prepared.initialEdit());try Self.checkLimits(candidate.document)
      linkedSourceWriteOperations[shareID]?.stage="saving"
      let saving=Task.detached(priority:.userInitiated){()throws->(PreparedEdit,[UUID:LinkedArtworkRead])in
        try prepared.publish();if prepared.fileWritten{try await after()};try Task.checkCancellation();return try prepared.finalized()
      }
      let savingObserver=Task{await withTaskCancellationHandler{_ = try? await saving.value}onCancel:{saving.cancel()}};store.geometryTask=savingObserver;linkedSourceWriteTasks[shareID]=savingObserver
      let (edit,files)=try await withTaskCancellationHandler{try await saving.value}onCancel:{saving.cancel()}
      try Task.checkCancellation();guard !savingObserver.isCancelled else{throw CancellationError()};try validate()
      let signature=Task.detached{try LinkedArtworkRead.signature(grant)}
      let current=try await signature.value;try Task.checkCancellation();try validate()
      guard current==files.values.first?.signature else{throw AutomationFailure(status:409,message:"The source changed after saving; the parent was not updated.")}
      linkedSourceWriteOperations[shareID]?.stage="refreshing"
      try store.executeCompositePreparedEdit(edit,allowLinkedSmartObject:true)
      store.synchronizeLinkedArtwork();store.linkedSourceController?.acknowledge(files)
      if store.document != original{store.onChange?(.changeDone)};store.status="Linked source saved"
      var response=AutomationResponse.json(["fileWritten":prepared.fileWritten,"documentUpdated":store.document != original,"sourceFingerprint":prepared.fingerprint,"state":state(share,document:document)])
      response.headers=["ETag":LinkedSourceFileAPI.etag(prepared.fingerprint)];reported=true;return response
    }catch {
      if let staged,staged.fileWritten {
        reported=true;store.status="Source saved; parent update pending"
        return .json(["error":"The original file was saved, but the parent was not updated. Refresh the source before retrying.","fileWritten":true,"documentUpdated":false,"sourceFingerprint":staged.fingerprint],status:409)
      }
      if error is CancellationError{throw AutomationFailure(status:409,message:"Linked source update cancelled before publication.")}
      throw error
    }
  }
}
