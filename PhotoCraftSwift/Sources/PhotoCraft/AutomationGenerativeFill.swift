import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum GenerativeFillAPI {
  static let run = "generativeFill.apply"
  static let expand = "generativeExpand.apply"
  static let background = "generativeBackground.apply"
  static let image = "generativeImage.apply"
  static let promptEdit = "promptEdit.apply"
  static let cancel = "generativeFill.cancel"

  private static var options: [String: Any] {
    [
      "prompt": ["type": "string", "maxLength": LocalGenerativeFill.maximumPromptCharacters, "default": ""],
      "seed": ["type": "integer", "minimum": 0, "maximum": UInt32.max],
      "targetLayerID": VariablesAPI.uuid,
      "referenceVariationID": VariablesAPI.uuid,
      "variationCount": ["type": "integer", "minimum": 1, "maximum": LocalGenerativeFill.maximumVariations, "default": 1]
    ]
  }

  static var parameters: [String: Any] { BrushAPI.object(options, required: []) }

  static var promptEditParameters: [String: Any] {
    BrushAPI.object(options.merging(["sourceLayerID": VariablesAPI.uuid]) { first, _ in first }, required: [])
  }

  static var schema: [String: Any] {
    BrushAPI.object([
      "supported": BrushAPI.flag, "modelConfigured": BrushAPI.flag, "canGenerate": BrushAPI.flag,
      "promptModelConfigured": BrushAPI.flag, "canGenerateFromPrompt": BrushAPI.flag,
      "operationID": VariablesAPI.nullableUUID,
      "localImage": BrushAPI.object(["canGenerate": BrushAPI.flag], required: ["canGenerate"]),
      "promptEdit": BrushAPI.object(["sourceLayerID": VariablesAPI.nullableUUID, "modelConfigured": BrushAPI.flag,
        "canEdit": BrushAPI.flag], required: ["sourceLayerID", "modelConfigured", "canEdit"]),
      "localBackground": BrushAPI.object(["foregroundLayerID": VariablesAPI.nullableUUID, "canGenerate": BrushAPI.flag],
        required: ["foregroundLayerID", "canGenerate"]),
      "selectedVariations": ["anyOf": [["type": "null"], BrushAPI.object([
        "layerID": VariablesAPI.uuid, "selectedID": VariablesAPI.uuid,
        "prompt": ["type": "string"], "model": ["type": "string"],
        "canGenerateMore": BrushAPI.flag, "canGenerateSimilar": BrushAPI.flag,
        "entries": ["type": "array", "items": BrushAPI.object([
          "id": VariablesAPI.uuid, "seed": ["type": "integer", "minimum": 0, "maximum": UInt32.max],
          "prompt": ["type": "string"], "referenceVariationID": VariablesAPI.nullableUUID
        ], required: ["id", "seed", "prompt"])]
      ], required: ["layerID", "selectedID", "prompt", "model", "canGenerateMore", "canGenerateSimilar", "entries"])]]
    ], required: ["supported", "modelConfigured", "canGenerate", "promptModelConfigured", "canGenerateFromPrompt",
      "operationID", "selectedVariations", "localBackground", "localImage", "promptEdit"])
  }

  static var capabilities: [String: Any] {
    ["command": run, "expandCommand": expand, "backgroundCommand": background, "imageCommand": image,
     "promptEditCommand": promptEdit,
     "cancelCommand": cancel, "stateSchema": schema,
     "minimumMacOS": "26.0", "requiresAppleSilicon": true, "requiresLocalModel": true,
     "maximumSelectionPixels": LocalGenerativeFill.maximumSelectionPixels,
     "maximumSelectionSide": LocalGenerativeFill.maximumSelectionSide,
     "expandGeometry": ["maximumCanvasSide": Surface.maxDimension, "windowSide": GenerativeExpandWindows.side,
      "windowOverlap": GenerativeExpandWindows.overlap, "tiledPromptVariations": true,
      "tiledRegenerationFromSavedContext": true, "promptWorkerPerJob": true] as [String: Any],
     "promptSupported": true, "maximumPromptCharacters": LocalGenerativeFill.maximumPromptCharacters,
     "maximumVariations": LocalGenerativeFill.maximumVariations, "variationSelectionCommand": SmartObjectLayerCompAPI.name,
     "maximumStoredVariations": GenerativeFillVariations.maximumStoredVariations,
     "similarity": "With targetLayerID, supply an existing referenceVariationID from that layer. The local model uses that result and the original mask to create new variations in one undoable batch.",
     "placement": "A fill adds an editable masked layer above the visible stack. A targetLayerID appends variations to the selected layer using its saved context. Each request is one undoable edit.",
     "edgeBlend": "A bounded color correction near selection edges uses opaque surrounding pixels and preserves selection coverage.",
     "model": "Configure LaMa512 for blank prompts and Runway_SD1.5_Inpaint for text prompts in the native Generative Fill sheet. API requests use the configured model. Inference runs on this Mac."]
  }

  static var expandParameters: [String: Any] {
    let frame = ["x", "y", "width", "height"]
    var properties = Dictionary(uniqueKeysWithValues: frame.compactMap { key in CropRequest.apiSchema(key).map { (key, $0) } })
    properties["prompt"] = ["type": "string", "maxLength": LocalGenerativeFill.maximumPromptCharacters, "default": ""]
    properties["seed"] = ["type": "integer", "minimum": 0, "maximum": UInt32.max]
    properties["variationCount"] = ["type": "integer", "minimum": 1, "maximum": LocalGenerativeFill.maximumVariations, "default": 1]
    return BrushAPI.object(properties, required: frame)
  }

  static var backgroundParameters: [String: Any] {
    BrushAPI.object([
      "foregroundLayerID": VariablesAPI.uuid,
      "prompt": ["type": "string", "maxLength": LocalGenerativeFill.maximumPromptCharacters, "default": ""],
      "seed": ["type": "integer", "minimum": 0, "maximum": UInt32.max],
      "variationCount": ["type": "integer", "minimum": 1, "maximum": LocalGenerativeFill.maximumVariations, "default": 1]
    ], required: [])
  }

  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    let configured = LocalGenerativeFill.supported && GenerativeFillModelPreference.url() != nil
    let promptConfigured = LocalGenerativeFill.supported && GenerativeFillModelPreference.url(prompted: true) != nil
    let editConfigured = LocalGenerativeFill.supported && GenerativeFillModelPreference.url(instructions: true) != nil
    let subjectID = GeneratedBackground.foreground(in: store.document)?.id.uuidString
    let editTarget = store.promptEditTarget
    var state: [String: Any] = ["supported": LocalGenerativeFill.supported, "modelConfigured": configured,
      "canGenerate": configured && store.canBeginGenerativeFill,
      "promptModelConfigured": promptConfigured, "canGenerateFromPrompt": promptConfigured && store.canBeginGenerativeFill,
      "operationID": store.generativeFillOperationID?.uuidString as Any? ?? NSNull(), "selectedVariations": NSNull(),
      "localImage": ["canGenerate": promptConfigured && store.canBeginLocalImage],
      "promptEdit": ["sourceLayerID": editTarget.map { $0.id.uuidString } as Any? ?? NSNull(),
        "modelConfigured": editConfigured, "canEdit": editConfigured && editTarget != nil] as [String: Any],
      "localBackground": ["foregroundLayerID": subjectID as Any? ?? NSNull(),
        "canGenerate": promptConfigured && store.canBeginLocalBackground && !store.editingMask] as [String: Any]]
    if let layer = store.activeLayer, let record = GenerativeFillVariations.read(layer),
      let selected = record.selectedID(layer.smartObject?.layerComps?.selectedID) {
      let canAppend = (record.isPromptEdit ? editConfigured : promptConfigured) && store.canBeginGenerativeFillBatch(layer.id)
      state["selectedVariations"] = [
        "layerID": layer.id.uuidString, "selectedID": selected.uuidString, "prompt": record.prompt, "model": record.model,
        "canGenerateMore": canAppend, "canGenerateSimilar": canAppend,
        "entries": record.entries.map { entry in
          ["id": entry.id.uuidString, "seed": entry.seed, "prompt": entry.prompt ?? record.prompt,
           "referenceVariationID": entry.referenceVariationID?.uuidString as Any? ?? NSNull()] as [String: Any]
        }
      ]
    }
    return state
  }
}

