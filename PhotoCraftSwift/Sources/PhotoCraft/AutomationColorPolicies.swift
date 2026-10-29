import PhotoCraftImaging

enum ColorPolicyAPI {
  static func choice(_ text: String?, opening: Bool) throws -> ColorPolicyChoice? {
    guard let text else { return nil }
    let allowed: [ColorPolicyChoice.Action] = opening
      ? [.preserveEmbedded, .convertToWorking, .discard, .leaveUntagged, .assignWorking]
      : [.convertAppearance, .preserveNumbers]
    guard let value = ColorPolicyChoice.Action(rawValue: text), allowed.contains(value) else {
      throw AutomationFailure(status: 400, message: "Unknown or unavailable color profile decision.")
    }
    return .init(value)
  }
  static func reviewResponse(_ assessment: ColorPolicyAssessment) -> AutomationResponse {
    .json(["error": "A color profile decision is required.", "colorProfileReview": [
      "kind": assessment.kind.rawValue, "source": assessment.source, "destination": assessment.destination,
      "choices": assessment.choices.filter { $0 != .assignProfile }.map(\.rawValue),
      "importHeader": "X-Photato-Color-Decision", "pasteParameter": "colorDecision"]], status: 409)
  }
  static var capabilities: [String: Any] {
    ["opening": ["header": "X-Photato-Color-Decision", "choices": ["preserveEmbedded", "convertToWorking", "discard", "leaveUntagged", "assignWorking"]],
      "paste": ["command": "clipboard.paste", "parameter": "colorDecision", "choices": ["convertAppearance", "preserveNumbers"]],
      "behavior": "Omitted decisions follow captured application color policies. Enabled alerts return409 colorProfileReview before document publication or paste history. Retry the same payload with an allowed explicit decision. Native Photato imports retain saved interpretation and reject an opening override. Policy Off makes default new documents untagged; explicit new-document ICC overrides that default. Existing open documents do not change when preferences change.",
      "reviewSchema": BrushAPI.object(["kind": BrushAPI.enumeration(["missing", "mismatch", "pasteMismatch"]),
        "source": ["type": "string"], "destination": ["type": "string"],
        "choices": ["type": "array", "items": ["type": "string"]], "importHeader": ["type": "string"], "pasteParameter": ["type": "string"]],
        required: ["kind", "source", "destination", "choices", "importHeader", "pasteParameter"]),
      "customAssignment": "The native Missing Profile dialog accepts an installed/custom ICC. Binary API imports can use leaveUntagged then document.assignProfile with profileBase64, or assignWorking after configuring the working profile. An atomic per-import custom ICC override is not yet supported.",
      "limits": "Policies apply to represented RGB/CMYK/Gray opening and component-mode clipboard content. Unsupported rich conversions reject without automatic flattening. Preserve Numbers requires the same mode and matching float-vs-integer storage; component Paste Into/Outside remains unavailable for that choice. Restricted/ink clipboard contexts retain their existing mode-aware behavior. Drag/drop, Place and additional source formats need separate qualification.",
      "adobe": "No interactive desktop color-policy endpoint in Adobe v2. Stateless Adobe and Photato jobs remain independent of desktop policies."]
  }
}
