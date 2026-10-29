import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum TimelineWorkspaceAPI {
  static let commands:Set<String>=["video.workArea","video.onionSkin","video.trimWorkArea"]
  static let definitions:[AutomationCommand.Definition]=[
    .init(name:"video.trimWorkArea",parameters:[:],description:"Trim document duration to its work area with one Undo. Rebase to frame zero while retaining editable source and interpolation handles; native58."),
    .init(name:"video.workArea",parameters:["operation":"set, reset, startAtPlayhead or endAtPlayhead","startFrame":"Inclusive zero-based start for set","endFrame":"Exclusive zero-based end for set"],description:"Set/reset the video work area used for playback and optional exports; one native Undo.",optionalParameters:["startFrame","endFrame"]),
    .init(name:"video.onionSkin",parameters:["settings":"Complete settings object, or null to reset"],description:"Set persistent onion-skin preview options with one Undo. Ordinary images/movies remain unchanged; GET onion-preview.png exposes the committed preview.")]
  static var settingsSchema:[String:Any]{BrushAPI.object([
    "enabled":BrushAPI.flag,"framesBefore":["type":"integer","minimum":0,"maximum":10],"framesAfter":["type":"integer","minimum":0,"maximum":10],
    "spacing":["type":"integer","minimum":1,"maximum":100],"minimumOpacity":["type":"number","minimum":0,"maximum":1],"maximumOpacity":["type":"number","minimum":0,"maximum":1],
    "blendMode":BrushAPI.enumeration(BlendMode.allCases.map(\.rawValue))],required:["enabled","framesBefore","framesAfter","spacing","minimumOpacity","maximumOpacity","blendMode"])}
  static func schema(_ key:String)->[String:Any]{
    if key=="operation"{return BrushAPI.enumeration(["set","reset","startAtPlayhead","endAtPlayhead"])}
    if key=="settings"{var value=settingsSchema;value["type"]=["object","null"];return value}
    return ["type":"integer","minimum":0,"maximum":20736001]
  }
  static var timeSchema:[String:Any]{["type":"number","minimum": -86400,"maximum":86400]}
  static var areaSchema:[String:Any]{BrushAPI.object(["startFrame":schema("startFrame"),"endFrame":schema("endFrame")],required:["startFrame","endFrame"])}
  static var capabilities:[String:Any]{[
    "commands":commands.sorted(),"workAreaSchema":areaSchema,"onionSkinSchema":settingsSchema,"nativeArchiveVersion":58,
    "onionDefaults":BrushAPI.json(OnionSkinSettings()),
    "workArea":"Start inclusive/end exclusive, in zero-based Timeline frames. Playback loops/stops inside this range; an outside playhead starts at its beginning. Source frame-rate changes preserve interval seconds with outward frame rounding. Duration reduction clamps the interval. Reset means full current Timeline.",
    "export":"video.render and sequence.export accept useWorkArea=true; explicit frame range fields are mutually exclusive. Default export still uses all frames. No source clips/keys are removed by changing a work area.",
    "preview":"Onion skins blend full neighboring composites far-to-near, before then after at each distance. Opacity interpolates maximum near the playhead to minimum at the configured furthest frame. Edges do not wrap. Native CPU blend modes are shared across8/16/32-bit preview contexts. At most20 neighbors and268435456 pixel visits. Composite/channel/proof/image/movie exports remain free of onion skins.",
    "endpoint":"GET /v1/documents/{id}/onion-preview.png uses committed playhead/settings and existing preview limits, source/revision/share checks; it does not return an interactive draft.",
    "trim":"video.trimWorkArea has no parameters. Output becomes the current work area, rebased to zero. Wholly unused clips/audio and redundant keys are removed; source bytes and bounding media/keyframe handles are retained to preserve fades, crossfades and interpolation. Returned timing may be negative for pre-roll handles. A trimmed Timeline has fixed duration until explicitly resized or new video/audio is inserted. Native58 is required; normal work-area/onion settings remain native57. Undo restores the complete original.",
    "qualification":"Public Photoshop controls guide behavior; exact2026 defaults, overlap ordering/blending and live/platform fidelity remain unqualified. Exact Photoshop trim retention/UI and rich Timeline interchange remain open.",
    "adobe":"No dedicated work-area/onion-skin route in the pinned Adobe v2 contract; no Adobe endpoint is invented."]}
}
extension AutomationCommand {
  func timelineWorkspaceCommand(in document:CraftDocument)throws->Command {
    guard let timeline=document.videoTimeline else{throw CraftError.invalid("Create a video Timeline first.")}
    if name=="video.trimWorkArea" {
      guard parameters.isEmpty else{throw AutomationFailure(status:400,message:"Trim Work Area takes no parameters.")}
      return .video(.workspace(.trimToWorkArea))
    }
    if name=="video.onionSkin" {
      if case .null=parameters["settings"]{return .video(.workspace(.onionSkin(nil)))}
      guard let raw=parameters["settings"],case .object(let fields)=raw,Set(fields.keys)==Set(["enabled","framesBefore","framesAfter","spacing","minimumOpacity","maximumOpacity","blendMode"]) else{throw AutomationFailure(status:400,message:"Provide onion-skin settings.")}
      let data=try JSONSerialization.data(withJSONObject:raw.jsonValue)
      let value:OnionSkinSettings
      do {value=try JSONDecoder().decode(OnionSkinSettings.self,from:data)}
      catch {throw AutomationFailure(status:400,message:"Onion-skin settings have an invalid type or blend mode.")}
      try value.validate();return .video(.workspace(.onionSkin(value)))
    }
    let operation=try string("operation"),area=timeline.effectiveWorkArea
    let required:Set<String>=operation=="set" ? ["operation","startFrame","endFrame"]:["operation"]
    guard Set(parameters.keys)==required else{throw AutomationFailure(status:400,message:"Provide only the required work-area fields.")}
    switch operation {
    case "set":return .video(.workspace(.workArea(try .init(startFrame:integer("startFrame",range:0...20736000),endFrame:integer("endFrame",range:1...20736001)))))
    case "reset":return .video(.workspace(.workArea(nil)))
    case "startAtPlayhead":return .video(.workspace(.workArea(.init(startFrame:timeline.currentFrame,endFrame:max(area.endFrame,timeline.currentFrame+1)))))
    case "endAtPlayhead":return .video(.workspace(.workArea(.init(startFrame:min(area.startFrame,timeline.currentFrame),endFrame:timeline.currentFrame+1))))
    default:throw AutomationFailure(status:400,message:"Unknown work-area operation.")
    }
  }
}
