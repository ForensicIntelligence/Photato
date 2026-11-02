import AppKit
import PhotoCraftCore

enum DocumentDuplicateAPI {
  static let name = "document.duplicate"
  static func schema(_ key: String) -> [String:Any] {
    key == "merged" ? ["type":"boolean","default":false] : ["type":"string","minLength":1,"maxLength":256]
  }
  static var stateSchema: [String:Any] { BrushAPI.object(["available":BrushAPI.flag,"dialogOpen":BrushAPI.flag,"mergedAvailable":BrushAPI.flag,"mergedUnavailableReason":["type":["string","null"]]],required:["available","dialogOpen","mergedAvailable","mergedUnavailableReason"]) }
  static var capabilities: [String:Any] { ["command":name,"stateSchema":stateSchema,"result":"201 new shared document state. Requires document transfers and a current source revision. Original source/history/file association are unchanged. The copy has a fresh document identity, empty history and no file URL.","behavior":"All-layer copy retains modeled layers, masks, native component/palette/ink samples, channels, selection, paths, profiles, guides, comps, variables, patterns, metadata and temporal data. Merged static RGB copy uses full visible canvas composition, preserving transparency and ignoring selection for rendering.","limits":"Current API sharing/transfer/memory limits apply; no logical megapixel cap. Merged native component/palette/ink and temporal composition remains unavailable rather than converting or losing source samples. Actions multi-document recording and exact Photoshop output/defaults/live/platform checks remain open.","adobe":"The pinned Firefly contract has no dedicated document-duplication endpoint. UXP Document.duplicate is a desktop API; it is not a Firefly route. Multi-document action execution remains unsupported and is not silently mapped to Flatten Image."] }
}
extension EditorStore {
  var documentDuplicateState: [String:Any] { ["available":canDuplicateDocument,"dialogOpen":documentDuplicateDraft != nil,"mergedAvailable":DocumentDuplication.mergedUnavailableReason(document) == nil,"mergedUnavailableReason":DocumentDuplication.mergedUnavailableReason(document) as Any? ?? NSNull()] }
}
extension AutomationService {
  func duplicateDocument(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers to create a duplicate document.") }
    guard !documentTransferBusy, shares.count < 8 else { throw AutomationFailure(status: 429, message: "Document transfer busy or sharing limit reached.") }
    let name = try command.parameters["name"].map { _ in try command.string("name") } ?? (document.store.document.name + " copy")
    try LayerDuplication.validateName(name)
    let merged = try command.pathFlag("merged",false), prepare = document.store.documentDuplicatePreparation
    let store = document.store, original = store.document, expectedToken = token, transferGeneration = documentTransferGeneration
    let panelGeneration = store.layerPanelGeneration, closing = controller.documentClosing.state?.id
    let opening = controller.documentOpening.generation, maintenance = controller.recoveryMaintenance.generation, discovery = controller.recoveryDiscovery.generation
    guard !controller.documentClosing.isActive, !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, !controller.recoveryIndex.isBusy else { throw AutomationFailure(status: 409, message: "Finish the document lifecycle operation first.") }
    documentTransferBusy = true; store.geometryBusy = true
    defer { documentTransferBusy = false; if store.layerPanelGeneration == panelGeneration { store.geometryBusy = false; store.geometryTask = nil } }
    let worker = Task.detached(priority: .userInitiated) { try prepare(original,name,merged) }
    store.geometryTask = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    let model = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard store.geometryTask?.isCancelled != true, isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transferGeneration,
      shares.contains(where: { $0.id == share.id && $0.document === document }), store.document == original, revision(store) == command.revision, store.layerPanelGeneration == panelGeneration,
      shares.count < 8, NSApp?.modalWindow == nil, !controller.documentClosing.isActive, controller.documentClosing.state?.id == closing,
      !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, controller.documentOpening.generation == opening,
      !controller.recoveryIndex.isBusy, controller.recoveryMaintenance.generation == maintenance, controller.recoveryDiscovery.generation == discovery else {
      throw AutomationFailure(status: 409, message: "Duplicate Image cancelled or sharing/lifecycle changed.")
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
