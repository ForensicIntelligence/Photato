import Foundation
import PhotoCraftCore

enum VideoKeyframeAPI {
  static let name="video.keyframe"
  static let definition=AutomationCommand.Definition(name:name,parameters:["operation":"enable, disable, set, delete, move or interpolation","layerID":"Layer UUID","property":"position, opacity, transform, style, visibility or content","time":"Timeline seconds for set/move","keyframeID":"Existing key UUID","interpolation":"linear or hold"],description:"Enable/capture and edit independent video property keyframes with native Undo. Normal property edits automatically key enabled tracks.",optionalParameters:["property","time","keyframeID","interpolation"])
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "operation":BrushAPI.enumeration(["enable","disable","set","delete","move","interpolation"])
    case "property":BrushAPI.enumeration(VideoProperty.allCases.map(\.rawValue))
    case "interpolation":BrushAPI.enumeration(KeyframeInterpolation.allCases.map(\.rawValue))
    case "time":["type":"number","minimum":0,"maximum":86400]
    default:["type":"string","format":"uuid"]
    }
  }
  static var stateSchema:[String:Any] {
    let affine=BrushAPI.object(Dictionary(uniqueKeysWithValues:["a","b","c","d","tx","ty"].map{($0,["type":"number"] as [String:Any])}),required:["a","b","c","d","tx","ty"])
    let geometry=BrushAPI.object(["x":["type":"integer"],"y":["type":"integer"],"affine":affine],required:["x","y","affine"])
    let key=BrushAPI.object(["id":schema("keyframeID"),"property":schema("property"),"time":TimelineWorkspaceAPI.timeSchema,"interpolation":schema("interpolation"),"geometry":geometry,"opacity":["type":"number","minimum":0,"maximum":1],"style":LayerStyle.apiSchema,"visibility":BrushAPI.flag,"frameComposition":BrushAPI.flag,"contentSummary":TemporalContentAPI.payloadSchema],required:["id","property","time","interpolation"])
    return ["type":"array","maxItems":LayerLimits.maximumLayers,"items":BrushAPI.object(["layerID":schema("layerID"),"keys":["type":"array","maxItems":4096,"items":key]],required:["layerID","keys"])]
  }
  static var capabilities:[String:Any] {
    ["command":name,"stateSchema":stateSchema,"nativeArchiveVersion":60,"maximumKeysPerLayer":4096,"maximumKeysPerDocument":65536,"behavior":"Independent Position/Opacity/Transform/Style/Visibility/Content tracks (Visibility and Content use Hold), Linear/Hold interpolation, add/capture/move/delete and disable. Disabling removes that property's keys, retaining the evaluated value. Existing normal move/transform/opacity/style edits automatically create or replace keys on enabled tracks. Position and Transform are alternative geometry tracks. Converted frameComposition keys retain direct placement semantics and remain editable. View/playback does not add Undo; key edits do.","values":"Set captures the current property. Use existing property commands at a chosen video.view frame to assign a value. Geometry uses subpixel position and decomposed affine rotation/scale/shear/translation; reflection switches are discrete. Matching style effects interpolate numeric controls and colors; categorical choices, gradient/pattern data and differing effect topology hold until the next key.","limits":"General group/Smart Filter/Warp geometry beyond converted frame placement, vector-mask-specific property tracks, global-light tracks, text-warp tracks, keyframe clipboard/multiselection, advanced motion and exact Photoshop numerical/live/platform equivalence remain open. Transition clips and audio have separate capabilities. Source movie limits are unchanged.","adobe":"No dedicated Timeline/keyframe endpoint in the pinned contract; generic action descriptors remain open."]
  }
}
extension AutomationCommand {
  func videoKeyframeCommand(in document:CraftDocument)throws->Command {
    let op=try string("operation"),id=try actionUUID("layerID")
    let required:Set<String>,optional:Set<String>
    switch op {
    case "enable","disable":required=["property"];optional=[]
    case "set":required=["property"];optional=["time"]
    case "delete":required=["keyframeID"];optional=[]
    case "move":required=["keyframeID","time"];optional=[]
    case "interpolation":required=["keyframeID","interpolation"];optional=[]
    default:throw AutomationFailure(status:400,message:"Unknown keyframe operation.")
    }
    let actual=Set(parameters.keys).subtracting(["operation","layerID"])
    guard required.isSubset(of:actual),actual.isSubset(of:required.union(optional)) else{throw AutomationFailure(status:400,message:"Missing or irrelevant keyframe parameters.")}
    func property()throws->VideoProperty{guard let p=VideoProperty(rawValue:try string("property")) else{throw AutomationFailure(status:400,message:"Unknown video property.")};return p}
    let edit:VideoKeyframeCommand
    switch op {
    case "enable":edit = .enable(id,try property())
    case "disable":edit = .disable(id,try property())
    case "set":edit = .set(id,try property(),try parameters["time"].map{_ in try number("time",range:0...86400)} ?? document.videoTimeline?.seconds ?? 0)
    case "delete":edit = .delete(id,try actionUUID("keyframeID"))
    case "move":edit = .move(id,try actionUUID("keyframeID"),try number("time",range:0...86400))
    default:guard let value=KeyframeInterpolation(rawValue:try string("interpolation")) else{throw AutomationFailure(status:400,message:"Choose linear or hold.")};edit = .interpolation(id,try actionUUID("keyframeID"),value)
    }
    return .video(.keyframe(edit))
  }
}
