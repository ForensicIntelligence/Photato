import Foundation
import PhotoCraftImaging

extension AutomationService {
  static let cameraRawPreferencesPath = "/v1/preferences/camera-raw"

  private var cameraRawPreferencesState: [String: Any] {
    let preferences = controller.cameraRawPreferences
    return [
      "revision": preferences.revision.uuidString,
      "dngStorage": preferences.dngStorage.rawValue,
      "openAsSmartObject": preferences.openAsSmartObject,
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
      Set(fields.keys).isSubset(of: ["revision", "dngStorage", "openAsSmartObject"]),
      fields.count >= 2,
      case .string(let revisionText) = fields["revision"], let revision = UUID(uuidString: revisionText) else {
      throw AutomationFailure(status: 400, message: "Provide a revision UUID and at least one Camera Raw preference.")
    }
    var storage: RawDNGSettingsStorage?
    if let value = fields["dngStorage"] {
      guard case .string(let text) = value, let choice = RawDNGSettingsStorage(rawValue: text) else {
        throw AutomationFailure(status: 400, message: "Choose a supported dngStorage value.")
      }
      storage = choice
    }
    var openAsSmartObject: Bool?
    if let value = fields["openAsSmartObject"] {
      guard case .bool(let choice) = value else {
        throw AutomationFailure(status: 400, message: "openAsSmartObject must be a boolean.")
      }
      openAsSmartObject = choice
    }
    let preferences = controller.cameraRawPreferences
    guard preferences.revision == revision else {
      throw AutomationFailure(status: 409, message: "Camera Raw preferences changed. Read their latest revision.")
    }
    if let storage { preferences.dngStorage = storage }
    if let openAsSmartObject { preferences.openAsSmartObject = openAsSmartObject }
    return .json(cameraRawPreferencesState)
  }

  static var cameraRawPreferencesCapabilities: [String: Any] {
    let fields: [String: [String: Any]] = [
      "revision": ["type": "string", "format": "uuid"],
      "dngStorage": ["type": "string", "enum": RawDNGSettingsStorage.allCases.map(\.rawValue)],
      "openAsSmartObject": BrushAPI.flag,
    ]
    var stateFields = fields
    stateFields["canUpdate"] = BrushAPI.flag
    return [
      "path": cameraRawPreferencesPath,
      "readMethod": "GET",
      "updateMethod": "POST",
      "default": ["dngStorage": RawDNGSettingsStorage.embedXMP.rawValue, "openAsSmartObject": false],
      "stateSchema": BrushAPI.object(stateFields, required: stateFields.keys.sorted()),
      "updateSchema": BrushAPI.object(fields, required: ["revision"]).merging(["minProperties": 2]) { _, new in new },
      "nativeMenu": "Photato > Settings… > Camera Raw…",
      "permission": "Allow Photoshop file preference changes in the native API window.",
      "scope": "Sets the desktop opening mode and storage policy. The selected storage policy stays attached to each open source. Uploads default to object.",
    ]
  }
}
