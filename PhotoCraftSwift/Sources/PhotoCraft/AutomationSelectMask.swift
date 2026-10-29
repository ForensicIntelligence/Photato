import AppKit
import PhotoCraftCore
import PhotoCraftImaging

extension SelectionRefinement {
  static var apiSchema: [String:Any] {
    var p: [String:Any] = [:]
    for (key,lo,hi) in [("radius",0,250),("smooth",0,100),("feather",0,1000),("contrast",0,100),("shiftEdge",-100,100),("amount",0,100)] {
      p[key] = ["type":"number","minimum":lo,"maximum":hi,"default":key == "amount" ? 100:0]
    }
    p["smartRadius"] = ["type":"boolean","default":false]; p["decontaminate"] = ["type":"boolean","default":false]
    return ["type":"object","additionalProperties":false,"properties":p]
  }
  static var strokeSchema: [String:Any] {
    ["type":"array","maxItems":1024,"items":["type":"object","additionalProperties":false,"required":["points"],"properties":[
      "tool":["type":"string","enum":SelectionRefinementStroke.Tool.allCases.map(\.rawValue),"default":"add"],
      "size":["type":"number","minimum":1,"maximum":5000,"default":30],"hardness":["type":"number","minimum":0,"maximum":1,"default":0.8],
      "points":["type":"array","minItems":1,"maxItems":4096,"items":["type":"array","minItems":2,"maxItems":2,"items":["type":"number","minimum":-1_000_000,"maximum":1_000_000]]]]]]
  }
  static var apiCapabilities: [String:Any] {
    ["command":"selection.refine","settingsSchema":apiSchema,"strokeSchema":strokeSchema,"outputs":SelectionRefinementOutput.allCases.map(\.rawValue),
     "maximumPixels":SelectionMatting.maximumPixels,"maximumTotalStrokePoints":16384,"maximumBrushPixelVisits":250_000_000,
     "input":"Current selection; an absent selection starts empty. fromLayerMask=true uses the active pixel mask's stored coverage. Brush coordinates are canvas pixels, y down. sampleAllLayers controls the color guide.",
     "history":"Selection, layerMask and newLayer outputs are one native Undo transaction. New documents leave the source unchanged and return201 with the new shared document state; document-transfer permission and sharing capacity are required.",
     "decontamination":"selection/layerMask output changes to newLayerWithMask when decontaminate=true. Original RGB8/16/32 pixels are retained in the hidden source layer.",
     "limits":"Ordinary raster layers only. New layers retain layer geometry and effects; their pixel mask is replaced. Native guided matting is not Adobe Color/Object Aware or Refine Hair model equivalence. Photoshop refinement action descriptors remain unsupported; no invented Adobe endpoint."]
  }
}
struct SelectMaskAPIOptions: Sendable {
  let id: UUID
  let settings: SelectionRefinement
  let output: SelectionRefinementOutput
  let strokes: [SelectionRefinementStroke]
  let fromMask: Bool
  let all: Bool
  func edit(_ original: CraftDocument) throws -> SelectionRefinementEdit {
    try SelectionRefinementInput.prepare(original,layerID:id,fromLayerMask:fromMask,sampleAllLayers:all)
      .edit(settings:settings,output:output,strokes:strokes)
  }
}
extension AutomationCommand {
  func selectMaskOptions() throws -> SelectMaskAPIOptions {
    do {
      guard let id = UUID(uuidString:try string("layerID")) else { throw CraftError.invalid("Invalid layerID.") }
      let settings = try SelectionRefinement.decodeJSON(JSONSerialization.data(withJSONObject:parameters["settings"]?.jsonValue ?? [:]))
      let output: SelectionRefinementOutput
      if parameters["output"] == nil { output = .selection }
      else { guard let value = SelectionRefinementOutput(rawValue:try string("output")) else { throw CraftError.invalid("Unknown refinement output.") }; output = value }
      func bool(_ key: String) throws -> Bool {
        guard let value = parameters[key] else { return false }
        guard case .bool(let flag) = value else { throw CraftError.invalid("\(key) must be boolean.") }; return flag
      }
      var strokes: [SelectionRefinementStroke] = []
      if let value = parameters["strokes"] {
        guard let array = value.jsonValue as? [[String:Any]], array.count <= 1024 else { throw CraftError.invalid("Invalid refinement strokes.") }
        for raw in array {
          guard Set(raw.keys).isSubset(of:["tool","size","hardness","points"]) else { throw CraftError.invalid("Unknown brush parameter.") }
          var fields = try JSONSerialization.jsonObject(with:JSONEncoder().encode(SelectionRefinementStroke())) as! [String:Any]
          for (k,v) in raw { fields[k] = v }
          let stroke = try JSONDecoder().decode(SelectionRefinementStroke.self,from:JSONSerialization.data(withJSONObject:fields))
          try stroke.validate(); strokes.append(stroke)
        }
      }
      guard strokes.reduce(0,{ $0+$1.points.count }) <= 16384 else { throw CraftError.invalid("Refinement point limit exceeded.") }
      return try .init(id:id,settings:settings,output:output,strokes:strokes,fromMask:bool("fromLayerMask"),all:bool("sampleAllLayers"))
    } catch { throw AutomationFailure(status:400,message:error.localizedDescription) }
  }
}
extension AutomationService {
  func refineSelection(_ command: AutomationCommand,document: CraftNSDocument,share: Share) async throws -> AutomationResponse {
    let focus=command.name == "selection.focus",output:SelectionRefinementOutput
    let prepare:@Sendable (CraftDocument)throws->SelectionRefinementEdit
    if focus{let options=try command.focusOptions();output=options.output;prepare={try options.edit($0)}}
    else{let options=try command.selectMaskOptions();output=options.output.allowingDecontamination(options.settings.decontaminate);prepare={try options.edit($0)}}
    if !output.createsDocument {
      try await executePreparedOperation(document:document,shareID:share.id,revision:command.revision) { original in let edit=try prepare(original);return focus ? .focusArea(edit):.selectionRefinement(edit) }
      return .json(state(share,document:document))
    }
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document transfers to create a refined document.") }
    guard !documentTransferBusy, shares.count < 8 else { throw AutomationFailure(status:429,message:"Document transfer busy or sharing limit reached.") }
    let store = document.store, original = store.document, expectedToken = token, transferGeneration = documentTransferGeneration
    let panelGeneration = store.layerPanelGeneration, closing = controller.documentClosing.state?.id
    let opening = controller.documentOpening.generation, maintenance = controller.recoveryMaintenance.generation, discovery = controller.recoveryDiscovery.generation
    guard !controller.documentClosing.isActive, !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, !controller.recoveryIndex.isBusy else { throw AutomationFailure(status:409,message:"Finish the document lifecycle operation first.") }
    documentTransferBusy = true; store.geometryBusy = true; store.renderTask?.cancel()
    defer { documentTransferBusy = false; if store.layerPanelGeneration == panelGeneration { store.geometryBusy = false; store.geometryTask = nil; store.render() } }
    let worker = Task.detached(priority:.userInitiated) { try prepare(original).applied(to:original) }
    store.geometryTask = Task { await withTaskCancellationHandler { _ = try? await worker.value } onCancel: { worker.cancel() } }
    let model = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    try Task.checkCancellation(); prune()
    guard store.geometryTask?.isCancelled != true, isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transferGeneration,
      shares.contains(where:{ $0.id == share.id }), store.document == original, revision(store) == command.revision, store.layerPanelGeneration == panelGeneration,
      shares.count < 8, NSApp?.modalWindow == nil, !controller.documentClosing.isActive, controller.documentClosing.state?.id == closing,
      !controller.documentOpening.isActive, !controller.documentOpening.hasPendingRequests, controller.documentOpening.generation == opening,
      !controller.recoveryIndex.isBusy, controller.recoveryMaintenance.generation == maintenance, controller.recoveryDiscovery.generation == discovery else {
      throw AutomationFailure(status:409,message:"Refinement was cancelled or document sharing/lifecycle changed.")
    }
    try Self.checkLimits(model)
    let created = CraftNSDocument(model:model); controller.addDocument(created)
    do { try self.share(created) } catch { controller.removeDocument(created); throw error }
    created.updateChangeCount(.changeDone); created.makeWindowControllers(); created.showWindows()
    guard let added = shares.first(where:{ $0.document === created }) else { throw AutomationFailure(status:409,message:"Document sharing ended.") }
    return .json(state(added,document:created),status:201)
  }
}
