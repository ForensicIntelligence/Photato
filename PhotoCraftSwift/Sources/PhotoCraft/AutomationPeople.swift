import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum PeopleAPI {
  static let commands = ["selection.findPeople","selection.hoverPerson","selection.selectPeople"]
  static func schema(_ key: String) -> [String:Any] {
    if ["refresh","includeMasks","includeThumbnails","hardEdge"].contains(key) { return BrushAPI.flag }
    if key == "feature" { return ["type":"string","enum":PeopleFeature.allCases.map(\.rawValue),"default":"wholePerson"] }
    if key == "features" { return ["type":"array","minItems":1,"maxItems":6,"uniqueItems":true,"items":schema("feature")] }
    if key == "instanceIDs" { return ["type":"array","minItems":1,"maxItems":64,"uniqueItems":true,"items":ObjectFinderAPI.schema("instanceID")] }
    return ObjectFinderAPI.schema(key)
  }
  static var stateSchema: [String:Any] {
    let fields: [String:Any] = ["available":BrushAPI.flag,"busy":BrushAPI.flag,"ready":BrushAPI.flag,"pickerOpen":BrushAPI.flag,
      "cacheID":["anyOf":[["type":"null"],schema("cacheID")]],"hoveredID":["anyOf":[["type":"null"],schema("instanceID")]],
      "error":["anyOf":[["type":"null"],["type":"string"]]],"features":schema("features"),"modelAvailable":BrushAPI.flag,
      "featureError":["anyOf":[["type":"null"],["type":"string"]]],"hoveredFeature":schema("feature"),
      "selectedFeatures":["type":"array","maxItems":6,"uniqueItems":true,"items":schema("feature")],
      "selectedIDs":["type":"array","maxItems":64,"uniqueItems":true,"items":schema("instanceID")],
      "people":["type":"array","maxItems":64,"items":ObjectFinderAPI.objectSchema]]
    return BrushAPI.object(fields,required:Array(fields.keys).sorted())
  }
  static var resultSchema: [String:Any] {
    let mask = BrushAPI.object(["instanceID":schema("instanceID"),"width":BrushAPI.number(1,6000,integer:true),"height":BrushAPI.number(1,6000,integer:true),"coverageBase64":["type":"string"],"features":schema("features")],required:["instanceID","width","height","coverageBase64"])
    let thumbnail = BrushAPI.object(["instanceID":schema("instanceID"),"pngBase64":["type":"string"]],required:["instanceID","pngBase64"])
    return ["type":"object","required":["revision","peopleSelection"],"properties":["revision":["type":"string"],"peopleSelection":stateSchema,
      "peopleMasks":["type":"array","maxItems":64,"items":mask],"peopleThumbnails":["type":"array","maxItems":64,"items":thumbnail]]]
  }
  static var capabilities: [String:Any] {
    ["commands":commands,"stateSchema":stateSchema,"resultSchema":resultSchema,"onDevice":true,"minimumMacOS":"14.0","features":PeopleFeature.allCases.map(\.rawValue),
      "unavailableFeatures":["eyebrows","eyes","lips","teeth","nose","beard"],
      "lifecycle":"Same source/layer/sample-mode identity as Object Finder, but a separate person-specific model and cache. Source changes, tool switches, refresh, cancel and document reload/close invalidate IDs. Detection and hover do not edit history. Selection unions chosen people and available feature classes with one Undo and Actions4 coverage; Select and Mask supports manual refinement.",
      "featureModel":"Optional bundled native Core ML model; source Google MediaPipe multiclass256x256 Apache2.0, pinned SHA and reproducible conversion. Available classes: hair/bodySkin/faceSkin/clothes/accessories. Per-person masks intersect class confidence with Vision instance coverage. No proprietary model equality. Missing/corrupt model preserves whole-person selection and exposes featureError. findPeople features affects optional masks; selectPeople features defaults wholePerson; hoverPerson feature defaults wholePerson.",
      "limits":"Native8,388,608 pixels/6000 per side,64 people,16,777,216 aggregate raw mask pixels and padded-tile budget. Shared API4,194,304 pixels/8,000 layers/128MiB. Optional masks are full-canvas row-major UInt8 base64; thumbnails are PNG at most96 pixels per side. Empty detections return a ready empty list.",
      "adobe":"No dedicated Select People endpoint in pinned Photoshop v2. No new Adobe route or proprietary semantic model equivalence claimed."]
  }
}

