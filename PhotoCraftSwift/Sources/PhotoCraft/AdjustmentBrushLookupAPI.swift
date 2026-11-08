import Foundation
import PhotoCraftCore

enum AdjustmentBrushLookupAPI {
  static var settingsSchema:[String:Any]{
    var fields=ColorLookupAdjustment.apiSchema["properties"] as! [String:Any];fields.removeValue(forKey:"kind");fields["clearLUT"]=BrushAPI.flag
    var schema=BrushAPI.object(fields)
    let pair:[String:Any]=["required":["lutID","preset"]]
    let clearID:[String:Any]=["required":["clearLUT","lutID"],"properties":["clearLUT":["const":true]]]
    let clearPreset:[String:Any]=["required":["clearLUT","preset"],"properties":["clearLUT":["const":true]]]
    schema["not"]=["anyOf":[pair,clearID,clearPreset]]
    return schema
  }
  static func state(_ value:Adjustment)->Any {
    guard case .colorLookup(let v)=value else{return NSNull()};return v.apiObject
  }
  static var stateSchema:[String:Any]{
    let nullableID:[String:Any]=["anyOf":[VariablesAPI.uuid,["type":"null"]]]
    let mask=BrushAPI.object(["density":BrushAPI.number(0,1),"feather":BrushAPI.number(0,100),"enabled":BrushAPI.flag,"inverted":BrushAPI.flag],required:["density","feather","enabled","inverted"])
    let domain:[String:Any]=["type":"array","minItems":3,"maxItems":3,"items":BrushAPI.number(-1e100,1e100)]
    let metadata=BrushAPI.object(["title":["type":"string"],"size":BrushAPI.number(2,Double(ColorLUT.maximumSize),integer:true),"domainMin":domain,"domainMax":domain,"hasInputGrid":BrushAPI.flag,"curveLength":BrushAPI.number(0,65536,integer:true),"estimatedBytes":BrushAPI.number(0,Double(Int.max),integer:true),"sourceFile":["type":"string"]],required:["title","size","domainMin","domainMax","hasInputGrid","curveLength","estimatedBytes","sourceFile"])
    let lookup=BrushAPI.object(["kind":["const":"colorLookup"],"interpolation":BrushAPI.enumeration(ColorLUT.Interpolation.allCases.map(\.rawValue)),"dither":BrushAPI.flag,"lut":["anyOf":[["type":"null"],metadata]]],required:["kind","interpolation","dither","lut"])
    let fields:[String:Any]=["kind":BrushAPI.enumeration(AdjustmentBrushKind.allCases.map(\.rawValue)),"settings":["anyOf":AdjustmentBrushKind.allCases.map(AdjustmentBrushAPI.settingsSchema)],"lookup":["anyOf":[["type":"null"],lookup],"readOnly":true],"layerID":nullableID,"mask":["anyOf":[["type":"null"],mask]],"newLayer":BrushAPI.flag,"subtract":BrushAPI.flag,"applyToObject":BrushAPI.flag,"overlay":BrushAPI.flag,"available":BrushAPI.flag]
    return BrushAPI.object(fields,required:Array(fields.keys).sorted())
  }
  static var capabilities:[String:Any]{[
    "kind":"colorLookup","settingsSchema":settingsSchema,"stateSchema":stateSchema,
    "workflow":"Native Color Lookup is available in the Adjustment Brush picker, retyping and Properties. Painting/object targeting creates or refines the same editable masked Color Lookup layer. Properties uses existing LUT loading, Photato Looks, interpolation, Dither and Reset controls.",
    "API":"adjustmentBrush.stroke/object/edit replace accept settings with preset or session lutID, interpolation and dither. Omitted LUT fields preserve the existing embedded LUT. clearLUT:true removes it; it cannot accompany preset/lutID. settings carries editable scalars, lookup carries read-only LUT metadata. Existing LUT upload/download routes retain their permissions and limits.",
    "storage":"Embedded lookup data uses existing native18 or later layer storage. A recorded Color Lookup brush stroke/object requires portable Actions59; earlier brush/action versions and feature minima remain intact. Source LUT bytes travel with the layer and recorded request, independent of the session cache.",
    "limits":"No new kernel, object detector, pointer tool, modifier action or factory shortcut. Exact Photoshop lookup defaults/interpolation/dither/output, Color and vibrance semantics, ICC/CSP import and full B08 remain open. No proprietary Adobe looks are bundled and no Adobe Adjustment Brush route or descriptor is invented."
  ]}
}
extension AutomationService {
  func decodeAdjustmentBrushSettings(_ input:AutomationValue?,_ kind:AdjustmentBrushKind,_ base:Adjustment)throws->Adjustment {
    guard kind == .colorLookup,let input else{return try AdjustmentBrushAPI.decode(input,kind:kind,base:base)}
    let raw=try BrushAPI.merge(input,schema:AdjustmentBrushLookupAPI.settingsSchema,base:AdjustmentBrushAPI.settings(base),path:"Color Lookup settings") as! [String:Any]
    let hasID=raw["lutID"] != nil,hasPreset=raw["preset"] != nil,clear=raw["clearLUT"] as? Bool == true
    guard !(hasID && hasPreset),!(clear && (hasID || hasPreset)) else{throw AutomationFailure(status:400,message:"Choose a LUT reference or clearLUT, not both.")}
    if hasID || hasPreset {
      var fields=raw;fields.removeValue(forKey:"clearLUT");fields["kind"]="colorLookup"
      return .colorLookup(try resolveColorLookupParameters(fields))
    }
    return try AdjustmentBrushAPI.decode(input,kind:kind,base:base)
  }
}
