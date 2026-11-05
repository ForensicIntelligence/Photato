import Foundation
import PhotoCraftCore

enum LayerFilterAPI {
  static let command = "layers.filter"
  static let operations = ["configure", "enable", "disable", "find", "isolate", "selectAll", "reset", "cancel"]
  static var configurationSchema: [String: Any] {
    let fields: [String: Any] = [
      "enabled": BrushAPI.flag, "mode": BrushAPI.enumeration(LayerFilterMode.allCases.map(\.rawValue)),
      "kinds": choices(LayerFilterKind.allCases.map(\.rawValue)),
      "name": ["type": "string", "maxLength": 65_535],
      "effect": BrushAPI.enumeration(LayerEffect.Kind.allCases.map(\.rawValue)),
      "blend": BrushAPI.enumeration(["Pass Through"] + BlendMode.allCases.map(\.rawValue)),
      "attribute": BrushAPI.enumeration(LayerFilterAttribute.allCases.map(\.rawValue)),
      "color": ["type": "integer", "enum": LayerColorLabel.allCases.map { Int($0.rawValue) }],
      "smartKinds": choices(LayerFilterSmartKind.allCases.map(\.rawValue)),
      "artboardID": ["type": "string", "maxLength": 36],
    ]
    return BrushAPI.object(fields, required: [])
  }
  static func choices(_ values: [String]) -> [String: Any] {
    ["type": "array", "items": BrushAPI.enumeration(values), "uniqueItems": true, "maxItems": values.count]
  }
  static func schema(_ key: String) -> [String: Any] {
    key == "operation" ? BrushAPI.enumeration(operations) : configurationSchema
  }
  static var stateSchema: [String: Any] {
    BrushAPI.object(["filter": configurationSchema, "canChange": BrushAPI.flag, "isolated": BrushAPI.flag,
      "matchedLayerIDs": LayerLinksAPI.ids, "visibleLayerIDs": LayerLinksAPI.ids,
      "artboardTargetMissing": BrushAPI.flag, "focusRequest": ["type": "integer", "minimum": 0],
      "evaluation": BrushAPI.object(["phase": BrushAPI.enumeration(["idle", "running", "ready", "cancelled", "failed"]),
        "resolved": BrushAPI.flag, "operationID": ["type": ["string", "null"]],
        "candidate": ["oneOf": [configurationSchema, ["type": "null"]]],
        "message": ["type": ["string", "null"]]], required: ["phase", "resolved", "operationID", "candidate", "message"])],
      required: ["filter", "canChange", "isolated", "matchedLayerIDs", "visibleLayerIDs", "artboardTargetMissing", "focusRequest", "evaluation"])
  }
  static var capabilities: [String: Any] { [
    "command": command, "operations": operations, "configurationSchema": configurationSchema, "stateSchema": stateSchema,
    "native": "Document-local Layers filter with nine modes, multi-kind OR matching, multi-Smart-Object OR matching, enable switch, Select > Find Layers and Select > Isolate Layers. Find retains the factory Option-Shift-Command-F shortcut; Isolate has no factory shortcut.",
    "matching": "Kind uses native content semantics, including specific adjustments and fill layers; Smart Objects are distinct from cached raster pixels. Attribute predicates inspect the layer's own visible/link/clipping/protection/mask/style metadata. Effect presence includes disabled effects. Artboards include their descendants. Selected tracks current layer selection. Active criteria reveal matches through collapsed groups without changing their disclosure metadata; a renaming row stays exposed.",
    "state": "Changes are editor-local presentation state: no document sample, Undo/Redo, dirty notification, render or recorded Action change. Filtered-out selection is cleared, so archive view-selection metadata can change. Filtered Shift ranges and selectAll use visible matches; selectAll excludes Background from its explicit selection set and includes hidden layers when unfiltered. Changing criteria never auto-selects another row. Empty/NotEmpty scans immutable stored alpha off the main actor, with session/lifecycle/admission guards, cancellation and derived refresh. Cached membership is generation-bound; pending state is explicit. Opacity, visibility, masks and styles do not make pixel content empty. Childless groups are not empty; transparent Smart Object caches are empty without reading source files. Retained per editor when dock/floating views change; resets on a different document identity. Filter state/selection/disclosure/known link-status changes affect API revision.",
    "adobe": "The pinned published v2 contract has no Layers-panel filter, Find Layers or Isolate view-state operation. This is a Photato interface; no Adobe endpoint/actionJSON descriptor is invented. Existing image/layer visibility edits are different operations.",
    "remaining": "Group mode and Advanced Blending are observed but not yet implemented. Library-linked artwork is unavailable; remote links are never falsely labeled as library/local. Unknown/unauthorized/checking linked sources are not declared missing or modified. Exact Photoshop defaults, attribute list/predicates, mixed hierarchy/selection/path-tool behavior and physical qualification remain open. No full filtering/L01/Photoshop parity claim.",
  ] }
}