extension EditorStore {
  var peopleState: [String:Any] {
    let current = peopleWorkspace.source == objectFinderSource, scene = current ? peopleWorkspace.scene:nil
    return ["available":canSelectPeople,"busy":current && peopleWorkspace.busy,"ready":scene != nil,"pickerOpen":peopleWorkspace.presented,
      "cacheID":scene == nil ? NSNull():peopleWorkspace.cacheID.uuidString as Any,
      "hoveredID":current ? (peopleWorkspace.hoveredID as Any? ?? NSNull()):NSNull(),
      "error":current ? (peopleWorkspace.error as Any? ?? NSNull()):NSNull(),"features":scene?.availableFeatures.map(\.rawValue) ?? [PeopleFeature.wholePerson.rawValue],
      "modelAvailable":peopleFeaturesDetector != nil,"featureError":scene?.featureError as Any? ?? NSNull(),
      "hoveredFeature":peopleWorkspace.hoveredFeature.rawValue,"selectedFeatures":peopleWorkspace.selectedFeatures.map(\.rawValue).sorted(),"selectedIDs":peopleWorkspace.selectedIDs.sorted(),
      "people":scene?.people.map{["instanceID":$0.instanceID,"bounds":["x":$0.bounds.x,"y":$0.bounds.y,"width":$0.bounds.width,"height":$0.bounds.height]]} ?? []]
  }
}

