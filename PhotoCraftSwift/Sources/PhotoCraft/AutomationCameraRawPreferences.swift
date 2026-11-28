import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension AutomationService {
  static let cameraRawPreferencesPath = "/v1/preferences/camera-raw"

  private var cameraRawPreferencesState: [String: Any] {
    let preferences = controller.cameraRawPreferences
    return [
      "revision": preferences.revision.uuidString,
      "dngStorage": preferences.dngStorage.rawValue,
      "openAsSmartObject": preferences.openAsSmartObject,
      "workflow": preferences.workflowOutput.apiState,
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
      Set(fields.keys).isSubset(of: ["revision", "dngStorage", "openAsSmartObject", "workflow"]),
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
    let workflow = try fields["workflow"].map { try RawWorkflowOutput.apiValue($0.jsonValue) }
    let preferences = controller.cameraRawPreferences
    guard preferences.revision == revision else {
      throw AutomationFailure(status: 409, message: "Camera Raw preferences changed. Read their latest revision.")
    }
    if let storage { preferences.dngStorage = storage }
    if let openAsSmartObject { preferences.openAsSmartObject = openAsSmartObject }
    if let workflow { preferences.workflowOutput = workflow }
    return .json(cameraRawPreferencesState)
  }

  static var cameraRawPreferencesCapabilities: [String: Any] {
    let fields: [String: [String: Any]] = [
      "revision": ["type": "string", "format": "uuid"],
      "dngStorage": ["type": "string", "enum": RawDNGSettingsStorage.allCases.map(\.rawValue)],
      "openAsSmartObject": BrushAPI.flag,
      "workflow": RawWorkflowOutput.apiSchema,
    ]
    var stateFields = fields
    stateFields["canUpdate"] = BrushAPI.flag
    return [
      "path": cameraRawPreferencesPath,
      "readMethod": "GET",
      "updateMethod": "POST",
      "default": ["dngStorage": RawDNGSettingsStorage.embedXMP.rawValue, "openAsSmartObject": false, "workflow": [String: Any]()],
      "stateSchema": BrushAPI.object(stateFields, required: stateFields.keys.sorted()),
      "updateSchema": BrushAPI.object(fields, required: ["revision"]).merging(["minProperties": 2]) { _, new in new },
      "nativeMenu": "Photato > Settings… > Camera Raw…",
      "permission": "Allow Photoshop file preference changes in the native API window.",
      "scope": "Sets desktop opening mode, output options and storage policy. The selected storage policy stays attached to each open source. Uploads default to object.",
    ]
  }
}

extension RawWorkflowOutput {
  static let header = "x-photato-raw-workflow"
  static let maximumHeaderBytes = 4_096

  var apiState: [String: Any] {
    var value: [String: Any] = [:]
    if let profile { value["profile"] = profile.rawValue }
    if let depth { value["depth"] = depth.rawValue }
    if let pixelsPerInch { value["pixelsPerInch"] = pixelsPerInch }
    if let resize {
      var dimensions: [String: Any] = ["mode": resize.mode.rawValue, "value": resize.value,
        "dontEnlarge": resize.dontEnlarge]
      if let second = resize.secondValue { dimensions["secondValue"] = second }
      value["resize"] = dimensions
    }
    return value
  }

  static var apiSchema: [String: Any] {
    let resizeFields: [String: Any] = [
      "mode": BrushAPI.enumeration(Resize.Mode.allCases.map(\.rawValue)),
      "value": ["type": "number", "exclusiveMinimum": 0],
      "secondValue": ["type": "integer", "minimum": 1, "maximum": 300_000],
      "dontEnlarge": BrushAPI.flag,
    ]
    return BrushAPI.object([
      "profile": BrushAPI.enumeration(Profile.allCases.map(\.rawValue)),
      "depth": BrushAPI.enumeration([PixelDepth.u8.rawValue, PixelDepth.u16.rawValue]),
      "pixelsPerInch": ["type": "number", "minimum": 1, "maximum": 100_000],
      "resize": BrushAPI.object(resizeFields, required: ["mode", "value", "dontEnlarge"]),
    ])
  }

  static func apiValue(_ raw: Any) throws -> RawWorkflowOutput {
    guard let fields = raw as? [String: Any],
      Set(fields.keys).isSubset(of: ["profile", "depth", "pixelsPerInch", "resize"]),
      fields.values.allSatisfy({ !($0 is NSNull) }) else {
      throw AutomationFailure(status: 400, message: "Provide a RAW workflow object with supported fields.")
    }
    if let resize = fields["resize"] {
      let keys = ["mode", "value", "secondValue", "dontEnlarge"]
      guard let settings = resize as? [String: Any], Set(settings.keys).isSubset(of: keys),
        settings.values.allSatisfy({ !($0 is NSNull) }) else {
        throw AutomationFailure(status: 400, message: "Provide supported RAW resize fields.")
      }
    }
    do {
      let result = try JSONDecoder().decode(RawWorkflowOutput.self,
        from: JSONSerialization.data(withJSONObject: fields))
      try result.validate()
      return result
    } catch {
      throw AutomationFailure(status: 400, message: "Invalid Camera Raw output settings. Check profile, depth, resolution and resize values.")
    }
  }

  static func headerValue(_ value: String) throws -> RawWorkflowOutput {
    guard value.utf8.count <= maximumHeaderBytes,
      let bytes = Data(base64Encoded: value),
      let raw = try? JSONSerialization.jsonObject(with: bytes) else {
      throw AutomationFailure(status: 400, message: "X-Photato-Raw-Workflow must contain a base64-encoded JSON object.")
    }
    return try apiValue(raw)
  }
}
