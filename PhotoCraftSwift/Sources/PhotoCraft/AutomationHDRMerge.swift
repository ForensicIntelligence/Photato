import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension HDRMergeSettings {
  static let numericBounds: [String:(Double,Double)] = ["radius":(1,500),"strength":(0.1,4),"gamma":(0.1,4),"exposure":(-5,5),"detail":(-100,300),"shadows":(-100,100),"highlights":(-100,100),"vibrance":(-100,100),"saturation":(-100,100)]
  static var apiSchema: [String:Any] {
    var p: [String:Any] = [
      "exposureSource":["type":"string","enum":ExposureSource.allCases.map(\.rawValue),"default":"metadata"],
      "exposureEV":["type":"array","minItems":2,"maxItems":16,"items":["type":"number","minimum":-20,"maximum":20]],
      "align":["type":"boolean","default":true],"removeGhosts":["type":"boolean","default":false],
      "ghostBase":["type":"integer","minimum":0,"maximum":15],
      "depth":["type":"string","enum":PixelDepth.allCases.map(\.rawValue),"default":"32 bit"],
      "method":["type":"string","enum":Method.allCases.map(\.rawValue),"default":"localAdaptation"]]
    for (key,(lo,hi)) in numericBounds { p[key] = ["type":"number","minimum":lo,"maximum":hi] }
    return ["type":"object","additionalProperties":false,"properties":p]
  }
  static var apiCapabilities: [String:Any] {
    ["command":"document.hdrMerge","cancelCommand":"document.hdrMerge.cancel","settingsSchema":apiSchema,"sourcesSchema":PhotomergeSettings.sourcesSchema,
     "result":"HTTP201 shared unsaved document plus hdrMergeResult: exposureEV[number], exposureSource(metadata/manual/estimate), offsets[[x,y]], ghostBase zero-based index, ghostFraction0…1, stops, responseCurve[3][256], sourceCount. Sources/history stay unchanged; new-document edits use normal Undo and persistence.",
     "permission":"Document transfers enabled; two to7 explicitly shared id/revision sources, including the command target, leaving one output slot. No arbitrary local paths. Revocation, stale input, closing/recovery or cancellation publishes nothing.",
     "behavior":"Opaque equal-sized exposure brackets convert to sRGB. Manual EV, complete EXIF time/aperture/ISO, or explicit image estimation. Ward translation alignment, camera-response recovery, radiance merge, optional ghost-base removal;32-bit linear HDR or four16/8-bit tone mappings. Full output retains32-bit range. Native preview exposure does not change output.",
     "limits":"Native2–16 sources,16MP per source/32MP combined; API also4MP canvas/8,000layers/128MiB. Developed camera/display-range sources; extended-range HDR inputs and transparency reject. Output uses sRGB primaries; converted out-of-gamut input colors clamp to camera range. No Photoshop proprietary pixel/default equivalence.",
     "adobe":"No dedicated HDR merge route in the pinned published Photoshop v2 contract and no authenticated HDR descriptor implemented. This orchestration is Photato-specific; existing Adobe endpoints remain unchanged."]
  }
}
extension AutomationCommand {
  struct HDRMergeOptions: Sendable { var sources: [(UUID,String)];var settings: HDRMergeSettings;var name: String }
  func hdrMergeOptions() throws -> HDRMergeOptions {
    guard case .array(let raw) = parameters["sources"],(2...7).contains(raw.count) else { throw AutomationFailure(status:400,message:"Provide two to seven shared source documents.") }
    let sources = try raw.map { item -> (UUID,String) in
      guard case .object(let fields) = item,Set(fields.keys) == ["id","revision"],case .string(let text) = fields["id"],let id = UUID(uuidString:text),case .string(let revision) = fields["revision"],!revision.isEmpty,revision.count <= 256 else { throw AutomationFailure(status:400,message:"Each source requires a shared document id and current revision.") };return (id,revision)
    }
    guard Set(sources.map(\.0)).count == sources.count else { throw AutomationFailure(status:400,message:"Duplicate source documents are not allowed.") }
    var s = HDRMergeSettings()
    if let raw = parameters["settings"] {
      let allowed = Set(HDRMergeSettings.numericBounds.keys).union(["exposureSource","exposureEV","align","removeGhosts","ghostBase","depth","method"])
      guard case .object(let fields) = raw,Set(fields.keys).isSubset(of:allowed) else { throw AutomationFailure(status:400,message:"Unknown HDR merge settings.") }
      for (key,value) in fields {
        if let (lo,hi) = HDRMergeSettings.numericBounds[key] {
          guard case .number(let n) = value,n.isFinite,(Double(lo)...Double(hi)).contains(n) else { throw AutomationFailure(status:400,message:"Invalid HDR setting: \(key).") }
          switch key { case "radius":s.radius = Float(n);case "strength":s.strength = Float(n);case "gamma":s.gamma = Float(n);case "exposure":s.exposure = Float(n);case "detail":s.detail = Float(n);case "shadows":s.shadows = Float(n);case "highlights":s.highlights = Float(n);case "vibrance":s.vibrance = Float(n);default:s.saturation = Float(n) };continue
        }
        switch (key,value) {
        case ("exposureSource",.string(let v)) where HDRMergeSettings.ExposureSource(rawValue:v) != nil:s.exposureSource = .init(rawValue:v)!
        case ("depth",.string(let v)) where PixelDepth(rawValue:v) != nil:s.depth = .init(rawValue:v)!
        case ("method",.string(let v)) where HDRMergeSettings.Method(rawValue:v) != nil:s.method = .init(rawValue:v)!
        case ("align",.bool(let v)):s.align = v
        case ("removeGhosts",.bool(let v)):s.removeGhosts = v
        case ("ghostBase",.number(let n)) where n.isFinite && n.rounded() == n && (0...15).contains(n):s.ghostBase = Int(n)
        case ("exposureEV",.array(let values)) where (2...16).contains(values.count):
          s.exposureEV = try values.map { value in guard case .number(let n) = value,n.isFinite,(-20...20).contains(n) else { throw AutomationFailure(status:400,message:"Each manual EV must be between−20 and20.") };return n }
        default:throw AutomationFailure(status:400,message:"Invalid HDR setting: \(key).")
        }
      }
    }
    do { try s.validate(count:sources.count) } catch { throw AutomationFailure(status:400,message:error.localizedDescription) }
    return .init(sources:sources,settings:s,name:try parameters["name"] == nil ? "Untitled HDR":string("name"))
  }
}
extension AutomationService {
  func executeHDRMerge(_ command: AutomationCommand,anchorID: UUID) async throws -> AutomationResponse {
    let options = try command.hdrMergeOptions()
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document uploads and downloads in the native API window before creating a HDR image.") }
    guard !documentTransferBusy,controller.hdrMergeWorkspace == nil,controller.canPublishHDRMerge else { throw AutomationFailure(status:409,message:"Finish the current document transfer or HDR merge operation.") }
    guard options.sources.contains(where:{$0.0 == anchorID}) else { throw AutomationFailure(status:400,message:"Include the command target in the HDR image sources.") }
    guard shares.count < 8 else { throw AutomationFailure(status:429,message:"Leave one sharing slot available for the new HDR image.") }
    let documents = try options.sources.map { id,revision -> CraftNSDocument in
      guard let document = shares.first(where:{$0.id == id})?.document else { throw AutomationFailure(status:404,message:"A shared source document was not found.") }
      try preflight(document);guard self.revision(document.store) == revision else { throw AutomationFailure(status:409,message:"A source revision is stale.") };return document
    }
    let snapshots = documents.map{$0.store.document},storeGenerations = documents.map{$0.store.layerPanelGeneration}
    let expectedToken = token,transferGeneration = documentTransferGeneration,serviceGeneration = generation
    let openGeneration = controller.documentOpening.generation,closeID = controller.documentClosing.state?.id,maintenance = controller.recoveryMaintenance.generation,discovery = controller.recoveryDiscovery.generation
    let operationID = UUID();hdrMergeOperationID = operationID;hdrMergeSourceIDs = Set(options.sources.map(\.0))
    documentTransferBusy = true
    for document in documents { document.store.geometryBusy = true;document.store.renderTask?.cancel() }
    let worker = Task.detached(priority:.userInitiated) { try HDRMerge.prepare(snapshots,settings:options.settings,name:options.name) }
    hdrMergeTask = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    for document in documents { document.store.geometryTask = observer }
    defer {
      if hdrMergeOperationID == operationID { hdrMergeTask = nil;hdrMergeOperationID = nil;hdrMergeSourceIDs = [] }
      documentTransferBusy = false
      for (i,document) in documents.enumerated() where document.store.layerPanelGeneration == storeGenerations[i] {
        document.store.geometryBusy = false;document.store.geometryTask = nil;document.store.render()
      }
    }
    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation();guard !observer.isCancelled else { throw CancellationError() }
    prune()
    guard isRunning,token == expectedToken,generation == serviceGeneration,documentTransfersEnabled,documentTransferGeneration == transferGeneration,controller.hdrMergeWorkspace == nil,controller.canPublishHDRMerge,controller.documentOpening.generation == openGeneration,controller.documentClosing.state?.id == closeID,controller.recoveryMaintenance.generation == maintenance,controller.recoveryDiscovery.generation == discovery else { throw AutomationFailure(status:409,message:"HDR image creation was cancelled, revoked or interrupted by a document operation.") }
    for (i,document) in documents.enumerated() {
      guard shares.contains(where:{$0.id == options.sources[i].0 && $0.document === document}),revision(document.store) == options.sources[i].1,document.store.document == snapshots[i],document.store.layerPanelGeneration == storeGenerations[i] else { throw AutomationFailure(status:409,message:"A HDR image source changed or sharing ended.") }
    }
    try Self.checkLimits(result.document);guard shares.count < 8 else { throw AutomationFailure(status:429,message:"Document sharing capacity changed during HDR merge.") }
    let created = CraftNSDocument(model:result.document);controller.addDocument(created)
    do { try share(created) } catch { controller.removeDocument(created);throw error }
    created.updateChangeCount(.changeDone);created.makeWindowControllers();created.showWindows()
    guard let shared = shares.first(where:{$0.document === created}) else { throw AutomationFailure(status:409,message:"HDR image sharing ended.") }
    var output = state(shared,document:created)
    output["hdrMergeResult"] = ["exposureEV":result.exposureEV,"exposureSource":result.exposureSource.rawValue,"offsets":result.offsets,"ghostBase":result.ghostBase,"ghostFraction":result.ghostFraction,"stops":result.stops,"responseCurve":result.response,"sourceCount":snapshots.count]
    return .json(output,status:201)
  }
}
