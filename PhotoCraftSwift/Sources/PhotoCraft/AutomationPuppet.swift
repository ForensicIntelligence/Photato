import Foundation
import PhotoCraftCore

extension PuppetSettings {
  static var apiSchema:[String:Any] {
    let point:[String:Any]=["type":"object","additionalProperties":false,"required":["x","y"],"properties":["x":["type":"number","minimum":-1_000_000,"maximum":1_000_000],"y":["type":"number","minimum":-1_000_000,"maximum":1_000_000]]]
    return ["type":"object","additionalProperties":false,"properties":[
      "mode":["type":"string","enum":Mode.allCases.map(\.rawValue),"default":"normal"],"density":["type":"string","enum":Density.allCases.map(\.rawValue),"default":"normal"],
      "expansion":["type":"number","minimum":-200,"maximum":200,"default":2],"interpolation":["type":"string","enum":Resampling.allCases.map(\.rawValue),"default":"Bicubic"],
      "pins":["type":"array","maxItems":64,"items":["type":"object","additionalProperties":false,"required":["source"],"properties":["source":point,"destination":point,"rotation":["type":["number","null"],"minimum":-360,"maximum":360],"depth":["type":"integer","minimum":-1000,"maximum":1000,"default":0]]]]]]
  }
  static var apiCapabilities:[String:Any] {
    ["schema":apiSchema,"commands":["filter.apply","smartFilter.set"],"filterKind":"puppetWarp","parameter":"puppet","nativeArchiveVersion":25,
     "coordinates":"Pin source/destination use document pixels; omitted destination keeps the source. Omitted/null rotation is Auto; numeric degrees fix local rotation. Higher pin depth draws overlapping triangles later. Layer transforms move retained pins.",
     "engine":"Coverage mesh, cotangent ARAP/ASAP local-global solve,64 pins,8192 vertices,40 iterations, three modes/densities, expansion and premultiplied HDR-aware triangle sampling. Smart Objects retain editable pin programs in the filter stack; ordinary layers bake one transaction.",
     "limits":"8,388,608 source/output pixels and bounded coverage/factorization/raster work. Unlocked RGB targets without selections or vector masks. Groups/type/shapes require conversion to Smart Objects. Exact Photoshop meshes/pixels, richer contexts and live/platform qualification remain open.",
     "adobe":"No dedicated published Firefly Puppet endpoint; unverified actionJSON and editable PSD descriptors reject explicitly. Use Photato native25 or rasterize for PSD export."]
  }
}
