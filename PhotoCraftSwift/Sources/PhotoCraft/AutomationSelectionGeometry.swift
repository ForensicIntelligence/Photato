import Foundation
import PhotoCraftCore

enum SelectionGeometryAPI {
  static let commands=["selection.shape","selection.inverse","selection.feather"]
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "shape":
      let rect=BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000,integer:true),"y":BrushAPI.number(-1_000_000,1_000_000,integer:true),"width":BrushAPI.number(1,Double(Surface.maxDimension),integer:true),"height":BrushAPI.number(1,Double(Surface.maxDimension),integer:true)],required:["x","y","width","height"])
      let point=BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000),"y":BrushAPI.number(-1_000_000,1_000_000)],required:["x","y"])
      let index = BrushAPI.number(0, Double(Surface.maxDimension - 1), integer: true)
      return ["oneOf":[BrushAPI.object(["rectangle":rect],required:["rectangle"]),BrushAPI.object(["ellipse":rect],required:["ellipse"]),BrushAPI.object(["polygon":["type":"array","minItems":3,"maxItems":4096,"items":point]],required:["polygon"]),BrushAPI.object(["row":index],required:["row"]),BrushAPI.object(["column":index],required:["column"])]]
    case "mode":return SelectionToolAPI.schema("mode")
    case "antiAlias":return BrushAPI.flag
    case "feather","radius":return BrushAPI.number(0,100)
    default:return [:]
    }
  }
  static var capabilities:[String:Any] {[
    "commands":commands,"maximumDimension":Surface.maxDimension,"maximumPixels":Surface.maxPixels,
    "nativePagedSelectionVersion":64,"maximumPatchPixels":RasterGeometry.maximumPatchPixels,
    "behavior":"Native rectangle/ellipse/polygon coverage, mode combination, inversion and feathering use the same prepared desktop/history commands. selection.shape also accepts {row:integer} or {column:integer} for one full-width row or full-height column, with zero-based in-canvas indices. Shape defaults: replace, antiAlias=true, feather=0. Coordinates are canvas pixels; outside geometry coverage is clipped. Single-pixel marquee tools capture mode/feather at pointer-down, preview the current row/column and commit once on release; dragging beyond the canvas clamps to its edge. selection.rectangle/clear retain their existing contracts.",
    "storage":"Small coverage retains legacy GRAY8 bytes; large coverage uses immutable raster samples/index pages and checked dense extraction. Current backing uses16-byte RGBA Float tiles per explicit sample, not compact one-byte storage. Heap estimates exclude mapped residency and temporary extraction buffers.",
    "presentation":"Large contours are bounded to2048 cells per side over the viewport region, with adjacent samples across clipped edges. Coarse display does not resample stored selection values.",
    "limits":"Existing inference/refinement/filter/mode limits remain independent. Feather0–100 follows current native semantics; full Photoshop ranges/kernels/off-canvas retention, compact coverage, physical60fps and supported-platform qualification remain open. Adobe UXP documents these selection concepts, but corresponding execute-actions descriptors/UXP execution remain unqualified; no dedicated Adobe selection route is invented."]}
}
extension AutomationCommand {
  func selectionGeometryCommand(in document: CraftDocument)throws->Command {
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
      else if let row = raw["row"] as? Double, row < Double(document.height),
              let rect = SinglePixelMarquee.row.rectangle(at: row, width: document.width, height: document.height) { shape = .rectangle(rect) }
      else if let column = raw["column"] as? Double, column < Double(document.width),
              let rect = SinglePixelMarquee.column.rectangle(at: column, width: document.width, height: document.height) { shape = .rectangle(rect) }
      else {throw AutomationFailure(status:400,message:"Invalid or out-of-canvas selection shape.")}
      let feather=try parameters["feather"].map {_ in try number("feather",range:0...100)} ?? 0
      return .selectShape(shape,try selectionMode(.replace),try adjustmentBrushFlag("antiAlias",true),feather)
    default:throw AutomationFailure(status:400,message:"Unknown selection geometry command.")
    }
  }
}
