import Foundation

extension AutomationService {
  static let placementPreferencesPath = "/v1/preferences/placement"
  private static let placementSettingsFields: [String: WritableKeyPath<ArtworkPlacementSettings, Bool>] = [
    "resizeImageDuringPlace": \.resizeImageDuringPlace,
    "skipTransformWhenPlacing": \.skipTransformWhenPlacing,
    "alwaysCreateSmartObjectsWhenPlacing": \.alwaysCreateSmartObjectsWhenPlacing,
  ]

  var placementPreferencesState: [String: Any] {
    let preferences = controller.artworkPlacementPreferences
    var result: [String: Any] = Self.placementSettingsFields.mapValues { preferences.settings[keyPath: $0] }
    result["revision"] = preferences.revision.uuidString
    result["canUpdate"] = placementPreferenceChangesEnabled
    return result
  }

  func handlePlacementPreferences(_ request: AutomationRequest) throws -> AutomationResponse? {
    guard request.path == Self.placementPreferencesPath else { return nil }
    if request.method == "GET" { return .json(placementPreferencesState) }
    guard request.method == "POST" else {
      throw AutomationFailure(status: 405, message: "Use GET or POST for placement preferences.")
    }
    guard placementPreferenceChangesEnabled else {
      throw AutomationFailure(status: 403, message: "Allow placement preference changes in the native API window first.")
    }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    guard request.body.count <= 4096,
      var fields = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      case .string(let value) = fields.removeValue(forKey: "revision"), let revision = UUID(uuidString: value),
      !fields.isEmpty else {
      throw AutomationFailure(status: 400, message: "Provide a revision UUID and one or more placement preference flags.")
    }
    let preferences = controller.artworkPlacementPreferences
    guard preferences.revision == revision else {
      throw AutomationFailure(status: 409, message: "Placement preferences changed. Read their latest revision.")
    }
    var settings = preferences.settings
    for (key, value) in fields {
      guard let path = Self.placementSettingsFields[key], case .bool(let flag) = value else {
        throw AutomationFailure(status: 400, message: "Only the three placement preference flags may be changed.")
      }
      settings[keyPath: path] = flag
    }
    preferences.settings = settings
    return .json(placementPreferencesState)
  }

  static var placementPreferencesCapabilities: [String: Any] {
    let defaults = ArtworkPlacementSettings()
    var properties = placementSettingsFields.mapValues { _ in BrushAPI.flag }
    properties["revision"] = ["type": "string", "format": "uuid"]
    var updateSchema = BrushAPI.object(properties, required: ["revision"])
    updateSchema["minProperties"] = 2
    properties["canUpdate"] = BrushAPI.flag
    return [
      "path": placementPreferencesPath,
      "readMethod": "GET",
      "updateMethod": "POST",
      "default": placementSettingsFields.mapValues { defaults[keyPath: $0] },
      "stateSchema": BrushAPI.object(properties, required: properties.keys.sorted()),
      "updateSchema": updateSchema,
      "nativeMenu": "Photato > Settings… > General…",
      "permission": "Allow placement preference changes in the native API window. Permission resets when the API stops.",
      "scope": "Persistent defaults for future desktop placements. Each placement captures the three flags at the start.",
      "requests": "API placement uses explicit options and retains its existing defaults. Embedded and PDF source requests support rasterize and fit; approved linked placement supports fit and retains the external reference.",
      "adobe": "The published Photoshop v2 contract has no desktop preferences route. Existing Adobe placement jobs are unchanged.",
    ]
  }
}