@MainActor extension EditorStore {
  var layerFilterState: [String: Any] {
    let hierarchy = LayerHierarchyIndex(layerPanelDocument), selected = groupSelectionIDs, statuses = layerFilterStatuses
    return ["filter": BrushAPI.json(layerPanelFilter), "canChange": canChangeLayerFilter,
      "isolated": layerFilterIsolated, "focusRequest": layerFilterFocusRequest,
      "evaluation": ["phase": layerContentFilter.phase.rawValue,
        "resolved": layerContentFilter.isResolved(in: self),
        "operationID": layerContentFilter.operationID?.uuidString as Any? ?? NSNull(),
        "candidate": layerContentFilter.candidate.map { BrushAPI.json($0) } as Any? ?? NSNull(),
        "message": layerContentFilter.message as Any? ?? NSNull()],
      "matchedLayerIDs": layerPanelDocument.layers.reversed().filter {
        layerPanelFilter.matches($0, hierarchy: hierarchy, selected: selected, linkedStatus: statuses, emptyLayerIDs: layerContentFilter.resolvedIDs(in: self))
      }.map { $0.id.uuidString }, "visibleLayerIDs": layersInPanel().map { $0.id.uuidString },
      "artboardTargetMissing": !layerPanelFilter.artboardID.isEmpty && !document.layers.contains {
        $0.id.uuidString == layerPanelFilter.artboardID && $0.group?.artboard != nil
      }]
  }
  func applyLayerFilterAPI(_ command: AutomationCommand,
    admission: @escaping @MainActor () throws -> Void = {}) async throws {
    guard canChangeLayerFilter else { throw AutomationFailure(status: 409, message: "Finish the current interaction before changing layer filtering.") }
    let operation = try command.string("operation")
    guard operation == "configure" || command.parameters["filter"] == nil else {
      throw AutomationFailure(status: 400, message: "Only configure accepts a filter patch.")
    }
    switch operation {
    case "configure":
      guard let patch = command.parameters["filter"]?.jsonValue as? [String: Any], !patch.isEmpty,
        let base = BrushAPI.json(layerPanelFilter) as? [String: Any] else {
        throw AutomationFailure(status: 400, message: "Provide a nonempty filter patch.")
      }
      var candidate: LayerPanelFilter
      do {
        candidate = try JSONDecoder().decode(LayerPanelFilter.self,
          from: JSONSerialization.data(withJSONObject: base.merging(patch) { _, value in value }))
      } catch { throw AutomationFailure(status: 400, message: "Invalid filter patch: \(error.localizedDescription)") }
      if let identifier = UUID(uuidString: candidate.artboardID) { candidate.artboardID = identifier.uuidString }
      if !candidate.artboardID.isEmpty && UUID(uuidString: candidate.artboardID) == nil {
        throw AutomationFailure(status: 400, message: "Invalid artboard UUID.")
      }
      if candidate.artboardID != layerPanelFilter.artboardID, !candidate.artboardID.isEmpty,
        !document.layers.contains(where: { $0.id.uuidString == candidate.artboardID && $0.group?.artboard != nil }) {
        throw AutomationFailure(status: 404, message: "Filter artboard not found.")
      }
      do { try candidate.validate() }
      catch CraftError.invalid(let message) { throw AutomationFailure(status: 400, message: message) }
      try await applyEvaluatedLayerFilter(candidate, admission: admission)
    case "enable":
      var candidate = layerPanelFilter; candidate.enabled = true
      try await applyEvaluatedLayerFilter(candidate, admission: admission)
    case "disable": editLayerFilter { $0.enabled = false }
    case "find": findLayers()
    case "isolate":
      guard layerFilterIsolated || !groupSelectionIDs.isEmpty else {
        throw AutomationFailure(status: 422, message: "Select layers to isolate in the panel.")
      }
      toggleLayerIsolation()
    case "selectAll": selectAllLayers()
    case "reset": try setLayerFilter(LayerPanelFilter())
    case "cancel": layerContentFilter.cancel()
    default: throw AutomationFailure(status: 400, message: "Unknown layer filter operation.")
    }
  }
  func applyEvaluatedLayerFilter(_ candidate: LayerPanelFilter,
    admission: @escaping @MainActor () throws -> Void = {}) async throws {
    if candidate.requiresContentEvaluation {
      let task = layerContentFilter.start(candidate, in: self, admission: admission)
      let accepted = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
      guard accepted else { throw AutomationFailure(status: 409, message: "Layer content filtering was cancelled, changed or sharing was revoked.") }
    } else { try admission(); try setLayerFilter(candidate) }
  }

}
