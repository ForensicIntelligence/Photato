import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension ForegroundSelection {
  static var apiStateSchema: [String: Any] {
    ["type": "object", "properties": [
      "selection": ["anyOf": [["type": "null"], ["type": "object",
        "required": ["x", "y", "width", "height"], "properties": [
          "x": ["type": "integer"], "y": ["type": "integer"],
          "width": ["type": "integer"], "height": ["type": "integer"]]]]],
      "selectionHasSoftCoverage": ["type": "boolean"],
      "subjectDetection": ["type": "object", "properties": [
        "canSelectSubject": ["type": "boolean"], "canRemoveBackground": ["type": "boolean"],
        "sampleAllLayers": ["type": "boolean"]]],
    ]]
  }
  static var apiLayerStateSchema: [String: Any] {
    ["type": "object", "properties": ["hasMask": ["type": "boolean"],
      "maskEnabled": ["type": "boolean"], "maskDensity": ["type": "number", "minimum": 0, "maximum": 1],
      "maskFeather": ["type": "number", "minimum": 0]]]
  }
  static var apiCapabilities: [String: Any] {
    ["provider": "Apple Vision VNGenerateForegroundInstanceMaskRequest", "onDevice": true,
      "minimumMacOS": "14.0", "maximumPixels": maximumPixels, "maximumDimension": 6000,
      "commands": ["selection.subject", "layer.removeBackground"],
      "documentStateSchema": apiStateSchema, "layerStateSchema": apiLayerStateSchema,
      "adobeSubmit": "/v2/remove-background", "adobeStatus": "/v2/status/{jobId}",
      "result": "Selection or editable layer mask, one Undo transaction; source pixels retained.",
      "availability": "Requires a pixel layer and the system Vision model. Runtime model failure and no subject return explicit errors. No cloud fallback.",
      "limitations": "Native model, not Adobe's proprietary model. Exact edge/pixel parity is unqualified. Existing layer masks must be applied or deleted first. Detection uses an SDR proxy; editable RGB8/16/32 pixels are retained. Adobe jobs support JPEG/PNG/TIFF/WebP input, PNG/JPEG/PSD output; WebP encoding and default TIFF output are unsupported. Local edge color decontamination is an approximation."]
  }
}

extension AutomationCommand {
  struct ForegroundOptions: Sendable {
    let layerID: UUID
    let removeBackground: Bool
    let all: Bool
    let mode: SelectionMode
  }
  func foregroundOptions(document: CraftDocument) throws -> ForegroundOptions {
    guard let id = UUID(uuidString: try string("layerID")),
      document.layers.contains(where: { $0.id == id }) else {
      throw AutomationFailure(status: 404, message: "Layer not found.")
    }
    let all: Bool
    if let value = parameters["sampleAllLayers"] {
      guard case .bool(let flag) = value else {
        throw AutomationFailure(status: 400, message: "sampleAllLayers must be boolean.")
      }
      all = flag
    } else { all = false }
    let mode: SelectionMode
    switch parameters["mode"] {
    case nil, .string("replace"): mode = .replace
    case .string("add"): mode = .add
    case .string("subtract"): mode = .subtract
    case .string("intersect"): mode = .intersect
    default: throw AutomationFailure(status: 400, message: "Invalid selection mode.")
    }
    return .init(layerID: id, removeBackground: name == "layer.removeBackground", all: all, mode: mode)
  }
}
