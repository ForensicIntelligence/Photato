import Foundation
import PhotoCraftCore

enum PathComponentLayoutAPI {
  static let name = "paths.layout"

  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "layout":
      let align = BrushAPI.object(["operation": BrushAPI.enumeration(["align"]),
                                   "edge": BrushAPI.enumeration(LayerAlignment.allCases.map(\.rawValue))],
                                  required: ["operation", "edge"])
      let distribute = BrushAPI.object(["operation": BrushAPI.enumeration(["distribute"]),
                                        "edge": BrushAPI.enumeration(LayerDistribution.allCases.map(\.rawValue))],
                                       required: ["operation", "edge"])
      return ["oneOf": [align, distribute]]
    default: return PathTransformAPI.schema(key)
    }
  }

  static var stateSchema: [String: Any] {
    BrushAPI.object(["canAlign": BrushAPI.flag, "canDistribute": BrushAPI.flag,
                     "selectedComponents": BrushAPI.number(0, 256, integer: true)],
                    required: ["canAlign", "canDistribute", "selectedComponents"])
  }

  static var capabilities: [String: Any] {
    [
      "command": name, "stateSchema": stateSchema,
      "resultSchema": ["type": "object", "required": ["revision", "pathTransformSelection"],
                       "properties": ["revision": ["type": "string"], "pathTransformSelection": PathTransformAPI.selectionSchema]],
      "scope": "Align or distribute whole components of one saved path, shape path, or vector mask in document coordinates. Omit components to use every nonempty component of the specified path.",
      "minimumAlignmentComponents": 2, "minimumDistributionComponents": 3,
      "adobe": "The published Photoshop v2 API has no equivalent path component layout command."
    ]
  }
}

extension AutomationCommand {
  func pathComponentLayoutRequest() throws -> PathComponentLayoutRequest {
    let target = try PathGroupsAPI.target(["target": string("target"), "id": string("id")])
    guard let raw = parameters["layout"],
          let fields = try BrushAPI.merge(raw, schema: PathComponentLayoutAPI.schema("layout")) as? [String: String],
          let edge = fields["edge"] else {
      throw AutomationFailure(status: 400, message: "Supply a path alignment or distribution setting.")
    }
    let operation: LayerLayoutOperation
    switch fields["operation"] {
    case "align":
      guard let alignment = LayerAlignment(rawValue: edge) else {
        throw AutomationFailure(status: 400, message: "Supply a valid path alignment edge.")
      }
      operation = .align(alignment)
    case "distribute":
      guard let distribution = LayerDistribution(rawValue: edge) else {
        throw AutomationFailure(status: 400, message: "Supply a valid path distribution mode.")
      }
      operation = .distribute(distribution)
    default: throw AutomationFailure(status: 400, message: "Supply a valid path layout operation.")
    }
    let indices = try parameters["components"].map { raw -> [Int] in
      guard let numbers = try BrushAPI.merge(raw, schema: PathComponentLayoutAPI.schema("components")) as? [Double] else {
        throw AutomationFailure(status: 400, message: "Supply distinct component indices.")
      }
      return numbers.map(Int.init)
    }
    return .init(target: target, components: indices, operation: operation)
  }
}

@MainActor extension EditorStore {
  var pathComponentLayoutState: [String: Any] {
    let count = selectedLayoutComponents.count
    return ["canAlign": count >= 2, "canDistribute": count >= 3, "selectedComponents": count]
  }
}
