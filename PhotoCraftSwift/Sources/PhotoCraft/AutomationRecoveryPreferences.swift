import Foundation

extension AutomationService {
  var recoveryPreferencesState: [String: Any] {
    let preferences = controller.recoveryPreferences
    return [
      "revision": preferences.revision.uuidString,
      "enabled": preferences.value.enabled,
      "intervalMinutes": preferences.value.intervalMinutes,
      "effectiveIntervalSeconds": controller.autosavingDelay,
      "canUpdate": preferenceChangesEnabled && !controller.recoveryPreferencesBusy
        && preferences.loadError == nil,
      "isBusy": controller.recoveryPreferencesBusy,
      "loadError": preferences.loadError as Any? ?? NSNull(),
    ]
  }
  func handleRecoveryPreferences(_ request: AutomationRequest) throws -> AutomationResponse? {
    guard request.path == "/v1/preferences/recovery" else { return nil }
    if request.method == "GET" { return .json(recoveryPreferencesState) }
    guard request.method == "POST" else {
      throw AutomationFailure(status: 404, message: "Unknown recovery preferences operation.")
    }
    guard preferenceChangesEnabled else {
      throw AutomationFailure(
        status: 403, message: "Allow recovery preference changes in the native API window first.")
    }
    guard
      request.headers["content-type"]?.lowercased().split(separator: ";").first
        == "application/json"
    else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    let values: [String: AutomationValue]
    do {
      values = try JSONDecoder().decode([String: AutomationValue].self, from: request.body)
    } catch {
      throw AutomationFailure(status: 400, message: "Expected a JSON recovery preferences object.")
    }
    guard Set(values.keys) == ["revision", "enabled", "intervalMinutes"],
      case .string(let revision) = values["revision"], let expected = UUID(uuidString: revision),
      case .bool(let enabled) = values["enabled"],
      case .number(let minutes) = values["intervalMinutes"], minutes.isFinite,
      RecoveryPreferences.intervals.contains(where: { Double($0) == minutes })
    else {
      throw AutomationFailure(
        status: 400,
        message: "Required: revision UUID, enabled boolean and supported intervalMinutes.")
    }
    do {
      var next = controller.recoveryPreferences.value
      next.enabled = enabled
      next.intervalMinutes = Int(minutes)
      try controller.setRecoveryPreferences(next, revision: expected)
    } catch let failure as RecoveryPreferencesFailure {
      throw AutomationFailure(
        status: failure == .unreadable ? 422 : 409, message: failure.localizedDescription)
    } catch {
      throw AutomationFailure(status: 422, message: error.localizedDescription)
    }
    return .json(recoveryPreferencesState)
  }
  static var recoveryPreferencesCapabilities: [String: Any] {
    let boolean: [String: Any] = ["type": "boolean"]
    let revision: [String: Any] = ["type": "string", "format": "uuid"]
    let interval: [String: Any] = ["type": "integer", "enum": RecoveryPreferences.intervals]
    return [
      "path": "/v1/preferences/recovery",
      "readMethod": "GET", "updateMethod": "POST",
      "scope": "Application-wide; independent of document shares, content and Undo history.",
      "default": ["enabled": true, "intervalMinutes": 10],
      "writePermission":
        "Native Allow recovery preference changes toggle; off when the API starts or stops.",
      "completion":
        "Persists the settings before updating the controller timer. Busy file operations reject; settings changes do not delete existing backups or force an immediate backup.",
      "manualSnapshot":
        "document.autosave remains available when automatic recovery is disabled.",
      "storagePolicy":
        "See atomicPersistence for settings-file staging, synchronization and durability limits.",
      "adobe": "No corresponding application-preferences endpoint in the pinned Adobe v2 contract.",
      "updateSchema": [
        "type": "object", "additionalProperties": false,
        "required": ["revision", "enabled", "intervalMinutes"],
        "properties": ["revision": revision, "enabled": boolean, "intervalMinutes": interval],
      ],
      "stateSchema": [
        "type": "object", "additionalProperties": false,
        "required": [
          "revision", "enabled", "intervalMinutes", "effectiveIntervalSeconds", "canUpdate",
          "isBusy",
          "loadError",
        ],
        "properties": [
          "revision": revision, "enabled": boolean, "intervalMinutes": interval,
          "effectiveIntervalSeconds": ["type": "number", "minimum": 0],
          "canUpdate": boolean, "isBusy": boolean, "loadError": ["type": ["string", "null"]],
        ],
      ],
      "errors": [
        "400": "Invalid body, unknown fields, malformed revision or unsupported interval.",
        "401": "Missing or invalid session token.",
        "403": "Native preference-write permission is off.",
        "409": "Stale revision, external settings change or active file operation.",
        "415": "Content-Type must be application/json.",
        "422": "Settings load, validation or persistence failure.",
      ],
    ]
  }
}
