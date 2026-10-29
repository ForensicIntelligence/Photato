import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum MovieAPI {
  static var sourceSchema:[String:Any] {
    var value=BrushAPI.object(["retainedBytes":["type":"integer","minimum":1,"maximum":MovieSource.maximumBytes],"audioTracks":["type":"integer","minimum":0,"maximum":64],"audioPlayback":BrushAPI.flag,"originalFrameRate":["type":"number"],"presentationTimes":["type":"array","items":BrushAPI.object(["value":["type":"integer"],"timescale":["type":"integer","minimum":1]],required:["value","timescale"])],"endTime":BrushAPI.object(["value":["type":"integer"],"timescale":["type":"integer","minimum":1]],required:["value","timescale"])],required:["retainedBytes","audioTracks","audioPlayback","originalFrameRate","presentationTimes","endTime"])
    value["type"]=["object","null"];return value
  }
  static func state(_ movie:MovieSource?)->Any {
    guard let movie else{return NSNull()}
    return ["retainedBytes":movie.data.count,"audioTracks":movie.audioTracks,"audioPlayback":true,"originalFrameRate":movie.originalFrameRate,"presentationTimes":movie.presentationTimes.map{BrushAPI.json($0)},"endTime":BrushAPI.json(movie.endTime)] as [String:Any]
  }
  static var capabilities:[String:Any] {
    ["import":"POST /v1/documents/import with video/quicktime, video/mp4 or video/x-m4v; optional X-Photato-Open-Format: movie. Returns HTTP201 shared state. File/Open uses the same AVFoundation decoder.","placement":"video.place copies a shared one-layer video source into the target, centered at its current playhead. Color/depth convert all retained frames; source remains unchanged. video.place.cancel uses video.placementOperationID.","source":"Original container/audio retained byte-for-byte in native52; exact rational presentation timestamps and variable frame durations retained. Clip source rate scales source timing; Timeline rate changes sampling. Decoded editable frames use native SDR sRGB16 conversion and orientation.","limits":"MOV/MP4 recognized by container header, one unprotected video track and codecs supported by the host AVFoundation. Source64MiB, max512 frames; desktop1GiB/API128MiB total frame/source budget plus API4MP/64layer limit. Limits reject atomically. No external media references. HDR preservation, disk-backed long footage, multi-video-track import and full codec/Photoshop byte parity remain open.","audio":"Retained audio plays with synchronized native Timeline preview; audio.edit provides movie volume/mute/fades. See audio capabilities for mix/codec/budget limits.","adobe":"No dedicated movie/video import route in the pinned Adobe v2 contract; no new Adobe route is invented."]
  }
}
extension AutomationService {
  func placeMovie(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID) async throws {
    guard documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Enable document transfers before placing video.")}
    guard document.store.canImportMovieLayer else{throw AutomationFailure(status:409,message:"Finish the current edit and select an RGB target.")}
    let sourceID=try command.actionUUID("sourceDocumentID"),expected=try command.string("sourceRevision")
    guard let source=shares.first(where:{$0.id==sourceID})?.document else{throw AutomationFailure(status:404,message:"Video source is not shared.")}
    try preflight(source)
    guard revision(source.store)==expected,source.store.timelineTask==nil else{throw AutomationFailure(status:409,message:"Video source changed or is playing.")}
    let snapshot=source.store.document,transfer=documentTransferGeneration,operation=UUID()
    document.store.moviePlacementID=operation
    defer{if document.store.moviePlacementID==operation{document.store.moviePlacementID=nil}}
    try await executePreparedOperation(document:document,shareID:shareID,revision:command.revision,validateCommit:{[weak self] in
      guard let self,self.documentTransfersEnabled,self.documentTransferGeneration==transfer,self.shares.contains(where:{$0.id==sourceID && $0.document===source}),self.revision(source.store)==expected else{throw AutomationFailure(status:409,message:"Video source or transfer permission changed.")}
    }) { target in .video(.insert(try MovieIO.layer(from:snapshot,into:target,maximumBytes:128*1024*1024))) }
    document.store.timelineVisible=true;document.store.selectedLayerIDs=Set(document.store.document.activeLayerID.map{[$0]} ?? [])
  }
}
