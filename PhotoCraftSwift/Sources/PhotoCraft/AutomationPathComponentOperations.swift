import Foundation
import PhotoCraftCore

enum PathComponentOperationsAPI {
  static let name = "paths.components"

  static func schema(_ key: String) -> [String: Any] {
    if key == "operation" { return BrushAPI.enumeration(PathComponentOperation.allCases.map(\.rawValue)) }
    return PathTransformAPI.schema(key)
  }

  static var capabilities: [String: Any] {
    [
      "command": name,
      "resultSchema": ["type": "object", "required": ["revision", "pathTransformSelection"],
                       "properties": ["revision": ["type": "string"], "pathTransformSelection": PathTransformAPI.selectionSchema]],
      "stacking": PathComponentOperation.stacking.map(\.rawValue),
      "overlap": PathComponentOperation.overlap.map(\.rawValue),
      "scope": "Reorder, change overlap or merge the whole selected components of one editable path. Joined contours move together. Omit the index array to use the whole path.",
      "adobe": "The published Photoshop v2 contract has no independent path-component editing endpoint."
    ]
  }
}

extension AutomationCommand {
  func pathComponentEditRequest() throws -> PathComponentEditRequest {
    let target = try PathGroupsAPI.target(["target": string("target"), "id": string("id")])
    guard let operation = PathComponentOperation(rawValue: try string("operation")) else {
      throw AutomationFailure(status: 400, message: "Supply a valid path component operation.")
    }
    let components = try parameters["components"].map { value -> [Int] in
      guard let indices = try BrushAPI.merge(value, schema: PathComponentOperationsAPI.schema("components")) as? [Double] else {
        throw AutomationFailure(status: 400, message: "Supply distinct component indices.")
      }
      return indices.map(Int.init)
    }
    return .init(target: target, components: components, operation: operation)
  }
}
