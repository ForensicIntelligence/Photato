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

  static var imageParameters: [String: Any] {
    let reference = BrushAPI.object([
      "use": ["type": "string", "enum": LocalGenerationGuide.Kind.allCases.map(\.rawValue)],
      "dataBase64": ["type": "string", "minLength": 1, "maxLength": ImageGenerationReference.maximumBase64Characters]
    ], required: ["use", "dataBase64"])
    return BrushAPI.object(options.merging(["referenceImage": reference]) { first, _ in first }, required: [])
  }

  private static var referenceUse: [String: Any] {
    ["type": "string", "enum": LocalGenerationGuide.Kind.allCases.map(\.rawValue)]
  }

  static var promptEditParameters: [String: Any] {
    BrushAPI.object(options.merging(["sourceLayerID": VariablesAPI.uuid]) { first, _ in first }, required: [])
  }

  static var schema: [String: Any] {
    BrushAPI.object([
      "supported": BrushAPI.flag, "modelConfigured": BrushAPI.flag, "canGenerate": BrushAPI.flag,
      "promptModelConfigured": BrushAPI.flag, "canGenerateFromPrompt": BrushAPI.flag,
      "operationID": VariablesAPI.nullableUUID,
      "localImage": BrushAPI.object(["canGenerate": BrushAPI.flag,
        "referenceModels": BrushAPI.object(["style": BrushAPI.flag, "composition": BrushAPI.flag],
          required: ["style", "composition"])], required: ["canGenerate", "referenceModels"]),
      "promptEdit": BrushAPI.object(["sourceLayerID": VariablesAPI.nullableUUID, "modelConfigured": BrushAPI.flag,
        "canEdit": BrushAPI.flag], required: ["sourceLayerID", "modelConfigured", "canEdit"]),
      "localBackground": BrushAPI.object(["foregroundLayerID": VariablesAPI.nullableUUID, "canGenerate": BrushAPI.flag],
        required: ["foregroundLayerID", "canGenerate"]),
      "selectedVariations": ["anyOf": [["type": "null"], BrushAPI.object([
        "layerID": VariablesAPI.uuid, "selectedID": VariablesAPI.uuid,
        "prompt": ["type": "string"], "model": ["type": "string"],
        "canGenerateMore": BrushAPI.flag, "canGenerateSimilar": BrushAPI.flag,
        "referenceUse": ["anyOf": [referenceUse, ["type": "null"]]],
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
     "imageReference": ["uses": LocalGenerationGuide.Kind.allCases.map(\.rawValue),
       "maximumBytes": ImageGenerationReference.maximumBytes, "requiresDocumentTransfers": true,
       "savedWithVariations": true] as [String: Any],
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
      "localImage": ["canGenerate": promptConfigured && store.canBeginLocalImage,
        "referenceModels": Dictionary(uniqueKeysWithValues: LocalGenerationGuide.Kind.allCases.map { kind in
          (kind.rawValue, LocalGenerativeFill.supported && GenerativeFillModelPreference.guideBookmark(kind) != nil)
        })] as [String: Any],
      "promptEdit": ["sourceLayerID": editTarget.map { $0.id.uuidString } as Any? ?? NSNull(),
        "modelConfigured": editConfigured, "canEdit": editConfigured && editTarget != nil] as [String: Any],
      "localBackground": ["foregroundLayerID": subjectID as Any? ?? NSNull(),
        "canGenerate": promptConfigured && store.canBeginLocalBackground && !store.editingMask] as [String: Any]]
    if let layer = store.activeLayer, let record = GenerativeFillVariations.read(layer),
      let selected = record.selectedID(layer.smartObject?.layerComps?.selectedID) {
      let guideConfigured = record.guideUse.map { GenerativeFillModelPreference.guideBookmark($0) != nil } ?? true
      let canAppend = (record.isPromptEdit ? editConfigured : promptConfigured) && guideConfigured
        && store.canBeginGenerativeFillBatch(layer.id)
      state["selectedVariations"] = [
        "layerID": layer.id.uuidString, "selectedID": selected.uuidString, "prompt": record.prompt, "model": record.model,
        "canGenerateMore": canAppend, "canGenerateSimilar": canAppend,
        "referenceUse": record.guideUse.map(\.rawValue) as Any? ?? NSNull(),
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
  func imageReferenceOptions(appending: Bool) throws -> (use: LocalGenerationGuide.Kind, base64: String)? {
    guard let supplied = parameters["referenceImage"] else { return nil }
    guard !appending else {
      throw AutomationFailure(status: 400, message: "Generate More and Generate Similar use the reference saved with the layer.")
    }
    guard case .object(let fields) = supplied, Set(fields.keys) == ["use", "dataBase64"],
      case .string(let raw) = fields["use"], let use = LocalGenerationGuide.Kind(rawValue: raw),
      case .string(let encoded) = fields["dataBase64"], !encoded.isEmpty,
      encoded.utf8.count <= ImageGenerationReference.maximumBase64Characters else {
      throw AutomationFailure(status: 400, message: "Supply referenceImage with a style or composition use and bounded image dataBase64.")
    }
    return (use, encoded)
  }

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
