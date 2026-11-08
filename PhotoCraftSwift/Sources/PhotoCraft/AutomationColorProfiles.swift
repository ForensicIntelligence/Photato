import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ColorProfileAPI {
  static let commands = ["document.assignProfile", "document.convertProfile", "document.profile.read"]
  static func schema(_ key: String) -> [String: Any] {
    if key == "profileBase64" { return DocumentModeAPI.schema(key) }
    if key == "intent" { return DocumentModeAPI.schema(key) }
    return BrushAPI.flag
  }
  static var stateSchema: [String: Any] {
    BrushAPI.object(["name": ["type": "string"], "untagged": BrushAPI.flag,
      "available": BrushAPI.flag, "workspaceOpen": BrushAPI.flag, "previewBusy": BrushAPI.flag,
      "committing": BrushAPI.flag], required: ["name", "untagged", "available", "workspaceOpen", "previewBusy", "committing"])
  }
  static var capabilities: [String: Any] {
    ["unmanagedPSDTransport":["formats":["PSD","PSB"],"mode":"RGB8/16/32","admission":"Explicit untagged resource1041, no embeddedICC1039, kindnone and a fully represented empty display/view descriptor. Active OCIO, conflicting profiles and unknown layouts remain unsupported.","save":"Retains the neutral source descriptor while untagged. Assigning a profile omits the stale unmanaged descriptor and writes the current ICC policy.","interfaces":"Native Open/Save, optional document upload/download and both isolated resource-job APIs share the same Swift codec. No new command or Adobe route."],"commands": commands, "engine": "Apple ColorSync", "maximumPixels": ColorProfileInput.maximumDocumentPixels,
      "maximumDimension": Surface.maxDimension, "legacyKernelMaximumPixels": NativeModeRaster.maximumPixels,
      "pagedProfileOperations": true, "previewMaximumSide": 2048,
      "maximumProfileBytes": ICCProfile.maximumBytes, "untaggedArchiveVersion": 49,
      "readResultSchema": BrushAPI.object(["profileBase64": schema("profileBase64"), "name": ["type": "string"],
        "untagged": BrushAPI.flag, "revision": ["type": "string"]], required: ["profileBase64", "name", "untagged", "revision"]),
      "behavior": "Assignment preserves numeric artwork samples; profile must match the mode. removeProfile uses captured working-space interpretation, omits output ICC and requires native49. Conversion preserves alpha and hidden RGB; intent and blackPointCompensation use ColorSync. Same depth is retained, including linear RGB/Gray32. Raster/group layers and ordinary RGB text/solid fills/shapes stay editable. mergeVisible explicitly replaces the stack and discards hidden layers. Embedded variable replacement images are converted to the new RGB working profile for future placement; their IDs and row references are retained and Undo restores original assets. All edits share native preview/commit history, stale and busy checks. profile.read returns the effective interpretation even for an untagged document.",
      "limits": "Profile operations have no canvas-megapixel admission cap within the native300000-per-side geometry. Large rasters stream stored64-row patches up to2048wide and transform implicit samples once; previews reduce the converted composite to2048per side. Actual dense maximum-capacity, platform and60fps qualification remain open. Existing transfer/codec/resource-job budgets remain independent. No Adobe ACE or byte-identical Photoshop conversion claim. Dither, DeviceLink/abstract profiles, semantic Actions, full rich-layer conversion and import/paste color policies remain open. Missing Photoshop API endpoints are not invented."]
  }
}
extension AutomationCommand {
  func colorProfileRequest(in document: CraftDocument, settings: ColorSettings = .init()) throws -> ColorProfileRequest {
    let operation: ColorProfileRequest.Operation = name == "document.assignProfile" ? .assign : .convert
    let remove = try pathFlag("removeProfile", false)
    var profile: Data
    if let value = parameters["profileBase64"] {
      guard case .string(let text) = value, text.count <= 5_592_408, let bytes = Data(base64Encoded: text) else {
        throw AutomationFailure(status: 400, message: "Invalid ICC profile encoding.")
      }
      profile = bytes
    } else {
      guard operation == .assign, remove else { throw AutomationFailure(status: 400, message: "profileBase64 is required unless removing the profile.") }
      profile = try settings.profile(document.colorMode, depth: document.depth)
    }
    if remove, parameters["profileBase64"] != nil { throw AutomationFailure(status: 400, message: "Omit profileBase64 when removing the profile.") }
    do {
      let mode = try ProofSettings.mode(of: profile)
      try NativeModeProfile.validate(profile, mode: mode, depth: document.depth)
    } catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    var result = ColorProfileRequest(operation, profile: profile)
    result.removeProfile = remove; result.intent = settings.intent
    result.blackPointCompensation = try pathFlag("blackPointCompensation", settings.blackPointCompensation)
    result.mergeVisible = try pathFlag("mergeVisible", false)
    if parameters["intent"] != nil {
      guard let intent = ModeRenderingIntent(rawValue: try string("intent")) else { throw AutomationFailure(status: 400, message: "Unknown rendering intent.") }
      result.intent = intent
    }
    return result
  }
}
extension EditorStore {
  var colorProfileState: [String: Any] {
    ["name": ColorProfileInput.name(document), "untagged": document.profileIsUntagged == true,
      "available": canBeginColorProfile, "workspaceOpen": colorProfileWorkspace != nil,
      "previewBusy": colorProfileWorkspace?.rendering ?? false, "committing": colorProfileWorkspace?.committing ?? false]
  }
}
