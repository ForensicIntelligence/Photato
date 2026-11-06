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
     "workspace":"Native pins/path handles, numeric controls, multi-effect enablement, bokeh/noise, Preview, mask view, Save Mask to Channels, local undo/redo and document Cancel/OK. No document mutation before OK.",
     "maskOutput":BlurGalleryOutputAPI.capabilities,
     "limits":"8,388,608 source pixels, RGB targets. Independent Photoshop pixel/blur-composition/strobe matching and physical platform/live qualification remain open. Editable PSD/PSB Gallery descriptors are unsupported; save native29 or rasterize.",
     "adobe":"No dedicated published Blur Gallery endpoint or qualified actionJSON descriptor. Unknown descriptors reject; no Adobe operation is invented."]
  }
}

enum BlurGalleryOutputAPI {
  static let name="filter.blurGallery.apply"
  static var definition:AutomationCommand.Definition {
    .init(name:name,parameters:["layerID":"RGB raster/Smart Object UUID","gallery":"Blur Gallery settings","saveMaskToChannels":"Boolean, default false","filterID":"Optional existing Blur Gallery Smart Filter UUID"],description:"Apply or re-edit Blur Gallery and optionally save its numeric Blur Mask alpha channel in the same undoable native transaction.",optionalParameters:["saveMaskToChannels","filterID"])
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "gallery":return BlurGallerySettings.apiSchema
    case "saveMaskToChannels":return ["type":"boolean","default":false]
    default:return ["type":"string","format":"uuid"]
    }
  }
  static var capabilities:[String:Any] {
    ["command":name,"option":"saveMaskToChannels","default":false,"channelName":"Blur Mask","duplicateNames":"Blur Mask 2, Blur Mask 3, ...; existing channels remain unchanged.","history":"Filter and channel commit together, with one Undo/Redo. Cancel, stale, invalid, locked or channel-limit failures publish neither.","persistence":"Existing native/PSD alpha-channel storage; no new native document format. Portable output Actions require53; ordinary Blur Gallery recipes retain their existing version requirements.","coverage":"Numeric source-space blur amount normalized by the maximum configured amount per enabled tool; max union, placed into document space with pixel-center inverse mapping. Black sharp/outside, white maximum blur. Independent Photoshop references currently qualify only the uniform5px Field mask; other geometry, selection, multi-tool and subpixel fidelity remain open.","limits":"Existing8,388,608 source-pixel Gallery limit; transformed mask footprint also bounded to8,388,608 pixels. Large empty document canvases retain sparse storage. No all-input Photoshop/capacity/performance claim."]
  }
}

extension AutomationCommand {
  func blurGalleryOutputCommand(in document:CraftDocument)throws->Command {
    guard let layerID=UUID(uuidString:try string("layerID")) else {throw AutomationFailure(status:400,message:"Invalid layerID.")}
    guard let layer=document.layers.first(where:{$0.id==layerID}) else {throw AutomationFailure(status:404,message:"Layer not found.")}
    guard case .raster=layer.content,let raw=parameters["gallery"] else {throw AutomationFailure(status:422,message:"Choose an RGB pixel layer or Smart Object and supply gallery settings.")}
    let settings:BlurGallerySettings
    do {settings=try BlurGallerySettings.decodeJSON(JSONSerialization.data(withJSONObject:raw.jsonValue))}
    catch {throw AutomationFailure(status:400,message:error.localizedDescription)}
    var save=false
    if let value=parameters["saveMaskToChannels"] {guard case .bool(let flag)=value else {throw AutomationFailure(status:400,message:"saveMaskToChannels must be boolean.")};save=flag}
    var filterID:UUID?,opacity:Float=1,mode:PhotoCraftCore.BlendMode = .normal
    if parameters["filterID"] != nil {
      guard let id=UUID(uuidString:try string("filterID")),let item=layer.smartFilters?.filters.first(where:{$0.id==id}),item.filter.kind == .blurGallery else {throw AutomationFailure(status:422,message:"Choose an existing Blur Gallery Smart Filter.")}
      filterID=id;opacity=item.opacity;mode=item.blendMode
    }
    let edit=BlurGalleryMaskEdit(layerID:layerID,settings:settings,filterID:filterID,opacity:opacity,blendMode:mode)
    return try save ? .blurGalleryMask(edit):edit.filterCommand(in:document)
  }
}
