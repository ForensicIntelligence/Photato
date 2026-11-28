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
    guard let localDNGSource, localDNGSource.layerID == layerID,
      importedSourceURL == localDNGSource.original.url.standardizedFileURL.resolvingSymlinksInPath(),
      let object = store.document.layers.first(where: { $0.id == layerID })?.smartObject,
      object.rawDevelopment != nil else { return false }
    return object.data == localDNGSource.retainedBytes
  }

  func saveRawSourceSettings(layerID: UUID, settings: RawDevelopment, authorizedFolder: URL? = nil) async throws {
    guard !fileOperationBusy, closeWorkflowID == nil, !recoveryWriteBusy,
      let localDNGSource, canSaveRawSourceSettings(layerID: layerID)
    else { throw CraftError.invalid("Choose the original DNG layer of an open local RAW document.") }
    try Task.checkCancellation()
    fileOperationBusy = true
    let worker = Task.detached(priority: .userInitiated) {
      try localDNGSource.original.save(settings: settings, authorizedFolder: authorizedFolder)
    }
    dngSaveTask = worker
    defer {
      fileOperationBusy = false
      dngSaveTask = nil
    }
    let updated = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    self.localDNGSource = (layerID, updated, localDNGSource.retainedBytes)
  }
}
