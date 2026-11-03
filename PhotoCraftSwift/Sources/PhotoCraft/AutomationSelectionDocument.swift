import AppKit
import PhotoCraftCore

extension AutomationService {
  func newSelectionDocument(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers to create a selection document.") }
    guard !documentTransferBusy, shares.count < 8 else { throw AutomationFailure(status: 429, message: "Document transfer busy or sharing limit reached.") }
    guard try command.string("action")=="saveSelection",Set(command.parameters.keys).isSubset(of:["action","newDocument","name"]) else{throw AutomationFailure(status:400,message:"A new selection document accepts only action, newDocument and name.")}
    let name=try command.parameters["name"].map {_ in try command.string("name")} ?? "Alpha 1"
    let store = document.store, original = store.document, expectedToken = token, transferGeneration = documentTransferGeneration
    let panelGeneration = store.layerPanelGeneration, closing = controller.documentClosing.state?.id
    let opening = controller.documentOpening.generation, maintenance = controller.recoveryMaintenance.generation, discovery = controller.recoveryDiscovery.generation
    guard !controller.documentClosing.isActive, !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, !controller.recoveryIndex.isBusy else { throw AutomationFailure(status: 409, message: "Finish the document lifecycle operation first.") }
    documentTransferBusy = true; store.geometryBusy = true
    defer { documentTransferBusy = false; if store.layerPanelGeneration == panelGeneration { store.geometryBusy = false; store.geometryTask = nil } }
    let worker = Task.detached(priority: .userInitiated) { try original.selectionDocument(channelName:name) }
    store.geometryTask = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    let model = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard store.geometryTask?.isCancelled != true, isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transferGeneration,
      shares.contains(where: { $0.id == share.id && $0.document === document }), store.document == original, revision(store) == command.revision, store.layerPanelGeneration == panelGeneration,
      shares.count < 8, NSApp?.modalWindow == nil, !controller.documentClosing.isActive, controller.documentClosing.state?.id == closing,
      !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, controller.documentOpening.generation == opening,
      !controller.recoveryIndex.isBusy, controller.recoveryMaintenance.generation == maintenance, controller.recoveryDiscovery.generation == discovery else {
      throw AutomationFailure(status: 409, message: "Save Selection cancelled or sharing/lifecycle changed.")
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
