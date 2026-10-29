import Foundation
import PhotoCraftCore

enum AnimationAPI {
  static let commands: Set<String> = ["animation.edit", "animation.view", "animation.export", "animation.export.cancel"]
  static let operations = ["create", "remove", "toVideo", "fromVideo", "restoreVideoSource", "fromLayers", "duplicate", "delete", "reverse", "reorder", "delay", "loop", "tween"]
  static let definitions: [AutomationCommand.Definition] = [
    .init(name:"animation.export", parameters:["format":"gif", "alphaThreshold":"Binary alpha threshold from 0 to 1, default 0.5"], description:"Render every Timeline frame to a GIF download without changing history; requires document transfers. Returns image/gif.", optionalParameters:["alphaThreshold"]),
    .init(name:"animation.export.cancel", parameters:["operationID":"Active animation export UUID"], description:"Cancel the matching Timeline export."),
    .init(name:"animation.edit", parameters:["operation":"Frame operation","frameRate":"Target video rate for toVideo, 1–240 fps", "index":"Zero-based reorder destination", "delay":"Seconds per selected frame", "count":"Loop passes or tween additions", "position":"Tween position", "opacity":"Tween opacity"], description:"Edit the selected animation frame through the native transaction and history.", optionalParameters:["index","delay","count","position","opacity","frameRate"]),
    .init(name:"animation.view", parameters:["frameID":"Select a frame", "visible":"Show Timeline", "playing":"Start or stop transient playback"], description:"Control native Timeline selection, visibility and playback without content Undo entries.", optionalParameters:["frameID","visible","playing"])
  ]
  static func schema(_ key: String) -> [String: Any] {
    switch key {
    case "frameRate":["type":"number","minimum":1,"maximum":240]
    case "format": BrushAPI.enumeration(["gif"])
    case "alphaThreshold": ["type":"number","minimum":0,"maximum":1,"default":0.5]
    case "operationID": ["type":"string","format":"uuid"]
    case "operation": BrushAPI.enumeration(operations)
    case "index": ["type":"integer","minimum":0,"maximum":511]
    case "delay": ["type":"number","minimum":0,"maximum":3600]
    case "count": ["type":"integer","minimum":0,"maximum":65_535]
    case "frameID": ["type":"string","format":"uuid"]
    default: BrushAPI.flag
    }
  }
  static var stateSchema: [String: Any] {
    let layer = BrushAPI.object(["layerID":["type":"string","format":"uuid"],"visible":BrushAPI.flag,
      "opacity":["type":"number","minimum":0,"maximum":1],"x":["type":"integer"],"y":["type":"integer"],
      "affine":BrushAPI.object(Dictionary(uniqueKeysWithValues:["a","b","c","d","tx","ty"].map{($0,["type":"number"] as [String:Any])}),required:["a","b","c","d","tx","ty"]),"style":LayerStyle.apiSchema,"payloadSummary":TemporalContentAPI.payloadSchema], required:["layerID","visible","opacity","x","y"])
    let frame = BrushAPI.object(["id":["type":"string","format":"uuid"],"sourceVideoFrame":["type":"integer","minimum":0],"transitions":TemporalContentAPI.transitionsSchema,"delay":schema("delay"),"layers":["type":"array","items":layer,"maxItems":512]], required:["id","delay","layers"])
    var animation = BrushAPI.object(["sampledTimeline":TemporalContentAPI.samplingSchema,"retainedSource":TemporalContentAPI.sourceSchema,"frames":["type":"array","minItems":1,"maxItems":512,"items":frame],"selectedFrameID":["type":"string","format":"uuid"],"loopCount":schema("count")],required:["frames","selectedFrameID","loopCount"])
    animation["type"] = ["object","null"]
    return BrushAPI.object(["exportOperationID":["type":["string","null"],"format":"uuid"],"timelineVisible":BrushAPI.flag,"playing":BrushAPI.flag,"previewFrameID":["type":["string","null"],"format":"uuid"],"animation":animation],required:["timelineVisible","playing","previewFrameID","animation","exportOperationID"])
  }
  static var capabilities: [String: Any] {
    ["commands":commands.sorted(),"stateSchema":stateSchema,"nativeArchiveVersion":60,
      "conversion":"fromVideo samples every video frame into editable frame compositions with sparse content/mask payloads and transition states; maximum512 frames/65536 layer states. Original video/audio source is retained. Frame playback is silent. toVideo requires frameRate and creates Hold property/content keys. Unchanged sampled order and delays restore active audio; retimed/reordered frames retain audio only in the original source. restoreVideoSource restores that original Timeline/layers, replacing conversion edits with Undo available. Positive video-derived delays preserve rates above50fps; other frames use20ms minimum. Native60; exact Photoshop conversion fidelity remains open.",
      "operations":operations,"maximumFrames":FrameAnimation.maximumFrames,"maximumLayerStates":FrameAnimation.maximumLayerStates,
      "scope":"Ordinary editable layer content is shared; sampled content tracks vary by frame. Visibility, position, opacity and style vary by frame. Ordinary property edits update the selected frame; newly added layers initially appear in every frame. Selection and transient playback do not add content history. Loop count0 is forever; positive counts are total passes starting at the selected frame. Zero-delay preview uses20ms. Still copies render the selected frame.",
      "gif":["import":"File/Open and POST /v1/documents/import image/gif preserve all frames with ImageIO disposal/placement, unclamped delays and total-pass loops. One image opens as a still.","export":"animation.export or Timeline > Export Animated GIF. Every frame is rendered in order to sRGB8, native palette up to256 colors, alpha >= threshold and >0 is opaque, delays rounded to nearest centisecond; max655.35seconds.","maximumImportFrames":256,"maximumExportFrames":512,"maximumExportBytes":134_217_728,"memory":"Desktop1GiB; API128MiB decoded storage plus existing4MP/64layer sharing limits. Limits reject before GIF frame allocation.","cancellation":"animation.export.cancel with exportOperationID from animation state; HTTP task cancellation also cancels encoding. No history or source changes. API checks transfer permission/generation/sharing/revision after encoding."],
      "limits":"Single-frame selection; position/opacity tween with matching affine linear parts. PNG sequence export and one-layer video sequence import have separate shared capabilities. Advanced movie/audio/keyframe contexts, PSD-animation interchange and effect tween remain open. Whole-document geometry, merge and profile/mode conversion require a still copy until all-frame transforms are implemented. Artboards cannot start frame animation. Semantic Action recording remains unavailable.",
      "adobe":"The pinned published Photoshop v2 contract has no frame-animation/Timeline endpoint. These are Photato extensions, not invented Adobe routes.",
      "errors":["400":"Invalid or irrelevant parameters","409":"Stale revision or active desktop edit","422":"Unsupported context, invalid animation or capacity limit"]]
  }
}
extension AutomationCommand {
  func animationCommand() throws -> Command {
    let operation = try string("operation")
    let fields: Set<String>
    switch operation {
    case "toVideo": fields=["frameRate"]
    case "reorder": fields = ["index"]
    case "delay": fields = ["delay"]
    case "loop": fields = ["count"]
    case "tween": fields = ["count","position","opacity"]
    default: fields = []
    }
    let supplied = Set(parameters.keys).subtracting(["operation"])
    guard AnimationAPI.operations.contains(operation), supplied == fields else { throw AutomationFailure(status:400,message:"Missing or irrelevant animation parameters.") }
    let command: AnimationCommand
    switch operation {
    case "fromVideo":command = .convertFromVideo
    case "restoreVideoSource":command = .restoreVideoSource
    case "toVideo":command = .convertToVideo(try number("frameRate",range:1...240))
    case "create": command = .create
    case "remove": command = .remove
    case "fromLayers": command = .fromLayers
    case "duplicate": command = .duplicate
    case "delete": command = .delete
    case "reverse": command = .reverse
    case "reorder": command = .reorder(try integer("index",range:0...511))
    case "delay": command = .delay(try number("delay",range:0...3600))
    case "loop": command = .loop(try integer("count",range:0...65_535))
    default: command = .tween(count:try integer("count",range:1...100),position:try pathFlag("position",false),opacity:try pathFlag("opacity",false))
    }
    return .animation(command)
  }
  @MainActor func applyAnimationView(to store: EditorStore) throws {
    guard !parameters.isEmpty else { throw AutomationFailure(status:400,message:"Choose a Timeline view change.") }
    guard store.canUseTimeline else { throw AutomationFailure(status:409,message:"Choose a Timeline view change and finish the active edit.") }
    let frame = try parameters["frameID"].map { _ in try actionUUID("frameID") }
    let visible = try parameters["visible"].map { _ in try pathFlag("visible",false) }
    let playing = try parameters["playing"].map { _ in try pathFlag("playing",false) }
    if let frame, store.document.animation?.frames.contains(where:{$0.id==frame}) != true { throw AutomationFailure(status:400,message:"Unknown animation frame.") }
    if playing == true, store.document.animation == nil { throw AutomationFailure(status:422,message:"Create frame animation before playback.") }
    if let frame { try store.selectTimelineFrame(frame) }
    if let visible { store.timelineVisible = visible }
    if playing == false { store.stopTimelinePlayback(render:false) }
    if playing == true { try store.startTimelinePlayback() }
    store.render()
  }
}
