import Foundation
import PhotoCraftCore

extension WarpDefinition {
  static var apiSchema:[String:Any] {
    let point:[String:Any] = ["type":"object","additionalProperties":false,"required":["x","y"],"properties":["x":["type":"number","minimum":-1_000_000,"maximum":1_000_000],"y":["type":"number","minimum":-1_000_000,"maximum":1_000_000]]]
    let knots:[String:Any] = ["type":"array","minItems":2,"maxItems":17,"items":["type":"number","minimum":0,"maximum":1]]
    return ["type":"object","additionalProperties":false,"properties":[
      "style":["type":"string","enum":WarpStyle.allCases.map(\.rawValue),"default":"none"],
      "bend":["type":"number","minimum":-100,"maximum":100,"default":0],
      "horizontalDistortion":["type":"number","minimum":-100,"maximum":100,"default":0],
      "verticalDistortion":["type":"number","minimum":-100,"maximum":100,"default":0],
      "vertical":["type":"boolean","default":false],
      "interpolation":["type":"string","enum":Resampling.allCases.map(\.rawValue),"default":"Bicubic"],
      "sourceBounds":["anyOf":[["type":"null"],BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000),"y":BrushAPI.number(-1_000_000,1_000_000),"width":BrushAPI.number(Double.leastNonzeroMagnitude,1_000_000),"height":BrushAPI.number(Double.leastNonzeroMagnitude,1_000_000)])]],
      "mesh":["type":"object","additionalProperties":false,"required":["us","vs","points"],"properties":["us":knots,"vs":knots,"points":["type":"array","minItems":16,"maxItems":2401,"items":point]]]]]
  }
  var apiState:Any { (try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) ?? NSNull() }
  static var apiCapabilities:[String:Any] {
    ["command":"layer.warp","settingsSchema":apiSchema,"maximumPixels":WarpRaster.maximumPixels,
     "coordinates":"Optional sourceBounds retains the source frame x/y/width/height; null uses ordinary layer extents. Mesh points use unwarped layer pixels; us/vs ascend from0 to1. 3*(us.count−1)+1 control columns, analogous rows, row-major points. Warp precedes affine placement and Smart Filters. Presets take percentages.",
     "behavior":"Fifteen presets and custom bicubic meshes. Pixel layers bake once; Smart Objects retain per-instance Warp and unchanged source/cache. Linked pixel masks follow; unlinked masks stay in document space. One prepared Undo/Redo transaction, matching native preview output.",
     "availability":"Unlocked RGB raster layers and Smart Objects without a selection or vector mask; groups/type/shapes can first be converted to a Smart Object.",
     "persistence":"Editable Smart Object Warp requires native archive24. Rasterized outputs use existing formats. Editable PSD/PSB Warp export rejects explicitly.",
     "adobe":"No dedicated published v2 Warp endpoint. No authenticated actionJSON descriptor is implemented; such actions remain explicit unsupported errors.",
     "limits":"16 mesh patches per axis,256 tessellation cells per axis,134217728 triangle/pixel visits. Exact Photoshop output, live UI, richer contexts and PSD interchange remain unqualified."]
  }
}
extension AutomationCommand {
  func warpOptions() throws -> (UUID,WarpDefinition) {
    guard let id=UUID(uuidString:try string("layerID")),case .object(let fields)=parameters["settings"],Set(fields.keys).isSubset(of:["style","bend","horizontalDistortion","verticalDistortion","vertical","interpolation","mesh","sourceBounds"]) else { throw AutomationFailure(status:400,message:"Invalid Warp layer or settings.") }
    var settings=WarpDefinition()
    if let raw=fields["style"] { guard case .string(let s)=raw,let style=WarpStyle(rawValue:s) else { throw AutomationFailure(status:400,message:"Unknown Warp style.") };settings.style=style }
    for (key,path) in [("bend",\WarpDefinition.bend),("horizontalDistortion",\WarpDefinition.horizontalDistortion),("verticalDistortion",\WarpDefinition.verticalDistortion)] {
      if let raw=fields[key] { guard case .number(let n)=raw,n.isFinite,(-100...100).contains(n) else { throw AutomationFailure(status:400,message:"Warp amounts must be−100–100.") };settings[keyPath:path]=n }
    }
    if let raw=fields["vertical"] { guard case .bool(let b)=raw else { throw AutomationFailure(status:400,message:"Invalid Warp orientation.") };settings.vertical=b }
    if let raw=fields["interpolation"] { guard case .string(let s)=raw,let method=Resampling(rawValue:s) else { throw AutomationFailure(status:400,message:"Invalid Warp interpolation.") };settings.interpolation=method }
    if let raw=fields["sourceBounds"],case .null = raw {} else if let raw=fields["sourceBounds"] {
      guard case .object(let frame)=raw,Set(frame.keys)==["x","y","width","height"] else{throw AutomationFailure(status:400,message:"Invalid source Warp frame.")}
      func value(_ key:String)throws->Double{guard case .number(let number)=frame[key],number.isFinite else{throw AutomationFailure(status:400,message:"Source Warp frame must be finite.")};return number}
      settings.sourceBounds=try .init(x:value("x"),y:value("y"),width:value("width"),height:value("height"))
    }
    if let raw=fields["mesh"] {
      guard case .object(let mesh)=raw,Set(mesh.keys)==["us","vs","points"],case .array(let rawPoints)=mesh["points"],rawPoints.count<=2401 else { throw AutomationFailure(status:400,message:"Invalid Warp mesh.") }
      func knots(_ key:String) throws -> [Double] {
        guard case .array(let items)=mesh[key],(2...17).contains(items.count) else { throw AutomationFailure(status:400,message:"Invalid Warp knots.") }
        return try items.map { value in guard case .number(let n)=value,n.isFinite else { throw AutomationFailure(status:400,message:"Invalid Warp knot.") };return n }
      }
      let points=try rawPoints.map { value -> PathPoint in
        guard case .object(let p)=value,Set(p.keys)==["x","y"],case .number(let x)=p["x"],case .number(let y)=p["y"] else { throw AutomationFailure(status:400,message:"Invalid Warp control point.") };return PathPoint(x,y)
      }
      settings.mesh=try WarpMesh(us:knots("us"),vs:knots("vs"),points:points)
    }
    do { try settings.validate() } catch { throw AutomationFailure(status:400,message:error.localizedDescription) };return (id,settings)
  }
}
