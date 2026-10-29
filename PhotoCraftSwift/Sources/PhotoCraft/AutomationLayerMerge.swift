import AppKit
import PhotoCraftCore

extension AutomationService {
  /// Same prepared native transaction as the desktop, with API revocation guards.
  func executeMerge(
    _ command: Command, document: CraftNSDocument, shareID: UUID, revision expected: String
  ) async throws {
    try await executePreparedOperation(document: document, shareID: shareID, revision: expected) { _ in command }
  }
  func executePreparedOperation(document: CraftNSDocument, shareID: UUID, revision expected: String,
    allowAuxiliary: Bool = false, allowPathTarget: Bool = false, allowModeComponents: Bool = false,
    validateCommit: @escaping @MainActor () throws -> Void = {},
    prepare: @escaping @Sendable (CraftDocument) async throws -> Command) async throws {
    _ = try await executePreparedResult(document: document, shareID: shareID, revision: expected,
      allowAuxiliary: allowAuxiliary, allowPathTarget: allowPathTarget, allowModeComponents: allowModeComponents,
      validateCommit: validateCommit) { source in (try await prepare(source), true) }
  }
  /// Return bounded worker output only after the matching document transaction commits.
  func executePreparedResult<Output: Sendable>(document: CraftNSDocument, shareID: UUID, revision expected: String,
    allowAuxiliary: Bool = false, allowPathTarget: Bool = false, allowModeComponents: Bool = false,
    validateCommit: @escaping @MainActor () throws -> Void = {},
    prepare: @escaping @Sendable (CraftDocument) async throws -> (Command, Output)) async throws -> Output {
    let store = document.store
    let pathContext = allowPathTarget && !store.editingComponent && !store.editingMask && !store.smartFilterMaskEditing && !store.geometryBusy && !store.hasToneDraft && store.transformDraft == nil
    guard (allowModeComponents && store.canEditModeComponents) || pathContext || store.clipboardTargetAvailable || (allowAuxiliary && store.canEditChannels && store.isCompositeColorTarget) else {
      throw AutomationFailure(status: 422, message: "This operation requires the RGB layer target.")
    }
    let original = store.document
    let expectedToken = token
    let generation = store.layerPanelGeneration
    store.geometryBusy = true
    store.renderTask?.cancel()
    defer {
      if store.layerPanelGeneration == generation {
        store.geometryBusy = false
        store.geometryTask = nil
        store.render()
      }
    }
    let worker = Task.detached(priority: .userInitiated) {
      let (command, output) = try await prepare(original)
      return (try PreparedEdit(command: command, document: original), command, output)
    }
    store.geometryTask = Task {
      await withTaskCancellationHandler(operation: { _ = try? await worker.value }, onCancel: { worker.cancel() })
    }
    let (prepared, command, output) = try await withTaskCancellationHandler(
      operation: { try await worker.value }, onCancel: { worker.cancel() })
    try Task.checkCancellation()
    if store.geometryTask?.isCancelled == true { throw CancellationError() }
    prune()
    guard isRunning, token == expectedToken, shares.contains(where: { $0.id == shareID }),
      revision(store) == expected, store.layerPanelGeneration == generation
    else {
      throw AutomationFailure(
        status: 409, message: "The operation was cancelled, changed or sharing was revoked.")
    }
    try validateCommit()
    var candidate = store.session
    try candidate.executePrepared(prepared)
    try Self.checkLimits(candidate.document)
    try store.executeCompositePreparedEdit(prepared,allowAuxiliary:allowAuxiliary,allowModeComponents:allowModeComponents)
    switch command {
    case .photoAlign(let edit): store.selectedLayerIDs = edit.selectedLayerIDs
    case .photoBlend(let edit): store.selectedLayerIDs = edit.selectedLayerIDs
    case .preparedAction, .preparedDocumentMode, .toneAdjustment, .hdrToning, .proceduralRender, .maskAllObjects, .focusArea, .skyReplacement, .frame, .artboard, .contentAwareFill, .selectionRefinement, .mergeLayers, .embedSmartObject, .independentSmartObjectCopy, .addLayer:
      store.selectedLayerIDs = Set(store.document.activeLayerID.map { [$0] } ?? [])
    default: break
    }
    store.maskEditingLayerID = nil
    if store.document != original { store.onChange?(.changeDone) }
    store.status = command.label
    return output
  }
}
