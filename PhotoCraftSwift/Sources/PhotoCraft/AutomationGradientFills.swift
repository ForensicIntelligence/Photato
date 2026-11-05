import Foundation
import PhotoCraftCore

enum GradientFillAPI {
  static let command = "gradient.fill.patch"

  /// Objects merge with the current fill; stop arrays replace as complete arrays.
  static var patchSchema: [String: Any] {
    var schema = ShapeAPI.gradient
    schema["required"] = [String]()
    schema["minProperties"] = 1
    var properties = schema["properties"] as! [String: [String: Any]]
    for key in ["gradient", "placement"] {
      properties[key]?["required"] = [String]()
    }
    schema["properties"] = properties
    return schema
  }

  static func schema(_ key: String) -> [String: Any] {
    key == "fill" ? patchSchema : PathAPI.schema("layerID")
  }

  static var stateSchema: [String: Any] {
    BrushAPI.object([
      "activeLayerID": ["anyOf": [PathAPI.schema("layerID"), ["type": "null"]]],
      "activeFill": ["anyOf": [ShapeAPI.gradient, ["type": "null"]]],
      "canEditActive": BrushAPI.flag,
    ], required: ["activeLayerID", "activeFill", "canEditActive"])
  }

  static var capabilities: [String: Any] {
    ["command": command, "patchSchema": patchSchema, "stateSchema": stateSchema, "actionsVersion": 47,
     "resultSchema": ["type": "object", "required": ["revision", "gradientFills"],
       "properties": ["revision": ["type": "string"], "gradientFills": stateSchema]],
     "behavior": "Edits an existing live Gradient Fill through the same setGradientFill command as native Properties and canvas controls. Omitted object fields retain current values; supplied stop arrays replace the whole array. Colours must be captured, not foreground/background references. One Undo; masks, layer identity, placement transform and unrelated fields remain intact.",
     "coordinates": "Angle is counterclockwise degrees; scale and offsets are fractions, not UI percentages. Offset uses the native aligned layer/artboard/canvas reference frame.",
     "limits": "Native GradientFill validation and existing API sharing/body limits apply. Up to 1000 colour and 1000 opacity stops. Empty root patch, unknown fields, nonfinite/out-of-range values and non-gradient targets reject atomically.",
     "adobe": "Photato extension. No corresponding live Gradient Fill route or qualified actionJSON descriptor is added to the pinned Adobe v2 contract.",
     "remaining": "Gradient creation, Classic Gradient painting and preset-library automation, full Photoshop default/output/GRD/noise/dither and physical-platform qualification remain open."]
  }
}

extension AutomationCommand {
  func gradientFillCommand(_ document: CraftDocument) throws -> Command {
    try pathFields(["layerID", "fill"], [])
    let id = try actionUUID("layerID")
    guard let layer = document.layers.first(where: { $0.id == id }),
      case .gradientFill(let current) = layer.content
    else { throw AutomationFailure(status: 404, message: "Gradient Fill layer not found.") }
    guard !document.isLocked(id) else {
      throw AutomationFailure(status: 422, message: "Unlock the Gradient Fill layer and its parent groups.")
    }
    guard let value = parameters["fill"], case .object(let fields) = value, !fields.isEmpty
    else { throw AutomationFailure(status: 400, message: "Supply a nonempty Gradient Fill patch.") }
    do {
      let merged = try BrushAPI.merge(value, schema: GradientFillAPI.patchSchema,
        base: BrushAPI.json(current), path: "fill")
      let fill = try JSONDecoder().decode(GradientFill.self,
        from: JSONSerialization.data(withJSONObject: merged))
      try fill.validate()
      return .setGradientFill(id, fill)
    } catch let error as AutomationFailure { throw error }
    catch { throw AutomationFailure(status: 400, message: "Invalid Gradient Fill: \(error.localizedDescription)") }
  }
}

extension EditorStore {
  var gradientFillState: [String: Any] {
    guard let layer = activeLayer, case .gradientFill(let fill) = layer.content else {
      return ["activeLayerID": NSNull(), "activeFill": NSNull(), "canEditActive": false]
    }
    return ["activeLayerID": layer.id.uuidString, "activeFill": BrushAPI.json(fill),
      "canEditActive": canEditGradientFill(layer.id)]
  }
}
