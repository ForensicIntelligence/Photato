import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension EditorStore {
  var canDevelopRaw: Bool { canEditSmartObject && activeLayer?.smartObject?.rawDevelopment != nil }
  func beginRawDevelopment() {
    guard canDevelopRaw,let layer = activeLayer,let settings = layer.smartObject?.rawDevelopment else { return }
    var filter = RasterFilter(.cameraRaw); filter.cameraRaw = settings.adjustments
    filterDraft = FilterDraft(id:layer.id,filter:filter,rawDevelopment:settings)
  }
}

extension CraftNSDocument {
  /// Finish the initial import as a new editor baseline. The seeded sensor
  /// layer was a preview source and must never become an Undo state.
  func finishRawOpen(_ mode: RawOpenMode, from preview: CraftDocument, layerID: UUID,
    workflow: RawWorkflowOutput = .init(), authorizedFolder: URL? = nil) async throws {
    guard store.initialRawDocument === self, store.filterDraft?.id == layerID,
      preview.id == store.document.id, preview.layers.first?.id == layerID,
      fileURL == nil, !fileOperationBusy, !store.geometryBusy,
      closeWorkflowID == nil, !recoveryWriteBusy else {
      throw CraftError.invalid("The Camera Raw opening session changed. Open the file again.")
    }
    let generation = store.sessionGeneration
    let panelGeneration = store.layerPanelGeneration
    let worker = Task.detached(priority: .userInitiated) {
      try mode.output(from: preview, workflow: workflow)
    }
    let output = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try validateRawOpening(layerID, generation: generation, panelGeneration: panelGeneration)
    if mode.savesSourceSettings, localRawSource != nil,
      let settings = preview.layers.first?.smartObject?.rawDevelopment {
      try await saveRawSourceSettings(layerID: layerID, settings: settings, authorizedFolder: authorizedFolder)
    }
    try validateRawOpening(layerID, generation: generation, panelGeneration: panelGeneration)
    completedRawOpenMode = mode
    completedRawWorkflow = workflow
    store.initialRawDocument = nil
    store.filterDraft = nil
    if mode != .object { localRawSource = nil }
    store.session = EditorSession(document: output)
    if let fileName = preview.layers.first?.smartObject?.fileName {
      displayName = mode == .object ? "\(preview.name)-1" : fileName
    }
    updateChangeCount(.changeDone)
    store.render()
    ownerController?.scriptEventsDispatcher.enqueue(.openDocument, document: self)
  }

  private func validateRawOpening(_ layerID: UUID, generation: UUID, panelGeneration: UUID) throws {
    try Task.checkCancellation()
    guard store.initialRawDocument === self, store.filterDraft?.id == layerID,
      store.sessionGeneration == generation, store.layerPanelGeneration == panelGeneration,
      fileURL == nil, !fileOperationBusy, !store.geometryBusy, closeWorkflowID == nil, !recoveryWriteBusy else {
      throw CraftError.invalid("The Camera Raw opening session changed. Open the file again.")
    }
  }

  func canSaveRawSourceSettings(layerID: UUID) -> Bool {
    guard let localRawSource, localRawSource.layerID == layerID,
      importedSourceURL == localRawSource.original.url.standardizedFileURL.resolvingSymlinksInPath(),
      let object = store.document.layers.first(where: { $0.id == layerID })?.smartObject,
      object.rawDevelopment != nil else { return false }
    return object.data == localRawSource.retainedBytes
  }

  func saveRawSourceSettings(layerID: UUID, settings: RawDevelopment, authorizedFolder: URL? = nil) async throws {
    guard !fileOperationBusy, closeWorkflowID == nil, !recoveryWriteBusy,
      let localRawSource, canSaveRawSourceSettings(layerID: layerID)
    else { throw CraftError.invalid("Choose the original layer of a locally opened Camera Raw document.") }
    try Task.checkCancellation()
    fileOperationBusy = true
    let worker = Task.detached(priority: .userInitiated) {
      try localRawSource.original.save(settings: settings, authorizedFolder: authorizedFolder)
    }
    rawSettingsSaveTask = worker
    defer {
      fileOperationBusy = false
      rawSettingsSaveTask = nil
    }
    let updated = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    self.localRawSource = (layerID, updated, localRawSource.retainedBytes)
  }
}
