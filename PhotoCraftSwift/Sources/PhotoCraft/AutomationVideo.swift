import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum VideoAPI {
  static let commands: Set<String> = ["video.place","video.place.cancel","video.edit","video.view","video.sequence","video.sequence.cancel"]
  static let definitions: [AutomationCommand.Definition] = [
    .init(name:"video.edit",parameters:["operation":"create, blankLayer, duration, remove, timing, frameRate, loop, split, group, arrange, stillTiming, groupStart, trim, transition or removeTransition","layerID":"Video layer UUID","startTime":"Timeline start in seconds","inFrame":"First source frame","outFrame":"Exclusive source end","frameRate":"Source or Timeline fps","looping":"Loop preview","durationFrames":"Timeline length in frames","layerIDs":"Selected clip UUIDs","name":"Video group name","groupID":"Destination video group UUID or null for root","position":"Zero-based clip order","duration":"Clip or transition duration in seconds","sourceIn":"Exact source start in source-frame units","sourceOut":"Exact exclusive source end","transitionID":"Existing transition UUID","previousLayerID":"Outgoing clip UUID for crossFade","kind":"fade, crossFade, black, white or color","edge":"start or end","color":"Opaque RGBA color for color transition"],description:"Edit video clip timing or Timeline settings through native history.",optionalParameters:["layerID","startTime","inFrame","outFrame","frameRate","looping","durationFrames","layerIDs","name","groupID","position","duration","sourceIn","sourceOut","transitionID","previousLayerID","kind","edge","color"]),
    .init(name:"video.view",parameters:["frame":"Zero-based Timeline frame","playing":"Preview playback","visible":"Show Timeline","pixelsPerSecond":"Graphical Timeline zoom, 5–400","transitionID":"Select a transition UUID or null","transitionEditorVisible":"Show transition controls"],description:"Select or preview a video frame without content history.",optionalParameters:["frame","playing","visible","pixelsPerSecond","transitionID","transitionEditorVisible"]),
    .init(name:"video.place",parameters:["sourceDocumentID":"Shared one-layer video document UUID","sourceRevision":"Current source revision"],description:"Place the shared video into the target at its playhead with one Undo; requires document transfers."),
    .init(name:"video.place.cancel",parameters:["operationID":"Active movie placement UUID"],description:"Cancel the matching video-layer preparation."),
    .init(name:"video.sequence",parameters:["sources":"Ordered shared still-document id/revision pairs","frameRate":"Frames per second","name":"New video document name"],description:"Create a new shared document containing one video layer from ordered still images; requires document transfers. Returns HTTP201 document state."),
    .init(name:"video.sequence.cancel",parameters:["operationID":"Active sequence creation UUID"],description:"Cancel the matching video sequence creation.")
  ]
  static func schema(_ key:String,command:String?=nil) -> [String:Any] {
    switch key {
    case "operation": BrushAPI.enumeration(["create","blankLayer","duration","remove","timing","frameRate","loop","split","group","arrange","stillTiming","groupStart","trim","transition","removeTransition"])
    case "transitionID": command == "video.view" ? ["type":["string","null"],"format":"uuid"]:["type":"string","format":"uuid"]
    case "kind","edge","color","previousLayerID":VideoTransitionAPI.schema(key)
    case "pixelsPerSecond":["type":"number","minimum":5,"maximum":400]
    case "sourceIn","sourceOut":["type":"number","minimum":0,"maximum":VideoFrames.maximumLogicalFrames]
    case "groupID": ["type":["string","null"],"format":"uuid"]
    case "layerIDs": ["type":"array","maxItems":LayerLimits.maximumLayers,"uniqueItems":true,"items":["type":"string","format":"uuid"]]
    case "position": ["type":"integer","minimum":0,"maximum":512]
    case "duration": ["type":"number","exclusiveMinimum":0,"maximum":86400]
    case "sources": ["type":"array","minItems":1,"maxItems":7,"items":BrushAPI.object(["id":["type":"string","format":"uuid"],"revision":["type":"string","minLength":1,"maxLength":256]],required:["id","revision"])]
    case "sourceRevision": ["type":"string","minLength":1,"maxLength":256]
    case "sourceDocumentID","layerID","operationID": ["type":"string","format":"uuid"]
    case "name": ["type":"string","minLength":1,"maxLength":256]
    case "frameRate": ["type":"number","minimum":1,"maximum":240]
    case "startTime": TimelineWorkspaceAPI.timeSchema
    case "inFrame": ["type":"integer","minimum":0,"maximum":VideoFrames.maximumLogicalFrames-1]
    case "outFrame": ["type":"integer","minimum":1,"maximum":VideoFrames.maximumLogicalFrames]
    case "durationFrames": ["type":"integer","minimum":1,"maximum":20736001]
    case "frame": ["type":"integer","minimum":0,"maximum":20736000]
    default: BrushAPI.flag
    }
  }
  static var stateSchema: [String:Any] {
    var timeline = BrushAPI.object(["frameRate":schema("frameRate"),"currentFrame":schema("frame"),"durationFrames":["type":"integer","minimum":1,"maximum":20736001],"looping":BrushAPI.flag,"transitions":VideoTransitionAPI.stateSchema,"workArea":TimelineWorkspaceAPI.areaSchema,"onionSkin":TimelineWorkspaceAPI.settingsSchema,"trimmedToWorkArea":BrushAPI.flag,"finiteLoopCount":["type":"integer","minimum":1,"maximum":65535],"retainedSource":TemporalContentAPI.sourceSchema,"frameTransitionKeys":TemporalContentAPI.transitionKeysSchema],required:["frameRate","currentFrame","durationFrames","looping"]);timeline["type"] = ["object","null"]
    let clip = BrushAPI.object(["layerID":schema("layerID"),"sourceFrames":["type":"integer","minimum":1,"maximum":VideoFrames.maximumLogicalFrames],"sparseFrames":BrushAPI.flag,"storedFrames":["type":"integer","minimum":1,"maximum":VideoFrames.maximumOverrides+1],"sourceFrameRate":schema("frameRate"),"startTime":TimelineWorkspaceAPI.timeSchema,"inFrame":schema("inFrame"),"outFrame":schema("outFrame"),"duration":["type":"number"],"sourceIn":["type":"number"],"sourceOut":["type":"number"],"movie":MovieAPI.sourceSchema],required:["layerID","sourceFrames","sourceFrameRate","startTime","inFrame","outFrame","duration"])
    return BrushAPI.object(["canCreateBlankLayer":BrushAPI.flag,"placementOperationID":["type":["string","null"],"format":"uuid"],"timeline":timeline,"previewFrame":["type":["integer","null"]],"clips":["type":"array","items":clip,"maxItems":LayerLimits.maximumLayers],"keyframes":VideoKeyframeAPI.stateSchema,"arrangement":VideoArrangementAPI.stateSchema,"pixelsPerSecond":schema("pixelsPerSecond"),"selectedTransitionID":schema("transitionID",command:"video.view"),"transitionEditorVisible":BrushAPI.flag],required:["timeline","previewFrame","clips"])
  }
  static var capabilities: [String:Any] {
    ["commands":commands.sorted(),"stateSchema":stateSchema,"nativeArchiveVersion":90,"workspace":TimelineWorkspaceAPI.capabilities,"transitions":VideoTransitionAPI.capabilities,"arrangement":VideoArrangementAPI.capabilities,"keyframes":VideoKeyframeAPI.capabilities,"sourceFrames":VideoFrames.maximumLogicalFrames,"maximumDecodedSourceFrames":VideoClip.maximumFrames,"blankVideoLayers":["operation":"video.edit blankLayer","nativeMenu":"Layer > Video Layers > New Blank Video Layer","storage":"One document-sized transparent prototype plus only edited frames. Logical frame indexing, per-frame painting, existing history/timing and native90 share the core engine. Legacy sampled media retains its512decoded-frame budget.","requires":"An idle still RGB8/16/32 video Timeline within the existing one-day clip bound; maximum logical Timeline range and normal layer/storage limits apply.","factoryDefaultsQualified":false,"PhotoshopOutputQualified":false],"frameRateRange":[1,240],"behavior":"One video layer retains source frames. Timeline/source rates, start and in/out trim are separate. Painting changes only the source frame at the playhead; source images remain unchanged. Select/playback are view operations; timing and painting use Undo. Native51 retains all frames.","sequence":"Desktop chooses numerically ordered equal-sized PNG files; API takes 1–7 ordered explicitly shared still documents including the target and returns a new shared document. Original layers flatten per source frame; color converts to the first source RGB working profile/depth. Desktop 1GiB/API128MiB frame budget, plus normal sharing limits.","movie":MovieAPI.capabilities,"limits":"In-memory movie/image-sequence sources. Advanced keyframe contexts, all-frame geometry/profile changes, complete rich-layer contexts, editable PSD/Actions/Adobe animation descriptors, full Render Video remain open. PNG sequence export is described by imageSequenceExport capabilities. No Photoshop byte or platform/live equivalence claim.","adobe":"No dedicated video endpoint in the pinned contract; Photato extensions do not invent Adobe routes.","creationState":"videoSequenceCreation on shared document state exposes operationID/sourceIDs for cancellation."]
  }
}
extension AutomationCommand {
  func videoCommand() throws -> Command {
    let operation = try string("operation")
    let required: Set<String>
    var optional=Set<String>()
    switch operation {case "blankLayer":required=[];case "create":required=["frameRate","durationFrames"];case "duration":required=["durationFrames"];case "remove":required=[]; case "timing": required=["layerID","startTime","inFrame","outFrame","frameRate"];case "frameRate":required=["frameRate"];case "loop":required=["looping"];case "split":required=["layerIDs"];case "group":required=["name","layerIDs"];case "arrange":required=["layerID","groupID","position"];optional=["startTime"];case "stillTiming":required=["layerID","startTime","duration"];case "groupStart":required=["layerID","startTime"];case "trim":required=["layerID","startTime","sourceIn","sourceOut"];case "transition":required=["layerID","kind","edge","duration"];optional=["transitionID","previousLayerID","color"];case "removeTransition":required=["transitionID"];default:throw AutomationFailure(status:400,message:"Unknown video operation.") }
    let actual=Set(parameters.keys).subtracting(["operation"])
    guard required.isSubset(of:actual),actual.isSubset(of:required.union(optional)) else { throw AutomationFailure(status:400,message:"Missing or irrelevant video parameters.") }
    switch operation {
    case "transition":return try videoTransitionCommand()
    case "removeTransition":return .video(.transition(.remove(try actionUUID("transitionID"))))
    case "trim":return .video(.arrange(.trim(try actionUUID("layerID"),startTime:try number("startTime",range: -86400...86400),sourceIn:try number("sourceIn",range:0...Double(VideoFrames.maximumLogicalFrames)),sourceOut:try number("sourceOut",range:0...Double(VideoFrames.maximumLogicalFrames)))))
    case "split":return .video(.arrange(.split(try videoLayerIDs())))
    case "group":return .video(.arrange(.group(try string("name"),try videoLayerIDs().sorted{$0.uuidString<$1.uuidString})))
    case "arrange":
      let parent:UUID?;if case .null = parameters["groupID"] {parent=nil}else{parent=try actionUUID("groupID")}
      return .video(.arrange(.move(try actionUUID("layerID"),group:parent,position:try integer("position",range:0...512),startTime:try parameters["startTime"].map{_ in try number("startTime",range: -86400...86400)})))
    case "stillTiming":return .video(.arrange(.stillTiming(try actionUUID("layerID"),startTime:try number("startTime",range: -86400...86400),duration:try number("duration",range:0...86400))))
    case "groupStart":return .video(.arrange(.groupStart(try actionUUID("layerID"),try number("startTime",range: -86400...86400))))
    case "blankLayer":return .video(.blankLayer)
    case "create":return .video(.create(frameRate:try number("frameRate",range:1...240),durationFrames:try integer("durationFrames",range:1...20736001)))
    case "duration":return .video(.duration(try integer("durationFrames",range:1...20736001)))
    case "remove":return .video(.remove)
    case "timing": return .video(.timing(try actionUUID("layerID"),startTime:try number("startTime",range: -86400...86400),inFrame:try integer("inFrame",range:0...Double(VideoFrames.maximumLogicalFrames-1)),outFrame:try integer("outFrame",range:1...Double(VideoFrames.maximumLogicalFrames)),frameRate:try number("frameRate",range:1...240)))
    case "frameRate": return .video(.frameRate(try number("frameRate",range:1...240)))
    default:return .video(.loop(try pathFlag("looping",false)))
    }
  }
  private func videoLayerIDs() throws -> Set<UUID> {
    guard case .array(let values)=parameters["layerIDs"],values.count<=512 else{throw AutomationFailure(status:400,message:"Provide clip UUIDs.")}
    let ids=try values.map { value -> UUID in guard case .string(let text)=value,let id=UUID(uuidString:text) else{throw AutomationFailure(status:400,message:"Invalid clip UUID.")};return id }
    guard Set(ids).count==ids.count else{throw AutomationFailure(status:400,message:"Duplicate clip UUID.")};return Set(ids)
  }
  @MainActor func applyVideoView(to store:EditorStore) throws {
    guard !parameters.isEmpty else { throw AutomationFailure(status:400,message:"Choose a video view change.") }
    guard store.canUseTimeline,let timeline = store.document.videoTimeline else { throw AutomationFailure(status:409,message:"Create a video Timeline and finish the current edit.") }
    let frame = try parameters["frame"].map{_ in try integer("frame",range:0...Double(timeline.durationFrames-1))}
    let visible = try parameters["visible"].map{_ in try pathFlag("visible",false)}
    let playing = try parameters["playing"].map{_ in try pathFlag("playing",false)}
    let zoom=try parameters["pixelsPerSecond"].map{_ in try number("pixelsPerSecond",range:5...400)}
    let editor=try parameters["transitionEditorVisible"].map{_ in try pathFlag("transitionEditorVisible",false)}
    var selected=store.videoSelectedTransitionID
    if let value=parameters["transitionID"] {
      if case .null=value{selected=nil}else{
        let id=try actionUUID("transitionID");guard store.document.videoTimeline?.transitions?.contains(where:{$0.id==id}) == true else{throw AutomationFailure(status:400,message:"Unknown transition.")};selected=id
      }
    }
    if let zoom{store.videoTimelinePixelsPerSecond=zoom};if let editor{store.videoTransitionEditorVisible=editor};store.videoSelectedTransitionID=selected
    if let frame { try store.selectVideoFrame(frame) };if let visible { store.timelineVisible=visible }
    if playing == false { store.stopTimelinePlayback(render:false) };if playing == true { try store.startVideoPlayback() };store.render()
  }
}
extension AutomationService {
  var videoSequenceCreationState: [String:Any] { ["operationID":videoSequenceOperationID?.uuidString as Any? ?? NSNull(),"sourceIDs":videoSequenceSourceIDs.map(\.uuidString).sorted()] }
  func createVideoSequence(_ command: AutomationCommand, anchorID: UUID) async throws -> AutomationResponse {
    guard documentTransfersEnabled else { throw AutomationFailure(status:403,message:"Enable document transfers before creating a video sequence.") }
    guard !documentTransferBusy,controller.canPublishVideoSequence else { throw AutomationFailure(status:409,message:"Finish the current document operation.") }
    guard case .array(let raw) = command.parameters["sources"], (1...7).contains(raw.count) else { throw AutomationFailure(status:400,message:"Choose 1–7 shared still documents in frame order.") }
    let sources: [(UUID,String)] = try raw.map { value in
      guard case .object(let fields)=value,Set(fields.keys)==["id","revision"],case .string(let text)=fields["id"],let id=UUID(uuidString:text),case .string(let revision)=fields["revision"],!revision.isEmpty,revision.count<=256 else { throw AutomationFailure(status:400,message:"Each source requires its shared id and current revision.") };return (id,revision)
    }
    guard Set(sources.map(\.0)).count==sources.count,sources.contains(where:{$0.0==anchorID}) else { throw AutomationFailure(status:400,message:"Use distinct sources and include the command target.") }
    guard shares.count<8 else { throw AutomationFailure(status:429,message:"Leave one sharing slot for the sequence.") }
    let rate=try command.number("frameRate",range:1...240),name=try command.string("name")
    guard !name.isEmpty,name.count<=256 else { throw AutomationFailure(status:400,message:"Choose a name of 1–256 characters.") }
    let documents=try sources.map { id,revision -> CraftNSDocument in
      guard let document=shares.first(where:{$0.id==id})?.document else { throw AutomationFailure(status:404,message:"Shared source not found.") }
      try preflight(document);guard self.revision(document.store)==revision,document.store.timelineTask==nil else { throw AutomationFailure(status:409,message:"A source is stale or playing.") };return document
    }
    let snapshots=documents.map{$0.store.document},stores=documents.map{$0.store.layerPanelGeneration}
    let expectedToken=token,transfer=documentTransferGeneration,opening=controller.documentOpening.generation,closing=controller.documentClosing.state?.id
    let operation=UUID();videoSequenceOperationID=operation;videoSequenceSourceIDs=Set(sources.map(\.0));documentTransferBusy=true
    for document in documents { document.store.geometryBusy=true;document.store.renderTask?.cancel() }
    let worker=Task.detached(priority:.userInitiated) { try VideoSequence.make(snapshots,frameRate:rate,name:name,maximumBytes:128*1024*1024) };videoSequenceTask=worker
    let observer=Task { await withTaskCancellationHandler { _=try? await worker.value } onCancel:{worker.cancel()} }
    for document in documents { document.store.geometryTask=observer }
    defer {
      if videoSequenceOperationID==operation { videoSequenceTask=nil;videoSequenceOperationID=nil;videoSequenceSourceIDs=[] }
      documentTransferBusy=false
      for (i,document) in documents.enumerated() where document.store.layerPanelGeneration==stores[i] { document.store.geometryBusy=false;document.store.geometryTask=nil;document.store.render() }
    }
    let model=try await withTaskCancellationHandler { try await worker.value } onCancel:{worker.cancel()}
    try Task.checkCancellation();guard !observer.isCancelled else { throw CancellationError() };prune()
    guard isRunning,token==expectedToken,documentTransfersEnabled,documentTransferGeneration==transfer,controller.canPublishVideoSequence,controller.documentOpening.generation==opening,controller.documentClosing.state?.id==closing else { throw AutomationFailure(status:409,message:"Sequence creation was revoked or interrupted.") }
    for (i,document) in documents.enumerated() {
      guard shares.contains(where:{$0.id==sources[i].0 && $0.document===document}),revision(document.store)==sources[i].1,document.store.document==snapshots[i],document.store.layerPanelGeneration==stores[i] else { throw AutomationFailure(status:409,message:"A source changed or sharing ended.") }
    }
    try Self.checkLimits(model);guard shares.count<8 else { throw AutomationFailure(status:429,message:"Sharing capacity changed.") }
    let created=try controller.publishVideoSequence(model,display:false)
    do { try share(created) } catch { controller.removeDocument(created);throw error }
    created.makeWindowControllers();created.showWindows()
    guard let shared=shares.first(where:{$0.document===created}) else { throw AutomationFailure(status:409,message:"Sequence sharing ended.") }
    return .json(state(shared,document:created),status:201)
  }
}
