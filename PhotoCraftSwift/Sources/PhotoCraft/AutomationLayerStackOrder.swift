import Foundation
import PhotoCraftCore

enum LayerStackOrderAPI {
  static let command = "layers.arrange"
  static func schema(_ key: String) -> [String: Any] {
    key == "operation" ? BrushAPI.enumeration(LayerStackOperation.allCases.map(\.rawValue)) : LayerCollectionTransformAPI.schema("layerIDs")
  }
  static var stateSchema: [String: Any] {
    BrushAPI.object(["selection": LayerLinksAPI.ids,
      "available": BrushAPI.object(Dictionary(uniqueKeysWithValues: LayerStackOperation.allCases.map { ($0.rawValue, BrushAPI.flag) }), required: LayerStackOperation.allCases.map(\.rawValue))], required: ["selection", "available"])
  }
  static var capabilities: [String: Any] { [
    "command": command, "stateSchema": stateSchema,
    "operations": LayerStackOperation.allCases.map(\.rawValue),
    "order": "Native arrays are bottom to top. Selected sibling roots keep relative order when brought to an edge or moved one slot. Reverse exchanges only selected sibling positions. Each parent is independent; complete group subtrees travel together and selected descendants are subsumed by a selected ancestor.",
    "history": "One prepared transaction; no-op requests add no Undo. Preserves active layer, selection, parent IDs, all layer fields, links, source assets, masks, timeline/comps, profiles and numeric pixel samples. Does not expand spatial layer links.",
    "guards": "Distinct existing layer IDs, Background boundary, selected-root and ancestor full locks, source/session/interaction/revision/cancellation/share admission. No rendering or conversion formula change.",
    "recording": "Portable semantic stacking targets require Actions48; prior operations retain their earlier feature minima. Native archive86 unchanged.",
    "adobe": "Published create-composite MoveLayer/MoveOperation placement adapter shares native stack/relocate primitives; resource jobs retain their isolated lifecycle. No relative Arrange actionJSON descriptor or endpoint is invented.",
    "limits": "Exact current Photoshop mixed-parent/lock/clipping/temporal/default and physical-platform qualification remains open. All original L01/filter/isolation/extended-empty scope remains. Existing layer/document/API budgets apply."
  ] }
}

extension AutomationCommand {
  func layerStackOrderOptions() throws -> LayerStackOrderRequest {
    guard let operation = LayerStackOperation(rawValue: try string("operation")) else { throw AutomationFailure(status: 400, message: "Unknown layer arrangement.") }
    return .init(layerIDs: try linkLayerIDs(), operation: operation)
  }
}

@MainActor extension EditorStore {
  var layerStackOrderState: [String: Any] { ["selection": stackSelectionIDs.map(\.uuidString),
    "available": Dictionary(uniqueKeysWithValues: LayerStackOperation.allCases.map { ($0.rawValue, canArrangeLayerStack($0)) })] }
}
