import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum RemoveToolAPI {
  static let name = "retouch.remove"
  static var definition: AutomationCommand.Definition {
    .init(name:name,parameters:["operation":"configure, removeWires, findPeople, findDistractions, configureDistractionReview, preview, stroke, apply, cancel or execute",
      "settings":"Partial window options or immutable execute overrides",
      "stroke":"One pending Add/Subtract stroke", "strokes":"Complete ordered removal marks",
      "enabledCategories":"Replace enabled general-distraction categories in the current review",
      "overlayOpacity":"General-distraction overlay opacity from 0 to 1",
      "layerID":"Raster target UUID; execute only"],
      description:"Mark or remove objects through the native Remove tool. Choose Auto, traditional or eligible on-device generation. One Undo per applied batch.",
      optionalParameters:["settings","stroke","strokes","layerID","enabledCategories","overlayOpacity"])
  }
  static var distractionCategorySchema: [String:Any] {
    BrushAPI.enumeration(RemoveDistractionCategory.allCases.map(\.rawValue))
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
    case "operation": BrushAPI.enumeration(["configure","removeWires","findPeople","findDistractions","configureDistractionReview","preview","stroke","apply","cancel","execute"])
    case "settings": settingsSchema
    case "stroke": strokeSchema
    case "strokes": ["type":"array","minItems":1,"maxItems":256,"items":strokeSchema]
    case "layerID": ["type":"string","format":"uuid"]
    case "enabledCategories": ["type":"array","items":distractionCategorySchema,"maxItems":6,"uniqueItems":true]
    case "overlayOpacity": BrushAPI.number()
    default: [:]
    }
  }
  static var branches: [[String:Any]] {
    [("configure",["operation","settings"],["settings"]),
     ("stroke",["operation","stroke"],["stroke"]),
     ("removeWires",["operation"],[]), ("findPeople",["operation"],[]), ("preview",["operation"],[]),
     ("findDistractions",["operation"],[]), ("configureDistractionReview",["operation","enabledCategories","overlayOpacity"],[]),
     ("apply",["operation"],[]), ("cancel",["operation"],[]),
     ("execute",["operation","layerID","settings","strokes"],["strokes"])].map { operation,keys,required in
      var fields = Dictionary(uniqueKeysWithValues:keys.map { ($0,schema($0)) })
      fields["operation"] = ["const":operation]
      if operation == "configure" {
        var settings = settingsSchema; settings["minProperties"] = 1; fields["settings"] = settings
      }
      var branch = BrushAPI.object(fields,required:["operation"]+required)
      if operation == "configureDistractionReview" { branch["minProperties"] = 2 }
      return branch
    }
  }
  static var distractionSchema: [String:Any] {
    let group = BrushAPI.object(["category":distractionCategorySchema,"count":BrushAPI.number(1,16384,integer:true),
      "enabled":BrushAPI.flag],required:["category","count","enabled"])
    return BrushAPI.object(["available":BrushAPI.flag,"detecting":BrushAPI.flag,"reviewOpen":BrushAPI.flag,
      "modelConfigured":BrushAPI.flag,"overlayOpacity":BrushAPI.number(),
      "categories":["type":"array","maxItems":6,"items":group]],
      required:["available","detecting","reviewOpen","modelConfigured","overlayOpacity","categories"])
  }
  @MainActor static func state(_ store:EditorStore) -> [String:Any] {
    let draft = store.removeDraft ?? store.removeApplying
    let review = store.removeDraft?.distractionReview
    let categories: [[String:Any]] = review?.groups.map { group in
      ["category":group.category.rawValue,"count":group.count,"enabled":review?.enabled.contains(group.category) == true]
    } ?? []
    return ["available":store.canUseRemove,"settings":BrushAPI.json(store.removeSettings),
      "pendingStrokes":store.removeDraft?.strokes.count ?? 0,
      "gestureActive":store.removeStroke != nil,"busy":store.removeApplying != nil || store.removeDetectionID != nil || store.removeDistractionID != nil || store.removeWiresID != nil,
      "pendingSourceValid":store.removeDraft.map { store.removeSourceMatches($0) } ?? true,
      "resolvedProcessing":store.removeProcessing(draft?.settings ?? store.removeSettings, in: draft?.original ?? store.document).rawValue,
      "generativeAvailable":store.localRemoveAvailable,
      "distractionDetectionAvailable":true,"detectingPeople":store.removeDetectionID != nil,
      "wiresAvailable":store.canRemoveWires,"removingWires":store.removeWiresID != nil,
      "generalDistractions":["available":store.canFindGeneralDistractions,"detecting":store.removeDistractionID != nil,
        "reviewOpen":review != nil,"modelConfigured":RemoveDistractionModelPreference.url(bookmark: store.removeDistractionModelBookmark) != nil,
        "overlayOpacity":review?.overlayOpacity ?? 0.45,"categories":categories],
      "detectedPeople":store.removeDraft?.detectedPeople ?? 0,"hasPendingMarks":store.removeDraft?.hasMarks ?? false]
  }
  static var stateSchema: [String:Any] {
    BrushAPI.object(["available":BrushAPI.flag,"settings":settingsSchema,
      "pendingStrokes":["type":"integer","minimum":0,"maximum":256],
      "gestureActive":BrushAPI.flag,"busy":BrushAPI.flag,"pendingSourceValid":BrushAPI.flag,
      "resolvedProcessing":BrushAPI.enumeration(RemoveProcessing.allCases.map(\.rawValue)),"generativeAvailable":BrushAPI.flag,
      "distractionDetectionAvailable":["const":true],"detectingPeople":BrushAPI.flag,
      "wiresAvailable":BrushAPI.flag,"removingWires":BrushAPI.flag,
      "generalDistractions":distractionSchema,
      "detectedPeople":["type":"integer","minimum":0,"maximum":64],"hasPendingMarks":BrushAPI.flag],required:["available","settings","pendingStrokes","gestureActive","busy","pendingSourceValid","resolvedProcessing","generativeAvailable","distractionDetectionAvailable","detectingPeople","wiresAvailable","removingWires","generalDistractions","detectedPeople","hasPendingMarks"])
  }
  static var capabilities: [String:Any] {
    ["command":name,"stateSchema":stateSchema,
      "resultSchema":["type":"object","additionalProperties":true,"required":["revision","removeTool"],"properties":["revision":["type":"string"],"removeTool":stateSchema,
        "removePeopleResult":BrushAPI.object(["candidates":BrushAPI.number(0,64,integer:true),"protectedForegroundPeople":BrushAPI.number(0,64,integer:true)],required:["candidates","protectedForegroundPeople"]),
        "removeWiresResult":BrushAPI.object(["candidateTracks":["type":"integer","minimum":0],"applied":BrushAPI.flag],required:["candidateTracks","applied"]),
        "removalMask":BrushAPI.object(["width":BrushAPI.number(1,300000,integer:true),"height":BrushAPI.number(1,300000,integer:true),"coverageBase64":["type":"string","maxLength":22369624],"meaning":["const":"marksBeforeDocumentSelection"]],required:["width","height","coverageBase64","meaning"])]],
      "native":"J tool group, Add/Subtract marking with captured Option alternate, size, processing mode, Sample All Layers, Remove after each stroke, Create New Layer, Return Apply and Escape Clear. Pending strokes and options are window-local.",
      "processing":"Auto uses LaMa512 when configured for an eligible document, and traditional removal otherwise. generativeOn requires the configured device model and never falls back. generativeOff uses traditional removal. Brush marks and reviewed People and General distractions use the same prepared edit. Wires and cables uses its traditional detector and repair in Auto or Off. Open the native Remove options to choose a local model.",
      "uniformFields":"Uniform known RGBA fields and constant harmonic boundaries retain their exact Float sample words through the shared native engine. This invariant does not establish Photoshop output equivalence.",
      "supportedModes":["auto","generativeOff"],"conditionalModes":["generativeOn"],
      "device":"Apple Silicon on macOS 26 and later with a configured compiled LaMa512 model and still RGB document.",
      "history":"One shared prepared transaction per applied batch; exact original selection representation, source layer metadata and unmarked pixels retained. New-layer output is a separate transparent raster patch. Native archive keeps resulting pixels/layers. Semantic Remove Actions and Adobe actionJSON remain unsupported.",
      "cursor":"Add/Subtract follows the setting captured at pointer-down, inverted by captured Option. Control/Command/Shift do not change the operation. Space pans; all16 modifier combinations tested separately.",
      "limits":["maximumCanvasPixels":RemovePreparation.maximumCanvasPixels,"maximumSolvePixels":ContentAwareSynthesis.maximumPixels,
        "maximumLocalCanvasSide":Surface.maxDimension,"maximumLocalRepairRegions":RemovePreparation.maximumGenerativeRegions,
        "maximumPreviewPixels":RemovePreparation.maximumCanvasPixels,"strokes":256,"pointsPerStroke":4096,"pointsPerOperation":16384,"size":[1,5000]],
      "loop":"Near endpoints within one brush diameter fill a nondegenerate loop. A stroke between adjacent canvas edges can enclose the shared corner. The preview and committed mask share the same geometry. Exact Photoshop thresholds are unqualified.",
      "wireRemoval":"removeWires follows Sample All Layers, Create New Layer and the active selection, with no pending marking batch. One Undo if applied. An empty detection or fully protected target returns applied=false. Candidate tracks are connected ridge samples, so fragmented or intersecting runs need not correspond one-to-one with physical cables. Inference uses a bounded 1536-pixel analysis side followed by native-resolution reconstruction. Small, low-contrast, or heavily occluded wires can be missed.",
      "generalDistractionReview":"findDistractions stages six named categories where detected. Available classifiers are Apple Vision, local spot analysis, and an optional local OWLv2 Core ML model. configureDistractionReview replaces the enabled categories and/or overlay opacity. stroke refines their union, preview reports coverage with transfer permission, apply commits one edit, and cancel discards the review. Overlay opacity changes only the display.",
      "peopleDetection":"findPeople uses captured source, Sample All Layers and native person detection without the optional feature model. The same source grid feeds foreground-subject detection; whole foreground people are excluded when weighted mask overlap is at least50%. This explicit policy is not an Adobe classifier-equivalence claim. Missing subject classification fails rather than silently marking every person; a valid no-subject result retains all candidates. findPeople also returns candidates/protectedForegroundPeople counts. Detection is read-only. Refine with stroke; detected marks always require explicit apply even when Remove after each stroke is on. preview returns full-canvas row-major UInt8 marking coverage before document selection clipping, plus width/height, and requires document transfer permission. Native/API share cancellation, lifecycle/source guards and one final editing transaction.",
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
    case "apply","cancel","removeWires","findPeople","findDistractions","preview": allowed = ["operation"]
    case "configureDistractionReview": allowed = ["operation","enabledCategories","overlayOpacity"]
    default: throw AutomationFailure(status:400,message:"Unknown Remove operation.")
    }
    guard Set(command.parameters.keys).isSubset(of:allowed) else {
      throw AutomationFailure(status:400,message:"Irrelevant Remove parameter for this operation.")
    }
    if operation == "cancel", store.removeApplying != nil || store.removeDetectionID != nil || store.removeDistractionID != nil || store.removeWiresID != nil {
      store.cancelRemove(); return .json(state(try removeShare(shareID),document:document))
    }
    try preflight(document,allowRemove:true)
    guard store.removeStroke == nil else { throw AutomationFailure(status:409,message:"Finish the pointer stroke first.") }
    if operation == "cancel" { store.cancelRemove(); return .json(state(try removeShare(shareID),document:document)) }
    if operation == "removeWires" { return try await executeRemoveWires(document: document, shareID: shareID) }
    if operation == "findDistractions" {
      let expectedToken = token, expectedGeneration = generation
      guard store.canFindGeneralDistractions else { throw AutomationFailure(status:409,message:"Finish or clear the current Remove interaction first.") }
      do {
        try await store.detectGeneralDistractions { [self] in
          prune()
          guard isRunning, token == expectedToken, generation == expectedGeneration,
            shares.contains(where: { $0.id == shareID && $0.document === document }) else {
            throw AutomationFailure(status:409,message:"Distraction detection was cancelled or sharing changed.")
          }
          try preflight(document,allowRemove:true)
        }
      } catch is CancellationError {
        throw AutomationFailure(status:409,message:"Distraction detection was cancelled or its source changed.")
      }
      return .json(state(try removeShare(shareID),document:document))
    }
    if operation == "configureDistractionReview" {
      let opacity = try command.parameters["overlayOpacity"].map { _ in try command.number("overlayOpacity", range: 0...1) }
      let categories = try command.parameters["enabledCategories"].map { value -> Set<RemoveDistractionCategory> in
        guard case .array(let items) = value, items.count <= 6 else {
          throw AutomationFailure(status:400,message:"Provide up to six distraction categories.")
        }
        let requested = try items.map { item -> RemoveDistractionCategory in
          guard case .string(let name) = item, let category = RemoveDistractionCategory(rawValue: name) else {
            throw AutomationFailure(status:400,message:"Unknown distraction category.")
          }
          return category
        }
        let unique = Set(requested)
        guard unique.count == requested.count else { throw AutomationFailure(status:400,message:"Duplicate distraction categories.") }
        return unique
      }
      guard categories != nil || opacity != nil else { throw AutomationFailure(status:400,message:"Specify categories or overlay opacity.") }
      guard store.removeDraft?.distractionReview != nil else { throw AutomationFailure(status:409,message:"Find distractions before configuring the review.") }
      try store.updateGeneralDistractions(categories: categories, opacity: opacity)
      return .json(state(try removeShare(shareID),document:document))
    }
    if operation == "findPeople" {
      let expectedToken = token, expectedGeneration = generation
      let result: RemovePeopleDetection
      do {
        result = try await store.detectRemovePeople { [self] in
          prune()
          guard isRunning, token == expectedToken, generation == expectedGeneration,
            shares.contains(where: { $0.id == shareID && $0.document === document }) else {
            throw AutomationFailure(status:409,message:"Person detection was cancelled or sharing changed.")
          }
          try preflight(document,allowRemove:true)
        }
      } catch is CancellationError {
        throw AutomationFailure(status:409,message:"Person detection was cancelled or its source changed.")
      }
      var response = state(try removeShare(shareID),document:document)
      response["removePeopleResult"] = ["candidates":result.count,"protectedForegroundPeople":result.protectedCount]
      return .json(response)
    }
    if operation == "preview" { return try await previewRemoveMarks(document:document,shareID:shareID) }
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
      if store.removeDraft?.settings.removeAfterEachStroke != true || store.removeDraft?.requiresExplicitApply == true {
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
      guard let pending = store.removeDraft, pending.hasMarks, store.removeSourceMatches(pending) else {
        throw AutomationFailure(status:409,message:"There is no valid pending Remove batch.")
      }
      draft = pending
    }
    try draft.request.validate()
    let prepare = try store.removeWorker(for: draft), request = draft.request, restore = store.removeDraft
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

  private func executeRemoveWires(document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    let store = document.store
    guard store.removeDraft == nil else { throw AutomationFailure(status:409,message:"Apply or clear pending Remove marks first.") }
    guard store.canRemoveWires, let layerID = store.activeLayer?.id else {
      throw AutomationFailure(status:422,message:"Wire removal requires an available RGB raster target.")
    }
    let id = UUID(), settings = store.removeSettings, prepare = store.removeWiresPreparation
    store.removeWiresID = id
    defer { if store.removeWiresID == id { store.removeWiresID = nil } }
    let result: RemoveWiresResult
    do {
      result = try await executePreparedResult(document: document, shareID: shareID, revision: revision(store),
        allowPathTarget: true, validateCommit: {
          guard store.removeWiresID == id else { throw CancellationError() }
        }, prepare: { original in
          let prepared = try prepare(original, layerID, settings)
          return (.regionRetouch(prepared.edit), prepared)
        })
    } catch is CancellationError {
      throw AutomationFailure(status:409,message:"Wire removal was cancelled or its source changed.")
    }
    if result.applied { store.selectedLayerIDs = Set(store.document.activeLayerID.map { [$0] } ?? []) }
    store.removeWiresID = nil
    var response = state(try removeShare(shareID), document: document)
    response["removeWiresResult"] = ["candidateTracks":result.candidateTracks,"applied":result.applied]
    return .json(response)
  }

  private func removeShare(_ id:UUID) throws -> Share {
    guard let share = shares.first(where:{ $0.id == id }) else { throw AutomationFailure(status:409,message:"Sharing ended.") }
    return share
  }
}
