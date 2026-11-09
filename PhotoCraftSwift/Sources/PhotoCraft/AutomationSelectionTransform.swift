import Foundation
import PhotoCraftCore

enum SelectionTransformAPI {
  static func schema(_ key:String)->[String:Any] {switch key {
    case "matrix":["type":"array","minItems":9,"maxItems":9,"items":BrushAPI.number(-1e12,1e12)]
    default:BrushAPI.enumeration(Resampling.allCases.map(\.rawValue))
  }}
  static var stateSchema:[String:Any] {let fields:[String:Any]=["target":BrushAPI.enumeration(["boundary","pixels","pixelMask","channel","layers"]),"available":BrushAPI.flag,"active":BrushAPI.flag,"previewBusy":BrushAPI.flag,"committing":BrushAPI.flag,"mode":BrushAPI.enumeration(SelectionTransformMode.allCases.map(\.rawValue)),"reference":BrushAPI.enumeration(CanvasAnchor.allCases.map(\.rawValue)),"matrix":["anyOf":[["type":"null"],schema("matrix")]],"interpolation":schema("interpolation"),"error":["anyOf":[["type":"null"],["type":"string"]]]];return BrushAPI.object(fields,required:Array(fields.keys).sorted())}
  static var resultSchema:[String:Any] {["type":"object","required":["revision","selectionTransform"],"properties":["revision":["type":"string"],"selectionTransform":stateSchema]]}
  static var capabilities:[String:Any] {[
    "command":"selection.transform","matrixSchema":schema("matrix"),"stateSchema":stateSchema,"resultSchema":resultSchema,
    "matrix":"Nine row-major homogeneous coefficients mapping original document coordinates to destination coordinates. Nonsingular, finite, within coefficient bounds and without a projective horizon across supported selection/filter support. Output clips to the existing canvas.",
    "interpolation":"Nearest Neighbor, Bilinear or Bicubic (default Bicubic). Numeric GRAY8 samples, zero exterior, no RGB/gamma conversion. Integer grid permutations preserve raw coverage exactly. Exact Photoshop interpolation/gray/aliasing unqualified.",
    "native":"Scale/rotation/move/flips, skew/distort/perspective, six transform modes, numeric X/Y/W/H/angle, nine reference positions, proportional/Shift/Option controls, arrow/Shift-arrow nudges, contextual menus and captured modifier cursors. Selection Warp unavailable. Contour preview coalesces off-main without per-pointer image recomposition; final coverage is sampled once from the immutable source.",
    "directBorderInteraction":"With New Selection active, plain drag inside a marquee/lasso/wand selection moves only its boundary, with a translated contour preview and one selection.transform-equivalent nearest-grid commit. Shift during drag constrains to45degrees. Arrow keys move1pixel; Shift-arrow10, with queued repeated input. Replacement drafts hide the old outline immediately; Escape restores it. Native integer moves preserve coverage bytes and all image content. Existing transform clipping and off-canvas limits remain.",
    "history":"One Transform Selection Undo transaction with native coverage Actions, original pixels/layers/masks/channels/profile/depth and editing target preserved. Cancel/read/close/stale/revoked work commits nothing; no new native/Actions version.",
    "limits":"No extra8MP/36MP or side admission limit; sparse support/tiled output and bounded scratch patches. Existing API document/request limits apply. Coordinates retain existing±1000000 guard; coefficients±1e12. Preview contour uses bounded analysis; physical60fps/dense maximum capacity/full runtime/native/default parity remain open.",
    "adobe":"No dedicated published border-transform route. Unverified semantic actionJSON descriptors stay unsupported; no invented endpoint. Native explicit coverage Actions remains distinct."
  ]}
}
extension AutomationCommand {
  func selectionTransformOptions()throws->(ProjectiveTransform,Resampling) {
    guard let value=parameters["matrix"] else {throw AutomationFailure(status:400,message:"Transform Selection requires a matrix.")}
    do {
      let raw=try BrushAPI.merge(value,schema:SelectionTransformAPI.schema("matrix"),path:"matrix") as! [Double]
      let matrix=try ProjectiveTransform(raw),interpolation:Resampling
      if parameters["interpolation"]==nil{interpolation = .bicubic}else{guard let method=Resampling(rawValue:try string("interpolation")) else{throw CraftError.invalid("Unknown selection interpolation.")};interpolation=method}
      return (matrix,interpolation)
    }catch let failure as AutomationFailure{throw failure}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
}
@MainActor extension EditorStore {
  var selectionTransformState:[String:Any] {
    let draft=transformDraft?.selection == true ? transformDraft:nil
    return ["target":draft?.collectionLayerIDs != nil ? "layers":draft?.channelTarget != nil ? "channel":draft?.pixelMask == true ? "pixelMask":draft?.selectedPixels == true ? "pixels":"boundary","available":canBeginSelectionTransform,"active":draft != nil,"previewBusy":selectionTransform.map{$0.loading || $0.previewBusy} ?? false,"committing":selectionTransform?.committing ?? false,"mode":draft?.selectionMode.rawValue ?? SelectionTransformMode.free.rawValue,"reference":draft?.referenceAnchor.rawValue ?? "center","matrix":(try? draft?.selectionProjection.values) as Any? ?? NSNull(),"interpolation":draft?.interpolation.rawValue ?? Resampling.bicubic.rawValue,"error":selectionTransform?.error as Any? ?? NSNull()]
  }
}
