import Foundation
import PhotoCraftCore

enum MaskAllObjectsAPI {
  static var stateSchema: [String: Any] {
    BrushAPI.object(["available": BrushAPI.flag, "busy": BrushAPI.flag], required: ["available", "busy"])
  }
  static var groupsSchema: [String: Any] {
    ["type": "array", "minItems": 1, "maxItems": MaskAllObjectsEdit.maximumObjects,
      "uniqueItems": true, "items": ["type": "string", "format": "uuid"]]
  }
  static var resultSchema: [String: Any] {
    ["type": "object", "required": ["revision", "maskAllObjects", "createdGroupIDs"],
      "properties": ["revision": ["type": "string"], "maskAllObjects": stateSchema, "createdGroupIDs": groupsSchema]]
  }
  static var capabilities: [String: Any] {
    ["command": "layer.maskAllObjects", "onDevice": true, "minimumMacOS": "14.0",
      "provider": "Apple Vision VNGenerateForegroundInstanceMaskRequest; one inference, separate instance masks",
      "maximumMaskTileBytes": 268_435_456, "maximumObjects": MaskAllObjectsEdit.maximumObjects, "maximumAggregateMaskPixels": MaskAllObjectsEdit.maximumMaskPixels,
      "stateSchema": stateSchema, "resultSchema": resultSchema,
      "input": "One raster layer, rendered into canvas coordinates with its mask/transform but without layer effects. A locked source is allowed; its parent must be unlocked. Existing selection does not constrain detection.",
      "output": "Separate empty Pass Through masked groups above the source clipping family, ascending Vision instance order bottom to top. The top group becomes active. Source pixels, masks, hierarchy and document selection are preserved. Add an adjustment inside a group to target its object. One Undo transaction.",
      "limits": "Native8,388,608 canvas pixels/6000 per side/8,000 layers. Shared API4,194,304 canvas pixels/8,000 layers/128MiB. Excess objects or mask budget fail atomically without truncation. No cloud fallback. Actions recording and Adobe actionJSON unsupported. Native masks remain editable and persist in archive32.",
      "parity": "Independent native implementation; no dedicated published Adobe v2 endpoint. Model edges, semantic names, order and full Photoshop equivalence remain unqualified."]
  }
}

extension EditorStore {
  var maskAllObjectsState: [String: Any] { ["available": canMaskAllObjects(), "busy": geometryBusy] }
}
