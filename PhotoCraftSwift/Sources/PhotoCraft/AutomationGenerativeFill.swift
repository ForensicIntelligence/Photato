import Foundation
import PhotoCraftImaging

enum GenerativeFillAPI {
  static let run = "generativeFill.apply"
  static let cancel = "generativeFill.cancel"

  static var parameters: [String: Any] {
    BrushAPI.object([
      "prompt": ["type": "string", "maxLength": LocalGenerativeFill.maximumPromptCharacters, "default": ""],
      "seed": ["type": "integer", "minimum": 0, "maximum": UInt32.max]
    ], required: [])
  }

  static var schema: [String: Any] {
    BrushAPI.object([
      "supported": BrushAPI.flag, "modelConfigured": BrushAPI.flag, "canGenerate": BrushAPI.flag,
      "promptModelConfigured": BrushAPI.flag, "canGenerateFromPrompt": BrushAPI.flag,
      "operationID": VariablesAPI.nullableUUID
    ], required: ["supported", "modelConfigured", "canGenerate", "promptModelConfigured", "canGenerateFromPrompt", "operationID"])
  }

  static var capabilities: [String: Any] {
    ["command": run, "cancelCommand": cancel, "stateSchema": schema,
     "minimumMacOS": "26.0", "requiresAppleSilicon": true, "requiresLocalModel": true,
     "maximumSelectionPixels": LocalGenerativeFill.maximumSelectionPixels,
     "maximumSelectionSide": LocalGenerativeFill.maximumSelectionSide,
     "promptSupported": true, "maximumPromptCharacters": LocalGenerativeFill.maximumPromptCharacters,
     "placement": "A local fill from surrounding pixels adds an editable masked raster layer above the visible stack in one undoable edit.",
     "edgeBlend": "A bounded color correction near selection edges uses opaque surrounding pixels and preserves selection coverage.",
     "model": "Configure LaMa512 for blank prompts and Runway_SD1.5_Inpaint for text prompts in the native Generative Fill sheet. API requests use the configured model. Inference runs on this Mac."]
  }

  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    let configured = LocalGenerativeFill.supported && GenerativeFillModelPreference.url() != nil
    let promptConfigured = LocalGenerativeFill.supported && GenerativeFillModelPreference.url(prompted: true) != nil
    return ["supported": LocalGenerativeFill.supported, "modelConfigured": configured,
      "canGenerate": configured && store.canBeginGenerativeFill,
      "promptModelConfigured": promptConfigured, "canGenerateFromPrompt": promptConfigured && store.canBeginGenerativeFill,
      "operationID": store.generativeFillOperationID?.uuidString as Any? ?? NSNull()]
  }
}

extension AutomationCommand {
  func generativeFillOptions() throws -> (prompt: String, seed: UInt32) {
    let prompt: String
    switch parameters["prompt"] {
    case nil: prompt = ""
    case .string(let value):
      do { prompt = try LocalGenerativeFill.validatePrompt(value) }
      catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    default: throw AutomationFailure(status: 400, message: "Invalid prompt.")
    }
    if parameters["seed"] != nil {
      guard !prompt.isEmpty else { throw AutomationFailure(status: 400, message: "A seed requires a text prompt.") }
      return (prompt, UInt32(try integer("seed", range: 0...Double(UInt32.max))))
    }
    return (prompt, .random(in: .min ... .max))
  }
}
