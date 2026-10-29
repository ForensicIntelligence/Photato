import Foundation

extension AutomationService {
  var photoshopFilePreferencesState: [String: Any] {
    let preferences = controller.recoveryPreferences
    return [
      "revision": preferences.revision.uuidString,
      "disablePSDCompression": preferences.value.disablePSDCompression,
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
      Set(fields.keys) == ["revision", "disablePSDCompression"],
      case .string(let revision) = fields["revision"], let expected = UUID(uuidString: revision),
      case .bool(let disabled) = fields["disablePSDCompression"] else {
      throw AutomationFailure(status: 400,
        message: "Required: revision UUID and disablePSDCompression boolean.")
    }
    do {
      var next = controller.recoveryPreferences.value
      next.disablePSDCompression = disabled
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
      "default": ["disablePSDCompression": false],
      "scope": "Persistent application-wide File Handling preference. No document content or Undo changes.",
      "effect": "For RGB16/32 PSD and PSB document Save/Save As/Copy and shared document downloads, omitted layer and composite compression choices resolve to raw when enabled. RGB8 and other formats are unaffected. Explicit per-output choices override each component independently. Disabling restores existing codec defaults for omitted fields.",
      "lifecycle": "Native and API saves remember requested choices, not resolved defaults. Later preference changes affect future default saves. Each output operation snapshots the preference before encoding. Busy native saves/recovery reject preference writes; downloads already encoding keep their snapshot.",
      "jobs": "Stateless Photato and Adobe resource jobs use their own explicit/default output contract and do not inherit application preferences.",
      "storage": "Atomic version3 File Handling archive retains recovery and recent files; reads version1/2 with compression enabled. Older readers reject version3. Stale revision/external changes and unreadable settings reject writes.",
      "adobe": "No desktop application-preference endpoint in the pinned Adobe v2 contract; no Adobe route or field is invented.",
      "limits": "Photato defaultfalse preserves prior output; Photoshop factory defaults, exact dialogs, Maximize Compatibility and whole-file equivalence remain unqualified.",
      "updateSchema": ["type": "object", "additionalProperties": false,
        "required": ["revision", "disablePSDCompression"],
        "properties": ["revision": revision, "disablePSDCompression": boolean]],
      "stateSchema": ["type": "object", "additionalProperties": false,
        "required": ["revision", "disablePSDCompression", "isPersistent", "canUpdate", "isBusy", "loadError"],
        "properties": ["revision": revision, "disablePSDCompression": boolean, "isPersistent": boolean,
          "canUpdate": boolean, "isBusy": boolean, "loadError": ["type": ["string", "null"]]]],
      "errors": ["400": "Invalid fields, boolean or revision", "401": "Authentication",
        "403": "Photoshop preference writes disabled", "404": "Unknown method",
        "409": "Busy/stale/external change", "415": "Content type", "422": "Settings load/write failure"],
    ]
  }
}
