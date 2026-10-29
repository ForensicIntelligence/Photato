import Foundation
import PhotoCraftCore

extension BlurGallerySettings {
  static var apiSchema: [String:Any] {
    func number(_ min:Double,_ max:Double)->[String:Any] { ["type":"number","minimum":min,"maximum":max] }
    let point:[String:Any] = ["type":"object","additionalProperties":false,"required":["x","y"],"properties":["x":number(-4,5),"y":number(-4,5)]]
    let pin:[String:Any] = ["type":"object","additionalProperties":false,"properties":["x":number(-4,5),"y":number(-4,5),"blur":number(0,500),"radiusX":number(0.001,8),"radiusY":number(0.001,8),"angle":number(-360,360),"feather":number(0,0.999),"roundness":number(0,100),"focus":number(0,2),"transition":number(0.001,2),"blurAngle":number(0,360)]]
    let pins:[String:Any] = ["type":"array","maxItems":64,"items":pin]
    var properties:[String:Any] = ["enabled":["type":"array","maxItems":5,"uniqueItems":true,"items":["type":"string","enum":Mode.allCases.map(\.rawValue)],"default":["field"]],"field":pins,"iris":pins,"tiltShift":pins,"spin":pins,
      "paths":["type":"array","maxItems":16,"items":["type":"object","additionalProperties":false,"properties":["points":["type":"array","minItems":2,"maxItems":32,"items":point],"speed":number(0,500),"taper":number(0,100),"curved":["type":"boolean"],"centered":["type":"boolean"]]]],
      "lightMin":number(0,1),"lightMax":number(0,1),"noise":["type":"string","enum":Noise.allCases.map(\.rawValue)],"noiseSize":number(0.1,10),"seed":["type":"integer","minimum":0,"maximum":UInt32.max],"strobeFlashes":["type":"integer","minimum":1,"maximum":30]]
    for key in ["lightBokeh","bokehColor","noiseAmount","noiseRoughness","noiseColor","noiseHighlights","strobeStrength"] { properties[key]=number(0,100) }
    properties["strobeDuration"] = number(0,360)
    return ["type":"object","additionalProperties":false,"properties":properties]
  }
  static var apiCapabilities:[String:Any] {
    ["schema":apiSchema,"commands":["filter.apply","smartFilter.set"],"filterKind":"blurGallery","parameter":"gallery","nativeArchiveVersion":29,
     "coordinates":"Pin/path x,y are normalized source-image coordinates; ellipse radii, focus and transition are fractions of the shorter source edge. Blur/speed are source pixels; angles are degrees. Source-relative settings follow Smart Object placement transforms.",
     "engine":"Enabled effects apply in field,iris,tiltShift,path,spin order. Up to64 pins per tool and16 paths with2–32 points. Lens blur interpolates six Gaussian levels plus identity; continuous motion uses up to64 premultiplied bilinear samples; spin strobes add up to30 flashes with1 or5 exposure samples each. Curved paths use Catmull–Rom interpolation. Selection coverage and transparency locks share the native filter transaction.",
     "workspace":"Native pins/path handles, numeric controls, multi-effect enablement, bokeh/noise, Preview, mask view, local undo/redo and document Cancel/OK. No document mutation before OK.",
     "limits":"8,388,608 source pixels, RGB targets. Independent Photoshop pixel/blur-composition/strobe matching and physical platform/live qualification remain open. Editable PSD/PSB Gallery descriptors are unsupported; save native29 or rasterize.",
     "adobe":"No dedicated published Blur Gallery endpoint or qualified actionJSON descriptor. Unknown descriptors reject; no Adobe operation is invented."]
  }
}
