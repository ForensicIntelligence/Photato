import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Declarative suggestions only. No scripts, file paths, model-supplied targets or executable code.
public enum NativeEditOperation: String, Codable, CaseIterable, Sendable {
  case autoTone, autoContrast, autoColor, desaturate, invert
  public var title: String {
    switch self {
    case .autoTone: "Auto Tone"
    case .autoContrast: "Auto Contrast"
    case .autoColor: "Auto Color"
    case .desaturate: "Desaturate"
    case .invert: "Invert"
    }
  }
}

public struct NativeEditPlan: Codable, Equatable, Sendable {
  public var summary: String
  public var operations: [NativeEditOperation]
  public init(summary: String, operations: [NativeEditOperation]) {
    self.summary = summary; self.operations = operations
  }
  public func validate() throws {
    guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      summary.utf8.count <= 512, (1...8).contains(operations.count) else {
      throw LocalAIError.unavailable("An edit plan needs a summary up to 512 UTF-8 bytes and one to eight supported operations.")
    }
  }
  public static func decode(_ data: Data) throws -> Self {
    guard data.count <= 8192,
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(object.keys) == ["summary", "operations"] else {
      throw LocalAIError.unavailable("Use an edit plan containing only summary and operations (maximum 8 KiB).")
    }
    let plan = try JSONDecoder().decode(Self.self, from: data)
    try plan.validate(); return plan
  }
}

public enum EditPlanProvider: String, CaseIterable, Sendable {
  case onDevice, privateCloudCompute
  public var title: String { self == .onDevice ? "On-device" : "Private Cloud Compute" }
  public var capability: AICapability {
    guard LocalAI.platform.available else { return LocalAI.platform }
    if self == .onDevice { return LocalAI.textCapability }
    #if canImport(FoundationModels)
    if #available(macOS 27.0, *) {
      let model = PrivateCloudComputeLanguageModel()
      return AICapability(available: model.isAvailable, message: model.isAvailable
        ? "Apple's Private Cloud Compute language model is ready. Your instruction is sent to Apple's service. No image pixels are sent."
        : "Apple's Private Cloud Compute language model is unavailable on this Mac.")
    }
    #endif
    return AICapability(available: false, message: "Private Cloud Compute text planning requires macOS 27 or later on Apple Silicon.")
  }
}

public enum NativeEditPlanner {
  public static func propose(_ prompt: String, provider: EditPlanProvider) async throws -> NativeEditPlan {
    let prompt = try LocalAI.validatePrompt(prompt)
    let capability = provider.capability
    guard capability.available else { throw LocalAIError.unavailable(capability.message) }
    try Task.checkCancellation()
    #if canImport(FoundationModels)
    if #available(macOS 26.0, *) {
      let instructions = """
        Plan edits to the active RGB pixel layer. The ONLY supported operations are:
        autoTone, autoContrast, autoColor, desaturate, invert.
        Return one to eight operations in execution order and a short factual summary.
        No image pixels are available; do not claim to inspect the image.
        Preserve the user's intent. If their request requires any other operation, image understanding,
        object selection, generative editing or guidance, return no operations and explain the missing
        capability in unsupportedReason. Never approximate an unsupported request with other edits.
        Otherwise unsupportedReason must be empty. Suggestions will be previewed; nothing runs automatically.
        """
      let response: ModelEditPlan
      if provider == .privateCloudCompute {
        if #available(macOS 27.0, *) {
          response = try await LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
            .respond(to: prompt, generating: ModelEditPlan.self).content
        } else { throw LocalAIError.unavailable(capability.message) }
      } else {
        response = try await LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
          .respond(to: prompt, generating: ModelEditPlan.self).content
      }
      try Task.checkCancellation()
      guard response.unsupportedReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw LocalAIError.unavailable(String(response.unsupportedReason.prefix(1000)))
      }
      let operations = try response.operations.map { value in
        guard let operation = NativeEditOperation(rawValue: value) else {
          throw LocalAIError.unavailable("The model suggested an unsupported operation. Nothing was changed.")
        }
        return operation
      }
      let result = NativeEditPlan(summary: response.summary, operations: operations)
      try result.validate(); return result
    }
    #endif
    throw LocalAIError.unavailable(capability.message)
  }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable private struct ModelEditPlan {
  var summary: String
  var operations: [String]
  var unsupportedReason: String
}
#endif
