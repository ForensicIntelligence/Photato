import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RemoveToolAPI {
  static let name = "retouch.remove"
  static var definition: AutomationCommand.Definition {
    .init(name:name,parameters:["operation":"configure, stroke, apply, cancel or execute",
      "settings":"Partial window options or immutable execute overrides",
      "stroke":"One pending Add/Subtract stroke", "strokes":"Complete ordered removal marks",
      "layerID":"Raster target UUID; execute only"],
      description:"Mark or remove objects through the native Remove tool. Auto currently resolves to traditional processing; generative-on is explicitly unsupported. One Undo per applied batch.",
      optionalParameters:["settings","stroke","strokes","layerID"])
  }
  static var settingsSchema: [String:Any] {
    BrushAPI.object(["size":BrushAPI.number(1,5000),"subtract":BrushAPI.flag,
      "mode":BrushAPI.enumeration(RemoveToolSettings.Mode.allCases.map(\.rawValue)),
      "sampleAllLayers":BrushAPI.flag,"removeAfterEachStroke":BrushAPI.flag,"createNewLayer":BrushAPI.flag])
  }
  static var strokeSchema: [String:Any] {
    BrushAPI.object(["size":BrushAPI.number(1,5000),"subtract":BrushAPI.flag,
      "points":["type":"array","minItems":1,"maxItems":4096,
        "items":["type":"array","minItems":2,"maxItems":2,"items":BrushAPI.number(-1_000_000,1_000_000)]]],required:["points"])
  }
  static func schema(_ key:String) -> [String:Any] {
    switch key {
    case "operation": BrushAPI.enumeration(["configure","stroke","apply","cancel","execute"])
    case "settings": settingsSchema
    case "stroke": strokeSchema
    case "strokes": ["type":"array","minItems":1,"maxItems":256,"items":strokeSchema]
    case "layerID": ["type":"string","format":"uuid"]
    default: [:]
    }
  }
  static var branches: [[String:Any]] {
    [("configure",["operation","settings"],["settings"]),
     ("stroke",["operation","stroke"],["stroke"]),
     ("apply",["operation"],[]), ("cancel",["operation"],[]),
     ("execute",["operation","layerID","settings","strokes"],["strokes"])].map { operation,keys,required in
      var fields = Dictionary(uniqueKeysWithValues:keys.map { ($0,schema($0)) })
      fields["operation"] = ["const":operation]
      if operation == "configure" {
        var settings = settingsSchema; settings["minProperties"] = 1; fields["settings"] = settings
      }
      return BrushAPI.object(fields,required:["operation"]+required)
    }
  }
  @MainActor static func state(_ store:EditorStore) -> [String:Any] {
    ["available":store.canUseRemove,"settings":BrushAPI.json(store.removeSettings),
      "pendingStrokes":store.removeDraft?.strokes.count ?? 0,
      "gestureActive":store.removeStroke != nil,"busy":store.removeApplying != nil,
      "pendingSourceValid":store.removeDraft.map { store.removeSourceMatches($0) } ?? true,
      "resolvedProcessing":"traditional","generativeAvailable":false,
      "distractionDetectionAvailable":false]
  }
  static var stateSchema: [String:Any] {
    BrushAPI.object(["available":BrushAPI.flag,"settings":settingsSchema,
      "pendingStrokes":["type":"integer","minimum":0,"maximum":256],
      "gestureActive":BrushAPI.flag,"busy":BrushAPI.flag,"pendingSourceValid":BrushAPI.flag,
      "resolvedProcessing":["const":"traditional"],"generativeAvailable":["const":false],
      "distractionDetectionAvailable":["const":false]],required:["available","settings","pendingStrokes","gestureActive","busy","pendingSourceValid","resolvedProcessing","generativeAvailable","distractionDetectionAvailable"])
  }
  static var capabilities: [String:Any] {
    ["command":name,"stateSchema":stateSchema,
      "resultSchema":BrushAPI.object(["revision":["type":"string"],"removeTool":stateSchema],required:["revision","removeTool"]),
      "native":"J tool group, Add/Subtract marking with captured Option alternate, size, processing mode, Sample All Layers, Remove after each stroke, Create New Layer, Return Apply and Escape Clear. Pending strokes and options are window-local.",
      "processing":"Native traditional content-aware synthesis only. Auto resolves to this engine. generativeOn rejects explicitly; no network request or learned model is invoked. Distraction detection, generative modes and Photoshop quality/pixel equivalence are unfinished.",
      "uniformFields":"Uniform known RGBA fields and constant harmonic boundaries retain their exact Float sample words through the shared native engine. This invariant does not establish Photoshop output equivalence.",
      "supportedModes":["auto","generativeOff"],"unavailableModes":["generativeOn"],
      "history":"One shared prepared transaction per applied batch; exact original selection representation, source layer metadata and unmarked pixels retained. New-layer output is a separate transparent raster patch. Native archive keeps resulting pixels/layers. Semantic Remove Actions and Adobe actionJSON remain unsupported.",
      "cursor":"Add/Subtract follows the setting captured at pointer-down, inverted by captured Option. Control/Command/Shift do not change the operation. Space pans; all16 modifier combinations tested separately.",
      "limits":["maximumCanvasPixels":RemovePreparation.maximumCanvasPixels,"maximumSolvePixels":ContentAwareSynthesis.maximumPixels,"strokes":256,"pointsPerStroke":4096,"pointsPerOperation":16384,"size":[1,5000]],
      "loop":"Near endpoints within one brush diameter fill a nondegenerate loop. This geometric threshold and brush coverage are not Photoshop-qualified. Edge-to-edge corner closure remains unimplemented.",
      "api":"execute applies captured strokes without changing defaults. configure requires native preferenceChangesEnabled. stroke/apply/cancel share native pending state; other edits reject pending Remove state. Existing sharing/revision/busy/cancellation/revocation guards apply.",
      "adobe":"No dedicated Remove endpoint in the pinned Firefly Photoshop v2 contract. No invented Adobe route, UXP runtime or plugin compatibility."]
  }
  static func settings(_ raw:AutomationValue?, base:RemoveToolSettings) throws -> RemoveToolSettings {
    let settings = try RetouchStrokeAPI.decode(raw,schema:settingsSchema,base:base)
    try settings.validate(); return settings
  }
  static func stroke(_ raw:AutomationValue, settings:RemoveToolSettings) throws -> RemoveStroke {
    let value = try BrushAPI.merge(raw,schema:strokeSchema,
      base:["size":settings.size,"subtract":settings.subtract],path:"stroke")
    do {
      let result = try JSONDecoder().decode(RemoveStroke.self,from:JSONSerialization.data(withJSONObject:value))
      try result.validate(); return result
    } catch { throw AutomationFailure(status:400,message:"Invalid Remove stroke: \(error.localizedDescription)") }
  }
}

