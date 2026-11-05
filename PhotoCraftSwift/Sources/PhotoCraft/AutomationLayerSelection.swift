import AppKit
import Foundation
import PhotoCraftCore

enum LayerSelectionAPI {
  static let command = "layers.selection"
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "operation": BrushAPI.enumeration(["select", "all", "none", "linked"])
    case "mode": BrushAPI.enumeration(["replace", "toggle", "range"])
    default: ["type": "string", "format": "uuid", "minLength": 36, "maxLength": 36]
    }
  }
  static var stateSchema: [String: Any] {
    BrushAPI.object(["activeLayerID": ["type": ["string", "null"]],
      "selectedLayerIDs": LayerLinksAPI.ids, "canSelect": BrushAPI.flag,
      "canDeselect": BrushAPI.flag, "canSelectLinked": BrushAPI.flag],
      required: ["activeLayerID", "selectedLayerIDs", "canSelect", "canDeselect", "canSelectLinked"])
  }
  static var capabilities: [String: Any] { ["command": command,
    "operations": ["select", "all", "none", "linked"], "stateSchema": stateSchema,
    "native": "Native single/toggle/filtered-range selection, existing All/Select Linked, Select > Deselect Layers (no factory shortcut), and plain click below the layer rows. Command-clicking the last selected row clears the active layer.",
    "history": "Selection changes no samples or content Undo/Redo/dirty state. Active-layer archive view metadata can change. User Deselect Layers is recorded as a portable Actions49 step; filter-derived deselection remains unrecorded. Mask-only display is refreshed when leaving its owner; auxiliary channel/pixel-selection data remain intact.",
    "adobe": "No panel-selection operation in the pinned published Photoshop v2 contract. No Adobe route or actionJSON event is invented; native portable Actions are not Adobe ATN files.",
    "remaining": "Photoshop multi-selection target ordering, channel/path combinations, All Layers Background-only semantics and current physical/reference validation remain open. Group/Advanced Blending/library/full L01 remain open." ] }
}

@MainActor extension EditorStore {
  var layerSelectionState: [String: Any] {
    let selected = groupSelectionIDs
    return ["activeLayerID": document.activeLayerID?.uuidString as Any? ?? NSNull(),
      "selectedLayerIDs": document.layers.filter { selected.contains($0.id) }.map { $0.id.uuidString },
      "canSelect": canChangeLayerSelection, "canDeselect": canDeselectLayers,
      "canSelectLinked": canSelectLinkedLayers(context: nil)]
  }
  func applyLayerSelectionAPI(_ command: AutomationCommand) throws {
    guard canChangeLayerSelection else { throw AutomationFailure(status: 409, message: "Finish the current interaction before selecting layers.") }
    let operation = try command.string("operation")
    guard operation == "select" || command.parameters["mode"] == nil,
      operation == "select" || operation == "linked" || command.parameters["layerID"] == nil else {
      throw AutomationFailure(status: 400, message: "Selection parameters do not apply to this operation.")
    }
    var id: UUID?
    if let value = command.parameters["layerID"] {
      guard case .string(let text) = value, let parsed = UUID(uuidString: text) else { throw AutomationFailure(status: 400, message: "Invalid layer UUID.") }
      guard document.layers.contains(where: { $0.id == parsed }) else { throw AutomationFailure(status: 404, message: "Layer not found.") }
      id = parsed
    }
    switch operation {
    case "select":
      guard let id else { throw AutomationFailure(status: 400, message: "Provide a layerID to select.") }
      let mode = try command.parameters["mode"].map { _ in try command.string("mode") } ?? "replace"
      select(id, modifiers: mode == "toggle" ? .command : mode == "range" ? .shift : [])
    case "all": selectAllLayers()
    case "none": _ = deselectLayers()
    case "linked":
      guard canSelectLinkedLayers(context: id) else { throw AutomationFailure(status: 422, message: "Choose a linked layer selection.") }
      selectLinkedLayers(context: id)
    default: throw AutomationFailure(status: 400, message: "Unknown layer selection operation.")
    }
  }
}
