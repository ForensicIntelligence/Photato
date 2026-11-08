import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension AutomationService {
  /// Same prepared native transaction as the desktop, with API revocation guards.
  func executeMerge(
    _ command: Command, document: CraftNSDocument, shareID: UUID, revision expected: String
  ) async throws {
    if case .mergeLayers=command,document.store.smartFilterMaskEditing {throw AutomationFailure(status:422,message:"Merge requires the composite layer target.")}
    let store=document.store,prepare=store.layerMergePreparation
    let maskTarget=store.selectedMaskPaintTarget
    let selectedFilterMaskEdit:Bool
    if case .smartFilterMask(let owner,_)=command {
      selectedFilterMaskEdit=maskTarget == MaskPaintTarget(layerID:owner,smartFilter:true)
    } else if case .applyFilter=command,maskTarget != nil {
      selectedFilterMaskEdit=true
    } else if case .maskFilter=command {
      guard !store.editingComponent else {throw AutomationFailure(status:422,message:"Leave component editing before filtering a mask.")}
      selectedFilterMaskEdit=true
    } else {selectedFilterMaskEdit=false}
    try await executePreparedOperation(document: document, shareID: shareID, revision: expected,
      allowAuxiliary:selectedFilterMaskEdit,validateCommit:{
        if selectedFilterMaskEdit,store.selectedMaskPaintTarget != maskTarget {
          throw AutomationFailure(status:409,message:"The Filter Mask editing target changed.")
        }
      }) { source in
      if case .mergeLayers(let ids,let operation)=command {return try prepare(source,ids,operation)}
      return command
    }
  }
  func executePreparedOperation(document: CraftNSDocument, shareID: UUID, revision expected: String,
    allowFitImage:Bool = false,allowPixelMaskTransform:Bool = false,allowSelection:Bool = false,allowPixelPaint:Bool = false, allowAuxiliary: Bool = false, allowPathTarget: Bool = false, allowModeComponents: Bool = false, allowColorProfile: Bool = false, allowLinkedSmartObject: Bool = false,
    validateCommit: @escaping @MainActor () throws -> Void = {},
    prepare: @escaping @Sendable (CraftDocument) async throws -> Command) async throws {
    _ = try await executePreparedResult(document: document, shareID: shareID, revision: expected,
      allowFitImage:allowFitImage,allowPixelMaskTransform:allowPixelMaskTransform,allowSelection:allowSelection,allowPixelPaint:allowPixelPaint,allowAuxiliary: allowAuxiliary, allowPathTarget: allowPathTarget, allowModeComponents: allowModeComponents, allowColorProfile: allowColorProfile, allowLinkedSmartObject: allowLinkedSmartObject,
      validateCommit: validateCommit) { source in (try await prepare(source), true) }
  }
  /// Return bounded worker output only after the matching document transaction commits.
  func executePreparedResult<Output: Sendable>(document: CraftNSDocument, shareID: UUID, revision expected: String,
    allowFitImage:Bool = false,allowPixelMaskTransform:Bool = false,allowSelection:Bool = false,allowPixelPaint:Bool = false, allowAuxiliary: Bool = false, allowPathTarget: Bool = false, allowModeComponents: Bool = false, allowColorProfile: Bool = false, allowLinkedSmartObject: Bool = false,
    validatePreparedOutput: @escaping @Sendable (Output) throws -> Void = {_ in},
    validateCommit: @escaping @MainActor () throws -> Void = {},
    prepare: @escaping @Sendable (CraftDocument) async throws -> (Command, Output)) async throws -> Output {
    let store = document.store
    if allowColorProfile, !store.canBeginColorProfile {
      throw AutomationFailure(status: 422, message: "This operation requires the composite color-profile target.")
    }
    let pathContext = allowPathTarget && !store.editingComponent && !store.editingMask && !store.smartFilterMaskEditing && !store.geometryBusy && !store.hasToneDraft && store.transformDraft == nil
    guard (allowFitImage && store.canBeginFitImage) || (allowPixelPaint && store.canUsePixelPaint) || (allowPixelMaskTransform && store.canBeginPixelMaskTransform) || allowSelection || (allowLinkedSmartObject && store.canManageLinkedArtwork) || (allowModeComponents && store.canEditModeComponents) || (allowColorProfile && store.canBeginColorProfile) || pathContext || store.clipboardTargetAvailable || (allowAuxiliary && store.canEditChannels) else {
      throw AutomationFailure(status: 422, message: "This operation requires the RGB layer target.")
    }
    let paintMaskTarget=allowAuxiliary ? store.selectedMaskPaintTarget:nil
    let paintTarget=allowPixelPaint ? store.nativePixelPaintTarget:nil
    let maskTarget=allowPixelMaskTransform ? store.maskEditingLayerID:nil
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
      if allowColorProfile { guard case .preparedColorProfile = command else { throw CraftError.invalid("Expected a prepared profile assignment or conversion.") } }
      if allowPixelMaskTransform{guard case .transformPixelMask(let request)=command,request.layerID==maskTarget else{throw CraftError.invalid("Expected a pixel-mask transform command.")}}
      if allowPixelPaint{guard case .pixelPaint(let request)=command,request.target==paintTarget else{throw CraftError.invalid("Expected the captured pixel-paint target.")}}
      let prepared=try PreparedEdit(command: command, document: original)
      guard !allowFitImage || prepared.isFitImageEdit else {throw CraftError.invalid("This transaction requires a whole-document Fit Image command.")}
      guard !allowSelection || prepared.isSelectionOnly else {throw CraftError.invalid("This transaction requires a selection-only edit.")}
      try validatePreparedOutput(output)
      return (prepared, command, output)
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
      revision(store) == expected, store.layerPanelGeneration == generation, store.document == original
    else {
      throw AutomationFailure(
        status: 409, message: "The operation was cancelled, changed or sharing was revoked.")
    }
    if allowPixelMaskTransform{guard store.editingMask,!store.smartFilterMaskEditing,store.maskEditingLayerID==maskTarget else{throw AutomationFailure(status:409,message:"The mask editing target changed.")}}
    if allowPixelPaint{guard store.nativePixelPaintTarget==paintTarget else{throw AutomationFailure(status:409,message:"The paint target changed.")}}
    try validateCommit()
    var candidate = store.session
    try candidate.executePrepared(prepared)
    try Self.checkLimits(candidate.document)
    try store.executeCompositePreparedEdit(prepared,allowAuxiliary:allowAuxiliary,allowModeComponents:allowModeComponents,allowLinkedSmartObject:allowLinkedSmartObject)
    switch command {
    case .photoAlign(let edit): store.selectedLayerIDs = edit.selectedLayerIDs
    case .photoBlend(let edit): store.selectedLayerIDs = edit.selectedLayerIDs
    case .preparedAction, .preparedDocumentMode, .toneAdjustment, .hdrToning, .proceduralRender, .maskAllObjects, .focusArea, .skyReplacement, .frame, .artboard, .contentAwareFill, .selectionRefinement, .mergeLayers, .preparedLayerMerge, .embedSmartObject, .independentSmartObjectCopy, .addLayer:
      store.selectedLayerIDs = Set(store.document.activeLayerID.map { [$0] } ?? [])
    default: break
    }
    if !allowPixelPaint && !allowPixelMaskTransform && !allowLinkedSmartObject && !allowSelection {store.maskEditingLayerID = nil}
    if allowAuxiliary {store.restoreMaskPaintTarget(paintMaskTarget)}
    if store.document != original { store.onChange?(.changeDone) }
    store.status = command.label
    return output
  }
}
