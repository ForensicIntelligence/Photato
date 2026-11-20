import Foundation
import PhotoCraftCore

enum PathTransformAPI {
  static let name = "path.transform"
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "target": BrushAPI.enumeration(["saved", "vectorMask", "shape"])
    case "id": ["type": "string", "format": "uuid"]
    case "matrix": SelectionTransformAPI.schema(key)
    case "components":
      ["type": "array", "minItems": 1, "maxItems": 256, "uniqueItems": true,
       "items": BrushAPI.number(0, 255, integer: true)]
    default:
      ["type": "array", "minItems": 1, "maxItems": VectorPath.maxKnots, "uniqueItems": true,
       "items": BrushAPI.object(["component": BrushAPI.number(0, 255, integer: true),
                                 "knot": BrushAPI.number(0, 4095, integer: true)],
                                required: ["component", "knot"])]
    }
  }

  static var selectionSchema: [String: Any] {
    BrushAPI.object(
      ["scope": BrushAPI.enumeration(["all", "components", "anchors"]),
       "components": schema("components").merging(["minItems": 0]) { _, value in value },
       "anchors": schema("anchors").merging(["minItems": 0]) { _, value in value }],
      required: ["scope", "components", "anchors"])
  }

  static var capabilities: [String: Any] {
    ["command": name, "matrixSchema": schema("matrix"), "selectionSchema": selectionSchema,
     "resultSchema": ["type": "object", "required": ["revision", "pathTransformSelection"],
                      "properties": ["revision": ["type": "string"], "pathTransformSelection": selectionSchema]],
     "targets": ["saved", "vectorMask", "shape"],
     "selection": "Omit both index fields to transform the whole path. Supply either zero-based components or anchors. The result reports the resulting selection, including anchors inserted in a fitted segment.",
     "curve": "Affine edits transform selected anchors and handles directly. Projective edits fit fully selected cubic segments within 1/64 document pixel. Unselected anchors and their handles retain their coordinates.",
     "desktop": "Choose a path, vector mask or shape contour, then press Command-T. The shared Free Transform preview, modes, modifier cursors, fixed turns and Undo apply to the selected geometry.",
     "adobe": "No corresponding independent path or anchor transform exists in the pinned Photoshop v2 API. Use the Photato command for this workflow."]
  }

  static func selection(_ value: PathTransformSelection) -> [String: Any] {
    var result: [String: Any] = ["scope": "all", "components": [Int](), "anchors": [[String: Int]]()]
    switch value {
    case .all: break
    case .components(let components):
      result["scope"] = "components"
      result["components"] = components
    case .anchors(let anchors):
      result["scope"] = "anchors"
      result["anchors"] = anchors.map { ["component": $0.component, "knot": $0.knot] }
    }
    return result
  }
}

extension AutomationCommand {
  func pathTransformOptions() throws -> PathTransformRequest {
    let id = try actionUUID("id")
    let target: PathTransformTarget
    switch try string("target") {
    case "saved": target = .saved(id)
    case "vectorMask": target = .vectorMask(id)
    case "shape": target = .shape(id)
    default: throw AutomationFailure(status: 400, message: "Unknown path target.")
    }
    guard parameters["components"] == nil || parameters["anchors"] == nil else {
      throw AutomationFailure(status: 400, message: "Choose components or anchors.")
    }
    let selection: PathTransformSelection
    if let value = parameters["components"] {
      guard let indices = try BrushAPI.merge(value, schema: PathTransformAPI.schema("components")) as? [Double],
            Set(indices).count == indices.count else {
        throw AutomationFailure(status: 400, message: "Supply unique path components.")
      }
      selection = .components(indices.map(Int.init))
    } else if let value = parameters["anchors"] {
      guard let indices = try BrushAPI.merge(value, schema: PathTransformAPI.schema("anchors")) as? [[String: Double]]
      else { throw AutomationFailure(status: 400, message: "Invalid path anchor selection.") }
      let anchors: [PathTransformAnchor] = try indices.map {
        guard let component = $0["component"], let knot = $0["knot"] else {
          throw AutomationFailure(status: 400, message: "Supply an anchor's component and knot.")
        }
        return .init(component: Int(component), knot: Int(knot))
      }
      guard Set(anchors).count == anchors.count else {
        throw AutomationFailure(status: 400, message: "Supply unique path anchors.")
      }
      selection = .anchors(anchors)
    } else {
      selection = .all
    }
    let (matrix, _) = try selectionTransformOptions()
    return .init(target: target, selection: selection, matrix: matrix)
  }
}
