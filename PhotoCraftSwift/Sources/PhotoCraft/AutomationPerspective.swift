import Foundation
import PhotoCraftCore

extension PerspectiveSettings {
  static var apiSchema:[String:Any] {
    let point:[String:Any]=["type":"object","additionalProperties":false,"required":["x","y"],"properties":["x":["type":"number","minimum":-1_000_000,"maximum":1_000_000],"y":["type":"number","minimum":-1_000_000,"maximum":1_000_000]]]
    let quad:[String:Any]=["type":"array","minItems":4,"maxItems":4,"items":point]
    return ["type":"object","additionalProperties":false,"properties":[
      "planes":["type":"array","maxItems":16,"items":["type":"object","additionalProperties":false,"required":["source"],"properties":["source":quad,"destination":quad]]],
      "locks":["type":"array","maxItems":64,"items":["type":"object","additionalProperties":false,"required":["plane","edge","axis"],"properties":["plane":["type":"integer","minimum":0,"maximum":15],"edge":["type":"integer","minimum":0,"maximum":3],"axis":["type":"string","enum":["horizontal","vertical"]]]]],
      "interpolation":["type":"string","enum":Resampling.allCases.map(\.rawValue),"default":"Bicubic"],
      "straighten":["type":"string","enum":Straighten.allCases.map(\.rawValue)]]]
  }
  static var apiCapabilities:[String:Any] {
    ["schema":apiSchema,"commands":["filter.apply","smartFilter.set"],"filterKind":"perspectiveWarp","parameter":"perspective","nativeArchiveVersion":26,
     "coordinates":"Four clockwise corners from top-left, in document pixels. Destination defaults to source. Source corners within0.5px link. Plane/edge indices are zero-based. Optional straighten modifies canonical destinations once; locks persist. Layer transforms carry source/destination points; non-axis-aligned transforms release axis locks without changing the transformed plane geometry.",
     "engine":"Up to16 convex planes, shared-edge corrected homographies, exact inverse sampling for a single plane, bounded256-cell tessellation per axis for multiple planes, premultiplied HDR sampling. Smart Objects retain editable programs; ordinary layers bake one undoable transaction.",
     "limits":"8,388,608 source/output pixels and bounded raster work. Unlocked RGB targets without selections or vector masks; alpha/Quick Mask targets reject. Convert groups/type/shapes to Smart Objects first. Exact Photoshop pixels and richer/live/platform contexts remain open.",
     "adobe":"No dedicated published Firefly Perspective Warp endpoint. Unverified actionJSON and editable PSD descriptors reject explicitly; use native26 or rasterize before PSD export."]
  }
}
