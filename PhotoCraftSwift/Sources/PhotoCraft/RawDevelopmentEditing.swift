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
