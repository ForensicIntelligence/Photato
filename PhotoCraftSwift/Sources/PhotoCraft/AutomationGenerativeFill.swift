import Foundation
import PhotoCraftImaging

enum GenerativeFillAPI {
  static let run = "generativeFill.apply"
  static let cancel = "generativeFill.cancel"

  static var schema: [String: Any] {
    BrushAPI.object([
      "supported": BrushAPI.flag, "modelConfigured": BrushAPI.flag, "canGenerate": BrushAPI.flag,
      "operationID": VariablesAPI.nullableUUID
    ], required: ["supported", "modelConfigured", "canGenerate", "operationID"])
  }

  static var capabilities: [String: Any] {
    ["command": run, "cancelCommand": cancel, "stateSchema": schema,
     "minimumMacOS": "26.0", "requiresAppleSilicon": true, "requiresLocalModel": true,
     "maximumSelectionPixels": LocalGenerativeFill.maximumSelectionPixels,
     "maximumSelectionSide": LocalGenerativeFill.maximumSelectionSide,
     "promptSupported": false,
     "placement": "A local fill from surrounding pixels adds an editable masked raster layer above the visible stack in one undoable edit.",
     "model": "Choose a compiled LaMa512 model in the native Generative Fill sheet. API requests use the selected model and pass no path, data or URL. Inference runs on this Mac."]
  }

  @MainActor static func state(_ store: EditorStore) -> [String: Any] {
    let configured = LocalGenerativeFill.supported && GenerativeFillModelPreference.url() != nil
    return ["supported": LocalGenerativeFill.supported, "modelConfigured": configured,
      "canGenerate": configured && store.canBeginGenerativeFill,
      "operationID": store.generativeFillOperationID?.uuidString as Any? ?? NSNull()]
  }
}
