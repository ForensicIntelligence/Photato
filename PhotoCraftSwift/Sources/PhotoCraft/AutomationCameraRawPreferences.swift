import Foundation
import PhotoCraftImaging

extension AutomationService {
  static let cameraRawPreferencesPath = "/v1/preferences/camera-raw"

  private var cameraRawPreferencesState: [String: Any] {
    let preferences = controller.cameraRawPreferences
    return [
      "revision": preferences.revision.uuidString,
      "dngStorage": preferences.dngStorage.rawValue,
      "canUpdate": photoshopPreferenceChangesEnabled,
    ]
  }

  func handleCameraRawPreferences(_ request: AutomationRequest) throws -> AutomationResponse? {
    guard request.path == Self.cameraRawPreferencesPath else { return nil }
    if request.method == "GET" { return .json(cameraRawPreferencesState) }
    guard request.method == "POST" else {
      throw AutomationFailure(status: 405, message: "Use GET or POST for Camera Raw preferences.")
    }
    guard photoshopPreferenceChangesEnabled else {
      throw AutomationFailure(status: 403, message: "Allow Photoshop file preference changes in the native API window first.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    guard request.body.count <= 4096,
      let fields = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      fields.count == 2,
      case .string(let revisionText) = fields["revision"], let revision = UUID(uuidString: revisionText),
      case .string(let storageText) = fields["dngStorage"], let storage = RawDNGSettingsStorage(rawValue: storageText) else {
      throw AutomationFailure(status: 400, message: "Provide a revision UUID and a supported dngStorage value.")
    }
    let preferences = controller.cameraRawPreferences
    guard preferences.revision == revision else {
      throw AutomationFailure(status: 409, message: "Camera Raw preferences changed. Read their latest revision.")
    }
    preferences.dngStorage = storage
    return .json(cameraRawPreferencesState)
  }

  static var cameraRawPreferencesCapabilities: [String: Any] {
    let fields: [String: [String: Any]] = [
      "revision": ["type": "string", "format": "uuid"],
      "dngStorage": ["type": "string", "enum": RawDNGSettingsStorage.allCases.map(\.rawValue)],
    ]
    var stateFields = fields
    stateFields["canUpdate"] = BrushAPI.flag
    return [
      "path": cameraRawPreferencesPath,
      "readMethod": "GET",
      "updateMethod": "POST",
      "default": ["dngStorage": RawDNGSettingsStorage.embedXMP.rawValue],
      "stateSchema": BrushAPI.object(stateFields, required: stateFields.keys.sorted()),
      "updateSchema": BrushAPI.object(fields, required: fields.keys.sorted()),
      "nativeMenu": "Photato > Settings… > Camera Raw…",
      "permission": "Allow Photoshop file preference changes in the native API window.",
      "scope": "Persistent DNG storage policy for future local opens. The selected policy stays attached to each open source.",
    ]
  }
}
