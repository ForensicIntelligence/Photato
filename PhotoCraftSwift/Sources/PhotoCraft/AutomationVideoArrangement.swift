import Foundation
import PhotoCraftCore

enum VideoArrangementAPI {
  static var stateSchema:[String:Any] {
    let clip=BrushAPI.object(["layerID":VideoAPI.schema("layerID"),"startTime":TimelineWorkspaceAPI.timeSchema,"duration":VideoAPI.schema("duration")],required:["layerID","startTime","duration"])
    let group=BrushAPI.object(["layerID":VideoAPI.schema("layerID"),"startTime":TimelineWorkspaceAPI.timeSchema,"clips":VideoAPI.schema("layerIDs")],required:["layerID","startTime","clips"])
    return BrushAPI.object(["stills":["type":"array","maxItems":LayerLimits.maximumLayers,"items":clip],"groups":["type":"array","maxItems":LayerLimits.maximumLayers,"items":group]],required:["stills","groups"])
  }
  static func state(_ document:CraftDocument)->[String:Any] {
    ["stills":document.layers.compactMap{layer -> [String:Any]? in guard let timing=layer.videoTiming else{return nil};return ["layerID":layer.id.uuidString,"startTime":timing.startTime,"duration":timing.duration]},
     "groups":document.layers.compactMap{layer -> [String:Any]? in guard let start=layer.group?.videoStartTime else{return nil};return ["layerID":layer.id.uuidString,"startTime":start,"clips":document.children(of:layer.id).map{$0.id.uuidString}]}]
  }
  static var capabilities:[String:Any] {
    ["command":"video.edit","operations":["split","group","arrange","stillTiming","groupStart"],"nativeArchiveVersion":54,"stateSchema":stateSchema,
     "behavior":"Split selected clips at the current playhead, retaining exact source intervals, editable content and independent copies with shared source storage. Video groups sequence children in bottom-to-top layer order; group, move, duration and hierarchy edits reflow their clips. Keys follow moved clips; keys crossing time zero preserve the evaluated boundary value. Stills, type, shapes and ordinary groups retain editable content with duration gating. Empty group selections create an empty track. Arrange accepts null groupID for an independent track.",
     "limits":"Clipping-mask chains and nested video groups cannot be split. Transitions, audio, graphical Timeline bars/dragging, automatic movie grouping, full PSD/Actions and Photoshop exact/live/platform qualification remain open.","adobe":"No video arrangement endpoint exists in the pinned Adobe contract."]
  }
}
