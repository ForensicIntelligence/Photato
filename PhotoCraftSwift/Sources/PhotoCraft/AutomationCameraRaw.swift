import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension CameraRawSettings {
  static var apiSchema: [String:Any] {
    var properties: [String:Any] = [:]
    for c in controls { properties[c.key] = ["type":"number","minimum":c.minimum,"maximum":c.maximum,"default":c.initial] }
    let unit: [String:Any] = ["type":"number","minimum":0,"maximum":255]
    let point: [String:Any] = ["type":"array","minItems":2,"maxItems":2,"items":unit]
    for key in ["pointCurve","pointCurveRed","pointCurveGreen","pointCurveBlue"] { properties[key] = ["type":"array","maxItems":16,"items":point,"description":"Empty identity or 2–16 points with strictly increasing inputs."] }
    for key in ["hslHue","hslSat","hslLum"] { properties[key] = ["type":"array","minItems":8,"maxItems":8,"items":["type":"number","minimum":-100,"maximum":100]] }
    properties["curveSplits"] = ["type":"array","minItems":3,"maxItems":3,"items":["type":"number","minimum":5,"maximum":95],"description":"Strictly increasing region boundaries."]
    for key in ["gradeShadows","gradeMidtones","gradeHighlights","gradeGlobal"] { properties[key] = ["type":"object","additionalProperties":false,"properties":["hue":["type":"number","minimum":0,"maximum":360],"sat":["type":"number","minimum":0,"maximum":100],"lum":["type":"number","minimum":-100,"maximum":100]]] }
    properties["vignetteStyle"] = ["type":"string","enum":["highlightPriority","colorPriority","paintOverlay"]]
    properties["seed"] = ["type":"integer","minimum":0,"maximum":UInt32.max]
    properties["pixelScale"] = ["type":"number","minimum":0.01,"maximum":16]
    return ["type":"object","additionalProperties":false,"properties":properties]
  }
  static var apiCapabilities: [String:Any] {
    ["schema":apiSchema,"commands":["filter.apply","smartFilter.set",CameraRawXMPAPI.name],"nativeArchiveVersion":21,
     "preset":"Load or save standard Camera Raw XMP for supported controls. Photato JSON presets retain all native values. XMP conversion is available through cameraRaw.settings.convert.",
     "controls":controls.map { ["key":$0.key,"title":$0.title,"group":$0.group] },
     "workflow":"RGB Camera Raw Filter with editable Smart Filters; sensor RAW decoding is not provided by this filter.",
     "adobe":"Published /v2/edit light, color saturation/vibrance, effects, noiseReduction, sharpness and sharpen subsets share this engine. Other edits and Camera Raw action descriptors fail explicitly.",
     "limits":"8,388,608 layer pixels, RGB image target; no Adobe pixel/model equivalence or PSD/PSB editable Camera Raw descriptor interchange."]
  }
}


enum CameraRawXMPAPI {
  static let name = "cameraRaw.settings.convert"
  static let definition = AutomationCommand.Definition(name: name,
    parameters: ["mode": "raw or rendered", "xmp": "Camera Raw XMP text", "settings": "Photato Camera Raw settings"],
    description: "Convert Camera Raw XMP and Photato settings without changing the shared document.",
    optionalParameters: ["xmp", "settings"])

  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "mode": return ["type": "string", "enum": ["raw", "rendered"]]
    case "xmp": return ["type": "string", "minLength": 1, "maxLength": CameraRawXMP.maximumBytes]
    default: return ["anyOf": [RawDevelopment.apiSchema, CameraRawSettings.apiSchema]]
    }
  }

  static func packet(_ value: AutomationValue?) throws -> Data {
    guard case .string(let text) = value, !text.isEmpty, text.utf8.count <= CameraRawXMP.maximumBytes else {
      throw AutomationFailure(status: 400, message: "Camera Raw XMP must be text under 256 KiB.")
    }
    return Data(text.utf8)
  }

  static func convert(_ command: AutomationCommand) throws -> [String: Any] {
    let mode = try command.string("mode")
    guard mode == "raw" || mode == "rendered" else {
      throw AutomationFailure(status: 400, message: "Camera Raw settings mode must be raw or rendered.")
    }
    let xmp = command.parameters["xmp"]
    let settings = command.parameters["settings"]
    guard (xmp == nil) != (settings == nil) else {
      throw AutomationFailure(status: 400, message: "Supply either XMP text or a settings object.")
    }
    do {
      if xmp != nil {
        let data = try packet(xmp)
        let decoded = try mode == "raw"
          ? JSONEncoder().encode(CameraRawXMP.read(data, into: RawDevelopment()))
          : JSONEncoder().encode(CameraRawXMP.read(data))
        var object = try JSONSerialization.jsonObject(with: decoded) as! [String: Any]
        if mode == "raw" {
          object["temperature"] = object["temperature"] ?? NSNull()
          object["tint"] = object["tint"] ?? NSNull()
        }
        return ["mode": mode, "settings": object]
      }
      guard let settings else { throw CraftError.invalid("Missing Camera Raw settings.") }
      let data = try JSONSerialization.data(withJSONObject: settings.jsonValue, options: .fragmentsAllowed)
      let output = try mode == "raw"
        ? CameraRawXMP.write(RawDevelopment.decodeJSON(data))
        : CameraRawXMP.write(CameraRawSettings.decodeJSON(data))
      return ["mode": mode, "xmp": String(decoding: output, as: UTF8.self)]
    } catch let failure as AutomationFailure { throw failure }
    catch { throw AutomationFailure(status: 400, message: error.localizedDescription) }
  }
}
