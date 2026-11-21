import Foundation
import PhotoCraftCore
import PhotoCraftImaging

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
      "gradient": ShapeAPI.gradient,
      "pattern": ShapeAPI.pattern,
    ]]
    var effectProperties=effect["properties"] as! [String:Any]
    effectProperties["advanced"]=AdvancedStyleAPI.nullable(AdvancedStyleAPI.advanced)
    effectProperties["distance"]=number(-30000,30000);effectProperties["depth"]=number(0,1000)
    effect["properties"]=effectProperties
    return ["type": ["object", "null"], "additionalProperties": false, "properties": [
      "restrictedChannels":["type":["array","null"],"maxItems":3,"uniqueItems":true,"items":["type":"integer","minimum":0,"maximum":2]],
      "enabled": ["type": "boolean"], "fillOpacity": number(0,1), "scale": number(1,1000),
      "lightAngle": number(-360,360), "lightAltitude": number(0,90),
      "effects": ["type": "array", "maxItems": 32, "items": effect],
      "referenceOffset":AdvancedStyleAPI.nullable(AdvancedStyleAPI.point), "sourcePSDData":["type":["string","null"],"contentEncoding":"base64","maxLength":1398104],
    ]]
  }
  static var apiCapabilities: [String: Any] {
    ["channelBlending":["field":"restrictedChannels","components":["0":"Red","1":"Green","2":"Blue"],"commands":["layer.style","layer.style.patch"],"nativeArchiveVersion":89,"ActionsVersion":56,"behavior":"Existing native Blending Options and style transactions; omitted/nil retains legacy rendering,[] explicitly enables all channels. Numeric RGB exclusions preserve backdrop components after layer/group/clipping composition; all excluded has no contribution. Alpha/transparent/effect/group/default Photoshop details remain unqualified.","capacity":"Channel-only settings do not require effect maps; sparse maximum geometry retained. Existing effect limits remain independent.","scope":"RGB8/16/32 only. Non-RGB component exclusion,BlendIf,knockout and other advanced flags remain functional gaps; no full L03 closure. No new Firefly route/descriptor support claimed."],"command": "layer.style", "schema": apiSchema,
      "maximumCanvasPixels": maximumWholeCanvasPixels,
      "maximumCanvasPixelsScope": "Whole-canvas effect preparation. Basic RGB Pattern Overlay, regional Drop Shadow and RGB channel-only styles retain document dimensions.",
      "maximumChannelCanvasDimension": Surface.maxDimension,
      "regionalPatternOverlay": [
        "maximumCanvasDimension": Surface.maxDimension, "commands": ["layer.style", "layer.style.patch"],
        "scope": "RGB styles containing basic Pattern Overlay effects and no advanced or opaque source effect records. Renders bounded regions at their absolute document coordinates.",
        "sparseComposition": "Top-level translated raster sources with finite coverage can skip implicit canvas tiles when the surrounding stack also admits sparse composition.",
      ],
      "patternCanvasPreview": [
        "routes": ["preview.png", "channel-preview.png", "proof-preview.png"],
        "maximumCanvasDimension": Surface.maxDimension,
        "maximumPeriodPixels": PatternCanvasPreview.maximumPeriodPixels,
        "scope": "Area reduction of basic RGB overlays. Eligible repeats use bounded cells and sparse corrections. Wide nonperiodic fits can reduce document-coordinate patches in tile order without a full composite. Composite, RGB channel and proof previews share the editor renderer.",
      ],
      "nativeArchiveVersion": 13,"advancedArchiveVersion":75,"advancedActionsVersion":30,"advancedDefaults":AdvancedStyleAPI.defaults,"globalLight":AdvancedStyleAPI.light,"patchCommand":"layer.style.patch","retainedInactiveFields":["nonDropShadow.noise","jitter","nonDropShadow.antiAlias","gradient.aligned","gradient.dither","gradient.stopColorAlpha","bevel.highlightEnabled","bevel.shadowEnabled","advancedBevel.genericBlendMode","advancedBevel.genericOpacity","effectColorAlpha"], "kinds": LayerEffect.Kind.allCases.map(\.rawValue),
      "advancedDropShadow": ["editableFiles": ["psd", "psb"], "controls": ["contour", "antiAlias", "noise", "knocksOut"],
        "regionalCanvasDimension": Surface.maxDimension,
        "regionalScope": "RGB Drop Shadow stacks, optionally with basic Pattern Overlay. Each region prepares the shifted coverage and its filter margin. Scratch limits still apply per effect.",
        "overviewScope": "Eligible RGB Drop Shadows on uniform raster and fill layers reuse constant regions and render edge profiles and sparse corrections. Composite, channel and soft-proof PNG use the same reduced preview.",
        "contourContinuity": "Optional smoothPoints has one Boolean per point. False sets a corner.",
        "adobeRoute": "POST /v2/create-composite",
        "adobeFields": ["contour", "antiAliased", "noise", "layerKnocksOut"]],
      "targets": "Effect styles target editable raster, text, shape, fill and isolated group layers. Pure RGB channel settings also support adjustment layers and sparse maximum geometry. Replaces the entire style, null clears. Full locks reject. Selection does not restrict effects.",
      "temporalEditing": "Replace, patch and clear capture the current value on an enabled Style keyframe track before validation; replacement at the same time preserves key identity and interpolation. Frame Animation edits affect the selected frame. Preview is private, Cancel preserves the document and a committed edit uses one native Undo transaction.",
      "copyPaste": "Read layers[].style and submit it to layer.style for one or more layerIDs. Pattern references must already exist in the destination document.",
      "globalLightInterchange": "PSD/PSB integer shared angle/altitude, per-shadow Use Global Light and inactive local angles are retained through native/API/Adobe output. Fractional document lights and conflicting legacy fallback settings require Photato or an explicit shared-light choice. Global directions wrap consistently; local bevel altitude stays independent.",
      "limitations": "Editable advanced PSD/PSB interchange covers represented Drop Shadow controls. Other advanced effects retain their full settings in Photato documents. Exact Photoshop samples, vector outlines, text gamma, off-canvas source and larger effect processing remain unqualified. Advanced maps have a 16,777,216-sample and 512 MiB scratch budget within the 8,388,608-pixel preparation path."]
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
