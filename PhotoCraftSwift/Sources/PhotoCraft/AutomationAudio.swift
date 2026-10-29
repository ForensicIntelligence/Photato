import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum TimelineAudioAPI {
  static let commands:Set<String> = ["audio.edit","audio.view","audio.import.cancel"]
  static let definitions:[AutomationCommand.Definition] = [
    .init(name:"audio.edit",parameters:["operation":"newTrack, renameTrack, deleteTrack, muteTrack, deleteClip, move, trim, clipSettings, movieSettings or split","trackID":"Audio track UUID","clipID":"Audio clip UUID","layerID":"Movie layer UUID","name":"Track name","startTime":"Timeline seconds","sourceIn":"Source start seconds","sourceOut":"Exclusive source end seconds","seconds":"Split time","volume":"0–1 gain","muted":"Mute audio","fadeIn":"Fade-in seconds","fadeOut":"Fade-out seconds"],description:"Edit retained Timeline audio through native history.",optionalParameters:["trackID","clipID","layerID","name","startTime","sourceIn","sourceOut","seconds","volume","muted","fadeIn","fadeOut"]),
    .init(name:"audio.view",parameters:["trackID":"Select track UUID or null","clipID":"Select clip UUID or null","settingsVisible":"Show audio settings"],description:"Select audio without content history.",optionalParameters:["trackID","clipID","settingsVisible"]),
    .init(name:"audio.import.cancel",parameters:["operationID":"Active audio import UUID"],description:"Cancel the matching retained-audio import.")]
  static func schema(_ key:String,command:String? = nil)->[String:Any] {
    switch key {
    case "operation":BrushAPI.enumeration(["newTrack","renameTrack","deleteTrack","muteTrack","deleteClip","move","trim","clipSettings","movieSettings","split"])
    case "name":["type":"string","minLength":1,"maxLength":256]
    case "volume":["type":"number","minimum":0,"maximum":1]
    case "startTime":TimelineWorkspaceAPI.timeSchema
    case "sourceIn","sourceOut","seconds","fadeIn","fadeOut":["type":"number","minimum":0,"maximum":86400]
    case "muted","settingsVisible":BrushAPI.flag
    default:command == "audio.view" ? ["type":["string","null"],"format":"uuid"]:["type":"string","format":"uuid"]
    }
  }
  static var settingsSchema:[String:Any] {BrushAPI.object(["volume":schema("volume"),"muted":schema("muted"),"fadeIn":schema("fadeIn"),"fadeOut":schema("fadeOut")],required:["volume","muted","fadeIn","fadeOut"])}
  static var clipSchema:[String:Any] {BrushAPI.object(["id":schema("clipID"),"name":schema("name"),"startTime":TimelineWorkspaceAPI.timeSchema,"sourceIn":schema("sourceIn"),"sourceOut":schema("sourceOut"),"duration":schema("seconds"),"sourceDuration":schema("seconds"),"retainedBytes":["type":"integer","minimum":1,"maximum":TimelineAudioSource.maximumBytes],"settings":settingsSchema,"playbackRate":["type":"number","exclusiveMinimum":0,"maximum":240]],required:["id","name","startTime","sourceIn","sourceOut","duration","sourceDuration","retainedBytes","settings"])}
  static var stateSchema:[String:Any] {BrushAPI.object([
    "tracks":["type":"array","maxItems":32,"items":BrushAPI.object(["id":schema("trackID"),"name":schema("name"),"muted":schema("muted"),"clips":["type":"array","maxItems":512,"items":clipSchema]],required:["id","name","muted","clips"])],
    "movies":["type":"array","maxItems":512,"items":BrushAPI.object(["layerID":schema("layerID"),"settings":settingsSchema,"playbackRate":["type":"number","exclusiveMinimum":0,"maximum":240]],required:["layerID","settings"])],
    "preparing":BrushAPI.flag,"playing":BrushAPI.flag,"importOperationID":schema("operationID",command:"audio.view"),"selectedTrackID":schema("trackID",command:"audio.view"),"selectedClipID":schema("clipID",command:"audio.view"),"settingsVisible":BrushAPI.flag],required:["tracks","movies","preparing","playing","importOperationID","selectedTrackID","selectedClipID","settingsVisible"])}
  @MainActor static func state(_ store:EditorStore)->[String:Any] {
    ["tracks":(store.document.videoTimeline?.audioTracks ?? []).map{track in ["id":track.id.uuidString,"name":track.name,"muted":track.muted,"clips":track.clips.map{clip in ["id":clip.id.uuidString,"name":clip.name,"startTime":clip.startTime,"sourceIn":clip.sourceIn,"sourceOut":clip.sourceOut,"duration":clip.duration,"sourceDuration":clip.source.duration,"playbackRate":clip.effectiveRate,"retainedBytes":clip.source.data.count,"settings":BrushAPI.json(clip.settings)] as [String:Any]}] as [String:Any]},
     "movies":store.document.layers.filter{($0.video?.movie?.audioTracks ?? 0)>0}.map{["layerID":$0.id.uuidString,"settings":BrushAPI.json($0.video?.audio ?? .init())]},
     "preparing":store.timelineAudioPreparing,"playing":store.timelineAudioPlayer?.isPlaying ?? false,"importOperationID":store.timelineAudioImportID?.uuidString as Any? ?? NSNull(),"selectedTrackID":store.selectedAudioTrackID?.uuidString as Any? ?? NSNull(),"selectedClipID":store.selectedAudioClipID?.uuidString as Any? ?? NSNull(),"settingsVisible":store.showAudioControls]
  }
  static var capabilities:[String:Any] {
    ["commands":commands.sorted(),"stateSchema":stateSchema,"nativeArchiveVersion":60,
     "import":["method":"POST","path":"/v1/documents/{id}/audio","mediaTypes":TimelineAudioIO.mediaTypes,"maximumBytes":TimelineAudioSource.maximumBytes,"requiredHeaders":["X-Photato-Revision"],"optionalHeaders":["X-Photato-Audio-Track","X-Photato-Audio-Name","X-Photato-Audio-Start"],"behavior":"Requires document transfers and an idle shared video Timeline. Name is percent-encoded UTF-8; omitted track creates a new Audio Track. Start defaults to playhead. Original bytes retained; result is one Undo and HTTP200 state. Revocation/cancellation/stale checks precede commit."],
     "preview":["method":"GET","path":"/v1/documents/{id}/audio.wav","contentType":"audio/wav","behavior":"Read-only full-Timeline stereo48kHz Float32 WAVE mixed by the native preview engine. Document-transfer permission required. Request cancellation cancels rendering; changed/revoked sources reject."],
     "behavior":"Independent soundtrack clips and retained movie audio have volume, mute, linear fade-in/out. Graphical audio tracks share Timeline move/trim/playhead. Native audio clock drives video frames during audible playback. Source trims and movie speed affect audio time; silence fills absent audio. Mix clips add and clamp to [-1,1]. Original sources remain unchanged; settings/tracks use native56 and Undo.",
     "limits":"32 audio tracks/512 clips; original source64MiB. Desktop decoded sources256MiB plus256MiB mix, API128MiB each. Native AVFoundation codec support; fixed48kHz stereo mix and linear speed resampling. Long disk-backed streaming, pitch preservation, multichannel output, waveforms, richer PSD/Actions, Render Video and exact Photoshop/live/platform fidelity remain open.",
     "adobe":"No dedicated Timeline audio endpoint in the pinned Adobe v2 contract; these are Photato extensions."]
  }
}
extension AutomationCommand {
  func timelineAudioCommand()throws->Command {
    let op=try string("operation"),required:Set<String>
    switch op {
    case "newTrack":required=["name"]
    case "renameTrack":required=["trackID","name"]
    case "deleteTrack":required=["trackID"]
    case "muteTrack":required=["trackID","muted"]
    case "deleteClip":required=["clipID"]
    case "move":required=["clipID","trackID","startTime"]
    case "trim":required=["clipID","startTime","sourceIn","sourceOut"]
    case "clipSettings":required=["clipID","volume","muted","fadeIn","fadeOut"]
    case "movieSettings":required=["layerID","volume","muted","fadeIn","fadeOut"]
    case "split":required=["clipID","seconds"]
    default:throw AutomationFailure(status:400,message:"Unknown audio operation.")
    }
    guard Set(parameters.keys)==required.union(["operation"]) else{throw AutomationFailure(status:400,message:"Missing or irrelevant audio parameters.")}
    func seconds(_ key:String)throws->Double{try number(key,range:key == "startTime" ? -86400...86400 : 0...86400)}
    let edit:TimelineAudioCommand
    switch op {
    case "newTrack":edit = .addTrack(UUID(),try string("name"))
    case "renameTrack":edit = .renameTrack(try actionUUID("trackID"),try string("name"))
    case "deleteTrack":edit = .removeTrack(try actionUUID("trackID"))
    case "muteTrack":edit = .muteTrack(try actionUUID("trackID"),try pathFlag("muted",false))
    case "deleteClip":edit = .removeClip(try actionUUID("clipID"))
    case "move":edit = .move(try actionUUID("clipID"),track:try actionUUID("trackID"),startTime:try seconds("startTime"))
    case "trim":edit = .trim(try actionUUID("clipID"),startTime:try seconds("startTime"),sourceIn:try seconds("sourceIn"),sourceOut:try seconds("sourceOut"))
    case "split":edit = .split(try actionUUID("clipID"),try seconds("seconds"))
    default:
      let settings=TimelineAudioSettings(volume:try number("volume",range:0...1),muted:try pathFlag("muted",false),fadeIn:try seconds("fadeIn"),fadeOut:try seconds("fadeOut"))
      edit = op == "clipSettings" ? .settings(try actionUUID("clipID"),settings):.movieSettings(try actionUUID("layerID"),settings)
    }
    return .video(.audio(edit))
  }
  @MainActor func applyAudioView(_ store:EditorStore)throws {
    guard !parameters.isEmpty,store.canUseTimeline,store.document.videoTimeline != nil else{throw AutomationFailure(status:409,message:"Choose audio view changes in an idle video Timeline.")}
    func id(_ key:String,_ current:UUID?)throws->UUID?{guard let value=parameters[key] else{return current};if case .null=value{return nil};return try actionUUID(key)}
    var track=try id("trackID",store.selectedAudioTrackID);let clip=try id("clipID",store.selectedAudioClipID)
    if let clip {
      guard let owner=store.document.videoTimeline?.audioTracks?.first(where:{$0.clips.contains(where:{$0.id==clip})}) else{throw AutomationFailure(status:400,message:"Unknown audio clip.")}
      if parameters["trackID"] != nil,track != owner.id{throw AutomationFailure(status:400,message:"The clip is not in the chosen track.")};track=owner.id
    }
    if let track,store.document.videoTimeline?.audioTracks?.contains(where:{$0.id==track}) != true{throw AutomationFailure(status:400,message:"Unknown audio track.")}
    let visible=try parameters["settingsVisible"].map{_ in try pathFlag("settingsVisible",false)}
    store.selectedAudioTrackID=track;store.selectedAudioClipID=clip;if let visible{store.showAudioControls=visible}
  }
}
extension AutomationService {
  func cancelSharedAudio(_ share:Share) {
    if let operation=audioImportOperations[share.id],let store=share.document?.store,store.timelineAudioImportID==operation{store.geometryTask?.cancel()}
    audioPreviewWorkers[share.id]?.cancel()
  }
  func importTimelineAudio(_ request:AutomationRequest,share:Share,document:CraftNSDocument)async throws->AutomationResponse {
    guard documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Enable document transfers before importing audio.")}
    try preflight(document)
    guard document.store.canImportTimelineAudio else{throw AutomationFailure(status:409,message:"Create a video Timeline and stop playback before importing audio.")}
    guard let expected=request.headers["x-photato-revision"],expected==revision(document.store) else{throw AutomationFailure(status:409,message:"Stale or missing audio import revision.")}
    let media=request.headers["content-type"]?.split(separator:";").first?.lowercased() ?? ""
    guard TimelineAudioIO.mediaTypes.contains(media) else{throw AutomationFailure(status:415,message:"Choose a supported audio content type.")}
    guard !request.body.isEmpty,request.body.count<=TimelineAudioSource.maximumBytes else{throw AutomationFailure(status:413,message:"Audio source exceeds64MiB or is empty.")}
    let track:UUID?
    if let value=request.headers["x-photato-audio-track"] {guard let id=UUID(uuidString:value) else{throw AutomationFailure(status:400,message:"Invalid audio track UUID.")};track=id}else{track=nil}
    let rawName=request.headers["x-photato-audio-name"] ?? "Audio",name=rawName.removingPercentEncoding ?? ""
    guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=256 else{throw AutomationFailure(status:400,message:"Invalid audio clip name.")}
    let start:Double
    if let raw=request.headers["x-photato-audio-start"] {guard let value=Double(raw),value.isFinite,(0...86400).contains(value) else{throw AutomationFailure(status:400,message:"Invalid audio start time.")};start=value}else{start=document.store.document.videoTimeline!.seconds}
    let data=request.body,clipID=UUID(),operation=UUID(),transfer=documentTransferGeneration
    document.store.timelineAudioImportID=operation;audioImportOperations[share.id]=operation
    defer{audioImportOperations.removeValue(forKey:share.id);if document.store.timelineAudioImportID==operation{document.store.timelineAudioImportID=nil}}
    try await executePreparedOperation(document:document,shareID:share.id,revision:expected,validateCommit:{[weak self] in
      guard let self,self.documentTransfersEnabled,self.documentTransferGeneration==transfer else{throw AutomationFailure(status:409,message:"Audio import permission changed.")}
    }) { _ in
      let source=try TimelineAudioIO.decode(data,maximumBytes:128*1024*1024).0
      return .video(.audio(.importClip(track,.init(id:clipID,name:name,source:source,startTime:start))))
    }
    document.store.selectedAudioClipID=clipID
    document.store.selectedAudioTrackID=document.store.document.videoTimeline?.audioTracks?.first(where:{$0.clips.contains(where:{$0.id==clipID})})?.id
    document.store.timelineAudioImportID=nil
    return .json(state(share,document:document))
  }
  func timelineAudioPreview(_ share:Share,document:CraftNSDocument)async throws->AutomationResponse {
    guard documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Enable document transfers before downloading audio.")}
    try preflight(document)
    guard !previewBusy else{throw AutomationFailure(status:429,message:"A preview is already rendering.")}
    previewBusy=true;defer{previewBusy=false}
    let source=document.store.document,expected=revision(document.store),transfer=documentTransferGeneration,expectedToken=token
    let worker=Task.detached(priority:.userInitiated){try TimelineAudioMixer.render(source,maximumBytes:128*1024*1024)?.wave()}
    audioPreviewWorkers[share.id]=worker
    defer{audioPreviewWorkers.removeValue(forKey:share.id)}
    let data=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
    try Task.checkCancellation()
    guard isRunning,token==expectedToken,documentTransfersEnabled,documentTransferGeneration==transfer,revision(document.store)==expected,shares.contains(where:{$0.id==share.id && $0.document===document}) else{throw AutomationFailure(status:409,message:"Audio preview changed or was revoked.")}
    guard let data else{throw AutomationFailure(status:422,message:"The Timeline has no audible clips.")}
    return .init(status:200,contentType:"audio/wav",body:data)
  }
}
