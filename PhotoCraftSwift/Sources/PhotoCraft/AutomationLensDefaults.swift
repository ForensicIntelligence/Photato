import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum LensDefaultsAPI {
  static let name = "filter.lens.defaults"
  static var definition: AutomationCommand.Definition {
    .init(name: name, parameters: ["operation": "set or remove", "settings": "Lens Correction settings for set"],
      description: "Save or remove the lens default for the shared document's exact capture metadata. Requires native API preference-change permission. No image/history change; apply returned settings using filter.apply.", optionalParameters: ["settings"])
  }
  static var parameterSchema: [String: Any] {
    var schema = BrushAPI.object(["operation": BrushAPI.enumeration(["set", "remove"]),
      "settings": LensCorrectionSettings.apiSchema], required: ["operation"])
    schema["oneOf"] = [
      BrushAPI.object(["operation": ["const": "set"], "settings": LensCorrectionSettings.apiSchema], required: ["operation", "settings"]),
      BrushAPI.object(["operation": ["const": "remove"]], required: ["operation"]),
    ]; return schema
  }
  static var commandSchema: [String: Any] {
    BrushAPI.object(["command": ["const": name], "revision": ["type": "string", "minLength": 1],
      "parameters": parameterSchema], required: ["command", "revision", "parameters"])
  }
  static var identitySchema: [String: Any] {
    var fields = [String: Any]()
    for key in ["cameraMake", "cameraModel", "lensModel"] { fields[key] = ["type": "string", "minLength": 1, "maxLength": 256] }
    for key in ["focalLength", "fNumber"] { fields[key] = ["type": "number", "exclusiveMinimum": 0] }
    return BrushAPI.object(fields, required: fields.keys.sorted())
  }
  static var stateSchema: [String: Any] {
    func nullable(_ schema: [String: Any]) -> [String: Any] { ["anyOf": [["type": "null"], schema]] }
    let fields: [String: Any] = ["identity": nullable(identitySchema),
      "settings": nullable(LensCorrectionSettings.apiSchema), "previousConversion": nullable(LensCorrectionSettings.apiSchema),
      "hasSavedDefault": BrushAPI.flag, "canSetDefault": BrushAPI.flag,
      "metadataError": ["type": ["string", "null"]], "defaultError": ["type": ["string", "null"]],
      "previousConversionError": ["type": ["string", "null"]]]
    return BrushAPI.object(fields, required: fields.keys.sorted())
  }
  static var capabilities: [String: Any] {
    ["command": name, "parameterSchema": parameterSchema, "stateSchema": stateSchema,
      "state": "lensCorrection.defaults", "applyCommand": "filter.apply",
      "identity": "Exact camera make/model, lens model, focal length in mm and f-number from document ImageIO EXIF/PSD EXIF/XMP. Canonically equivalent Unicode names match; no case folding, numeric interpolation, camera serial or GPS use.",
      "behavior": "Set Lens Default saves the complete explicit Lens Correction settings. New native Lens Correction drafts load a matching default. Settings menu loads Lens Default, Previous Conversion or Default Correction with local history/Cancel. Existing Smart Filter re-edit, Last Filter, Actions and explicit filter.apply payloads remain self-contained and do not acquire later defaults.",
      "persistence": "Shared application preferences, one atomic bounded32KiB file per exact identity,64 cached records without a database entry limit. Default app restores across launches; isolated stores remain memory-only. Previous Conversion changes only after a successfully published lens filter. Cancel/preview/failed/stale/revoked edits and Undo/Redo do not replace it. Corrupt defaults are preserved, removal moves the record to Retired before reuse. A failed save changes neither the default nor document; a post-edit Previous Conversion save failure leaves session recall available and reports a warning.",
      "authorization": "Native API preference-change permission and an idle shared document with a current revision are required for set/remove. No document history or dirty-state changes. Preference changes invalidate revisions of all controller documents. Clients read resolved settings and supply them explicitly to filter.apply for the same editing engine/history/Smart Filter/Actions path.",
      "limits": "Calibrated manufacturer profiles, Adobe lens preset transport, exact Photoshop saved-field/default/matching/session policy and numerical output remain unqualified. Existing filter size/mode/depth limits remain; this does not establish full F05 parity.",
      "adobe": "No corresponding dedicated operation in the pinned Photoshop v2 contract. Lens Correction actionJSON remains explicitly unsupported; no route is invented."]
  }
  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    func value<T: Encodable>(_ v: T?) -> Any {
      v.flatMap { try? JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) } ?? NSNull()
    }
    let identity = store.cameraLensIdentity, library = store.filterRecall.lensDefaults
    let entry = identity.map { library.lookup($0) }
    return ["identity": value(identity), "settings": value(entry?.settings),
      "previousConversion": value(library.previous), "hasSavedDefault": entry?.exists ?? false,
      "canSetDefault": identity != nil && entry?.error == nil,
      "metadataError": store.cameraLensMetadataCache.error as Any? ?? NSNull(),
      "defaultError": entry?.error as Any? ?? NSNull(), "previousConversionError": library.previousError as Any? ?? NSNull()]
  }
  @MainActor static func apply(_ command: AutomationCommand, store: EditorStore) throws {
    let operation = try command.string("operation")
    switch operation {
    case "set":
      guard Set(command.parameters.keys) == ["operation", "settings"], let value = command.parameters["settings"] else {
        throw AutomationFailure(status: 400, message: "Supply operation and settings for set.")
      }
      let object = try BrushAPI.merge(value, schema: LensCorrectionSettings.apiSchema, path: "settings")
      let settings = try LensCorrectionSettings.decodeJSON(JSONSerialization.data(withJSONObject: object))
      try store.setLensDefault(settings)
    case "remove":
      guard Set(command.parameters.keys) == ["operation"] else {
        throw AutomationFailure(status: 400, message: "Remove takes only operation.")
      }
      try store.removeLensDefault()
    default: throw AutomationFailure(status: 400, message: "Choose set or remove.")
    }
  }
}
