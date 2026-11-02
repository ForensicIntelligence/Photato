import Foundation
import PhotoCraftCore

enum BackgroundLayerAPI {
  static let commands=["layer.background","pixels.clear"]
  static func schema(_ key:String)->[String:Any] {switch key {
    case "layerID":["type":"string","format":"uuid"]
    case "operation":BrushAPI.enumeration(["toLayer","fromLayer"])
    case "name":["type":"string","minLength":1,"maxLength":65535]
    case "mode":BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue))
    case "opacity":BrushAPI.number(0,1)
    case "color":["type":"integer","minimum":0,"maximum":11]
    default:["type":"array","minItems":4,"maxItems":4,"items":BrushAPI.number(0,1)]
  }}
  static var stateSchema:[String:Any] {BrushAPI.object(["available":BrushAPI.flag,"hasBackground":BrushAPI.flag,"activeIsBackground":BrushAPI.flag,"conversionOpen":BrushAPI.flag,"backgroundLayerID":["anyOf":[["type":"null"],["type":"string"]]]],required:["available","hasBackground","activeIsBackground","conversionOpen","backgroundLayerID"])}
  static var resultSchema:[String:Any] {["type":"object","required":["revision","backgroundLayer"],"properties":["revision":["type":"string"],"backgroundLayer":stateSchema]]}
  static var capabilities:[String:Any] {[
    "commands":commands,"stateSchema":stateSchema,"resultSchema":resultSchema,
    "identity":"Explicit isBackground layer state; a name is never identity. One opaque root layer at the canvas bottom; position, alpha, blend, opacity and masks require conversion. Native83 preserves identity; old documents retain ordinary-layer semantics. New opaque RGB File/New documents have Background; transparent documents have a normal layer.",
    "conversion":"layer.background toLayer takes optional name (Layer0), color label, mode and opacity. fromLayer takes optional opaque backgroundColor (desktop palette default), fills transparency and canvas padding, moves to bottom and restores Normal/100%. Initial fromLayer supports ordinary RGB raster roots without masks/styles/Smart Objects; richer/mode/merge contexts remain open.",
    "pixels":"pixels.clear shares native Clear and background palette fill. Cut and normal Eraser preserve Background opacity and use captured background color. Existing positional/transparency protections apply; normal alpha edits require conversion.",
    "history":"One native Undo/Redo transaction; source/revision/target/busy/cancel guards. Semantic Background Actions32, older Actions remain readable. Native83 opt-in is required on downloads carrying Background identity.",
    "adobe":"Published create-composite background_layer add/edit/delete, isVisible/image.source and explicit convertToLayer/convertedLayerName share the model. Background placement/move and unsupported direct properties reject. Full hosted/model/output/default/live/platform compatibility remains unqualified.",
    "limits":"Existing sparse/tiled surface, coordinate, import and API limits; no extra36MP in Background conversion/clear. Exact Photoshop sampling/fill/default/dialog/PSD interpretation and physical60fps/dense capacity remain open."
  ]}
}
extension AutomationCommand {
  func backgroundColor(default fallback:Pixel)throws->Pixel {
    guard let value=parameters["backgroundColor"] else{return fallback}
    let numbers=try BrushAPI.merge(value,schema:BackgroundLayerAPI.schema("backgroundColor")) as! [Double]
    let color=Pixel(Float(numbers[0]),Float(numbers[1]),Float(numbers[2]),Float(numbers[3]));do{try BackgroundLayer.validate(color)}catch{throw AutomationFailure(status:400,message:error.localizedDescription)};return color
  }
  func backgroundCommand(in document:CraftDocument,defaultColor:Pixel)throws->Command {
    guard let id=UUID(uuidString:try string("layerID")) else{throw AutomationFailure(status:400,message:"Invalid layer UUID.")}
    guard let layer=document.layers.first(where:{$0.id==id}) else{throw AutomationFailure(status:404,message:"Layer not found.")}
    if name=="pixels.clear"{return layer.isBackground ? .backgroundLayer(.clear(id,try backgroundColor(default:defaultColor))):.clear(id)}
    let operation=try string("operation")
    if operation=="fromLayer" {
      guard Set(parameters.keys).isSubset(of:["layerID","operation","backgroundColor"]) else{throw AutomationFailure(status:400,message:"fromLayer accepts only backgroundColor options.")}
      return .backgroundLayer(.fromLayer(id,try backgroundColor(default:defaultColor)))
    }
    guard operation=="toLayer",parameters["backgroundColor"]==nil else{throw AutomationFailure(status:400,message:"Invalid conversion options.")}
    var options=NewPixelLayerOptions(name:parameters["name"]==nil ? "Layer 0":try string("name"))
    if parameters["opacity"] != nil {options.opacity=Float(try number("opacity",range:0...1))}
    if parameters["mode"] != nil {guard let mode=BlendMode(rawValue:try string("mode")) else{throw AutomationFailure(status:400,message:"Invalid blend mode.")};options.mode=mode}
    if parameters["color"] != nil {options.color=LayerColorLabel(rawValue:UInt16(try integer("color",range:0...11)))!}
    return .backgroundLayer(.toLayer(id,options))
  }
}
@MainActor extension EditorStore {
  var backgroundLayerState:[String:Any] {["available":canConvertBackground,"hasBackground":document.layers.contains{$0.isBackground},"activeIsBackground":activeLayer?.isBackground ?? false,"conversionOpen":backgroundLayerDraft != nil,"backgroundLayerID":document.layers.first{$0.isBackground}?.id.uuidString as Any? ?? NSNull()]}
}
