import Foundation
import PhotoCraftCore

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
    ["schema":apiSchema,"commands":["filter.apply","smartFilter.set"],"nativeArchiveVersion":21,
     "preset":"Bounded UTF-8 JSON settings, .photatoraw; partial keys merge neutral defaults.",
     "controls":controls.map { ["key":$0.key,"title":$0.title,"group":$0.group] },
     "workflow":"RGB Camera Raw Filter with editable Smart Filters; sensor RAW decoding is not provided by this filter.",
     "adobe":"Published /v2/edit light, color saturation/vibrance, effects, noiseReduction, sharpness and sharpen subsets share this engine. Other edits and Camera Raw action descriptors fail explicitly.",
     "limits":"8,388,608 layer pixels, RGB image target; no Adobe pixel/model equivalence or PSD/PSB editable Camera Raw descriptor interchange."]
  }
}
