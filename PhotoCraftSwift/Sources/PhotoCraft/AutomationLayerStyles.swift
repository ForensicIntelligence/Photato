import Foundation
import PhotoCraftCore

extension LayerStyle {
  var apiObject: Any { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) ?? NSNull() }
  static var apiSchema: [String: Any] {
    func number(_ low: Double, _ high: Double) -> [String: Any] { ["type": "number", "minimum": low, "maximum": high] }
    let pixel: [String: Any] = ["type": "object", "additionalProperties": false,
      "required": ["r", "g", "b", "a"], "properties": ["r": number(0,1), "g": number(0,1), "b": number(0,1), "a": number(0,1)]]
    let effect: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["kind"], "properties": [
      "kind": ["type": "string", "enum": LayerEffect.Kind.allCases.map(\.rawValue)],
      "enabled": ["type": "boolean"], "opacity": number(0,1), "blendMode": ["type": "string", "enum": BlendMode.allCases.map(\.rawValue)],
      "color": pixel, "size": number(0,250), "distance": number(0,30000), "angle": number(-360,360), "spread": number(0,100),
      "useGlobalLight": ["type": "boolean"], "position": ["type": "string", "enum": ["inside", "outside", "center"]],
      "depth": number(1,1000), "soften": number(0,16), "highlightColor": pixel, "shadowColor": pixel,
      "highlightOpacity": number(0,1), "shadowOpacity": number(0,1),
      "gradient": ["type": "object", "description": "Native GradientFill Codable object; required for gradientOverlay. Preserve the object read from layer state when editing complex stops."],
      "pattern": ["type": "object", "description": "Native PatternFill Codable object, including patternID, placement and linked; required for patternOverlay. The patternID must exist in the document."],
    ]]
    return ["type": ["object", "null"], "additionalProperties": false, "properties": [
      "enabled": ["type": "boolean"], "fillOpacity": number(0,1), "scale": number(1,1000),
      "lightAngle": number(-360,360), "lightAltitude": number(0,90),
      "effects": ["type": "array", "maxItems": 32, "items": effect],
    ]]
  }
  static var apiCapabilities: [String: Any] {
    ["command": "layer.style", "schema": apiSchema, "maximumCanvasPixels": 8_388_608,
      "nativeArchiveVersion": 13, "kinds": LayerEffect.Kind.allCases.map(\.rawValue),
      "targets": "Editable raster, text, shape, fill and isolated group layers; no adjustment layers. Replaces the entire style, null clears. Full locks reject. Selection does not restrict effects.",
      "copyPaste": "Read layers[].style and submit it to layer.style for one or more layerIDs. Pattern references must already exist in the destination document.",
      "limitations": "Native approximations; Photoshop pixel parity, contours, noise, advanced blending, all bevel variants and effects beyond canvas bounds are unqualified. Merge of styled layers is guarded. PSD supports the represented drop/inner shadows, glows, stroke and color overlays; other effects require native archives or explicit flattened output."]
  }
}

extension AutomationCommand {
  func layerStyleCommand(document: CraftDocument) throws -> Command {
    guard case .array(let values) = parameters["layerIDs"], (1...64).contains(values.count) else {
      throw AutomationFailure(status: 400, message: "Provide one to64 unique layerIDs.")
    }
    let ids = try values.map { value -> UUID in
      guard case .string(let text) = value, let id = UUID(uuidString: text) else {
        throw AutomationFailure(status: 400, message: "Invalid layer UUID.")
      }
      return id
    }
    guard Set(ids).count == ids.count else { throw AutomationFailure(status: 400, message: "Duplicate layer UUID.") }
    guard Set(ids).isSubset(of: Set(document.layers.map(\.id))) else { throw AutomationFailure(status: 404, message: "Layer not found.") }
    guard let value = parameters["style"] else { throw AutomationFailure(status: 400, message: "Missing style.") }
    if case .null = value { return .layerStyle(Set(ids), nil) }
    do {
      let style = try LayerStyle.decodeJSON(JSONSerialization.data(withJSONObject: value.jsonValue))
      try style.validate(in: document)
      return .layerStyle(Set(ids), style)
    } catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
  }
}