extension AutomationCommand {
  func generativeFillOptions() throws -> (prompt: String, seed: UInt32?, count: Int, target: UUID?, reference: UUID?) {
    let target = try parameters["targetLayerID"].map { _ in try actionUUID("targetLayerID") }
    let reference = try parameters["referenceVariationID"].map { _ in try actionUUID("referenceVariationID") }
    if reference != nil && target == nil {
      throw AutomationFailure(status: 400, message: "Supply targetLayerID with referenceVariationID.")
    }
    let prompt: String
    switch parameters["prompt"] {
    case nil: prompt = ""
    case .string(let value):
      do { prompt = try LocalGenerativeFill.validatePrompt(value) }
      catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
    default: throw AutomationFailure(status: 400, message: "Invalid prompt.")
    }
    let count = try parameters["variationCount"].map { _ in
      try integer("variationCount", range: 1...Double(LocalGenerativeFill.maximumVariations))
    } ?? 1
    if [GenerativeFillAPI.image, GenerativeFillAPI.promptEdit].contains(name), target == nil, prompt.isEmpty {
      throw AutomationFailure(status: 400, message: "Enter a text prompt for this image operation.")
    }
    if target != nil, parameters["prompt"] != nil, prompt.isEmpty {
      throw AutomationFailure(status: 400, message: "Enter a text prompt, or omit it to use the source variation’s prompt.")
    }
    if name != GenerativeFillAPI.background, target == nil, prompt.isEmpty && (count > 1 || parameters["seed"] != nil) {
      throw AutomationFailure(status: 400, message: "A seed or multiple variations require a text prompt.")
    }
    let seed = try parameters["seed"].map { _ in UInt32(try integer("seed", range: 0...Double(UInt32.max))) }
    return (prompt, seed, count, target, reference)
  }
}
