import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum UpscaleAPI {
  static let name="document.upscale", cancel="document.upscale.cancel"
  static let commands=[name,cancel]
  static func schema(_ key:String)->[String:Any] {
    key == "scale" ? ["type":"integer","enum":[2,4],"default":2] : ["type":"string","format":"uuid"]
  }
  static var stateSchema:[String:Any] {BrushAPI.object([
    "available":BrushAPI.flag,"reason":["type":["string","null"]],"dialogOpen":BrushAPI.flag,"busy":BrushAPI.flag,
    "operationID":["type":["string","null"],"format":"uuid"],
    "progress":["type":["object","null"],"properties":["completedTiles":["type":"integer"],"totalTiles":["type":"integer"]]]],
    required:["available","reason","dialogOpen","busy","operationID","progress"])}
  @MainActor static func state(_ store:EditorStore)->[String:Any] {
    let reason=LearnedUpscaleDocument.unavailableReason(store.document) ?? store.upscaleUnavailableReason()
    return ["available":reason == nil,"reason":reason as Any? ?? NSNull(),"dialogOpen":store.upscaleDraft != nil,
      "busy":store.upscaleOperationID != nil,"operationID":store.upscaleOperationID?.uuidString as Any? ?? NSNull(),
      "progress":store.upscaleProgress.map{["completedTiles":$0.completedTiles,"totalTiles":$0.totalTiles]} as Any? ?? NSNull()]
  }
  static var capabilities:[String:Any] {[
    "commands":commands,"model":LocalUpscaleProvider.identifier,"processing":"onDevice","requiresDocumentTransfers":true,
    "modelPolicy":"Optional pinned BSD-3 Real-ESRGAN model, macOS26+AppleSilicon; no credentials, network call, credits, arbitrary model upload or silent resize fallback. Core editing remains macOS14+.",
    "output":"201 new shared unsaved merged RGB document with fresh identity, updated name, retained PPI/depth/working profile and empty history. Source samples/layers/selection/history/file association remain unchanged. Saved channels, paths and temporal data are not copied into this derived merged document.",
    "numeric":"Local learned4xRGB in encoded sRGB;2x is area reduction of that learned output. Alpha is independently bilinear. SDR still RGB required; HDR/out-of-gamut samples reject rather than being silently clipped before inference. Model outputs are finite-checked and clamped to SDR. Tiled bounded inference/paged scratch/output; existing render/profile/storage and API budgets apply.",
    "cancellation":"operationID and current revision cancel the exact active job. A Core ML prediction finishes before cancellation can be observed. Tile preparation/output check cancellation. Session/token/share/transfer/source/lifecycle/capacity are checked again before registering the output.",
    "adobe":"No corresponding generative upscale route or model is defined by the pinned Photoshop v2 contract; none is invented. This provider does not reproduce Firefly/Topaz output. Actions multi-document transport, provider/default equality, full AI06, physical-platform and60fps qualification remain open.","stateSchema":stateSchema]}
}
extension AutomationService {
  func upscaleDocument(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers to create an upscaled document.") }
    guard !documentTransferBusy, shares.count < 8 else { throw AutomationFailure(status: 429, message: "Document transfer busy or sharing limit reached.") }
    let scale = try command.parameters["scale"].map {_ in try command.integer("scale",range:2...4)} ?? 2
    guard [2,4].contains(scale) else {throw AutomationFailure(status:400,message:"scale must be 2 or 4.")}
    if let reason = LearnedUpscaleDocument.unavailableReason(document.store.document) ?? document.store.upscaleUnavailableReason() {
      throw AutomationFailure(status:422,message:reason)
    }
    _ = try LearnedUpscale.outputSize(width:document.store.document.width,height:document.store.document.height,scale:scale)
    let prepare = document.store.upscalePreparation, operation = UUID()
    let store = document.store, original = store.document, expectedToken = token, transferGeneration = documentTransferGeneration
    let panelGeneration = store.layerPanelGeneration, closing = controller.documentClosing.state?.id
    let opening = controller.documentOpening.generation, maintenance = controller.recoveryMaintenance.generation, discovery = controller.recoveryDiscovery.generation
    guard !controller.documentClosing.isActive, !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, !controller.recoveryIndex.isBusy else { throw AutomationFailure(status: 409, message: "Finish the document lifecycle operation first.") }
    documentTransferBusy = true; store.geometryBusy = true; store.upscaleOperationID = operation; store.upscaleProgress = nil
    defer {
      documentTransferBusy = false
      if store.upscaleOperationID == operation {
        store.upscaleOperationID = nil; store.upscaleProgress = nil
        if store.layerPanelGeneration == panelGeneration {store.geometryBusy = false; store.geometryTask = nil}
      }
    }
    let report: @Sendable (LearnedUpscale.Progress) -> Void = { [weak store] value in
      Task { @MainActor [weak store] in store?.updateUpscaleProgress(value,operation:operation) }
    }
    let worker = Task.detached(priority: .userInitiated) { try await prepare(original,scale,report) }
    store.geometryTask = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    let model = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard store.upscaleOperationID == operation, store.geometryTask?.isCancelled != true, isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transferGeneration,
      shares.contains(where: { $0.id == share.id && $0.document === document }), store.document == original, revision(store) == command.revision, store.layerPanelGeneration == panelGeneration,
      shares.count < 8, NSApp?.modalWindow == nil, !controller.documentClosing.isActive, controller.documentClosing.state?.id == closing,
      !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, controller.documentOpening.generation == opening,
      !controller.recoveryIndex.isBusy, controller.recoveryMaintenance.generation == maintenance, controller.recoveryDiscovery.generation == discovery else {
      throw AutomationFailure(status: 409, message: "Upscaling cancelled or sharing/lifecycle changed.")
    }
    try Self.checkLimits(model)
    let created = CraftNSDocument(model: model); controller.addDocument(created)
    do { try self.share(created) } catch { controller.removeDocument(created); throw error }
    created.updateChangeCount(.changeDone); store.geometryBusy = false
    controller.documentWindows.presentAfterCurrentSheet(created)
    guard let added = shares.first(where: { $0.document === created }) else { throw AutomationFailure(status: 409, message: "Document sharing ended.") }
    return .json(state(added, document: created), status: 201)
  }
}
