import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LayerCompsAPI {
  static let commands: Set<String> = ["layerComps.edit", "layerComps.export", "layerComps.export.cancel"]
  static let operations = ["capture", "update", "apply", "restoreLast", "duplicate", "delete", "reorder", "clear"]
  static let formats = ["photato", "psd", "psb", "png", "jpeg", "tiff", "pdf"]
  static let definitions: [AutomationCommand.Definition] = [
    .init(name: "layerComps.edit", parameters: ["operation": "capture, update, apply, restoreLast, duplicate, delete, reorder or clear", "id": "Comp UUID; optional explicit UUID for capture", "newID": "Optional duplicate UUID", "name": "Comp name", "comment": "Descriptive comment", "visibility": "Record visibility", "position": "Record position", "appearance": "Record opacity, blending and layer styles", "smartObjects": "Record Smart Object source comp selections", "recapture": "Update recorded properties (default true)", "ids": "Delete selection or complete reordered UUID list"], description: "Create and manage saved layer compositions through one native Undo transaction. Shared pixel content is unchanged.", optionalParameters: ["id", "newID", "name", "comment", "visibility", "position", "appearance", "smartObjects", "recapture", "ids"]),
    .init(name: "layerComps.export", parameters: ["format": "photato, psd, psb, png, jpeg, tiff or multipage pdf", "ids": "Selected comp UUIDs; omitted means all", "prefix": "Safe filename prefix", "includeICC": "Embed retained profile in raster outputs"], description: "Download independent comp variations and a manifest as ZIP, or a multipage PDF. Requires transfers; source/history unchanged.", optionalParameters: ["ids", "prefix", "includeICC"]),
    .init(name: "layerComps.export.cancel", parameters: ["operationID": "Active comp export UUID"], description: "Cancel the matching comp export.")
  ]
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "operation": BrushAPI.enumeration(operations)
    case "format": BrushAPI.enumeration(formats)
    case "id", "newID", "operationID": VariablesAPI.uuid
    case "ids": ["type": "array", "maxItems": LayerComps.maximumComps, "uniqueItems": true, "items": VariablesAPI.uuid]
    case "visibility", "position", "appearance", "smartObjects", "recapture", "includeICC": BrushAPI.flag
    case "comment": ["type": "string", "maxLength": 65_536]
    case "prefix": ["type": "string", "minLength": 1, "maxLength": 64]
    default: ["type": "string", "minLength": 1, "maxLength": 1024]
    }
  }
  static func state(_ document: CraftDocument, operationID: UUID? = nil) -> [String: Any] {
    let library = document.layerComps ?? LayerComps()
    return ["sourceCompsCleared": document.clearedSourceLayerComps, "comps": library.comps.map { comp -> [String: Any] in
      ["id": comp.id.uuidString, "name": comp.name, "comment": comp.comment,
       "visibility": comp.options.visibility, "position": comp.options.position, "appearance": comp.options.appearance, "smartObjects": comp.options.recordsSmartObjects,
       "matchesCurrent": comp.matches(document), "missingLayerIDs": comp.missingLayers(in: document).map(\.uuidString), "unavailableSmartObjectLayerIDs": comp.unavailableSmartObjectLayers(in: document).map(\.uuidString)]
    }, "appliedID": library.appliedID?.uuidString as Any? ?? NSNull(), "canRestoreLast": library.lastDocumentState != nil,
      "exportOperationID": operationID?.uuidString as Any? ?? NSNull()]
  }
  static var stateSchema: [String: Any] {
    let fields: [String: Any] = ["id": VariablesAPI.uuid, "name": schema("name"), "comment": schema("comment"),
      "visibility": BrushAPI.flag, "position": BrushAPI.flag, "appearance": BrushAPI.flag, "smartObjects": BrushAPI.flag, "matchesCurrent": BrushAPI.flag,
      "unavailableSmartObjectLayerIDs": ["type": "array", "maxItems": LayerLimits.maximumLayers, "items": VariablesAPI.uuid],
      "missingLayerIDs": ["type": "array", "maxItems": LayerLimits.maximumLayers, "items": VariablesAPI.uuid]]
    return BrushAPI.object(["sourceCompsCleared": BrushAPI.flag, "comps": ["type": "array", "maxItems": LayerComps.maximumComps, "items": BrushAPI.object(fields, required: Array(fields.keys))],
      "appliedID": VariablesAPI.nullableUUID, "canRestoreLast": BrushAPI.flag, "exportOperationID": VariablesAPI.nullableUUID], required: ["sourceCompsCleared", "comps", "appliedID", "canRestoreLast", "exportOperationID"])
  }
  static var capabilities: [String: Any] {
    ["commands": commands.sorted(), "operations": operations, "formats": formats, "nativeArchiveVersion": 82,
     "psdInterchange": "Editable catalogue, visibility/position deltas and basic embedded source-comp selections share PSD/PSB IO. Missing enab values inherit preceding visibility, default true. No-property comps and explicit source-comp clearing use native82; state exposes sourceCompsCleared. Older native opaque comp resources remain intact when a typed library is absent. Unknown/appearance-changing/parent-child records retain explicit loss guards.",
     "properties": "Visibility, integer layer position plus affine translation, opacity/blend mode/fill/style, group Pass Through and opt-in Smart Object source-comp choices. Pixels, text, layer order, masks and transform rotation/scale are shared, not copied.",
     "history": "Desktop and API use the same atomic command/history. Create/update/duplicate/delete/reorder/apply/restore are undoable. Exports use independent immutable snapshots without document/history changes.",
     "warnings": "Deleted recorded layers remain listed as missing; applying restores surviving layers and leaves new layers alone. Export refuses missing-layer comps for explicit review/recapture.",
     "limits": "2048 comps,262144 property records,64MiB metadata; export128MiB total and existing per-format processing limits. API shares retain existing resource limits. No arbitrary server filesystem writes.",
     "remaining": ["PSD appearance variations and parent child-comp records; fractional/group/style-reference geometry and cached-only linked comp descriptors", "Nested linked-source resolution and full geometry/mode conversion semantics", "Docked panel, thumbnails and Photoshop2026 defaults/live/UI/output/platform qualification", "Semantic Actions/ATN/Adobe descriptors"],
     "adobe": "No dedicated Layer Comps route in the pinned Photoshop v2 contract. Existing execute-actions does not advertise comp descriptors; no Adobe endpoint is invented."]
  }
}
extension AutomationCommand {
  func layerCompText(_ key: String) throws -> String {
    guard let value = parameters[key] else { throw AutomationFailure(status:400,message:"Missing Layer Comp text.") }
    return try BrushAPI.merge(value, schema: LayerCompsAPI.schema(key), path: key) as! String
  }
  func layerCompIDs() throws -> [UUID] {
    guard let input = parameters["ids"] else { return [] }
    let values = try BrushAPI.merge(input, schema: LayerCompsAPI.schema("ids"), path: "ids") as! [String]
    return try values.map(VariablesAPI.parseUUID)
  }
  func layerCompCommand(in document: CraftDocument) throws -> Command {
    let operation = try string("operation"), required: Set<String>, optional: Set<String>
    switch operation {
    case "capture": required = ["name"]; optional = ["id", "comment", "visibility", "position", "appearance", "smartObjects"]
    case "update": required = ["id"]; optional = ["name", "comment", "visibility", "position", "appearance", "smartObjects", "recapture"]
    case "apply": required = ["id"]; optional = []
    case "duplicate": required = ["id"]; optional = ["newID"]
    case "delete", "reorder": required = ["ids"]; optional = []
    case "restoreLast", "clear": required = []; optional = []
    default: throw AutomationFailure(status: 400, message: "Unknown Layer Comps operation.")
    }
    let keys = Set(parameters.keys).subtracting(["operation"])
    guard required.isSubset(of: keys), keys.isSubset(of: required.union(optional)) else { throw AutomationFailure(status: 400, message: "Missing or irrelevant Layer Comp parameters.") }
    if operation == "clear" { return .layerComp(.clear) }
    if operation == "restoreLast" { return .layerComp(.restoreLast) }
    if operation == "delete" { return .layerComp(.delete(try layerCompIDs())) }
    if operation == "reorder" { return .layerComp(.reorder(try layerCompIDs())) }
    let id = try parameters["id"].map { _ in try actionUUID("id") } ?? UUID()
    if operation == "apply" { return .layerComp(.apply(id)) }
    if operation == "duplicate" { return .layerComp(.duplicate(id, newID: try parameters["newID"].map { _ in try actionUUID("newID") } ?? UUID())) }
    let existing = document.layerComps?.comps.first { $0.id == id }
    if operation == "update", existing == nil { throw AutomationFailure(status: 404, message: "Layer Comp not found.") }
    let name = try parameters["name"].map { _ in try layerCompText("name") } ?? existing!.name
    let comment = try parameters["comment"].map { _ in try layerCompText("comment") } ?? existing?.comment ?? ""
    let options = try LayerCompOptions(visibility: pathFlag("visibility", existing?.options.visibility ?? true), position: pathFlag("position", existing?.options.position ?? true), appearance: pathFlag("appearance", existing?.options.appearance ?? true), smartObjects: pathFlag("smartObjects", existing?.options.recordsSmartObjects ?? false))
    if operation == "capture" { return .layerComp(.capture(id: id, name: name, comment: comment, options: options)) }
    return .layerComp(.update(id, name: name, comment: comment, options: options, recapture: try pathFlag("recapture", true)))
  }
  func layerCompExportOptions() throws -> LayerCompExportOptions {
    .init(format: try string("format"), ids: try layerCompIDs(), prefix: try parameters["prefix"].map { _ in try string("prefix") } ?? "layer-comp", includeICC: try pathFlag("includeICC", true))
  }
}
extension AutomationService {
  func exportLayerComps(_ command: AutomationCommand, document: CraftNSDocument, shareID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status: 403, message: "Enable document transfers before exporting Layer Comps.") }
    let snapshot = document.store.document, expectedToken = token, transfer = documentTransferGeneration, options = try command.layerCompExportOptions()
    layerCompExportShares.insert(shareID); defer { layerCompExportShares.remove(shareID) }
    let grants = try layerCompGrants(LayerCompSourceFiles.targets(options, document: snapshot), store: document.store)
    if !grants.isEmpty { layerCompFileShares.insert(shareID) }; defer { layerCompFileShares.remove(shareID) }
    let output = try await document.store.encodedLayerComps(options, grants: grants)
    try validateLayerCompGrants(grants, store: document.store)
    prune()
    guard isRunning, token == expectedToken, documentTransfersEnabled, documentTransferGeneration == transfer,
      shares.contains(where: { $0.id == shareID && $0.document === document }), document.closeWorkflowID == nil,
      document.store.document == snapshot, revision(document.store) == command.revision else { throw AutomationFailure(status: 409, message: "Layer Comp export was revoked or its source changed.") }
    return .init(status: 200, contentType: output.contentType, body: output.data)
  }
  func cancelSharedLayerCompExport(_ share: Share) {
    if layerCompExportShares.contains(share.id) { share.document?.store.layerCompExportWorker?.cancel() }
  }
}
