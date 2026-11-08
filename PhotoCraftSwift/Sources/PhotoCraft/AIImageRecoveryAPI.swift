import Foundation
import PhotoCraftCore

extension AutomationService {
  func authorizedAIInbox(_ id:UUID,store:EditorStore)throws->GeneratedResultInbox {
    guard let ownership=store.authorizedGeneratedResults[id],ownership.documentID==store.document.id,
      ownership.lifecycle==store.layerPanelGeneration else{throw AutomationFailure(status:404,message:"That saved result is not authorized in this document session.")}
    return store.generatedResultInbox
  }
  func savedAIResult(_ id:UUID,request:AutomationRequest,share:Share,document:CraftNSDocument,metadata:Bool)async throws->AutomationResponse {
    let inbox=try authorizedAIInbox(id,store:document.store)
    guard metadata || documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Allow document transfers before downloading an original result.")}
    let expected=revision(document.store),expectedToken=token,expectedGeneration=generation
    guard request.headers["x-photato-revision"]==nil || request.headers["x-photato-revision"]==expected else{throw AutomationFailure(status:409,message:"Stale AI document revision.")}
    let stamp=try inbox.identity(id)
    let worker=Task.detached(priority:.userInitiated){try Task.checkCancellation();let result=try inbox.load(id);try Task.checkCancellation();return result}
    let result=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    prune()
    guard !Task.isCancelled,isRunning,token==expectedToken,generation==expectedGeneration,metadata || documentTransfersEnabled,
      shares.contains(where:{$0.id==share.id && $0.document===document}),revision(document.store)==expected,
      (try? inbox.identity(id))==stamp else{throw AutomationFailure(status:409,message:"The saved-result request was cancelled or changed.")}
    _ = try authorizedAIInbox(id,store:document.store)
    if metadata {
      var object=AIImageAPI.record(result.0,layerID:id);object.removeValue(forKey:"layerID");object["resultID"]=id.uuidString
      return .json(object)
    }
    return .init(status:200,contentType:result.0.originalMediaType,body:result.1)
  }
  func openSavedAIResult(_ id:UUID,share:Share,document:CraftNSDocument,inbox:GeneratedResultInbox)async throws->AutomationResponse {
    guard documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Allow document transfers before opening a saved original.")}
    try preflight(document)
    guard shares.count<8 else{throw AutomationFailure(status:429,message:"Share up to eight documents at once.")}
    let expected=revision(document.store),expectedToken=token,expectedGeneration=generation
    let stamp=try inbox.identity(id),closing=controller.documentClosing.state?.id,opening=controller.documentOpening.generation
    let maintenance=controller.recoveryMaintenance.generation,discovery=controller.recoveryDiscovery.generation
    let worker=Task.detached(priority:.userInitiated){let value=try inbox.load(id);return try GeneratedImageStorage.recoveredDocument(value.0,original:value.1)}
    let model=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
    prune()
    guard !Task.isCancelled,isRunning,token==expectedToken,generation==expectedGeneration,documentTransfersEnabled,
      shares.contains(where:{$0.id==share.id && $0.document===document}),revision(document.store)==expected,
      (try? inbox.identity(id))==stamp else{throw AutomationFailure(status:409,message:"Opening the saved result was cancelled or changed.")}
    _ = try authorizedAIInbox(id,store:document.store);try preflight(document);try Self.checkLimits(model)
    guard shares.count<8,!controller.documentClosing.isActive,controller.documentClosing.state?.id==closing,
      !controller.documentOpening.isActive,!controller.documentOpening.hasPendingRequests,controller.documentOpening.generation==opening,
      !controller.recoveryIndex.isBusy,controller.recoveryMaintenance.generation==maintenance,controller.recoveryDiscovery.generation==discovery else{throw AutomationFailure(status:409,message:"A document lifecycle or sharing operation started while opening the result.")}
    let created=CraftNSDocument(model:model);controller.addDocument(created)
    do {try self.share(created)}catch{controller.removeDocument(created);created.close();throw error}
    created.updateChangeCount(.changeDone)
    guard let createdShare=shares.first(where:{$0.document===created})else{controller.removeDocument(created);created.close();throw AutomationFailure(status:500,message:"The recovered document could not be shared.")}
    return .json(state(createdShare,document:created),status:201)
  }
}

