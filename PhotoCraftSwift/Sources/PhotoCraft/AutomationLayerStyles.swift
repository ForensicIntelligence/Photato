import Foundation
import PhotoCraftCore

extension LayerStyle {
  var apiObject: Any { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) ?? NSNull() }
  static var apiSchema: [String: Any] {
    func number(_ low: Double, _ high: Double) -> [String: Any] { ["type": "number", "minimum": low, "maximum": high] }
    let pixel: [String: Any] = ["type": "object", "additionalProperties": false,
      "required": ["r", "g", "b", "a"], "properties": ["r": number(0,1), "g": number(0,1), "b": number(0,1), "a": number(0,1)]]
    var effect: [String: Any] = ["type": "object", "additionalProperties": false, "required": ["kind"], "properties": [
      "kind": ["type": "string", "enum": LayerEffect.Kind.allCases.map(\.rawValue)],
      "enabled": ["type": "boolean"], "opacity": number(0,1), "blendMode": ["type": "string", "enum": BlendMode.allCases.map(\.rawValue)],
      "color": pixel, "size": number(0,250), "distance": number(0,30000), "angle": number(-360,360), "spread": number(0,100),
      "useGlobalLight": ["type": "boolean"], "position": ["type": "string", "enum": ["inside", "outside", "center"]],
      "depth": number(1,1000), "soften": number(0,16), "highlightColor": pixel, "shadowColor": pixel,
      "highlightOpacity": number(0,1), "shadowOpacity": number(0,1),
      "gradient": ["type": "object", "description": "Native GradientFill Codable object; required for gradientOverlay. Preserve the object read from layer state when editing complex stops."],
      "pattern": ["type": "object", "description": "Native PatternFill Codable object, including patternID, placement and linked; required for patternOverlay. The patternID must exist in the document."],
    ]]
    var effectProperties=effect["properties"] as! [String:Any]
    effectProperties["advanced"]=AdvancedStyleAPI.nullable(AdvancedStyleAPI.advanced)
    effectProperties["distance"]=number(-30000,30000);effectProperties["depth"]=number(0,1000)
    effect["properties"]=effectProperties
    return ["type": ["object", "null"], "additionalProperties": false, "properties": [
      "enabled": ["type": "boolean"], "fillOpacity": number(0,1), "scale": number(1,1000),
      "lightAngle": number(-360,360), "lightAltitude": number(0,90),
      "effects": ["type": "array", "maxItems": 32, "items": effect],
      "referenceOffset":AdvancedStyleAPI.nullable(AdvancedStyleAPI.point), "sourcePSDData":["type":["string","null"],"contentEncoding":"base64","maxLength":1398104],
    ]]
  }
  static var apiCapabilities: [String: Any] {
    ["command": "layer.style", "schema": apiSchema, "maximumCanvasPixels": 8_388_608,
      "nativeArchiveVersion": 13,"advancedArchiveVersion":75,"advancedActionsVersion":30,"advancedDefaults":AdvancedStyleAPI.defaults,"globalLight":AdvancedStyleAPI.light,"patchCommand":"layer.style.patch","retainedInactiveFields":["noise","jitter","antiAlias","gradient.aligned","gradient.dither","gradient.stopColorAlpha","bevel.highlightEnabled","bevel.shadowEnabled","advancedBevel.genericBlendMode","advancedBevel.genericOpacity","effectColorAlpha"], "kinds": LayerEffect.Kind.allCases.map(\.rawValue),
      "targets": "Editable raster, text, shape, fill and isolated group layers; no adjustment layers. Replaces the entire style, null clears. Full locks reject. Selection does not restrict effects.",
      "temporalEditing": "Replace, patch and clear capture the current value on an enabled Style keyframe track before validation; replacement at the same time preserves key identity and interpolation. Frame Animation edits affect the selected frame. Preview is private, Cancel preserves the document and a committed edit uses one native Undo transaction.",
      "copyPaste": "Read layers[].style and submit it to layer.style for one or more layerIDs. Pattern references must already exist in the destination document.",
      "globalLightInterchange": "PSD/PSB integer shared angle/altitude, per-shadow Use Global Light and inactive local angles are retained through native/API/Adobe output. Fractional document lights and conflicting legacy fallback settings require Photato or an explicit shared-light choice. Global directions wrap consistently; local bevel altitude stays independent. Advanced PSD effects remain guarded.",
      "limitations": "Legacy approximation and advanced original-source stack are distinct. Source contours, glow methods, bevel variants/texture, paint and shared light have typed controls; source-inactive fields are retained, not executed. Exact source/Photoshop words, vector outlines, text gamma, off-canvas source and larger effect processing remain unqualified. Advanced maps have a16,777,216-sample/512MiB scratch budget within the existing8,388,608-pixel preparation path. Advanced editable PSD export rejects; native archives or explicit flattened output preserve the intended scope."]
  }
}

extension AutomationCommand {
  func layerStyleCommand(document: CraftDocument) throws -> Command {
    guard case .array(let values) = parameters["layerIDs"], (1...LayerLimits.maximumLayers).contains(values.count) else {
      throw AutomationFailure(status: 400, message: "Provide one to8,000 unique layerIDs.")
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
    let light=try AdvancedStyleAPI.readLight(parameters["globalLight"])
    if case .null = value { return light.map{.layerStyles(LayerStyleEdit(layerIDs:Set(ids),style:nil,globalLight:$0))} ?? .layerStyle(Set(ids), nil) }
    do {
      let style = try LayerStyle.decodeJSON(JSONSerialization.data(withJSONObject: value.jsonValue))
      try style.validate(in: document)
      return light.map{.layerStyles(LayerStyleEdit(layerIDs:Set(ids),style:style,globalLight:$0))} ?? .layerStyle(Set(ids), style)
    } catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
  }
}
