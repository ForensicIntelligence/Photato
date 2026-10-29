import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension CraftDocumentController {
  var canPublishScanCrop: Bool {
    contactSheetWorkspace == nil && imageStackWorkspace == nil && photomergeWorkspace == nil && hdrMergeWorkspace == nil && !documentOpening.isActive && !documentOpening.hasPendingRequests && documentOpenPanel == nil && !documentClosing.isActive && !recoveryIndex.isBusy && initialRecoveryTask == nil && NSApp?.modalWindow == nil
  }
  func canCropScan(_ document: CraftNSDocument) -> Bool {
    guard let layer = document.store.activeLayer else {return false}
    if case .adjustment = layer.content {return false}
    let model = document.store.document
    return canPublishScanCrop && scanCropOperationID == nil && ContactSheetWorkspace.readable(document) && DocumentColorMode.componentModes.contains(model.colorMode) && model.animation == nil && model.videoTimeline == nil && !model.hasArtboards && !model.hasFrames
  }
  @discardableResult func cropAndStraighten(_ document: CraftNSDocument,forceSingle: Bool = false,display: Bool = true) async throws -> [CraftNSDocument] {
    guard canCropScan(document),documents.contains(where:{$0 === document}) else {throw CraftError.invalid("Finish the current document operation before extracting photos.")}
    let store = document.store,snapshot = store.document,storeGeneration = store.layerPanelGeneration
    let openGeneration = documentOpening.generation,closeID = documentClosing.state?.id,maintenance = recoveryMaintenance.generation,discovery = recoveryDiscovery.generation
    let oldStatus = store.status;store.status = "Crop and Straighten Photos…"
    let operation = UUID();scanCropOperationID = operation
    store.geometryBusy = true;store.renderTask?.cancel()
    let worker = Task.detached(priority:.userInitiated) {try ScanCrop.prepare(snapshot,forceSingle:forceSingle)}
    let observer = Task {await withTaskCancellationHandler {_ = try? await worker.value} onCancel:{worker.cancel()}}
    store.geometryTask = observer
    defer {
      if scanCropOperationID == operation {scanCropOperationID = nil}
      if store.layerPanelGeneration == storeGeneration {store.geometryBusy = false;store.geometryTask = nil;store.status = oldStatus;store.render()}
    }
    let result = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
    try Task.checkCancellation();guard !observer.isCancelled else {throw CancellationError()}
    guard scanCropOperationID == operation,canPublishScanCrop,documents.contains(where:{$0 === document}),store.document == snapshot,store.layerPanelGeneration == storeGeneration,document.closeWorkflowID == nil,!document.fileOperationBusy,documentOpening.generation == openGeneration,documentClosing.state?.id == closeID,recoveryMaintenance.generation == maintenance,recoveryDiscovery.generation == discovery else {throw CraftError.invalid("The scan or document state changed. Run Crop and Straighten Photos again.")}
    let created = result.documents.map{CraftNSDocument(model:$0)}
    for item in created {addDocument(item);item.updateChangeCount(.changeDone)}
    if display {for item in created {item.makeWindowControllers();item.showWindows()}}
    return created
  }
}
extension AppDelegate {
  @objc func cropAndStraightenPhotos() {
    guard let document = controller.currentDocument as? CraftNSDocument else {return}
    let single = NSApp.currentEvent?.modifierFlags.contains(.option) == true
    Task {do {try await controller.cropAndStraighten(document,forceSingle:single)} catch is CancellationError {} catch {document.store.error = error.localizedDescription}}
  }
}
