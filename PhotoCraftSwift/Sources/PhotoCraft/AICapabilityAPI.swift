import PhotoCraftAI

/// Native readiness, shared by image and reviewed-plan discovery. Reading never starts inference.
enum AICapabilityAPI {
  static var reasonSchema: [String: Any] {
    ["type": "string", "enum": AICapabilityReason.allCases.map(\.rawValue)]
  }
  static var schema: [String: Any] {
    BrushAPI.object(["available": ["type": "boolean"], "message": ["type": "string"],
      "reason": reasonSchema], required: ["available", "message", "reason"])
  }
  static func state(_ capability: AICapability) -> [String: Any] {
    ["available": capability.available, "message": capability.message, "reason": capability.reason.rawValue]
  }
}
