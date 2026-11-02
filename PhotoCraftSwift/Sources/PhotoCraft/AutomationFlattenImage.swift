import Foundation
import PhotoCraftCore

enum FlattenImageAPI {
  static let name = "layer.flatten"
  static var stateSchema: [String:Any] { BrushAPI.object([
    "available":BrushAPI.flag,"confirmationPending":BrushAPI.flag,"hiddenLayerIDs":["type":"array","maxItems":LayerLimits.maximumLayers,"items":["type":"string","format":"uuid"]],
    "requiresHiddenLayerConfirmation":BrushAPI.flag,"reason":["type":["string","null"]]],required:["available","confirmationPending","hiddenLayerIDs","requiresHiddenLayerConfirmation","reason"]) }
  static var capabilities: [String:Any] {[
    "command":name,"stateSchema":stateSchema,"discardHiddenLayersSchema":BrushAPI.flag,
    "behavior":"Render full visible document into one opaque Background over white, discard hidden layers only with explicit approval, ignore pixel selection for composition and retain saved selection/channels/paths/guides/profiles/comps. Shared native transaction, one Undo, cancellation and stale/revocation checks.",
    "contexts":"Ordinary static RGB rich stacks, groups, masks, transforms, type, shapes, effects and resolved Smart artwork use the native compositor. An aligned opaque single-layer native component image preserves numerical source planes without RGB conversion.",
    "limits":"Layered/transparent native components, Indexed/Bitmap/ink and temporal flattening still require their numerical/plate/frame composition paths. Current compositor resource/feature budgets apply. No independent full Photoshop samples/defaults/live/platform/dense/60fps claim.",
    "adobe":"Published v2 execute-actions supports the documented flattenImage actionJSON event through the same compositor; no new route. Native semantic recording requires Actions43; earlier operation minimum versions remain." ] }
}
extension EditorStore {
  var flattenImageState: [String:Any] {
    let hidden = FlattenImageEdit.hiddenLayerIDs(in:document)
    return ["available":canFlattenImage,"confirmationPending":flattenImageConfirmationID != nil,"hiddenLayerIDs":hidden.map(\.uuidString),"requiresHiddenLayerConfirmation":!hidden.isEmpty,
      "reason":FlattenImageEdit.unavailableReason(document) as Any? ?? NSNull()]
  }
}
