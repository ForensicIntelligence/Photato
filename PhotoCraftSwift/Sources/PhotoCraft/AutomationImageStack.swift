import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension ImageStackSettings {
  static var modeSchema: [String:Any] { ["type":"string","enum":["none"]+ImageStackMode.allCases.map(\.rawValue)] }
  static var apiSchema: [String:Any] { ["type":"object","additionalProperties":false,"properties":["align":["type":"boolean","default":false],"createSmartObject":["type":"boolean","default":false],"mode":modeSchema]] }
  static var apiCapabilities: [String:Any] {
    ["command":"document.imageStack","cancelCommand":"document.imageStack.cancel","editCommand":"smartObject.stackMode","settingsSchema":apiSchema,"sourcesSchema":PhotomergeSettings.sourcesSchema,
     "behavior":"Load files/open sources as editable photo layers, optionally align and convert to a statistical Smart Object. Modes are per instance and survive source replacement. None restores ordinary compositing. Mode changes and source edits use one Undo step.",
     "result":"HTTP201 shared unsaved document plus imageStackResult(sourceCount,aligned,mode,smartObject). Source documents/history stay unchanged.",
     "limits":"Two to the existing document layer limit for native sources; two to7 explicitly shared API sources, including target. Document transfers enabled, one output slot. Paged RGB stacks follow native logical canvas dimensions and document layer limits. Automatic alignment retains16sources/its pixel budgets; non-RGB SmartObject admission8MP, owned256MiB, nesting, encoded64MiB, sharing/composition/scratch budgets remain. First input depth/profile; transparent samples ignored, alpha max; finite32-bit summation preserves HDR range.",
     "capacity":["maximumDimension":Surface.maxDimension,"maximumDocumentPixels":ImageStack.maximumDocumentPixels,"maximumNativeSources":ImageStack.maximumSources,"maximumSampleFrames":ImageStack.maximumSources,"maximumAPISources":7,"legacyDirectSamplePixels":ImageStack.maximumTotalPixels,"behavior":"Unchanged eleven scalar operators; sparse/paged sample-support preparation/output. No new statistical formula, opacity weighting or working-image resampling. Existing masks, visible-root/group semantics, editing/history/source retention and API descriptors remain. Dense maximum capacity/60fps/Photoshop pixels/defaults remain unqualified."],
     "statistics":"Published sample variance (n−1), sample standard deviation, signed skewness, raw kurtosis and Shannon entropy of equal channel values. Double intermediate moments; entropy counts sorted for deterministic summation. Empty/single/zero-variance standardized moments use explicit finite0 policy. Exact Photoshop binning, rounding, display scaling, degenerate behavior and pixels remain unqualified. Visible root groups are single samples; a lone outer group exposes its children with its masks retained. Standalone adjustment samples reject.",
     "adobe":"Stack renderer actionJSON subset shares this engine through published execute-actions. No dedicated image-stack creation endpoint; source orchestration is Photato-only. PSD stack metadata interchange rejects explicitly; use native23 for editable saving."]
  }
}
extension AutomationCommand {
  struct ImageStackOptions: Sendable { var sources: [(UUID,String)];var settings: ImageStackSettings;var name: String }
  func imageStackOptions() throws -> ImageStackOptions {
    guard case .array(let raw) = parameters["sources"],(2...7).contains(raw.count) else { throw AutomationFailure(status:400,message:"Provide two to seven shared source documents.") }
    let sources = try raw.map { item -> (UUID,String) in
      guard case .object(let fields) = item,Set(fields.keys) == ["id","revision"],case .string(let text) = fields["id"],let id = UUID(uuidString:text),case .string(let revision) = fields["revision"],!revision.isEmpty,revision.count <= 256 else { throw AutomationFailure(status:400,message:"Each source requires its shared id and current revision.") };return (id,revision)
    }
    guard Set(sources.map(\.0)).count == sources.count else { throw AutomationFailure(status:400,message:"Duplicate source documents are not allowed.") }
    var s = ImageStackSettings()
    if let raw = parameters["settings"] {
      guard case .object(let fields) = raw,Set(fields.keys).isSubset(of:["align","createSmartObject","mode"]) else { throw AutomationFailure(status:400,message:"Unknown image stack settings.") }
      for (key,value) in fields { switch (key,value) {
        case ("align",.bool(let b)):s.align = b
        case ("createSmartObject",.bool(let b)):s.createSmartObject = b
        case ("mode",.string(let text)) where text == "none" || ImageStackMode(rawValue:text) != nil:s.mode = ImageStackMode(rawValue:text)
        default:throw AutomationFailure(status:400,message:"Invalid image stack setting: \(key).")
      } }
    }
    do { try s.validate() } catch { throw AutomationFailure(status:400,message:error.localizedDescription) }
    return .init(sources:sources,settings:s,name:try parameters["name"] == nil ? "Untitled Stack":string("name"))
  }
}
extension AutomationService {
  func executeImageStack(_ command: AutomationCommand,anchorID: UUID) async throws -> AutomationResponse {
    let options = try command.imageStackOptions()
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document uploads and downloads in the native API window before creating a image stack.") }
    guard !documentTransferBusy,controller.imageStackWorkspace == nil,controller.canPublishImageStack else { throw AutomationFailure(status:409,message:"Finish the current document transfer or image stack operation.") }
    guard options.sources.contains(where:{$0.0 == anchorID}) else { throw AutomationFailure(status:400,message:"Include the command target in the image stack sources.") }
    guard shares.count < 8 else { throw AutomationFailure(status:429,message:"Leave one sharing slot available for the new image stack.") }
    let documents = try options.sources.map { id,revision -> CraftNSDocument in
      guard let document = shares.first(where:{$0.id == id})?.document else { throw AutomationFailure(status:404,message:"A shared source document was not found.") }
      try preflight(document);guard self.revision(document.store) == revision else { throw AutomationFailure(status:409,message:"A source revision is stale.") };return document
    }
    let snapshots = documents.map{$0.store.document},storeGenerations = documents.map{$0.store.layerPanelGeneration}
    let expectedToken = token,transferGeneration = documentTransferGeneration,serviceGeneration = generation
    let openGeneration = controller.documentOpening.generation,closeID = controller.documentClosing.state?.id,maintenance = controller.recoveryMaintenance.generation,discovery = controller.recoveryDiscovery.generation
    let operationID = UUID();imageStackOperationID = operationID;imageStackSourceIDs = Set(options.sources.map(\.0))
    documentTransferBusy = true
    for document in documents { document.store.geometryBusy = true;document.store.renderTask?.cancel() }
    let worker = Task.detached(priority:.userInitiated) { try ImageStack.prepare(snapshots,settings:options.settings,name:options.name) }
    imageStackTask = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    for document in documents { document.store.geometryTask = observer }
    defer {
      if imageStackOperationID == operationID { imageStackTask = nil;imageStackOperationID = nil;imageStackSourceIDs = [] }
      documentTransferBusy = false
      for (i,document) in documents.enumerated() where document.store.layerPanelGeneration == storeGenerations[i] {
        document.store.geometryBusy = false;document.store.geometryTask = nil;document.store.render()
      }
    }
    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation();guard !observer.isCancelled else { throw CancellationError() }
    prune()
    guard isRunning,token == expectedToken,generation == serviceGeneration,documentTransfersEnabled,documentTransferGeneration == transferGeneration,controller.imageStackWorkspace == nil,controller.canPublishImageStack,controller.documentOpening.generation == openGeneration,controller.documentClosing.state?.id == closeID,controller.recoveryMaintenance.generation == maintenance,controller.recoveryDiscovery.generation == discovery else { throw AutomationFailure(status:409,message:"image stack creation was cancelled, revoked or interrupted by a document operation.") }
    for (i,document) in documents.enumerated() {
      guard shares.contains(where:{$0.id == options.sources[i].0 && $0.document === document}),revision(document.store) == options.sources[i].1,document.store.document == snapshots[i],document.store.layerPanelGeneration == storeGenerations[i] else { throw AutomationFailure(status:409,message:"A image stack source changed or sharing ended.") }
    }
    try Self.checkLimits(result.document);guard shares.count < 8 else { throw AutomationFailure(status:429,message:"Document sharing capacity changed during image stack.") }
    let created = CraftNSDocument(model:result.document);controller.addDocument(created)
    do { try share(created) } catch { controller.removeDocument(created);throw error }
    created.updateChangeCount(.changeDone);created.makeWindowControllers();created.showWindows()
    guard let shared = shares.first(where:{$0.document === created}) else { throw AutomationFailure(status:409,message:"image stack sharing ended.") }
    var output = state(shared,document:created)
    output["imageStackResult"] = ["sourceCount":result.sourceCount,"aligned":result.aligned,"mode":options.settings.mode?.rawValue as Any? ?? NSNull(),"smartObject":options.settings.createSmartObject]
    return .json(output,status:201)
  }
}
