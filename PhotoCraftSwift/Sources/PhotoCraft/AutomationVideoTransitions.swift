import Foundation
import PhotoCraftCore

enum VideoTransitionAPI {
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "kind":BrushAPI.enumeration(VideoTransitionKind.allCases.map(\.rawValue))
    case "edge":BrushAPI.enumeration(VideoTransitionEdge.allCases.map(\.rawValue))
    case "color":BrushAPI.object(["r":BrushAPI.number(),"g":BrushAPI.number(),"b":BrushAPI.number(),"a":["type":"number","const":1]],required:["r","g","b","a"])
    case "duration":["type":"number","exclusiveMinimum":0,"maximum":86400]
    default:["type":"string","format":"uuid"]
    }
  }
  static var itemSchema:[String:Any] {BrushAPI.object(["id":schema("id"),"layerID":schema("id"),"previousLayerID":schema("id"),"kind":schema("kind"),"edge":schema("edge"),"duration":schema("duration"),"color":schema("color")],required:["id","layerID","kind","edge","duration"])}
  static var stateSchema:[String:Any] {["type":"array","maxItems":1024,"items":itemSchema]}
  static var capabilities:[String:Any] {
    ["command":"video.edit","operations":["transition","removeTransition","trim"],"nativeArchiveVersion":55,"stateSchema":stateSchema,
     "behavior":"Editable Fade, Cross Fade, Fade With Black/White/Color. Edge fades are inside the clip; crossfades center on the shared boundary of adjacent clips. Retained video handles are used; absent handles hold the first/last source frame. Rendering mixes premultiplied branches over the same backdrop, preserving current masks/styles/blending. Color fades retain the clip's rendered coverage. Overlapping transitions on a clip reject. Trim/reorder/delete reconcile durations and remove broken crossfade boundaries within the same Undo transaction. Split carries the outgoing edge transition to the right portion.",
     "view":"Native graphical Timeline supports clip selection, horizontal movement/reorder, vertical track moves, exact trim handles, draggable playhead, transition selection and duration editing. video.view exposes pixelsPerSecond, transitionID and transitionEditorVisible; these do not alter content history.",
     "limits":"Automatic movie grouping, Render Video, rich PSD/Actions animation and exact Photoshop output/defaults/live/platform qualification remain open. Transition behavior described here is native behavior, not a verified Adobe numerical match.","adobe":"No dedicated Timeline transition/trim endpoint in the pinned contract."]
  }
}
extension AutomationCommand {
  func videoTransitionCommand()throws->Command {
    guard let kind=VideoTransitionKind(rawValue:try string("kind")),let edge=VideoTransitionEdge(rawValue:try string("edge")) else{throw AutomationFailure(status:400,message:"Unknown transition kind or edge.")}
    let id=try parameters["transitionID"].map{_ in try actionUUID("transitionID")} ?? UUID()
    let previous=try parameters["previousLayerID"].map{_ in try actionUUID("previousLayerID")}
    let color:Pixel?
    if let raw=parameters["color"] {
      guard case .object(let fields)=raw,Set(fields.keys)==["r","g","b","a"] else{throw AutomationFailure(status:400,message:"Transition color requires r, g, b and a.")}
      let values=try ["r","g","b","a"].map{key->Float in guard case .number(let value)=fields[key],value.isFinite,(0...1).contains(value) else{throw AutomationFailure(status:400,message:"Invalid transition color.")};return Float(value)}
      color=Pixel(values[0],values[1],values[2],values[3])
    }else{color=nil}
    return .video(.transition(.set(.init(id:id,layerID:try actionUUID("layerID"),previousLayerID:previous,kind:kind,edge:edge,duration:try number("duration",range:0...86400),color:color))))
  }
}
