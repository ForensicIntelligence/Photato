import Foundation
import PhotoCraftCore

enum SelectedPixelMoveAPI {
  static let name="pixels.move"
  static func schema(_ key:String)->[String:Any] {switch key {case "layerID":return SelectedPixelTransformAPI.schema(key);case "dx","dy":return BrushAPI.number(-1_000_000,1_000_000);case "copy","constrain":return BrushAPI.flag;default:return BackgroundLayerAPI.schema(key)}}
  static var stateSchema:[String:Any] {let fields:[String:Any]=["available":BrushAPI.flag,"active":BrushAPI.flag,"copy":BrushAPI.flag,"dx":["type":"integer"],"dy":["type":"integer"],"previewBusy":BrushAPI.flag,"committing":BrushAPI.flag,"error":["anyOf":[["type":"null"],["type":"string"]]],"background":BrushAPI.flag,"backgroundColor":["anyOf":[["type":"null"],schema("backgroundColor")]]];return BrushAPI.object(fields,required:Array(fields.keys).sorted())}
  static var resultSchema:[String:Any] {["type":"object","required":["revision","selectedPixelMove"],"properties":["revision":["type":"string"],"selectedPixelMove":stateSchema]]}
  static var capabilities:[String:Any] {[
    "command":name,"stateSchema":stateSchema,"resultSchema":resultSchema,
    "native":"Move/V inside an editable RGB pixel selection moves its content. Option at gesture start copies on the same layer. Current Shift constrains to45degrees; arrows nudge1pixel, Shift-arrows10; Option-arrows copy from the latest selected duplicate. Source/selection/target/background swatch stay captured during each drag. No Free Transform handles are shown during Move.",
    "offset":"dx/dy are finite document-pixel displacement, rounded to integers after optional constrain=true. copy defaultsfalse. backgroundColor is optional opaque RGBA for Background; omission captures the native swatch. Ordinary layers leave transparency on move and keep originals on copy. Background stays opaque/full-canvas. Existing layer.move keeps whole-layer semantics.",
    "preview":"Shared bounded1024-side image/contour proxy; coalesced off-main work, immutable original samples and one final nearest-grid commit on release. No document/history writes per pointer input. Source/target/revision/busy/stale/revoke/cancel/read/close guards and one Move Undo. Native guide snapping is explicit gesture feedback, suppressed by Command or Shift-direction priority. API offsets are explicit, not synthetic pointer input.",
    "cursors":"Copy is captured at pointer-down, Shift remains live, effective guide-snap suppression is shown, all16 Control/Command/Option/Shift combinations use the same policy. Controls retain native text/control cursors.",
    "storage":"Tiled damage regions/off-canvas ordinary storage; no additional8MP/36MP admission cap. New Move/copy semantic Actions34; old31/32/33 requirements retained. Native83 unchanged.",
    "adobe":"No dedicated selected-content Move/copy route in the pinned published v2 contract. Existing whole-layer operations and resource jobs remain distinct; unverified move-selection actionJSON descriptors stay unsupported.",
    "limits":"One editable RGB raster or Background layer. Mode-component/mask/Smart Object/multi-layer/animation/video targets, temporary selection-tool Command move and whole-layer Option duplication remain separate work. Exact Photoshop soft overlap/bytes/defaults/cursors/live behavior, key-repeat scheduling, physical60fps, practical maximum dense capacity and supported platforms remain unqualified."
  ]}
}
extension AutomationCommand {
  func selectedPixelFlag(_ key:String)throws->Bool {guard case .bool(let value)=parameters[key] else{throw AutomationFailure(status:400,message:"Invalid boolean \(key).")} ;return value}
  func selectedPixelMoveOptions()throws->SelectedPixelMoveRequest {
    guard let id=UUID(uuidString:try string("layerID")) else{throw AutomationFailure(status:400,message:"Invalid layerID.")}
    let color=parameters["backgroundColor"]==nil ? nil:try backgroundColor(default:.white)
    let value=SelectedPixelMoveRequest(layerID:id,dx:try number("dx",range:-1_000_000...1_000_000),dy:try number("dy",range:-1_000_000...1_000_000),copy:parameters["copy"]==nil ? false:try selectedPixelFlag("copy"),constrain:parameters["constrain"]==nil ? false:try selectedPixelFlag("constrain"),backgroundColor:color)
    do{_ = try value.offset()}catch{throw AutomationFailure(status:400,message:error.localizedDescription)};return value
  }
}
@MainActor extension EditorStore {
  var selectedPixelMoveState:[String:Any] {let draft=transformDraft?.movingPixels == true ? transformDraft:nil,background=activeLayer?.isBackground == true,color=draft?.selectedPixelsBackgroundColor ?? (background ? backgroundColor:nil)
    return ["available":canBeginSelectedPixelMove,"active":draft != nil,"copy":draft?.copySelectedPixels ?? false,"dx":draft?.moveOffsetX ?? 0,"dy":draft?.moveOffsetY ?? 0,"previewBusy":draft != nil && (selectionTransform.map{$0.loading || $0.previewBusy} ?? false),"committing":draft != nil && (selectionTransform?.committing ?? false),"error":draft == nil ? NSNull():selectionTransform?.error as Any? ?? NSNull(),"background":background,"backgroundColor":color.map{[$0.r,$0.g,$0.b,$0.a]} as Any? ?? NSNull()]
  }
}
