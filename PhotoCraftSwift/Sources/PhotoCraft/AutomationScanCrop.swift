import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ScanCropAPI {
  static let commands: Set<String> = ["document.cropStraighten","document.cropStraighten.detect","document.cropStraighten.cancel"]
  struct Prepared: Sendable {let analysis: ScanCrop.Analysis;let result: ScanCrop.Result?}
  static func schema(_ key: String) -> [String:Any] {
    key == "forceSingle" ? ["type":"boolean","default":false]:["type":"string","format":"uuid"]
  }
  static var capabilities: [String:Any] {
    ["command":"document.cropStraighten","detectCommand":"document.cropStraighten.detect","cancelCommand":"document.cropStraighten.cancel",
     "parameters":"Optional layerID (default active) and forceSingle (default false; native Option modifier). Current document selection limits detection. Still RGB/Grayscale/CMYK/Lab layers/groups; no artboards/frames.",
     "result":"Detection HTTP200: photos (centerX/centerY/width/height/angle in document pixels/degrees/area), layerID, region, preservesNativeComponents. Empty detection returns photos[]. Creation HTTP201 adds documents (shared states) and count; every photo publishes together. Source pixels/history/selection are unchanged.",
     "limits":"8MP source and each photo,64 detections,32MP combined outputs,512MiB. Creation requires document transfers and one available share slot per output (8 total), plus4MP/64layers/128MiB per shared document. Detection requires existing explicit source sharing only.",
     "fidelity":"Ordinary native-mode raster scans retain numerical components; complex non-RGB layer composition uses existing RGB cache/reseparation and reports preservesNativeComponents=false. Licensed-source detection/bicubic sampling are not yet qualified against Photoshop. New photos retain depth/profile/resolution and use a locked-position/transparency Background layer.",
     "adobe":"No dedicated multi-photo extraction endpoint exists in the pinned contract. Published auto-crop handles a different single-document operation. Execute-actions descriptors and Photoshop exact output remain unqualified; no route is invented."]
  }
}
extension AutomationCommand {
  func scanCropOptions() throws -> (layerID: UUID?,forceSingle: Bool) {
    let id: UUID?
    if parameters["layerID"] != nil {id = try actionUUID("layerID")} else {id = nil}
    var single = false
    if let value = parameters["forceSingle"] {guard case .bool(let enabled) = value else {throw AutomationFailure(status:400,message:"forceSingle must be boolean.")};single = enabled}
    return (id,single)
  }
}
extension AutomationService {
  func executeScanCrop(_ command: AutomationCommand,document: CraftNSDocument,shareID: UUID) async throws -> AutomationResponse {
    let options = try command.scanCropOptions(),detectOnly = command.name == "document.cropStraighten.detect"
    if !detectOnly && !documentTransfersEnabled {throw AutomationFailure(status:403,message:"Enable document uploads and downloads before creating extracted photos.")}
    guard !documentTransferBusy,controller.scanCropOperationID == nil,controller.canPublishScanCrop else {throw AutomationFailure(status:409,message:"Finish the current document operation before extracting photos.")}
    let store = document.store,snapshot = store.document,storeGeneration = store.layerPanelGeneration
    let expectedToken = token,transferGeneration = documentTransferGeneration,serviceGeneration = generation
    let openGeneration = controller.documentOpening.generation,closeID = controller.documentClosing.state?.id,maintenance = controller.recoveryMaintenance.generation,discovery = controller.recoveryDiscovery.generation
    let oldStatus = store.status;store.status = detectOnly ? "Detecting scanned photos…":"Crop and Straighten Photos…"
    let operation = UUID();scanCropOperationID = operation;scanCropSourceID = shareID;controller.scanCropOperationID = operation
    documentTransferBusy = true;store.geometryBusy = true;store.renderTask?.cancel()
    let worker = Task.detached(priority:.userInitiated) {
      let analysis = try ScanCrop.analyze(snapshot,layerID:options.layerID,forceSingle:options.forceSingle)
      return ScanCropAPI.Prepared(analysis:analysis,result:detectOnly ? nil:try ScanCrop.extract(analysis,from:snapshot))
    }
    scanCropTask = worker
    let observer = Task {await withTaskCancellationHandler {_ = try? await worker.value} onCancel:{worker.cancel()}}
    store.geometryTask = observer
    defer {
      if scanCropOperationID == operation {scanCropTask = nil;scanCropOperationID = nil;scanCropSourceID = nil}
      if controller.scanCropOperationID == operation {controller.scanCropOperationID = nil}
      documentTransferBusy = false
      if store.layerPanelGeneration == storeGeneration {store.geometryBusy = false;store.geometryTask = nil;store.status = oldStatus;store.render()}
    }
    let prepared = try await withTaskCancellationHandler {try await worker.value} onCancel:{worker.cancel()}
    try Task.checkCancellation();guard !observer.isCancelled else {throw CancellationError()}
    prune()
    guard isRunning,token == expectedToken,generation == serviceGeneration,detectOnly || (documentTransfersEnabled && documentTransferGeneration == transferGeneration),controller.scanCropOperationID == operation,controller.canPublishScanCrop,controller.documentOpening.generation == openGeneration,controller.documentClosing.state?.id == closeID,controller.recoveryMaintenance.generation == maintenance,controller.recoveryDiscovery.generation == discovery,shares.contains(where:{$0.id == shareID && $0.document === document}),revision(store) == command.revision,store.document == snapshot,store.layerPanelGeneration == storeGeneration,document.closeWorkflowID == nil,!document.fileOperationBusy else {throw AutomationFailure(status:409,message:"The scan changed, sharing ended, or a document operation interrupted extraction.")}
    var response: [String:Any] = ["photos":try JSONSerialization.jsonObject(with:JSONEncoder().encode(prepared.analysis.photos)),"layerID":prepared.analysis.layerID.uuidString,"region":try JSONSerialization.jsonObject(with:JSONEncoder().encode(prepared.analysis.region)),"preservesNativeComponents":prepared.analysis.preservesNativeComponents]
    guard let result = prepared.result else {return .json(response)}
    guard shares.count+result.documents.count <= 8 else {throw AutomationFailure(status:429,message:"Leave one sharing slot available for every detected photo, or select fewer photos.")}
    for item in result.documents {try Self.checkLimits(item)}
    let created = result.documents.map{CraftNSDocument(model:$0)}
    do {for item in created {controller.addDocument(item);try share(item)}} catch {
      for item in created {for id in shares.filter({$0.document === item}).map(\.id) {revoke(id)};controller.removeDocument(item)};throw error
    }
    for item in created {item.updateChangeCount(.changeDone);item.makeWindowControllers();item.showWindows()}
    response["documents"] = try created.map {item -> [String:Any] in
      guard let share = shares.first(where:{$0.document === item}) else {throw AutomationFailure(status:409,message:"Extracted photo sharing ended.")};return state(share,document:item)
    }
    response["count"] = created.count;return .json(response,status:201)
  }
}
