import Foundation
import PhotoCraftCore

enum SelectionGeometryAPI {
  static let commands=["selection.shape","selection.inverse","selection.feather"]
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "shape":
      let rect=BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000,integer:true),"y":BrushAPI.number(-1_000_000,1_000_000,integer:true),"width":BrushAPI.number(1,Double(Surface.maxDimension),integer:true),"height":BrushAPI.number(1,Double(Surface.maxDimension),integer:true)],required:["x","y","width","height"])
      let point=BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000),"y":BrushAPI.number(-1_000_000,1_000_000)],required:["x","y"])
      return ["oneOf":[BrushAPI.object(["rectangle":rect],required:["rectangle"]),BrushAPI.object(["ellipse":rect],required:["ellipse"]),BrushAPI.object(["polygon":["type":"array","minItems":3,"maxItems":4096,"items":point]],required:["polygon"])]]
    case "mode":return SelectionToolAPI.schema("mode")
    case "antiAlias":return BrushAPI.flag
    case "feather","radius":return BrushAPI.number(0,100)
    default:return [:]
    }
  }
  static var capabilities:[String:Any] {[
    "commands":commands,"maximumDimension":Surface.maxDimension,"maximumPixels":Surface.maxPixels,
    "nativePagedSelectionVersion":64,"maximumPatchPixels":RasterGeometry.maximumPatchPixels,
    "behavior":"Native rectangle/ellipse/polygon coverage, mode combination, inversion and feathering use the same prepared desktop/history commands. Shape defaults: replace, antiAlias=true, feather=0. Coordinates are canvas pixels; outside coverage is clipped. selection.rectangle/clear retain their existing contracts.",
    "storage":"Small coverage retains legacy GRAY8 bytes; large coverage uses immutable raster samples/index pages and checked dense extraction. Current backing uses16-byte RGBA Float tiles per explicit sample, not compact one-byte storage. Heap estimates exclude mapped residency and temporary extraction buffers.",
    "presentation":"Large contours are bounded to2048 cells per side over the viewport region, with adjacent samples across clipped edges. Coarse display does not resample stored selection values.",
    "limits":"Existing inference/refinement/filter/mode limits remain independent. Feather0–100 follows current native semantics; full Photoshop ranges/kernels/off-canvas retention, compact coverage, physical60fps and supported-platform qualification remain open. Adobe UXP documents these selection concepts, but corresponding execute-actions descriptors/UXP execution remain unqualified; no dedicated Adobe selection route is invented."]}
}
extension AutomationCommand {
  func selectionGeometryCommand()throws->Command {
    switch name {
    case "selection.inverse":return .invertSelection
    case "selection.feather":return .featherSelection(try number("radius",range:0...100))
    case "selection.shape":
      guard let value=parameters["shape"] else {throw AutomationFailure(status:400,message:"Selection shape is required.")}
      let raw=try BrushAPI.merge(value,schema:SelectionGeometryAPI.schema("shape"),path:"shape")as![String:Any]
      let shape:SelectionShape
      if let rect=raw["rectangle"]as?[String:Double] {shape = .rectangle(.init(x:Int(rect["x"]!),y:Int(rect["y"]!),width:Int(rect["width"]!),height:Int(rect["height"]!)))}
      else if let rect=raw["ellipse"]as?[String:Double] {shape = .ellipse(.init(x:Int(rect["x"]!),y:Int(rect["y"]!),width:Int(rect["width"]!),height:Int(rect["height"]!)))}
      else if let points=raw["polygon"]as?[[String:Double]] {shape = .polygon(points.map{SelectionPoint($0["x"]!,$0["y"]!)})}
      else {throw AutomationFailure(status:400,message:"Invalid selection shape.")}
      let feather=try parameters["feather"].map {_ in try number("feather",range:0...100)} ?? 0
      return .selectShape(shape,try selectionMode(.replace),try adjustmentBrushFlag("antiAlias",true),feather)
    default:throw AutomationFailure(status:400,message:"Unknown selection geometry command.")
    }
  }
}