extension AutomationService {
  func peopleCommand(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> [String:Any] {
    let store = document.store, workspace = store.peopleWorkspace
    guard store.canSelectPeople else { throw AutomationFailure(status:422,message:"Select People requires an available RGB canvas up to8,388,608 pixels and6000 per side.") }
    if command.name == "selection.findPeople" {
      let refresh = try command.adjustmentBrushFlag("refresh",false), masks = try command.adjustmentBrushFlag("includeMasks",false), thumbnails = try command.adjustmentBrushFlag("includeThumbnails",false)
      let features=try command.peopleFeatures()
      let expectedToken = token, lifecycle = store.layerPanelGeneration
      store.requestPeople(force:refresh)
      let identity = workspace.cacheID, work = workspace.task
      await withTaskCancellationHandler(operation:{await work?.value},onCancel:{work?.cancel()})
      try Task.checkCancellation(); prune()
      guard isRunning, token == expectedToken, shares.contains(where:{$0.id == share.id}), revision(store) == command.revision,
        lifecycle == store.layerPanelGeneration, workspace.cacheID == identity, workspace.source == store.objectFinderSource else {
        throw AutomationFailure(status:409,message:"Person detection was cancelled, changed or sharing was revoked.")
      }
      guard let scene = workspace.scene else { throw AutomationFailure(status:422,message:workspace.error ?? "Person detection did not finish.") }
      var response = state(share,document:document)
      guard features.allSatisfy({scene.availableFeatures.contains($0)}) else {throw AutomationFailure(status:422,message:scene.featureError ?? "Requested person features are unavailable in this build.")}
      if masks { response["peopleMasks"] = try scene.people.map{person in
        let mask=try scene.coverage(instanceIDs:[person.instanceID],hardEdge:false,features:features)
        return ["instanceID":person.instanceID,"width":mask.width,"height":mask.height,"coverageBase64":Data((try mask.bytes)).base64EncodedString(),"features":features.map(\.rawValue)] as [String:Any]
      } }
      if thumbnails { response["peopleThumbnails"] = scene.people.compactMap { person -> [String:Any]? in
        guard let image = scene.thumbnails[person.instanceID], let data = NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:]) else { return nil }
        return ["instanceID":person.instanceID,"pngBase64":data.base64EncodedString()]
      } }
      return response
    }
    let cacheID = try command.actionUUID("cacheID")
    guard workspace.cacheID == cacheID, workspace.source == store.objectFinderSource, let scene = workspace.scene else { throw AutomationFailure(status:409,message:"Person cache expired. Detect people again.") }
    if command.name == "selection.hoverPerson" {
      let value = try command.parameters["instanceID"].map{_ in try command.number("instanceID",range:1...255)}
      if let value {
        guard value.rounded(.towardZero) == value else { throw AutomationFailure(status:400,message:"instanceID must be an integer.") }
        guard scene.people.contains(where:{$0.instanceID == Int(value)}) else { throw AutomationFailure(status:404,message:"Person instance not found.") }
      }
      let feature:PeopleFeature
      if let parameter=command.parameters["feature"] {
        guard case .string(let raw)=parameter,let parsed=PeopleFeature(rawValue:raw) else {throw AutomationFailure(status:400,message:"Invalid person feature.")};feature=parsed
      }else{feature = .wholePerson}
      if value != nil,!scene.availableFeatures.contains(feature){throw AutomationFailure(status:422,message:"Requested person feature is unavailable.")}
      store.hoverPerson(value.map(Int.init),feature:feature); return state(share,document:document)
    }
    guard case .array(let values) = command.parameters["instanceIDs"], !values.isEmpty, values.count <= 64 else { throw AutomationFailure(status:400,message:"instanceIDs must contain1–64 person IDs.") }
    let ids = try values.map { value -> Int in
      guard case .number(let n) = value, n.isFinite, (1...255).contains(n), n.rounded(.towardZero) == n else { throw AutomationFailure(status:400,message:"Person IDs must be integers from1–255.") }
      return Int(n)
    }
    guard Set(ids).count == ids.count else { throw AutomationFailure(status:400,message:"Duplicate person IDs.") }
    guard ids.allSatisfy({id in scene.people.contains{$0.instanceID == id}}) else { throw AutomationFailure(status:404,message:"Person instance not found.") }
    let features=try command.peopleFeatures()
    guard features.allSatisfy({scene.availableFeatures.contains($0)}) else {throw AutomationFailure(status:422,message:scene.featureError ?? "Requested person features are unavailable in this build.")}
    let mode = try command.selectionMode(store.selectionMode), hard = try command.adjustmentBrushFlag("hardEdge",store.objectFinderHardEdge)
    try await executePreparedOperation(document:document,shareID:share.id,revision:command.revision,
      validateCommit:{guard workspace.cacheID == cacheID else {throw AutomationFailure(status:409,message:"Person cache expired during selection.")}}) { _ in
      try scene.command(instanceIDs:ids,mode:mode,hardEdge:hard,features:features)
    }
    workspace.selectedIDs = Set(ids);workspace.selectedFeatures=Set(features)
    return state(share,document:document)
  }
}

extension AutomationCommand {
  func peopleFeatures() throws -> [PeopleFeature] {
    guard let parameter=parameters["features"] else{return [.wholePerson]}
    guard case .array(let values)=parameter,!values.isEmpty,values.count<=6 else{throw AutomationFailure(status:400,message:"features must contain1–6 unique feature names.")}
    let features=try values.map { value -> PeopleFeature in
      guard case .string(let name)=value,let feature=PeopleFeature(rawValue:name) else{throw AutomationFailure(status:400,message:"Invalid person feature.")};return feature
    }
    guard Set(features).count==features.count else{throw AutomationFailure(status:400,message:"Duplicate person features.")}
    return features
  }
}
