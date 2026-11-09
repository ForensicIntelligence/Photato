import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ProofAPI {
  static let commands = ["proof.configure", "proof.settings.read"]
  static var settings: [String: Any] { BrushAPI.object([
    "enabled": BrushAPI.flag, "gamutWarning": BrushAPI.flag,
    "device": BrushAPI.enumeration(ProofSettings.Device.allCases.map(\.rawValue)),
    "profile": ["anyOf": [["type": "string", "contentEncoding": "base64", "maxLength": (ICCProfile.maximumBytes + 2) / 3 * 4], ["type": "null"]]],
    "profileName": ["type": "string", "maxLength": 1024],
    "intent": BrushAPI.enumeration(ModeRenderingIntent.allCases.map(\.rawValue)),
    "blackPointCompensation": BrushAPI.flag, "preserveNumbers": BrushAPI.flag,
    "simulatePaper": BrushAPI.flag, "simulateBlack": BrushAPI.flag,
    "plate": BrushAPI.enumeration(ProofSettings.Plate.allCases.map(\.rawValue)),
    "warningColor": BrushAPI.color, "warningOpacity": BrushAPI.number(), "gamutThreshold": BrushAPI.number(0.01, 100)], required: []) }
  static var stateSchema: [String: Any] { BrushAPI.object([
    "displayError": ["type": ["string", "null"]], "settings": settings, "available": BrushAPI.flag, "workspaceOpen": BrushAPI.flag,
    "preserveNumbersAvailable": BrushAPI.flag, "gamutWarningAvailable": BrushAPI.flag], required: ["displayError", "settings", "available", "workspaceOpen", "preserveNumbersAvailable", "gamutWarningAvailable"]) }
  static var capabilities: [String: Any] { [
    "commands": commands, "settings": settings, "stateSchema": stateSchema,
    "resultSchema": BrushAPI.object(["proofing": stateSchema, "revision": ["type": "string"]], required: ["proofing", "revision"]),
    "previewRoute": "/v1/documents/{id}/proof-preview.png", "maximumPixels": SoftProof.maximumDocumentPixels,
    "largeDocuments":["maximumDimension":Surface.maxDimension,"maximumPreviewPixels":RasterPreviewRequest.maximumPixels,"overviewMaximumSide":2048,"patch":[2048,64],"policy":"Sparse/paged numeric/profile preparation around the unchanged ColorSync proof kernel, then existing area reduction. Native viewport and API overview use proofed pixels; source samples/history/normal exports remain unchanged. Composition/mode/scratch limits remain independent; dense90GP/60fps/Photoshopoutput qualification is not implied. Print preparation retains its separate8MPbudget."],
    "behavior": "Per-document view state. Configure merges validated settings atomically and advances the view revision without modifying pixels, Undo, dirty state, archive or normal exports. Proof preview uses committed settings and composite, excluding draft and channel visibility; ordinary preview.png remains unchanged. Custom profiles are bounded base64 ICC data. Native JSON presets retain the same settings. Explicit device:legacyMacintoshRGB selects the observed factory defaults (Apple RGB, relative intent, BPC/paper/black off, Preserve Numbers for RGB); supplied fields then override them.",
    "workingCMYK": "Captures the actual current CMYK working ICC on first use or explicit device:workingCMYK selection. Existing view snapshots and presets keep captured profiles when preferences change. Generic CMYK is the Photato fallback, never labelled as Adobe SWOP.",
    "legacyMacintosh": ["device":"legacyMacintoshRGB", "profile":"Independently generated ICC v2 Apple RGB matrix/TRC; gamma461/256, D65 white. No Adobe ICC dependency. Shared with Adobe-compatible named Apple RGB creation/output. ICC metadata and Photoshop-rendered pixel equivalence remain unqualified."],
    "gamut": "Relative-colorimetric device round trip measured in Lab D50 using Delta E76; default threshold4 derives from licensed PhotoCraft. Warning color/opacity are configurable. This is not a claim of Photoshop's exact gamut algorithm.",
    "limits": "Preserve Numbers requires matching modes; non-RGB requires a flat retained native raster. Composite component stacks use their RGB render cache. SDR preview of32-bit content; HDR/EDR proofing remains open. Adobe PSF presets, color-blind presets, remaining proof/print integration and exact/live/platform Photoshop parity remain open. No corresponding published Adobe display-proof route is claimed."] }
}
extension AutomationCommand {
  func proofSettings(base: ProofSettings, document: CraftDocument, colorSettings: ColorSettings = .init()) throws -> ProofSettings {
    guard let value = parameters["settings"] else { throw AutomationFailure(status: 400, message: "Proof settings are required.") }
    let selected: ProofSettings
    if case .object(let fields) = value, case .string("legacyMacintoshRGB") = fields["device"] {
      selected = base.selectingLegacyMacintosh(preserveNumbers: document.colorMode == .rgb)
    } else { selected = base }
    let merged = try BrushAPI.merge(value, schema: ProofAPI.settings, base: BrushAPI.json(selected), path: "proof settings")
    var result: ProofSettings
    do { result = try JSONDecoder().decode(ProofSettings.self, from: JSONSerialization.data(withJSONObject: merged)) }
    catch { throw AutomationFailure(status: 400, message: "Invalid proof settings: \(error.localizedDescription)") }
    let refresh: Bool
    if case .object(let fields) = value, case .string("workingCMYK") = fields["device"] { refresh = true } else { refresh = false }
    result = try colorSettings.resolvingProof(result, refresh: refresh)
    try SoftProof.validate(result, in: document); return result
  }
}
extension EditorStore {
  var proofState: [String: Any] { ["displayError": proofDisplayError as Any? ?? NSNull(), "settings": BrushAPI.json(proofSettings), "available": canBeginProof,
    "workspaceOpen": proofWorkspace != nil, "preserveNumbersAvailable": SoftProof.canPreserveNumbers(document, settings: proofSettings), "gamutWarningAvailable": proofSettings.gamutWarningAvailable] }
}
