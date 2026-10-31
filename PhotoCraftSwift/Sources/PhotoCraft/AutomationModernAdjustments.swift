import Foundation
import PhotoCraftCore

extension ModernAdjustment {
  var apiObject:[String:Any] { ["kind":kind.rawValue,"values":values,"seed":seed] }
  static var apiSchema:[String:Any] {
    ["oneOf":Kind.allCases.map {kind -> [String:Any] in
      let fields=Dictionary(uniqueKeysWithValues:controls(for:kind).map {($0.key,["type":"number","minimum":$0.minimum,"maximum":$0.maximum,"default":$0.initial] as [String:Any])})
      return ["type":"object","additionalProperties":false,"required":["kind"],"properties":["kind":["const":kind.rawValue],"values":["type":"object","additionalProperties":false,"properties":fields],"seed":["type":"integer","minimum":0,"maximum":UInt32.max,"default":0]]]
    }]
  }
  static func decodeAPI(_ raw:Any) throws -> Self {
    guard let object=raw as? [String:Any],let name=object["kind"] as? String,let kind=Kind(rawValue:name),Set(object.keys).isSubset(of:["kind","values","seed"]) else {throw AutomationFailure(status:400,message:"Invalid modern adjustment kind or fields.")}
    var result=Self(kind)
    if let fields=object["values"] {
      guard let fields=fields as? [String:Any],Set(fields.keys).isSubset(of:kind.keys) else {throw AutomationFailure(status:400,message:"Invalid modern adjustment controls.")}
      for (key,raw) in fields {
        guard let n=raw as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite else {throw AutomationFailure(status:400,message:"Modern controls require finite numbers.")}
        result.values[key]=n.floatValue
      }
    }
    if let raw=object["seed"] {
      guard let n=raw as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,n.doubleValue.rounded()==n.doubleValue,(0...Double(UInt32.max)).contains(n.doubleValue) else {throw AutomationFailure(status:400,message:"Invalid grain seed.")}
      result.seed=n.uint32Value
    }
    do {try result.validate();return result} catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static var apiCapabilities:[String:Any] {
    ["commands":["adjustment.create","adjustment.set","adjustment.apply"],"schema":apiSchema,"defaults":Kind.allCases.map {Self($0).apiObject},
     "nativeArchiveVersion":65,"actionsVersion":22,
     "coordinates":"Document-pixel grain coordinates; stored seed, stable across regions and reopen. Layer masks/opacity/blends share native composition.",
     "limits":"RGB. Current Light8/16; Color and vibrance/Grain and native Clarity work-alikes additionally accept32-bit. Active Clarity/Dehaze or Light Highlights/Shadows use the current8,388,608-pixel neighborhood engine. Pointwise and tiled grain composition retain native logical canvas admission; dense output, selection/apply and physical resource/performance gates remain independent.",
     "persistence":"Editable Photato65 and native Actions22. Modern Adobe PSD descriptors, legacy Light versions, full Photoshop/default/ICC/numerical and platform equality remain unqualified. PSD export rejects these live layers; explicitly flatten/export a copy or retain the Photato original.",
     "adobe":"Existing /v2/edit exposes its separately defined Camera Raw-style controls; no equivalent live desktop-layer route or unverified actionJSON descriptor is invented."]
  }
}

extension AutomationCommand {
  func modernAdjustmentCommand(document:CraftDocument,raw:Any) throws -> Command {
    let value=try ModernAdjustment.decodeAPI(raw)
    do {try value.validate(in:document)} catch {throw AutomationFailure(status:422,message:error.localizedDescription)}
    if name=="adjustment.create" {return .addLayer(try value.layer(in:document,name:parameters["name"] == nil ? nil:string("name")))}
    guard let id=UUID(uuidString:try string("layerID")),let layer=document.layers.first(where:{$0.id==id}) else {throw AutomationFailure(status:404,message:"Layer not found.")}
    if name=="adjustment.set" {
      guard case .adjustment(.modern(let old))=layer.content,old.kind==value.kind else {throw AutomationFailure(status:422,message:"Adjustment type does not match the layer.")}
      return .replaceContent(id,.adjustment(.modern(value)))
    }
    guard case .raster=layer.content,layer.smartObject==nil else {throw AutomationFailure(status:422,message:"Apply requires an ordinary pixel layer.")}
    return .applyAdjustment(id,.modern(value))
  }
}
