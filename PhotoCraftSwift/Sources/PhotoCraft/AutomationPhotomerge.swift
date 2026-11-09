import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension PhotomergeSettings {
  static var apiSchema: [String:Any] {
    ["type":"object","additionalProperties":false,"properties":[
      "projection":["type":"string","enum":PhotoAlignSettings.Projection.allCases.map(\.rawValue),"default":"auto"],
      "blendImages":["type":"boolean","default":true],"fillTransparentAreas":["type":"boolean","default":false],
      "focalLengthPixels":["type":"number","minimum":10,"maximum":1_000_000]]]
  }
  static var sourcesSchema: [String:Any] {
    ["type":"array","minItems":2,"maxItems":7,"items":["type":"object","additionalProperties":false,"required":["id","revision"],"properties":["id":["type":"string","format":"uuid"],"revision":["type":"string","minLength":1,"maxLength":256]]]]
  }
  static var apiCapabilities: [String:Any] {
    ["command":"document.photomerge","cancelCommand":"document.photomerge.cancel","settingsSchema":apiSchema,"sourcesSchema":sourcesSchema,
     "permission":"Document transfers must be enabled. Every input is an explicitly shared document; include the command's target among the sources, with its current revision. No server-side local paths are accepted.",
     "result":"HTTP201 with a new shared document state; sources stay unchanged. The new panorama is unsaved and uses ordinary native history/persistence for subsequent edits. Source revisions and session/lifecycle grants are revalidated after the worker completes.",
     "behavior":"Flattens each photograph, converts to the first source's working profile/depth, aligns content, expands the canvas to union bounds, and optionally blends and fills transparent areas. Blended photographs retain their names, editable corrected pixels and masks. Transparent-area fill adds a merged layer; partial-alpha sources require isolation. Source snapshots are immutable.",
     "limits":"Two to7 shared inputs leave capacity for the new eighth share. Desktop supports2–16 files/open documents. Alignment16MP/layer and32MP combined; blended output4MP and16MP combined grid; API additionally caps4MP canvas/8,000layers/128MiB.",
     "adobe":"The pinned published Photoshop v2 contract has no dedicated Photomerge endpoint. Existing create-composite and execute-actions alignment/blend subsets remain available; this new-document orchestration is Photato-specific. No Adobe route or proprietary equality is claimed."]
  }
}
extension AutomationCommand {
  struct PhotomergeOptions: Sendable { var sources: [(UUID,String)];var settings: PhotomergeSettings;var name: String }
  func photomergeOptions() throws -> PhotomergeOptions {
    guard case .array(let raw) = parameters["sources"],(2...7).contains(raw.count) else { throw AutomationFailure(status:400,message:"Provide two to seven shared source documents.") }
    let sources = try raw.map { item -> (UUID,String) in
      guard case .object(let fields) = item,Set(fields.keys) == ["id","revision"],case .string(let text) = fields["id"],let id = UUID(uuidString:text),case .string(let revision) = fields["revision"],!revision.isEmpty,revision.count <= 256 else { throw AutomationFailure(status:400,message:"Each source requires a shared document id and current revision.") };return (id,revision)
    }
    guard Set(sources.map(\.0)).count == sources.count else { throw AutomationFailure(status:400,message:"Duplicate source documents are not allowed.") }
    var settings = PhotomergeSettings()
    if let raw = parameters["settings"] {
      guard case .object(let fields) = raw,Set(fields.keys).isSubset(of:["projection","blendImages","fillTransparentAreas","focalLengthPixels"]) else { throw AutomationFailure(status:400,message:"Unknown Photomerge settings.") }
      if let value = fields["projection"] { guard case .string(let s) = value,let p = PhotoAlignSettings.Projection(rawValue:s) else { throw AutomationFailure(status:400,message:"Unknown panorama projection.") };settings.projection = p }
      if let value = fields["focalLengthPixels"] { guard case .number(let n) = value,n.isFinite,(10...1_000_000).contains(n) else { throw AutomationFailure(status:400,message:"Focal length must be10–1,000,000 pixels.") };settings.focalLengthPixels = n }
      for key in ["blendImages","fillTransparentAreas"] { if let value = fields[key] {
        guard case .bool(let enabled) = value else { throw AutomationFailure(status:400,message:"\(key) must be boolean.") };if key == "blendImages" { settings.blendImages = enabled } else { settings.fillTransparentAreas = enabled }
      } }
    }
    return .init(sources:sources,settings:settings,name:try parameters["name"] == nil ? "Untitled Panorama":string("name"))
  }
}
extension AutomationService {
  func executePhotomerge(_ command: AutomationCommand,anchorID: UUID) async throws -> AutomationResponse {
    let options = try command.photomergeOptions()
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document uploads and downloads in the native API window before creating a panorama.") }
    guard !documentTransferBusy,controller.photomergeWorkspace == nil,controller.canPublishPhotomerge else { throw AutomationFailure(status:409,message:"Finish the current document transfer or Photomerge operation.") }
    guard options.sources.contains(where:{$0.0 == anchorID}) else { throw AutomationFailure(status:400,message:"Include the command target in the panorama sources.") }
    guard shares.count < 8 else { throw AutomationFailure(status:429,message:"Leave one sharing slot available for the new panorama.") }
    let documents = try options.sources.map { id,revision -> CraftNSDocument in
      guard let document = shares.first(where:{$0.id == id})?.document else { throw AutomationFailure(status:404,message:"A shared source document was not found.") }
      try preflight(document);guard self.revision(document.store) == revision else { throw AutomationFailure(status:409,message:"A source revision is stale.") };return document
    }
    let snapshots = documents.map{$0.store.document},storeGenerations = documents.map{$0.store.layerPanelGeneration}
    let expectedToken = token,transferGeneration = documentTransferGeneration,serviceGeneration = generation
    let openGeneration = controller.documentOpening.generation,closeID = controller.documentClosing.state?.id,maintenance = controller.recoveryMaintenance.generation,discovery = controller.recoveryDiscovery.generation
    let operationID = UUID();photomergeOperationID = operationID;photomergeSourceIDs = Set(options.sources.map(\.0))
    documentTransferBusy = true
    for document in documents { document.store.geometryBusy = true;document.store.renderTask?.cancel() }
    let prepare = photomergePreparation
    let worker = Task.detached(priority:.userInitiated) { try prepare(snapshots,options.settings,options.name) }
    photomergeTask = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    for document in documents { document.store.geometryTask = observer }
    defer {
      if photomergeOperationID == operationID { photomergeTask = nil;photomergeOperationID = nil;photomergeSourceIDs = [] }
      documentTransferBusy = false
      for (i,document) in documents.enumerated() where document.store.layerPanelGeneration == storeGenerations[i] {
        document.store.geometryBusy = false;document.store.geometryTask = nil;document.store.render()
      }
    }
    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation();guard !observer.isCancelled else { throw CancellationError() }
    prune()
    guard isRunning,token == expectedToken,generation == serviceGeneration,documentTransfersEnabled,documentTransferGeneration == transferGeneration,controller.photomergeWorkspace == nil,controller.canPublishPhotomerge,controller.documentOpening.generation == openGeneration,controller.documentClosing.state?.id == closeID,controller.recoveryMaintenance.generation == maintenance,controller.recoveryDiscovery.generation == discovery else { throw AutomationFailure(status:409,message:"Panorama creation was cancelled, revoked or interrupted by a document operation.") }
    for (i,document) in documents.enumerated() {
      guard shares.contains(where:{$0.id == options.sources[i].0 && $0.document === document}),revision(document.store) == options.sources[i].1,document.store.document == snapshots[i],document.store.layerPanelGeneration == storeGenerations[i] else { throw AutomationFailure(status:409,message:"A panorama source changed or sharing ended.") }
    }
    try Self.checkLimits(result.document);guard shares.count < 8 else { throw AutomationFailure(status:429,message:"Document sharing capacity changed during Photomerge.") }
    let created = CraftNSDocument(model:result.document);controller.addDocument(created)
    do { try share(created) } catch { controller.removeDocument(created);throw error }
    created.updateChangeCount(.changeDone);created.makeWindowControllers();created.showWindows()
    guard let shared = shares.first(where:{$0.document === created}) else { throw AutomationFailure(status:409,message:"Panorama sharing ended.") }
    var output = state(shared,document:created)
    output["photomergeResult"] = ["projection":result.projection.rawValue,"matchedPoints":result.matchedPoints,"rmsPixels":result.rmsPixels,"sourceCount":snapshots.count]
    return .json(output,status:201)
  }
}
