import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ObjectFinderAPI {
  static let commands = ["selection.findObjects", "selection.hoverObject", "selection.selectFoundObject"]
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "refresh", "includeMasks", "hardEdge": return BrushAPI.flag
    case "instanceID": return BrushAPI.number(1,255,integer:true)
    case "mode": return SelectionToolAPI.schema("mode")
    default: return ["type":"string","format":"uuid"]
    }
  }
  static var objectSchema: [String: Any] {
    BrushAPI.object(["instanceID": schema("instanceID"), "bounds": BrushAPI.object([
      "x":BrushAPI.number(0,6000,integer:true),"y":BrushAPI.number(0,6000,integer:true),
      "width":BrushAPI.number(1,6000,integer:true),"height":BrushAPI.number(1,6000,integer:true)],required:["x","y","width","height"])],required:["instanceID","bounds"])
  }
  static var stateSchema: [String: Any] {
    let fields: [String: Any] = ["available":BrushAPI.flag,"enabled":BrushAPI.flag,"busy":BrushAPI.flag,"ready":BrushAPI.flag,
      "cacheID":["anyOf":[["type":"null"],schema("cacheID")]],"hoveredID":["anyOf":[["type":"null"],schema("instanceID")]],
      "error":["anyOf":[["type":"null"],["type":"string"]]],"hardEdge":BrushAPI.flag,"overlayColor":BrushAPI.color,
      "objects":["type":"array","maxItems":64,"items":objectSchema]]
    return BrushAPI.object(fields,required:Array(fields.keys).sorted())
  }
  static var resultSchema: [String: Any] {
    ["type":"object","required":["revision","objectFinder"],"properties":["revision":["type":"string"],"objectFinder":stateSchema,
      "objectMasks":["type":"array","maxItems":64,"items":BrushAPI.object(["instanceID":schema("instanceID"),"width":BrushAPI.number(1,6000,integer:true),"height":BrushAPI.number(1,6000,integer:true),"coverageBase64":["type":"string"]],required:["instanceID","width","height","coverageBase64"])]]]
  }
  static var capabilities: [String: Any] {
    ["commands":commands,"stateSchema":stateSchema,"resultSchema":resultSchema,"onDevice":true,"minimumMacOS":"14.0",
      "configuration":"selection.configure: objectFinderEnabled, hardEdge and finderOverlayColor; sampleAllLayers chooses the source. Native Object Selection uses cached hover/click masks. Rectangle/lasso and legacy point detection remain available when Finder is disabled.",
      "lifecycle":"Cache is tied to source document/layer/sample mode; source edits, layer switches, tool switches, refresh, cancel and document reload/close invalidate it. Selection-only edits reuse masks. Detection/hover do not dirty the document or create history. Selection commits one native Undo and can record frozen coverage in Actions4.",
      "maskEncoding":"findObjects includeMasks=true returns each full-canvas row-major UInt8 mask as base64. No pixels are sent to a cloud provider. At most16,777,216 raw aggregate mask bytes (about22.4MB base64), with the existing64-instance/canvas/tile limits. Responses use the current cacheID; selection/hover require it and reject expired caches.",
      "limits":"Native8,388,608 canvas pixels/6000 per side,64 instances,16,777,216 aggregate mask pixels; shared-document API4,194,304 pixels/8,000 layers/128MiB. One asynchronous hover overlay at a time. Hard Edge uses native128/255 threshold; exact Adobe edges/defaults and semantic instance identity are unqualified.",
      "adobe":"No dedicated Object Finder desktop-hover/selection endpoint in the pinned v2 contract. Auto-crop bounding boxes are a different operation; no unverified route or actionJSON support claimed."]
  }
}

