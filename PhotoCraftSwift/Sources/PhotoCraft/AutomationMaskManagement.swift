import Foundation
import PhotoCraftCore

enum MaskManagementAPI {
  static let command = "mask.manage"
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "layerID": ["type": "string", "format": "uuid"]
    case "target": ["type": "string", "enum": ManagedMaskTarget.allCases.map(\.rawValue), "default": "layerMask"]
    default: ["type": "string", "enum": ["apply", "delete"]]
    }
  }
  static var stateSchema: [String: Any] {
    BrushAPI.object([
      "footerTarget": ["anyOf": [["type": "null"], schema("target")]],
      "canDeleteFromFooter": BrushAPI.flag, "confirming": BrushAPI.flag,
    ], required: ["footerTarget", "canDeleteFromFooter", "confirming"])
  }
  static var capabilities: [String: Any] {
    ["command": command, "stateSchema": stateSchema,
      "resultSchema": ["type": "object", "required": ["revision", "maskManagement"],
        "properties": ["revision": ["type": "string"], "maskManagement": stateSchema], "additionalProperties": true],
      "targets": ManagedMaskTarget.allCases.map(\.rawValue),
      "operations": ["apply", "delete"],
      "behavior": "Apply supported pixel layer masks; delete pixel, vector or Smart Filter masks. Retains the layer and other masks, one prepared Undo transaction. Explicit API operations do not open native confirmation dialogs.",
      "native": "Layers trash follows the selected mask target, including a final remaining layer. Content selection retains whole-layer deletion. Pixel-mask prompt offers Apply/Delete/Cancel; other masks Delete/Cancel. Option-click deletes the selected target without prompting. Properties trash uses the pixel-mask prompt; explicit menu actions retain their semantics.",
      "guards": "Requires an existing unlocked mask. Applying Smart Object, vector or filter masks is unsupported. Existing busy/stale/revocation/transaction/resource limits apply. Native confirmation blocks API edits and rejects changed document, selection, target, session, generation or attachment.",
      "modifiers": "All16Control/Command/Option/Shift combinations use the same footer target. Only Option bypasses confirmation. Standard native button arrow; canvas tools/cursors unchanged.",
      "adobe": "No dedicated route or new action descriptor in the pinned published Adobe v2 contract; none invented. Existing document serializers/jobs retain supported mask changes.",
      "qualification": "Full mask transforms/clipboard/matting/Photoshop pixel/default/physical/platform/performance acceptance remains open. Historical dialog evidence does not establish current2026alert/default equivalence."]
  }
}

extension AutomationCommand {
  func maskManagementRequest(in document: CraftDocument) throws -> MaskManagementRequest {
    let id = try actionUUID("layerID")
    guard document.layers.contains(where: { $0.id == id }) else { throw AutomationFailure(status: 404, message: "Layer not found.") }
    let target: ManagedMaskTarget
    if parameters["target"] == nil { target = .layerMask }
    else {
      guard let value = ManagedMaskTarget(rawValue: try string("target")) else { throw AutomationFailure(status: 400, message: "Unknown mask target.") }
      target = value
    }
    guard let operation = MaskManagementRequest.Operation(rawValue: try string("operation")) else { throw AutomationFailure(status: 400, message: "Unknown mask operation.") }
    return .init(layerID: id, target: target, operation: operation)
  }
}

@MainActor extension EditorStore {
  var maskManagementState: [String: Any] {
    ["footerTarget": footerMaskTarget?.rawValue as Any? ?? NSNull(),
      "canDeleteFromFooter": canDeleteFromLayerFooter, "confirming": confirmingLayerDeletion]
  }
}
