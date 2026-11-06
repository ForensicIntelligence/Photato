import Foundation

extension AutomationService {
  var photoshopFilePreferencesState: [String: Any] {
    let preferences = controller.recoveryPreferences
    return [
      "revision": preferences.revision.uuidString,
      "disablePSDCompression": preferences.value.disablePSDCompression,
      "saveDialogFormats": SaveDialogFormats.ordered(preferences.value.saveDialogFormats).map(\.rawValue),
      "isPersistent": preferences.isPersistent,
      "canUpdate": photoshopPreferenceChangesEnabled && !controller.recoveryPreferencesBusy
        && preferences.loadError == nil,
      "isBusy": controller.recoveryPreferencesBusy,
      "loadError": preferences.loadError == nil ? NSNull()
        : "The File Handling settings file could not be loaded." as Any,
    ]
  }
  func handlePhotoshopFilePreferences(_ request: AutomationRequest) throws -> AutomationResponse? {
    guard request.path == "/v1/preferences/photoshop-file-handling" else { return nil }
    if request.method == "GET" { return .json(photoshopFilePreferencesState) }
    guard request.method == "POST" else {
      throw AutomationFailure(status: 404, message: "Unknown Photoshop file preferences operation.")
    }
    guard photoshopPreferenceChangesEnabled else {
      throw AutomationFailure(status: 403,
        message: "Allow Photoshop file preference changes in the native API window first.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first
      == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    guard let fields = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      Set(fields.keys).isSubset(of: ["revision", "disablePSDCompression", "saveDialogFormats"]), fields.count >= 2,
      case .string(let revision) = fields["revision"], let expected = UUID(uuidString: revision) else {
      throw AutomationFailure(status: 400, message: "Provide a revision UUID and file preference changes.")
    }
    var next = controller.recoveryPreferences.value
    if let value = fields["disablePSDCompression"] {
      guard case .bool(let disabled) = value else {
        throw AutomationFailure(status: 400, message: "disablePSDCompression must be boolean.")
      }
      next.disablePSDCompression = disabled
    }
    if let value = fields["saveDialogFormats"] {
      guard case .array(let values) = value else {
        throw AutomationFailure(status: 400, message: "saveDialogFormats must be an array.")
      }
      let strings = values.compactMap { if case .string(let value) = $0 { return value }; return nil }
      guard strings.count == values.count, let formats = try? SaveDialogFormats.parse(strings) else {
        throw AutomationFailure(status: 400, message: "Choose unique supported save formats.")
      }
      next.saveDialogFormats = formats
    }
    do {
      try controller.setRecoveryPreferences(next, revision: expected)
    } catch let failure as RecoveryPreferencesFailure {
      throw AutomationFailure(status: failure == .unreadable ? 422 : 409,
        message: failure.localizedDescription)
    } catch {
      throw AutomationFailure(status: 422, message: "The File Handling settings could not be saved.")
    }
    return .json(photoshopFilePreferencesState)
  }
  static var photoshopFilePreferencesCapabilities: [String: Any] {
    let revision: [String: Any] = ["type": "string", "format": "uuid"]
    let boolean: [String: Any] = ["type": "boolean"]
    return [
      "path": "/v1/preferences/photoshop-file-handling", "readMethod": "GET", "updateMethod": "POST",
      "writePermission": "Separate native Allow Photoshop file preference changes; off on every API session.",
      "default": ["disablePSDCompression": false, "saveDialogFormats": DocumentIO.Format.allCases.map(\.rawValue)],
      "nativeMenu": SaveDialogFormats.menuPath,
      "saveDialogVisibility": "The saved list filters native Save As and Save a Copy only. Save As also applies existing editable-content eligibility. Explicit API outputs, ordinary Save, recovery, encoder capabilities and output bytes are unaffected. Empty choices persist; native panels explain how to select formats instead of silently restoring a hidden type.",
      "scope": "Persistent application-wide File Handling preference. No document content or Undo changes.",
      "effect": "For RGB16/32 PSD and PSB document Save/Save As/Copy and shared document downloads, omitted layer and composite compression choices resolve to raw when enabled. RGB8 and other formats are unaffected. Explicit per-output choices override each component independently. Disabling restores existing codec defaults for omitted fields.",
      "lifecycle": "Native and API saves remember requested choices, not resolved defaults. Later preference changes affect future default saves. Each output operation snapshots the preference before encoding. Busy native saves/recovery reject preference writes; downloads already encoding keep their snapshot.",
      "jobs": "Stateless Photato and Adobe resource jobs use their own explicit/default output contract and do not inherit application preferences.",
      "storage": "Atomic version4 File Handling archive retains recovery, recent files, compression and the explicit format list. Versions1/2/3 migrate in memory with all supported formats visible; a version4 archive requires the list. Older readers reject version4. Stale revision/external changes and unreadable settings reject writes.",
      "adobe": "No desktop application-preference endpoint in the pinned Adobe v2 contract; no Adobe route or field is invented.",
      "limits": "Photato defaultfalse preserves prior output; Photoshop factory defaults, exact dialogs, Maximize Compatibility and whole-file equivalence remain unqualified.",
      "updateSchema": ["type": "object", "additionalProperties": false,
        "required": ["revision"], "minProperties": 2,
        "properties": ["revision": revision, "disablePSDCompression": boolean, "saveDialogFormats": SaveDialogFormats.schema]],
      "stateSchema": ["type": "object", "additionalProperties": false,
        "required": ["revision", "disablePSDCompression", "saveDialogFormats", "isPersistent", "canUpdate", "isBusy", "loadError"],
        "properties": ["revision": revision, "disablePSDCompression": boolean, "saveDialogFormats": SaveDialogFormats.schema, "isPersistent": boolean,
          "canUpdate": boolean, "isBusy": boolean, "loadError": ["type": ["string", "null"]]]],
      "errors": ["400": "Invalid fields, boolean or revision", "401": "Authentication",
        "403": "Photoshop preference writes disabled", "404": "Unknown method",
        "409": "Busy/stale/external change", "415": "Content type", "422": "Settings load/write failure"],
    ]
  }
}