extension EditorStore {
  var objectFinderState: [String: Any] {
    let current = objectFinder.source == objectFinderSource
    let scene = current ? objectFinder.scene : nil
    return ["available":canFindObjects,"enabled":objectFinderEnabled,"busy":current && objectFinder.busy,"ready":scene != nil,
      "cacheID":scene == nil ? NSNull() : objectFinder.cacheID.uuidString as Any,
      "hoveredID":current ? (objectFinder.hoveredID as Any? ?? NSNull()) : NSNull(),
      "error":current ? (objectFinder.error as Any? ?? NSNull()) : NSNull(),"hardEdge":objectFinderHardEdge,"overlayColor":BrushAPI.json(objectFinderColor),
      "objects":scene?.objects.map { ["instanceID":$0.instanceID,"bounds":["x":$0.bounds.x,"y":$0.bounds.y,"width":$0.bounds.width,"height":$0.bounds.height]] } ?? []]
  }
}

extension AutomationService {
  func objectFinderCommand(_ command: AutomationCommand, document: CraftNSDocument, share: Share) async throws -> [String: Any] {
    let store = document.store
    guard store.canFindObjects else { throw AutomationFailure(status:422,message:"Object Finder requires an available RGB canvas up to8,388,608 pixels and6000 per side.") }
    if command.name == "selection.findObjects" {
      let refresh = try command.adjustmentBrushFlag("refresh",false), masks = try command.adjustmentBrushFlag("includeMasks",false)
      let expectedToken = token, lifecycle = store.layerPanelGeneration
      store.requestObjectFinder(force:refresh)
      let identity = store.objectFinder.cacheID, work = store.objectFinder.task
      await withTaskCancellationHandler(operation: { await work?.value }, onCancel: { work?.cancel() })
      try Task.checkCancellation(); prune()
      guard isRunning, token == expectedToken, shares.contains(where: { $0.id == share.id }),
        revision(store) == command.revision, lifecycle == store.layerPanelGeneration,
        store.objectFinder.cacheID == identity, store.objectFinder.source == store.objectFinderSource else {
        throw AutomationFailure(status:409,message:"Object detection was cancelled, changed or sharing was revoked.")
      }
      guard let scene = store.objectFinder.scene else { throw AutomationFailure(status:422,message:store.objectFinder.error ?? "No detected objects are available.") }
      var response = state(share,document:document)
      if masks { response["objectMasks"] = try scene.objects.map { ["instanceID":$0.instanceID,"width":$0.mask.width,"height":$0.mask.height,"coverageBase64":Data(try $0.mask.bytes).base64EncodedString()] } }
      return response
    }
    let cacheID = try command.actionUUID("cacheID")
    guard store.objectFinder.cacheID == cacheID, store.objectFinder.source == store.objectFinderSource,
      let scene = store.objectFinder.scene else { throw AutomationFailure(status:409,message:"Object cache expired. Detect objects again.") }
    let instanceID = try command.parameters["instanceID"].map { _ in Int(try command.number("instanceID",range:1...255)) }
    if let instanceID {
      guard Double(instanceID) == (try command.number("instanceID",range:1...255)) else { throw AutomationFailure(status:400,message:"instanceID must be an integer.") }
      guard scene.objects.contains(where: { $0.instanceID == instanceID }) else { throw AutomationFailure(status:404,message:"Object instance not found.") }
    }
    if command.name == "selection.hoverObject" {
      store.setObjectHover(instanceID)
      return state(share,document:document)
    }
    guard let instanceID else { throw AutomationFailure(status:400,message:"instanceID is required.") }
    let mode = try command.selectionMode(store.selectionMode), hard = try command.adjustmentBrushFlag("hardEdge",store.objectFinderHardEdge)
    try await executePreparedOperation(document:document,shareID:share.id,revision:command.revision,
      validateCommit: { guard store.objectFinder.cacheID == cacheID else { throw AutomationFailure(status:409,message:"Object cache expired during selection.") } }) { _ in
      try scene.command(instanceID:instanceID,mode:mode,hardEdge:hard)
    }
    return state(share,document:document)
  }
}
