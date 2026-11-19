import Foundation
import PhotoCraftCore

enum LayerMergeAPI {
  static let operations = ["down", "clippingMask", "selected", "visible", "stampSelected", "stampVisible"]
  static var stateSchema: [String: Any] {
    var properties = Dictionary(uniqueKeysWithValues: operations.map { ($0, BrushAPI.flag) })
    properties["selectedLayerIDs"] = ["type": "array", "items": ["type": "string", "format": "uuid"]]
    return BrushAPI.object(properties, required: operations + ["selectedLayerIDs"])
  }
  static var capabilities:[String:Any] {[
    "command":"layer.merge","stateSchema":stateSchema,
    "behavior":"Source-bound native RGB composition. Merge Clipping Mask retains its base and merges consecutive clipped rasters. Stamp creates a raster directly above the active or top selected layer and preserves the source layers. Both workflows preserve transparency and document state with one Undo, cancellation and stale-commit protection. Sparse stamping visits the contributing raster regions for eligible translated Normal-layer stacks and groups.",
    "limitations":"Numerical, palette, ink and temporal composition remain open. Destructive merges retain their existing hierarchy restrictions. Selected stamping requires complete clipping bases. Exact Photoshop backdrop, effects, interpolation, bounds, platform and performance qualification is open.",
    "adobe":"Supported mergeLayersNew and mergeVisible ActionJSON events share the compositor on isolated resource jobs. A single clipping base selected for mergeLayersNew requests Merge Clipping Mask. A true duplicate flag requests stamping."]}
}
extension EditorStore {
  var layerMergeState: [String: Any] {
    ["down": canMerge(.down), "clippingMask": canMerge(.clippingMask), "selected": canMerge(.selected), "visible": canMerge(.visible),
     "stampSelected": canMerge(.stampSelected), "stampVisible": canMerge(.stampVisible),
     "selectedLayerIDs": clipboardLayerIDs.sorted { $0.uuidString < $1.uuidString }.map(\.uuidString)]
  }
}
