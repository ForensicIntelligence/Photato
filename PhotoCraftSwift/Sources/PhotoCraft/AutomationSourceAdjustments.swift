import Foundation
import PhotoCraftCore

extension SourceAdjustment {
  var apiObject:[String:Any] {["kind":"source","settings":(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) ?? [:]]}
  static var apiSchema:[String:Any] {
    let number:[String:Any]=["type":"number","minimum":-65504,"maximum":65504]
    let row:[String:Any]=["type":"array","maxItems":ColorLUT.maximumSize*ColorLUT.maximumSize*ColorLUT.maximumSize*3,"items":number]
    return ["type":"object","additionalProperties":false,"required":["kind","settings"],"properties":["kind":["const":"source"],"settings":["type":"object","additionalProperties":false,"required":["kind","parameters","records","options","space"],"properties":["kind":["enum":Kind.allCases.map(\.rawValue)],"parameters":["type":"object","maxProperties":3,"additionalProperties":number],"records":["type":"object","maxProperties":5,"additionalProperties":["type":"array","maxItems":4096,"items":row]],"options":["type":"object","maxProperties":2,"additionalProperties":["type":"boolean"]],"space":["enum":["rgb","cmyk","lab"]],"name":["type":"string","maxLength":1024],"opaqueKey":["type":"string","maxLength":64],"opaqueData":["type":"string","contentEncoding":"base64","maxLength":1398104]]]]]
  }
  static func decodeAPI(_ raw:[String:Any])throws->Self {
    guard Set(raw.keys)==["kind","settings"],raw["kind"] as? String == "source",let fields=raw["settings"] as? [String:Any],Set(fields.keys).isSubset(of:["kind","parameters","records","options","space","name","opaqueKey","opaqueData"]) else {throw AutomationFailure(status:400,message:"Unknown original adjustment fields.")}
    do {let value=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:fields));try value.validate();return value}
    catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static var apiCapabilities:[String:Any] {
    ["commands":["adjustment.create","adjustment.set","adjustment.apply"],"schema":apiSchema,"editableKinds":Kind.allCases.filter{$0 != .unsupported}.map(\.rawValue),"opaqueKind":"unsupported","controlPrecision":"Retained finite Float32; tone coordinates normalized, matrices in source units; no integer UI quantization.","nativeVersion":74,"actionsVersion":29,"history":"Shared native replaceContent/addLayer/applyAdjustment transactions. Set retains the kind, masks, identity and properties.","sourceToneSpaces":["rgb"],"adobeCompatible":false,"limitations":["Original PhotoCraft approximation, not independent Photoshop output qualification","CMYK/Lab tone-space evaluation and source document modes remain open","Opaque unknown PSD adjustments and missing-profile Color Lookup remain inert, preserved and visible","Source-specific limits: curves256 points/channel, gradient4096 stops, LUT129 cube, opaque1MiB","Physical60fps, full-current, native visual and supported-platform qualification remain open"]]
  }
}
extension AutomationCommand {
  func sourceAdjustmentCommand(document:CraftDocument,raw:[String:Any])throws->Command {
    let value=try SourceAdjustment.decodeAPI(raw)
    _ = try SourceAdjustmentTransfer(value,depth:document.depth)
    guard document.colorMode == .rgb,document.inkMode==nil,document.restrictedMode==nil else {throw AutomationFailure(status:422,message:"Original adjustments currently require RGB.")}
    if name=="adjustment.create" {return .addLayer(try value.layer(in:document,name:parameters["name"] == nil ? nil:string("name")))}
    guard let id=UUID(uuidString:try string("layerID")),let layer=document.layers.first(where:{$0.id==id}) else {throw AutomationFailure(status:404,message:"Layer not found.")}
    if name=="adjustment.set" {
      guard case .adjustment(.source(let old))=layer.content,old.kind==value.kind else {throw AutomationFailure(status:422,message:"Adjustment type does not match the layer.")}
      return .replaceContent(id,.adjustment(.source(value)))
    }
    guard case .raster=layer.content,layer.smartObject==nil,!value.isOpaque else {throw AutomationFailure(status:422,message:"Apply requires a pixel layer and an evaluated adjustment.")}
    return .applyAdjustment(id,.source(value))
  }
}
