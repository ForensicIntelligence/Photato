import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Declarative suggestions only. No scripts, file paths, model-supplied targets or executable code.
public enum NativeEditOperation: Codable, Equatable, CaseIterable, Sendable {
  case autoTone, autoContrast, autoColor, desaturate, invert
  case adjustment(NativeEditAdjustment)
  /// Preserve the original fixed-operation inventory. Parameterized operations
  /// are described separately, with required values, rather than fake defaults.
  public static let allCases: [Self] = [.autoTone, .autoContrast, .autoColor, .desaturate, .invert]
  public static var supportedNames: [String] { allCases.map(\.rawValue) + NativeEditAdjustment.Kind.allCases.map(\.rawValue) }
  public init?(rawValue: String) {
    switch rawValue {
    case "autoTone": self = .autoTone
    case "autoContrast": self = .autoContrast
    case "autoColor": self = .autoColor
    case "desaturate": self = .desaturate
    case "invert": self = .invert
    default: return nil
    }
  }
  public init(name: String, parameters: [String: Double]) throws {
    if let fixed = Self(rawValue: name) {
      guard parameters.isEmpty else { throw LocalAIError.unavailable("\(name) does not accept parameters.") }
      self = fixed
    } else if let kind = NativeEditAdjustment.Kind(rawValue: name) {
      self = .adjustment(try NativeEditAdjustment(kind, parameters: parameters))
    } else { throw LocalAIError.unavailable("The model suggested an unsupported operation. Nothing was changed.") }
  }
  public var rawValue: String {
    switch self {
    case .autoTone: "autoTone"
    case .autoContrast: "autoContrast"
    case .autoColor: "autoColor"
    case .desaturate: "desaturate"
    case .invert: "invert"
    case .adjustment(let value): value.operation.rawValue
    }
  }
  public var title: String {
    switch self {
    case .autoTone: "Auto Tone"
    case .autoContrast: "Auto Contrast"
    case .autoColor: "Auto Color"
    case .desaturate: "Desaturate"
    case .invert: "Invert"
    case .adjustment(let value): "\(value.operation.title): \(value.detail)"
    }
  }
  public init(from decoder: Decoder) throws {
    if let name = try? decoder.singleValueContainer().decode(String.self), let fixed = Self(rawValue: name) { self = fixed }
    else { self = .adjustment(try NativeEditAdjustment(from: decoder)) }
  }
  public func encode(to encoder: Encoder) throws {
    if case .adjustment(let value) = self { try value.encode(to: encoder) }
    else { var container = encoder.singleValueContainer(); try container.encode(rawValue) }
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
    for case .adjustment(let value) in operations { try value.validate() }
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
    self == .onDevice ? LocalAI.textCapability : LocalAI.privateCloudComputeCapability
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
      let adjustmentInstructions = NativeEditAdjustment.Kind.allCases.map { kind in
        kind.rawValue + ": " + kind.parameters.map { field in
          "\(field.name) [\(field.minimum), \(field.maximum)], neutral \(field.neutral)\(field.integer ? ", integer" : "")\(field.unit.isEmpty ? "" : ", " + field.unit)"
        }.joined(separator: "; ")
      }.joined(separator: "\n")
      let instructions = """
        Plan edits to the active RGB pixel layer. The ONLY fixed operations are
        autoTone, autoContrast, autoColor, desaturate, invert; each has an EMPTY parameters array.
        The following adjustments are also supported, with EVERY listed named parameter required:
        \(adjustmentInstructions)
        Return one to eight operations in execution order and a short factual summary.
        Each operation has an operation name and a parameters array of name/value pairs.
        Use exact requested values in these units. Do not repeat parameter names, add keys,
        choose layer targets, or invent operations. For unspecified parameters, use their neutral value.
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
        guard Set(value.parameters.map(\.name)).count == value.parameters.count else {
          throw LocalAIError.unavailable("The model repeated an adjustment value. Nothing was changed.")
        }
        return try NativeEditOperation(name: value.operation,
          parameters: Dictionary(uniqueKeysWithValues: value.parameters.map { ($0.name, $0.value) }))
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
  var operations: [ModelEditOperation]
  var unsupportedReason: String
}
@available(macOS 26.0, *)
@Generable private struct ModelEditOperation {
  var operation: String
  var parameters: [ModelEditParameter]
}
@available(macOS 26.0, *)
@Generable private struct ModelEditParameter {
  var name: String
  var value: Double
}
#endif
