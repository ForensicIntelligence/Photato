import Foundation
import PhotoCraftCore

/// Ordinary state describes temporal storage; native document transfer carries
/// the actual pixels/media under its existing authorization and byte limits.
enum TemporalContentAPI {
  static var payloadSchema:[String:Any] {
    BrushAPI.object(["contentType":["type":"string"],"rasterBytes":["type":"integer","minimum":0],
      "hasMask":BrushAPI.flag,"hasVectorMask":BrushAPI.flag,"hasSmartFilters":BrushAPI.flag],
      required:["contentType","rasterBytes","hasMask","hasVectorMask","hasSmartFilters"])
  }
  static var samplingSchema:[String:Any] {
    BrushAPI.object(["frameRate":["type":"number"],"durationFrames":["type":"integer"],"hasAudio":BrushAPI.flag,"audioTrackCount":["type":"integer","minimum":0,"maximum":32]],required:["frameRate","durationFrames","hasAudio","audioTrackCount"])
  }
  static var sourceSchema:[String:Any] {
    BrushAPI.object(["frameRate":["type":"number"],"durationFrames":["type":"integer"],
      "layerCount":["type":"integer"],"hasAudio":BrushAPI.flag,"retainedBytes":["type":"integer"],
      "restoreOperation":["type":"string","const":"restoreVideoSource"]],
      required:["frameRate","durationFrames","layerCount","hasAudio","retainedBytes","restoreOperation"])
  }
  static var transitionsSchema:[String:Any] {
    let transition=(VideoTransitionAPI.stateSchema["items"] as? [String:Any]) ?? [:]
    return ["type":"array","maxItems":1024,"items":BrushAPI.object([
      "transition":transition,"progress":["type":"number","minimum":0,"maximum":1]],required:["transition","progress"])]
  }
  static var transitionKeysSchema:[String:Any] {
    ["type":"array","maxItems":512,"items":BrushAPI.object([
      "time":TimelineWorkspaceAPI.timeSchema,"states":transitionsSchema],required:["time","states"])]
  }
  static func payload(_ value:AnimationLayerPayload)->[String:Any] {
    let kind:String
    switch value.content {
    case .raster:kind="raster"
    case .fill:kind="fill"
    case .adjustment:kind="adjustment"
    case .group:kind="group"
    case .text:kind="text"
    case .shape:kind="shape"
    case .gradientFill:kind="gradient"
    case .patternFill:kind="pattern"
    }
    return ["contentType":kind,"rasterBytes":value.rasterBytes,"hasMask":value.mask != nil,
      "hasVectorMask":value.vectorMask != nil,"hasSmartFilters":value.smartFilters != nil]
  }
  static func source(_ value:FrameVideoSource)->[String:Any] {
    ["frameRate":value.timeline.frameRate,"durationFrames":value.timeline.durationFrames,
      "layerCount":value.layers.count,"hasAudio":!(value.timeline.audioTracks?.flatMap(\.clips).isEmpty ?? true) || value.layers.contains{($0.video?.movie?.audioTracks ?? 0)>0},
      "retainedBytes":value.estimatedBytes,"restoreOperation":"restoreVideoSource"]
  }
  static func animation(_ value:FrameAnimation)->[String:Any] {
    var safe=value;safe.retainedVideoSource=nil;safe.sampledTimeline=nil
    for i in safe.frames.indices {for j in safe.frames[i].layers.indices {safe.frames[i].layers[j].payload=nil}}
    var result=BrushAPI.json(safe) as? [String:Any] ?? [:]
    var frames=result["frames"] as? [[String:Any]] ?? []
    for i in frames.indices {
      var layers=frames[i]["layers"] as? [[String:Any]] ?? []
      for j in layers.indices {if let content=value.frames[i].layers[j].payload {layers[j]["payloadSummary"]=payload(content)}}
      frames[i]["layers"]=layers
    }
    result["frames"]=frames
    if let current=value.sampledTimeline {result["sampledTimeline"]=["frameRate":current.frameRate,"durationFrames":current.durationFrames,"hasAudio":current.hasAudio,"audioTrackCount":current.audioTracks.count]}
    if let original=value.retainedVideoSource {result["retainedSource"]=source(original)}
    return result
  }
  static func timeline(_ value:VideoTimeline)->[String:Any] {
    var safe=value;safe.audioTracks=nil;safe.retainedFrameSources=nil
    var result=BrushAPI.json(safe) as? [String:Any] ?? [:]
    if let original=value.retainedFrameSources?.first {result["retainedSource"]=source(original)}
    return result
  }
  static func key(_ value:VideoKeyframe)->[String:Any] {
    var safe=value;safe.content=nil
    var result=BrushAPI.json(safe) as? [String:Any] ?? [:]
    if let content=value.content {result["contentSummary"]=payload(content)}
    return result
  }
}
