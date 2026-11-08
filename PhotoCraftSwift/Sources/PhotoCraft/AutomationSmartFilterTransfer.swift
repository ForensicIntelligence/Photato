import Foundation
import PhotoCraftCore

enum SmartFilterTransferAPI {
  static let name = "smartFilter.transfer"
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "sourceLayerID", "targetLayerID": return ["type":"string", "format":"uuid"]
    case "part": return ["type":"string", "enum":SmartFilterTransferRequest.Part.allCases.map(\.rawValue)]
    default: return ["type":"boolean"]
    }
  }
  static var capabilities: [String: Any] {
    ["command":name,
      "parameterSchema":AutomationCommand.definitions.first(where:{$0.name == name})!.schema,
      "parts":SmartFilterTransferRequest.Part.allCases.map(\.rawValue),
      "native":"Drag the Smart Filters label or mask thumbnail to a different Smart Object. Plain drag moves; Option at drop copies. Existing single-filter copy/reorder is unchanged.",
      "stack":"Append the entire source program above existing destination filters, retaining order and every filter setting. A new destination stack inherits the source mask/properties and enable state; an existing destination keeps its mask/properties and enable state. Copies receive fresh filter IDs; moved collisions are remapped. Move clears the source stack.",
      "mask":"Replace the destination's shared filter mask with exact source samples and document-space properties. Move removes only the source mask. Both layers must have existing stacks; destination filters must be nonempty.",
      "state":"Existing layers[].smartFilters schema, maskTransform, busy/error/revision and history state. One prepared Undo/Redo for both layers; semantic Actions58. Native89 unchanged.",
      "authorization":"Same explicitly shared RGB document, distinct Smart Object layers and current document revision. Copy may read a locked source; move requires both layers unlocked. Cancellation, stale source/session/generation, revoked sharing/token, capacity, unresolved destination preview and filter applicability failures reject the entire edit.",
      "limits":"Same-document transfers, existing32-filter/program/source/renderer budgets and supported filter contexts. Whole-stack Lens Blur transfer unavailable. Cross-document and full non-RGB/physical/placement/merge/default/output/platform/60fps qualification remain open.",
      "adobe":"No dedicated transfer endpoint in the pinned Firefly v2 contract. No Adobe descriptor/runtime/plugin compatibility invented."]
  }
}

extension AutomationCommand {
  func smartFilterTransferRequest() throws -> SmartFilterTransferRequest {
    guard let source = UUID(uuidString: try string("sourceLayerID")),
      let target = UUID(uuidString: try string("targetLayerID")),
      let part = SmartFilterTransferRequest.Part(rawValue: try string("part")),
      case .bool(let copy) = parameters["copy"] else {
      throw AutomationFailure(status:400, message:"Provide source/target layer UUIDs, stack or mask part, and a boolean copy flag.")
    }
    return .init(sourceLayerID:source, targetLayerID:target, part:part, copy:copy)
  }
}
