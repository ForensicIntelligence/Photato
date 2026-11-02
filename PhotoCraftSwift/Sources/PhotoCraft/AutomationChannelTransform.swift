import Foundation
import PhotoCraftCore

enum ChannelTransformAPI{
  static let name="channel.transform"
  static func schema(_ key:String)->[String:Any]{switch key{case "target":return ChannelAPI.parameterSchema("target")!;case "backgroundValue":return BrushAPI.number(0,1);case "copy":return BrushAPI.flag;default:return SelectionTransformAPI.schema(key)}}
  static var stateSchema:[String:Any]{var result=SelectionTransformAPI.stateSchema,properties=result["properties"] as! [String:Any],required=result["required"] as! [String];properties["channelTarget"]=["anyOf":[["type":"null"],schema("target")]];properties["backgroundValue"]=schema("backgroundValue");properties["selectedRegion"]=BrushAPI.flag;properties["copy"]=BrushAPI.flag;required += ["channelTarget","backgroundValue","selectedRegion","copy"];result["properties"]=properties;result["required"]=required;return result}
  static var resultSchema:[String:Any]{["type":"object","required":["revision","channelTransform"],"properties":["revision":["type":"string"],"channelTransform":stateSchema]]}
  static var capabilities:[String:Any]{[
    "command":name,"stateSchema":stateSchema,"resultSchema":resultSchema,"matrixSchema":schema("matrix"),
    "target":"Select an alpha/spot UUID or quickMask through existing channel.view, then channel.transform. The target must match the current native channel. Whole planes and selected regions share the engine. Individual color/ink components and multiple active channel editing remain separate work.",
    "native":"Command-T and Edit/Transform six modes/fixed rotations/flips use existing numeric/reference/Shift/Option/captured cursor controls. Channel previews honor gray, selectedAreas inversion, spot display and overlay. Return applies one Free Transform transaction; Escape/focus/tool/read/close cancel. Native Free Transform Option means centered transformation, not copy.",
    "samples":"Numeric channel coverage, original depth, fixed canvas clipping and captured editing-gray backgroundValue. Omitted value captures native background swatch gray; display/spot inversion is applied once. Whole projection shares the mask scalar sampler; selected coverage uses the shared opaque immutable-source compositor. copy=true explicitly duplicates selected/full-plane content over unchanged source. No color transfer. Other channels/layers/profiles/display/retained records survive; Float32spot source gray transforms with coverage and is used only where compatible.",
    "preview":"Coalesced off-main proxy at most1024pixels per side. Source/selection/channel/gray/overlay stay captured. No document/history writes per pointer input. Current target/revision/source/busy/stale/revoke/cancel validation and one Undo. No extra8MP/36MP admission cap; sparse maximum-plane tests do not establish practical maximum dense capacity.",
    "history":"Semantic channel transform Actions36 resolve alpha/spot by name+occurrence or Quick Mask role; original UUIDs are not required. Older operation minimum versions retained; native83 unchanged.",
    "adobe":"No dedicated auxiliary-channel transform route or qualified channel actionJSON descriptor in the pinned published v2 contract. Existing layer/resource operations remain distinct; no route is invented.",
    "limits":"Channel Move/V gestures, color/ink components, linked/selected/filter/vector mask targets, multi-layer/Warp/repeat, exact Photoshop gray/edge/bounds/default/cursor/live/byte behavior, full-current suite/platform/max-dense/physical60fps remain unqualified."
  ]}
}
extension AutomationCommand{
  func channelTransformOptions(defaultBackground:Float)throws->ChannelTransformRequest{
    let(matrix,method)=try selectionTransformOptions();return try .init(target:channelTarget(),matrix:matrix,interpolation:method,backgroundValue:parameters["backgroundValue"]==nil ? defaultBackground:Float(number("backgroundValue",range:0...1)),copy:parameters["copy"]==nil ? false:selectedPixelFlag("copy"))
  }
}
@MainActor extension EditorStore{
  var channelTransformState:[String:Any]{
    let draft=transformDraft?.channelTarget != nil ? transformDraft:nil,target=draft?.channelTarget ?? editingChannel,identifier:String?
    switch target{case .alpha(let id):identifier=id.uuidString;case .quickMask:identifier="quickMask";case nil:identifier=nil}
    return selectionTransformState.merging(["target":"channel","available":canBeginChannelTransform,"active":draft != nil,"channelTarget":identifier as Any? ?? NSNull(),"backgroundValue":draft?.channelBackgroundValue ?? channelTransformBackgroundValue,"selectedRegion":document.selection != nil,"copy":false]){_,b in b}
  }
}
