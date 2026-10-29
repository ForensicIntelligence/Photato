import AppKit
import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension ContactSheetSettings {
  static var apiSchema: [String:Any] {
    var fields: [String:[String:Any]] = [:]
    for key in ["width","height","resolution","horizontal","vertical","fontSize"] {fields[key] = ["type":"number","minimum":0.0,"maximum":1_000_000.0]}
    for key in ["columns","rows"] {fields[key] = ["type":"integer","minimum":1.0,"maximum":100.0]}
    for key in ["placeAcrossFirst","autoSpacing","rotateForBestFit","caption","flatten"] {fields[key] = ["type":"boolean"]}
    fields["units"] = ["type":"string","enum":Units.allCases.map(\.rawValue)]
    fields["mode"] = ["type":"string","enum":DocumentColorMode.componentModes.map(\.rawValue)]
    fields["depth"] = ["type":"string","enum":PixelDepth.allCases.map(\.rawValue)]
    fields["font"] = ["type":"string","minLength":1,"maxLength":256]
    fields["profile"] = ["type":"string","description":"Optional base64 ICC bytes matching mode/depth; body limit4MiB.","maxLength":4_000_000]
    return ["type":"object","additionalProperties":false,"properties":fields]
  }
  static var sourcesSchema: [String:Any] {
    ["type":"array","minItems":1,"maxItems":7,"items":["type":"object","additionalProperties":false,"required":["id","revision"],"properties":["id":["type":"string","format":"uuid"],"revision":["type":"string","minLength":1,"maxLength":256]]]]
  }
  static var apiCapabilities: [String:Any] {
    ["command":"document.contactSheet","cancelCommand":"document.contactSheet.cancel","settingsSchema":apiSchema,"sourcesSchema":sourcesSchema,
     "result":"HTTP201: documents (shared document states), pages, images, placements (zero-based source/page/column/row and pixel x/y/width/height/rotated). All pages publish together; source documents/history stay unchanged.",
     "limits":"Transfers enabled.1–7 shared sources including target. Leave one share slot per output page (8 total); each API page at most4MP/64layers/128MiB. Native pages8MP,32pages/64MP combined,256sources and512MiB source/output budgets. Still images only.",
     "behavior":"Page units/resolution, RGB/Gray/CMYK/Lab and depth/profile, across/down ordering, spacing, best-fit rotation, editable filename captions and optional flattening. Native and API share one layout engine. API has no arbitrary filesystem source access.",
     "adobe":"The pinned public v2 contract has no dedicated Contact Sheet II endpoint. Execute-actions descriptors and exact Photoshop layout/resampling/defaults remain unqualified; no Adobe endpoint is invented."]
  }
}
extension AutomationCommand {
  struct ContactSheetOptions: Sendable {var sources: [(UUID,String)];var settings: ContactSheetSettings;var name: String}
  func contactSheetOptions() throws -> ContactSheetOptions {
    guard case .array(let raw) = parameters["sources"],(1...7).contains(raw.count) else {throw AutomationFailure(status:400,message:"Provide one to seven shared source documents.")}
    let sources = try raw.map {item -> (UUID,String) in
      guard case .object(let fields) = item,Set(fields.keys) == ["id","revision"],case .string(let text) = fields["id"],let id = UUID(uuidString:text),case .string(let revision) = fields["revision"],!revision.isEmpty,revision.count <= 256 else {throw AutomationFailure(status:400,message:"Each source requires its shared UUID and current revision.")};return (id,revision)
    }
    guard Set(sources.map(\.0)).count == sources.count else {throw AutomationFailure(status:400,message:"Duplicate source documents are not allowed.")}
    var settings = ContactSheetSettings()
    if let value = parameters["settings"] {
      let base = try JSONSerialization.jsonObject(with:JSONEncoder().encode(settings))
      let merged = try BrushAPI.merge(value,schema:ContactSheetSettings.apiSchema,base:base,path:"contactSheet.settings")
      do {settings = try JSONDecoder().decode(ContactSheetSettings.self,from:JSONSerialization.data(withJSONObject:merged));_ = try settings.layout()} catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
    }
    return .init(sources:sources,settings:settings,name:try parameters["name"] == nil ? "ContactSheet":string("name"))
  }
}
extension AutomationService {
  func executeContactSheet(_ command: AutomationCommand,anchorID: UUID) async throws -> AutomationResponse {
    let options = try command.contactSheetOptions()
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document uploads and downloads in the native API window before creating a contact sheet.") }
    guard !documentTransferBusy,controller.contactSheetWorkspace == nil,controller.canPublishContactSheet else { throw AutomationFailure(status:409,message:"Finish the current document transfer or contact sheet operation.") }
    guard options.sources.contains(where:{$0.0 == anchorID}) else { throw AutomationFailure(status:400,message:"Include the command target in the contact sheet sources.") }
    let layout = try options.settings.layout(), pageCount = (options.sources.count+options.settings.columns*options.settings.rows-1)/(options.settings.columns*options.settings.rows)
    guard shares.count+pageCount <= 8 else {throw AutomationFailure(status:429,message:"Leave one sharing slot available for each contact sheet page.")}
    guard layout.width*layout.height <= 4_194_304 else {throw AutomationFailure(status:413,message:"Shared API pages are limited to4,194,304 pixels; reduce dimensions or resolution.")}
    let documents = try options.sources.map { id,revision -> CraftNSDocument in
      guard let document = shares.first(where:{$0.id == id})?.document else { throw AutomationFailure(status:404,message:"A shared source document was not found.") }
      try preflight(document);guard self.revision(document.store) == revision else { throw AutomationFailure(status:409,message:"A source revision is stale.") };return document
    }
    let snapshots = documents.map{$0.store.document},storeGenerations = documents.map{$0.store.layerPanelGeneration}
    let expectedToken = token,transferGeneration = documentTransferGeneration,serviceGeneration = generation
    let openGeneration = controller.documentOpening.generation,closeID = controller.documentClosing.state?.id,maintenance = controller.recoveryMaintenance.generation,discovery = controller.recoveryDiscovery.generation
    let operationID = UUID();contactSheetOperationID = operationID;contactSheetSourceIDs = Set(options.sources.map(\.0))
    documentTransferBusy = true
    for document in documents { document.store.geometryBusy = true;document.store.renderTask?.cancel() }
    let worker = Task.detached(priority:.userInitiated) { try ContactSheet.prepare(snapshots.map{ContactSheet.Source(document:$0)},settings:options.settings,name:options.name) }
    contactSheetTask = worker
    let observer = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    for document in documents { document.store.geometryTask = observer }
    defer {
      if contactSheetOperationID == operationID { contactSheetTask = nil;contactSheetOperationID = nil;contactSheetSourceIDs = [] }
      documentTransferBusy = false
      for (i,document) in documents.enumerated() where document.store.layerPanelGeneration == storeGenerations[i] {
        document.store.geometryBusy = false;document.store.geometryTask = nil;document.store.render()
      }
    }
    let result = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation();guard !observer.isCancelled else { throw CancellationError() }
    prune()
    guard isRunning,token == expectedToken,generation == serviceGeneration,documentTransfersEnabled,documentTransferGeneration == transferGeneration,controller.contactSheetWorkspace == nil,controller.canPublishContactSheet,controller.documentOpening.generation == openGeneration,controller.documentClosing.state?.id == closeID,controller.recoveryMaintenance.generation == maintenance,controller.recoveryDiscovery.generation == discovery else { throw AutomationFailure(status:409,message:"contact sheet creation was cancelled, revoked or interrupted by a document operation.") }
    for (i,document) in documents.enumerated() {
      guard shares.contains(where:{$0.id == options.sources[i].0 && $0.document === document}),revision(document.store) == options.sources[i].1,document.store.document == snapshots[i],document.store.layerPanelGeneration == storeGenerations[i] else { throw AutomationFailure(status:409,message:"A contact sheet source changed or sharing ended.") }
    }
    for page in result.documents {try Self.checkLimits(page)}
    guard shares.count+result.documents.count <= 8 else {throw AutomationFailure(status:429,message:"Document sharing capacity changed during contact sheet creation.")}
    let created = result.documents.map{CraftNSDocument(model:$0)}
    do {
      for document in created {controller.addDocument(document);try share(document)}
    } catch {
      for document in created {for id in shares.filter({$0.document === document}).map(\.id) {revoke(id)};controller.removeDocument(document)}
      throw error
    }
    for document in created {document.updateChangeCount(.changeDone);document.makeWindowControllers();document.showWindows()}
    let states = try created.map {document -> [String:Any] in
      guard let shared = shares.first(where:{$0.document === document}) else {throw AutomationFailure(status:409,message:"Contact sheet sharing ended.")}
      return state(shared,document:document)
    }
    let placements = try JSONSerialization.jsonObject(with:JSONEncoder().encode(result.placements))
    return .json(["documents":states,"pages":states.count,"images":options.sources.count,"placements":placements],status:201)
  }
}
