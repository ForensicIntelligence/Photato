import AppKit
import PhotoCraftCore
import PhotoCraftImaging

enum ColorSettingsAPI {
  static let path = "/v1/preferences/color-settings"
  static let fields: Set<String> = ["workingRGB", "workingCMYK", "workingGray", "intent", "blackPointCompensation"]
  static var policyFields: [String: WritableKeyPath<ColorSettings, ColorSettings.Policy>] { ["rgbPolicy": \.rgbPolicy, "cmykPolicy": \.cmykPolicy, "grayPolicy": \.grayPolicy] }
  static var alertFields: [String: WritableKeyPath<ColorSettings, Bool>] { ["askMismatchOpening": \.askMismatchOpening, "askMismatchPasting": \.askMismatchPasting, "askMissingOpening": \.askMissingOpening] }
  static let profileFields: [(String, DocumentColorMode)] = [("workingRGB", .rgb), ("workingCMYK", .cmyk), ("workingGray", .grayscale)]
  static func json(_ settings: ColorSettings) -> [String: Any] {
    var result: [String: Any] = ["intent": settings.intent.rawValue, "blackPointCompensation": settings.blackPointCompensation]
    for (key, mode) in profileFields { result[key] = settings.storedProfile(mode)?.base64EncodedString() as Any? ?? NSNull() }
    for (key, path) in policyFields { result[key] = settings[keyPath: path].rawValue }
    for (key, path) in alertFields { result[key] = settings[keyPath: path] }
    return result
  }
  static func decode(_ value: AutomationValue?, base: ColorSettings = .init()) throws -> ColorSettings {
    guard case .object(let fields) = value, Self.fields.isSubset(of: Set(fields.keys)),
      Set(fields.keys).isSubset(of: Self.fields.union(policyFields.keys).union(alertFields.keys)),
      case .string(let raw) = fields["intent"], let intent = ModeRenderingIntent(rawValue: raw),
      case .bool(let bpc) = fields["blackPointCompensation"] else {
      throw AutomationFailure(status: 400, message: "Provide all five Color Settings fields with a valid intent and boolean.")
    }
    var result = base; result.intent = intent; result.blackPointCompensation = bpc
    for (key, mode) in profileFields {
      let data: Data?
      switch fields[key] {
      case .null: data = nil
      case .string(let text):
        guard text.count <= 5_592_408, let bytes = Data(base64Encoded: text) else {
          throw AutomationFailure(status: 400, message: "Invalid working profile encoding.")
        }
        data = bytes
      default: throw AutomationFailure(status: 400, message: "A working profile must be ICC base64 or null for the Photato default.")
      }
      do { try result.setProfile(data, for: mode) }
      catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    }
    for (key, path) in policyFields where fields[key] != nil {
      guard case .string(let text) = fields[key], let value = ColorSettings.Policy(rawValue: text) else {
        throw AutomationFailure(status: 400, message: "Invalid color-management policy.")
      }
      result[keyPath: path] = value
    }
    for (key, path) in alertFields where fields[key] != nil {
      guard case .bool(let value) = fields[key] else { throw AutomationFailure(status: 400, message: "Profile alerts require booleans.") }
      result[keyPath: path] = value
    }
    return result
  }
  static var settingsSchema: [String: Any] {
    var properties: [String: Any] = ["intent": BrushAPI.enumeration(ModeRenderingIntent.allCases.map(\.rawValue)), "blackPointCompensation": BrushAPI.flag]
    for (key, _) in profileFields { properties[key] = ["type": ["string", "null"], "contentEncoding": "base64", "maxLength": 5_592_408] }
    for key in policyFields.keys { properties[key] = BrushAPI.enumeration(ColorSettings.Policy.allCases.map(\.rawValue)) }
    for key in alertFields.keys { properties[key] = BrushAPI.flag }
    return BrushAPI.object(properties, required: fields.sorted())
  }
  static var capabilities: [String: Any] {
    ["path": path, "readMethod": "GET", "updateMethod": "POST", "maximumBodyBytes": ColorSettings.maximumArchiveBytes,
      "writePermission": "Separate native Allow Color Settings changes; off on every API session.",
      "settingsSchema": settingsSchema,
      "updateSchema": BrushAPI.object(["revision": ["type": "string", "format": "uuid"], "settings": settingsSchema], required: ["revision", "settings"]),
      "stateSchema": BrushAPI.object(["revision": ["type": "string", "format": "uuid"], "settings": settingsSchema,
        "isPersistent": BrushAPI.flag, "canUpdate": BrushAPI.flag, "loadError": ["type": ["string", "null"]]],
        required: ["revision", "settings", "isPersistent", "canUpdate", "loadError"]),
      "scope": "Atomic persistent application settings. No direct document content/history change. Legacy version1 settings load with preserve-embedded policies and alerts off; writes use version2. Omitted policy/alert fields in older five-field updates retain their current values. Native New Document snapshots working spaces. Mode changes use the destination working space; precision-only changes retain the document profile. Assign Profile offers the working profile; untagging uses it as numerical interpretation. Convert to Profile defaults to working space, intent and black point compensation. Shared document API operations snapshot the same defaults; explicit parameters override them.",
      "defaults": "Null profiles resolve to sRGB, Generic CMYK and Dot Gain 20%; RGB/Gray32 use linear equivalents. The new gray profile is independently framed from recorded numerical tone response; no vendor ICC binary is bundled. Relative colorimetric and BPC true. These are Photato defaults, not a claim of Photoshop regional defaults.",
      "adobe": "No application Color Settings endpoint in the pinned Adobe v2 contract. Stateless Photato and Adobe jobs retain their own contract defaults and explicit output ICC options.",
      "limits": "Policies/alerts apply to documented native opening and shared imports/pastes; see colorPolicies. Working CMYK proofs capture the working ICC. Spot dot gain, CSF presets, dither, advanced blending and Adobe ACE parity remain open. Image Mode uses its existing conversion engine; BPC is applied by Convert to Profile.",
      "errors": ["400": "Invalid fields/profile/intent", "401": "Authentication", "403": "Writes disabled", "404": "Unknown method", "409": "Stale revision/external change", "413": "Body size", "415": "Content type", "422": "Settings load/write failure"]]
  }
}
extension AutomationService {
  var colorSettingsState: [String: Any] {
    let store = controller.colorSettings
    return ["revision": store.revision.uuidString, "settings": ColorSettingsAPI.json(store.value),
      "isPersistent": store.isPersistent, "canUpdate": colorSettingsChangesEnabled && store.loadError == nil,
      "loadError": store.loadError == nil ? NSNull() : "The Color Settings file could not be loaded." as Any]
  }
  func handleColorSettings(_ request: AutomationRequest) throws -> AutomationResponse? {
    guard request.path == ColorSettingsAPI.path else { return nil }
    if request.method == "GET" { return .json(colorSettingsState) }
    guard request.method == "POST" else { throw AutomationFailure(status: 404, message: "Unknown Color Settings operation.") }
    guard colorSettingsChangesEnabled else { throw AutomationFailure(status: 403, message: "Allow Color Settings changes in the native API window first.") }
    guard request.headers["content-type"]?.lowercased().split(separator: ";").first == "application/json" else {
      throw AutomationFailure(status: 415, message: "Content-Type must be application/json.")
    }
    guard request.body.count <= ColorSettings.maximumArchiveBytes else { throw AutomationFailure(status: 413, message: "Color Settings request is too large.") }
    guard let fields = try? JSONDecoder().decode([String: AutomationValue].self, from: request.body),
      Set(fields.keys) == ["revision", "settings"], case .string(let text) = fields["revision"], let revision = UUID(uuidString: text) else {
      throw AutomationFailure(status: 400, message: "Required: revision UUID and settings object.")
    }
    let settings = try ColorSettingsAPI.decode(fields["settings"], base: controller.colorSettings.value)
    do { try controller.colorSettings.commit(settings, revision: revision) }
    catch let failure as ColorSettingsFailure { throw AutomationFailure(status: failure == .changed ? 409 : 422, message: failure.localizedDescription) }
    catch { throw AutomationFailure(status: 422, message: "Color Settings could not be saved.") }
    return .json(colorSettingsState)
  }
}
