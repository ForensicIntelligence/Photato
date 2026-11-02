import Foundation
import PhotoCraftCore

enum SelectedPixelTransformAPI {
  static let name="pixels.transform"
  static func schema(_ key:String)->[String:Any] {if key=="copy"{return BrushAPI.flag};if key=="backgroundColor"{return BackgroundLayerAPI.schema(key)};return key=="layerID" ? ["type":"string","format":"uuid"]:SelectionTransformAPI.schema(key)}
  static var stateSchema:[String:Any] {var schema=SelectionTransformAPI.stateSchema,properties=schema["properties"] as! [String:Any],required=schema["required"] as! [String];properties["copy"]=BrushAPI.flag;properties["background"]=BrushAPI.flag;properties["backgroundColor"]=["anyOf":[["type":"null"],Self.schema("backgroundColor")]];required += ["background","backgroundColor","copy"];schema["properties"]=properties;schema["required"]=required;return schema}
  static var resultSchema:[String:Any] {["type":"object","required":["revision","selectedPixelTransform"],"properties":["revision":["type":"string"],"selectedPixelTransform":stateSchema]]}
  static var capabilities:[String:Any] {[
    "command":name,"copy":"Optional copy=true duplicates selected content over the unchanged source using the same native engine; new semantic copy Actions34. Native Move/Option-drag and pixels.move provide translation/copy workflows.","stateSchema":stateSchema,"resultSchema":resultSchema,"matrixSchema":schema("matrix"),
    "native":"Command-T on selected ordinary RGB raster or Background pixels; six shared transform modes, numeric controls, nine reference positions, aspect/Shift/Option controls, captured effective modifier cursors, fixed rotations/flips, Return/Cancel and bounded image previews.",
    "sampling":"Premultiplied selected RGB/alpha from immutable original samples; zero exterior and numeric selection coverage. Nearest/Bilinear/Bicubic, default Bicubic. Source-over onto the cut remainder; Background holes use captured backgroundColor and remain opaque/full-canvas; identity is exact no-op, hard unit-grid copies preserve stored samples when compositing permits. Source encoding/depth/profile retained. Exact Photoshop gray/soft-overlap/kernel behavior remains unqualified.",
    "storage":"Bounded tile regions, retained outside-damage samples and original off-canvas pixels; new transformed off-canvas pixels retained for ordinary layers. Background transformed output clips to its existing full-canvas opaque plane. No new8MP/36MP admission cap. Existing300000-side storage, coordinate guards, scratch and API limits apply. Sparse maximum-dimension tests do not qualify practical maximum dense capacity.",
    "preview":"Off-main coalesced image/contour preview from a source proxy at most1024 pixels per side; original samples used for final commit. Preview error is reported; real document/history remains unchanged until Apply. Physical60fps and exact live UI are unqualified.",
    "history":"One Free Transform transaction, Undo/Redo, source/revision/target guards, cancellation/revocation and native semantic Actions31 for ordinary pixels,33 for captured Background fill and34 for copies (older actions retain their required versions). Native83 unchanged.",
    "limits":"One editable ordinary RGB raster or Background layer, composite pixel target. No component/mask/Smart Object, Warp, multi-layer selected-pixel, animation or video branch yet. Background identity is explicit, never inferred from a name. backgroundColor accepts optional opaque RGBA; omitted native/API color captures the current background swatch.",
    "adobe":"No dedicated selected-pixel route in the published v2 contract; unverified actionJSON descriptors remain unsupported. Existing layer.transform keeps whole-layer semantics."
  ]}
}
extension AutomationCommand {
  func selectedPixelTransformOptions()throws->SelectedPixelTransformRequest {
    guard let id=UUID(uuidString:try string("layerID")) else{throw AutomationFailure(status:400,message:"Invalid layerID.")}
    let (matrix,interpolation)=try selectionTransformOptions()
    let color=parameters["backgroundColor"]==nil ? nil:try backgroundColor(default:.white)
    return .init(layerID:id,matrix:matrix,interpolation:interpolation,backgroundColor:color,copy:parameters["copy"]==nil ? nil:try selectedPixelFlag("copy"))
  }
}
@MainActor extension EditorStore {
  var selectedPixelTransformState:[String:Any] {
    let background=activeLayer?.isBackground == true,color=transformDraft?.selectedPixelsBackgroundColor ?? (background ? backgroundColor:nil)
    return selectionTransformState.merging(["available":canBeginSelectedPixelTransform,"active":transformDraft?.selectedPixels == true && transformDraft?.pixelMask != true && transformDraft?.channelTarget==nil && transformDraft?.collectionLayerIDs==nil,"target":"pixels","copy":transformDraft?.copySelectedPixels ?? false,"background":background,"backgroundColor":color.map{[$0.r,$0.g,$0.b,$0.a]} as Any? ?? NSNull()]){_,b in b}
  }
}
