import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum VideoRenderAPI {
  static let commands:Set<String>=["video.render","video.render.cancel"]
  static let definitions:[AutomationCommand.Definition]=[
    .init(name:"video.render",parameters:["codec":"h264/hevc/proRes422/proRes4444/uncompressed","useWorkArea":"Use Timeline work area; excludes explicit frame range","width":"Output width, default document","height":"Output height, default document","frameRate":"Output FPS, default Timeline or 30","firstFrame":"First source frame, zero-based inclusive","lastFrame":"Last source frame, zero-based inclusive","bitRate":"H.264/HEVC bits per second, default automatic","includeAudio":"Include mixed audio, default true","preserveAlpha":"Preserve alpha in ProRes4444/uncompressed, default false"],description:"Render a snapshot to MP4/QuickTime using native encoders. Requires transfers; returns movie bytes without editing document/history.",optionalParameters:["useWorkArea","width","height","frameRate","firstFrame","lastFrame","bitRate","includeAudio","preserveAlpha"]),
    .init(name:"video.render.cancel",parameters:["operationID":"Active Render Video UUID"],description:"Cancel the matching native movie encoder.")]
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "codec":BrushAPI.enumeration(VideoRenderCodec.allCases.map(\.rawValue))
    case "operationID":["type":"string","format":"uuid"]
    case "width","height":["type":"integer","minimum":1,"maximum":8192]
    case "frameRate":["type":"number","minimum":1,"maximum":240]
    case "bitRate":["type":"integer","minimum":100000,"maximum":200000000]
    case "includeAudio","preserveAlpha","useWorkArea":["type":"boolean"]
    default:["type":"integer","minimum":0,"maximum":20736000]
    }
  }
  static var stateSchema:[String:Any]{ImageSequenceAPI.stateSchema}
  static var capabilities:[String:Any]{[
    "commands":commands.sorted(),"stateSchema":stateSchema,"maximumBytes":VideoRender.apiMaximumBytes,
    "resultSchema":["type":"string","format":"binary","contentTypes":["video/mp4","video/quicktime"]],
    "codecs":VideoRenderCodec.allCases.map(\.rawValue),"maximumFrames":100000,"maximumPixels":33554432,
    "color":"SDR Rec.709, square pixels, 8-bit BGRA encoder input converted by ColorSync from working ICC. Alpha is straight, optional for ProRes4444/uncompressed; otherwise black matte. H.264/HEVC require even dimensions.",
    "timing":"Exact-time keyframes/transitions, constant output FPS. Selected source range is inclusive and zero-based. Final frame holds to the next output tick. Positive video-derived frame delays stay exact; ordinary frame-animation delays clamp to 0.02 seconds, matching playback. Movie output is one pass; loop flags are not embedded.",
    "audio":"48kHz stereo mix, range trimmed and padded to output duration. MP4 uses AAC192kbps; QuickTime uses Float32 PCM. No audible clips means no audio track. Decoded source cache and output mix each bounded to128MiB.",
    "lifecycle":"videoRender.operationID supports cancellation while busy. Closure, edits, revision changes and transfer/share revocation prevent delivery. Native source/history remain unchanged; encoders may produce differing bytes for equivalent frames.",
    "uncompressedInteroperability":"Uncompressed QuickTime carries explicit row-stride metadata. FFmpeg6.1 ignores rowb for narrow/nonaligned BGRA widths; Apple native decoding and direct packet/rowb checks preserve pixels. Cross-reader raw movie interchange remains open.",
    "limits":"Encoder availability depends on macOS/hardware. DPX, HDR, pixel aspect ratios, complete Adobe presets/descriptors and exact Photoshop/live/platform fidelity remain open.",
    "adobe":"The pinned public v2 contract has no dedicated Render Video route; no Adobe endpoint is invented."]}
}
extension AutomationCommand {
  func videoRenderOptions()throws->VideoRenderOptions {
    guard let codec=VideoRenderCodec(rawValue:try string("codec")) else{throw AutomationFailure(status:400,message:"Unknown video codec.")}
    func optionalInteger(_ key:String,_ range:ClosedRange<Double>)throws->Int?{try parameters[key].map{_ in try integer(key,range:range)}}
    func boolean(_ key:String,_ fallback:Bool)throws->Bool{guard let raw=parameters[key]else{return fallback};guard case .bool(let value)=raw else{throw AutomationFailure(status:400,message:"\(key) must be boolean.")};return value}
    if try boolean("useWorkArea",false),parameters["firstFrame"] != nil || parameters["lastFrame"] != nil{throw AutomationFailure(status:400,message:"Work area and explicit frame range are mutually exclusive.")}
    return try .init(codec:codec,width:optionalInteger("width",1...8192),height:optionalInteger("height",1...8192),
      frameRate:parameters["frameRate"].map{_ in try number("frameRate",range:1...240)},firstFrame:optionalInteger("firstFrame",0...20736000) ?? 0,
      lastFrame:optionalInteger("lastFrame",0...20736000),bitRate:optionalInteger("bitRate",100000...200000000),
      includeAudio:boolean("includeAudio",true),preserveAlpha:boolean("preserveAlpha",false),useWorkArea:boolean("useWorkArea",false))
  }
}
extension AutomationService {
  func exportVideo(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID)async throws->AutomationResponse {
    guard documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Enable document transfers before rendering video.")}
    let options=try command.videoRenderOptions(),snapshot=document.store.document,expectedToken=token,generation=documentTransferGeneration
    videoRenderShares.insert(shareID);defer{videoRenderShares.remove(shareID)}
    let output=try await document.store.encodedVideo(options,maximumBytes:VideoRender.apiMaximumBytes);defer{output.discard()}
    let worker=Task.detached(priority:.userInitiated){
      let file=try FileHandle(forReadingFrom:output.url);defer{try? file.close()};var bytes=Data()
      while let part=try file.read(upToCount:65536),!part.isEmpty{try Task.checkCancellation();guard part.count<=output.bytes-bytes.count else{throw CraftError.invalid("Video output size changed.")};bytes.append(part)}
      guard bytes.count==output.bytes else{throw CraftError.invalid("Incomplete video output.")};return bytes
    }
    let bytes=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
    try Task.checkCancellation();prune()
    guard isRunning,token==expectedToken,documentTransfersEnabled,documentTransferGeneration==generation,
      shares.contains(where:{$0.id==shareID && $0.document === document}),document.store.document==snapshot,
      revision(document.store)==command.revision else{throw AutomationFailure(status:409,message:"Video export was revoked or its source changed.")}
    return .init(status:200,contentType:options.codec.contentType,body:bytes)
  }
  func cancelSharedVideoRender(_ share:Share){guard videoRenderShares.contains(share.id)else{return};share.document?.store.videoRenderWorker?.cancel()}
}
