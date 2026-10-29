import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum InkModeAPI {
  static let commands = ["document.convertDuotone", "document.convertMultichannel", "ink.settings.read"]
  static let edits = ["document.convertDuotone", "document.convertMultichannel"]
  static var identity: [String: Any] { ["type": "string", "format": "uuid", "minLength": 36, "maxLength": 36] }
  static var ink: [String: Any] { BrushAPI.object([
    "id": identity, "name": ["type": "string", "minLength": 1, "maxLength": 1024], "color": BrushAPI.color,
    "curve": ["type": "array", "minItems": 2, "maxItems": 256, "items": BrushAPI.object(["input": BrushAPI.number(), "output": BrushAPI.number()], required: ["input", "output"])]], required: ["name", "color"]) }
  static var settings: [String: Any] { BrushAPI.object([
    "inks": ["type": "array", "minItems": 1, "maxItems": 4, "items": ink],
    "overprints": ["type": "array", "maxItems": 11, "items": BrushAPI.object(["mask": BrushAPI.number(1, 15, integer: true), "color": BrushAPI.color], required: ["mask", "color"])]], required: []) }
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "settings": return settings
    case "mergeVisible": return BrushAPI.flag
    case "plateIDs": return ["type": "array", "minItems": 1, "maxItems": 56, "uniqueItems": true, "items": identity]
    default: return [:]
    }
  }
  static var stateSchema: [String: Any] { BrushAPI.object([
    "duotoneAvailable": BrushAPI.flag, "multichannelAvailable": BrushAPI.flag,
    "requiresMerge": BrushAPI.flag, "workspace": BrushAPI.enumeration(["none", "duotone", "multichannel"]),
    "previewBusy": BrushAPI.flag, "committing": BrushAPI.flag, "inkCount": BrushAPI.number(0, 56, integer: true),
    "editingTargets": InkChannelAPI.targets, "visibleTargets": InkChannelAPI.targets, "channelEditingAvailable": BrushAPI.flag, "channelOptionsOpen": BrushAPI.flag],
    required: ["duotoneAvailable", "multichannelAvailable", "requiresMerge", "workspace", "previewBusy", "committing", "inkCount", "editingTargets", "visibleTargets", "channelEditingAvailable", "channelOptionsOpen"]) }
  static var capabilities: [String: Any] { [
    "commands": commands, "nativeArchive": 48, "actionsVersion": 20, "maximumPixels": InkPlane.maximumPixels,
    "settings": settings, "stateSchema": stateSchema,
    "behavior": "Duotone requires Grayscale8 or an existing Duotone document. Settings change ink names, opaque colors, density curves and preview-only overprints; stored gray samples remain unchanged. Multichannel accepts component8/16 and Duotone; existing ink identities are retained. Complex stacks require explicit mergeVisible; hidden layers are discarded and alpha masks retained. Each conversion is one prepared Undo with busy, stale and revocation checks.",
    "identities": "Omitted Duotone ink IDs and curves receive new UUIDs and straight-line curves. Omitted settings retain an existing Duotone or use Monotone Black. Multichannel plateIDs may be supplied for stable component conversion; otherwise they are generated once. When converting existing inks, their identities must be retained.",
    "resultSchema": BrushAPI.object([
      "mode": BrushAPI.enumeration(["duotone", "multichannel"]), "depth": ["type": "integer", "enum": [8, 16]],
      "settings": ["anyOf": [settings, ["type": "null"]]],
      "plates": ["type": "array", "maxItems": 56, "items": BrushAPI.object(["id": identity, "name": ["type": "string"], "color": BrushAPI.color, "solidity": BrushAPI.number()], required: ["id", "name", "color", "solidity"])],
      "revision": ["type": "string"]], required: ["mode", "depth", "settings", "plates", "revision"]),
    "presets": "Native Duotone settings are JSON using this settings schema, with all ink IDs and curve points included on save/read. Adobe ADO preset import is not implemented.",
    "limits": "Additional ink-channel tools/Actions, editable ink PSD/PSB, print separations and full Adobe conversion descriptors remain unfinished. Exact Photoshop curve/overprint/display behavior and live UI parity remain unqualified. No invented Adobe endpoint."] }
}

extension AutomationCommand {
  func inkModeRequest(in document: CraftDocument) throws -> InkModeRequest {
    var request = InkModeRequest(name == "document.convertDuotone" ? .duotone : .multichannel, document: document)
    request.mergeVisible = try pathFlag("mergeVisible", false)
    if let value = parameters["settings"] {
      guard var object = try BrushAPI.merge(value, schema: InkModeAPI.settings, base: BrushAPI.json(request.settings), path: "ink settings") as? [String: Any] else { throw AutomationFailure(status: 400, message: "Invalid ink settings.") }
      if let inks = object["inks"] as? [[String: Any]] {
        object["inks"] = inks.map { fields in
          var base: [String: Any] = ["id": UUID().uuidString, "curve": [["input": 0, "output": 0], ["input": 1, "output": 1]]]
          for (key, value) in fields { base[key] = value }; return base
        }
      }
      do { request.settings = try JSONDecoder().decode(DuotoneSettings.self, from: JSONSerialization.data(withJSONObject: object)) }
      catch { throw AutomationFailure(status: 400, message: "Invalid ink settings: \(error.localizedDescription)") }
    }
    if let ids = parameters["plateIDs"] {
      let raw = try BrushAPI.merge(ids, schema: InkModeAPI.schema("plateIDs"), base: [])
      do { request.plateIDs = try JSONDecoder().decode([UUID].self, from: JSONSerialization.data(withJSONObject: raw)) }
      catch { throw AutomationFailure(status: 400, message: "Invalid plate identities.") }
    }
    try request.validate(); return request
  }
}

extension EditorStore {
  var inkModeState: [String: Any] {
    let count: Int
    switch document.inkMode { case .duotone(let r): count = r.settings.inks.count; case .multichannel(let r): count = r.plates.count; case nil: count = 0 }
    return ["duotoneAvailable": canBeginInkMode(.duotone), "multichannelAvailable": canBeginInkMode(.multichannel),
      "requiresMerge": InkModeInput.needsMerge(document), "workspace": inkModeWorkspace?.request.kind.rawValue ?? "none",
      "previewBusy": inkModeWorkspace?.rendering ?? false, "committing": inkModeWorkspace?.committing ?? false, "inkCount": count, "editingTargets": effectiveInkTargets.map(\.key), "visibleTargets": document.inkChannelTargets.filter { visibleInkTargets.contains($0) }.map(\.key),
      "channelEditingAvailable": canEditInkChannels, "channelOptionsOpen": inkChannelOptions != nil]
  }
}

extension AutomationService {
  func inkSettings(_ document: CraftNSDocument) throws -> [String: Any] {
    let source = document.store.document
    var settings: Any = NSNull(), plates: [[String: Any]] = []
    switch source.inkMode {
    case .duotone(let r): settings = BrushAPI.json(r.settings)
    case .multichannel(let r): plates = r.plates.map { ["id": $0.id.uuidString, "name": $0.name, "color": BrushAPI.json($0.color), "solidity": $0.solidity] }
    case nil: throw AutomationFailure(status: 422, message: "Ink settings require a Duotone or Multichannel document.")
    }
    return ["mode": source.colorMode.rawValue, "depth": source.bitsPerChannel, "settings": settings, "plates": plates, "revision": revision(document.store)]
  }
}