extension AutomationService {
  func executeRemove(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID) async throws -> AutomationResponse {
    let store = document.store, operation = try command.string("operation")
    let allowed: Set<String>
    switch operation {
    case "configure": allowed = ["operation","settings"]
    case "stroke": allowed = ["operation","stroke"]
    case "execute": allowed = ["operation","settings","strokes","layerID"]
    case "apply","cancel": allowed = ["operation"]
    default: throw AutomationFailure(status:400,message:"Unknown Remove operation.")
    }
    guard Set(command.parameters.keys).isSubset(of:allowed) else {
      throw AutomationFailure(status:400,message:"Irrelevant Remove parameter for this operation.")
    }
    if operation == "cancel", store.removeApplying != nil {
      store.cancelRemove(); return .json(state(try removeShare(shareID),document:document))
    }
    try preflight(document,allowRemove:true)
    guard store.removeStroke == nil else { throw AutomationFailure(status:409,message:"Finish the pointer stroke first.") }
    if operation == "cancel" { store.cancelRemove(); return .json(state(try removeShare(shareID),document:document)) }
    if operation == "configure" {
      guard preferenceChangesEnabled else { throw AutomationFailure(status:403,message:"Enable preference changes in the native API window first.") }
      guard case .object(let patch) = command.parameters["settings"], !patch.isEmpty else {
        throw AutomationFailure(status:400,message:"Configure requires a nonempty settings patch.")
      }
      try store.updateRemoveSettings(RemoveToolAPI.settings(command.parameters["settings"],base:store.removeSettings))
      return .json(state(try removeShare(shareID),document:document))
    }
    guard !store.editingMask, !store.smartFilterMaskEditing, !store.editingComponent else {
      throw AutomationFailure(status:422,message:"Remove requires the RGB image target, not a mask or channel.")
    }
    if operation == "stroke" {
      guard let raw = command.parameters["stroke"] else { throw AutomationFailure(status:400,message:"Supply a Remove stroke.") }
      try store.appendRemoveStroke(RemoveToolAPI.stroke(raw,settings:store.removeSettings))
      if store.removeDraft?.settings.removeAfterEachStroke != true {
        return .json(state(try removeShare(shareID),document:document))
      }
    }
    let draft: RemoveDraft
    if operation == "execute" {
      guard store.removeDraft == nil else { throw AutomationFailure(status:409,message:"Apply or clear pending Remove strokes first.") }
      let settings = try RemoveToolAPI.settings(command.parameters["settings"],base:store.removeSettings)
      guard case .array(let values) = command.parameters["strokes"], !values.isEmpty,
        let id = try command.parameters["layerID"].map({ _ in try command.actionUUID("layerID") }) ?? store.document.activeLayerID else {
        throw AutomationFailure(status:400,message:"Supply strokes and a raster layer.")
      }
      draft = .init(original:store.document,session:store.sessionGeneration,generation:store.layerPanelGeneration,
        layerID:id,settings:settings,strokes:try values.map { try RemoveToolAPI.stroke($0,settings:settings) })
    } else {
      guard let pending = store.removeDraft, !pending.strokes.isEmpty, store.removeSourceMatches(pending) else {
        throw AutomationFailure(status:409,message:"There is no valid pending Remove batch.")
      }
      draft = pending
    }
    try draft.request.validate()
    let prepare = store.removePreparation, request = draft.request, restore = store.removeDraft
    store.removeDraft = nil; store.removeApplying = draft
    do {
      try await executePreparedOperation(document:document,shareID:shareID,revision:revision(store),allowPathTarget:true) { original in
        .regionRetouch(try prepare(request,original))
      }
      store.selectedLayerIDs = Set(store.document.activeLayerID.map { [$0] } ?? [])
      store.removeApplying = nil; store.removeRevision = UUID()
    } catch {
      if store.removeApplying != nil, store.removeSourceMatches(draft) { store.removeDraft = restore }
      store.removeApplying = nil; store.removeRevision = UUID(); throw error
    }
    return .json(state(try removeShare(shareID),document:document))
  }
  private func removeShare(_ id:UUID) throws -> Share {
    guard let share = shares.first(where:{ $0.id == id }) else { throw AutomationFailure(status:409,message:"Sharing ended.") }
    return share
  }
}
