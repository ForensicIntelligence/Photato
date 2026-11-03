import Foundation
import PhotoCraftCore

enum LayerMergeAPI {
  static var stateSchema:[String:Any] {BrushAPI.object(["down":BrushAPI.flag,"selected":BrushAPI.flag,"visible":BrushAPI.flag,"selectedLayerIDs":["type":"array","items":["type":"string","format":"uuid"]]],required:["down","selected","visible","selectedLayerIDs"])}
  static var capabilities:[String:Any] {[
    "command":"layer.merge","stateSchema":stateSchema,
    "behavior":"Shared source-bound native RGB compositor; text, shape, fills, masks, transforms, resolved Smart Objects, effects, groups and complete clipping bases. Preserve transparency, unmerged layers and document-owned state. One Undo, cancellation, stale/revocation protection. Dense/paged renderer budgets apply; no fixed 4MP merge ceiling.",
    "limitations":"Numerical/palette/ink/temporal composition, cross-parent selections, hidden descendants inside visible merged groups and clipped artwork without its selected base remain unavailable. Exact Photoshop backdrop/effects/interpolation/bounds/platform/performance qualification is open.",
    "adobe":"Existing documented mergeLayersNew/Mrg2 and mergeVisible/MrgV actionJSON events share the compositor on isolated resource jobs; no new route or proprietary service equivalence."]}
}
extension EditorStore {
  var layerMergeState:[String:Any] {["down":canMerge(.down),"selected":canMerge(.selected),"visible":canMerge(.visible),"selectedLayerIDs":clipboardLayerIDs.sorted{$0.uuidString<$1.uuidString}.map(\.uuidString)]}
}
