import Foundation
import PhotoCraftCore

enum LayerMergeAPI {
  static let operations = ["down", "clippingMask", "selected", "visible", "stampDown", "stampGroup", "stampSelected", "stampVisible"]
  static var stateSchema: [String: Any] {
    var properties = Dictionary(uniqueKeysWithValues: operations.map { ($0, BrushAPI.flag) })
    properties["selectedLayerIDs"] = ["type": "array", "items": ["type": "string", "format": "uuid"]]
    return BrushAPI.object(properties, required: operations + ["selectedLayerIDs"])
  }
  static var capabilities:[String:Any] {[
    "command":"layer.merge","stateSchema":stateSchema,
    "behavior":"Source-bound native RGB composition. Merge Clipping Mask retains its base and merges consecutive clipped rasters. Eligible Multiply, Darken, Lighten, Difference, Linear Dodge (Add), Subtract and Divide clips participate at all RGB depths. Screen clips participate at RGB8 and RGB16. Axis-aligned translated pixel masks on raster clips contribute coverage, Density and Feather through 1000 px while the clipping base retains its editable pixel mask. Feather requests affected raster regions through the native layer-mask sampler, including integer-rounded stages for aligned RGB8 and RGB16 masks. Aligned RGB32 masks also use measured fractional schedules. Exact Photoshop coverage varies with radius, geometry and reference architecture. The saved raster result preserves Blend Clipped Layers as Group and the clipping base blend mode. Merge Down and Stamp Down also accept an eligible pair of adjacent Normal raster clips. Stamp Down and Stamp Group update their existing raster destination while retaining the contributors and selection. Stamp Layers and Stamp Visible create a raster above the active or top selected layer. Both workflows preserve transparency and document state with one Undo, cancellation and stale-commit protection. Sparse stamping visits the contributing raster regions for eligible translated Normal-layer stacks and groups.",
    "limitations":"Numerical, palette, ink and temporal composition remain open. Destructive merges retain their existing hierarchy restrictions. Selected stamping requires complete clipping bases. Exact Photoshop backdrop, effects, interpolation, bounds, platform and performance qualification is open.",
    "adobe":"Supported mergeLayersNew and mergeVisible ActionJSON events share the compositor on isolated resource jobs. A single clipping base selected for mergeLayersNew requests Merge Clipping Mask. A true duplicate flag requests the contextual stamp operation for that selection."]}
}
extension EditorStore {
  var layerMergeState: [String: Any] {
    ["down": canMerge(.down), "clippingMask": canMerge(.clippingMask), "selected": canMerge(.selected), "visible": canMerge(.visible),
     "stampDown": canMerge(.stampDown), "stampGroup": canMerge(.stampGroup),
     "stampSelected": canMerge(.stampSelected), "stampVisible": canMerge(.stampVisible),
     "selectedLayerIDs": clipboardLayerIDs.sorted { $0.uuidString < $1.uuidString }.map(\.uuidString)]
  }
}
