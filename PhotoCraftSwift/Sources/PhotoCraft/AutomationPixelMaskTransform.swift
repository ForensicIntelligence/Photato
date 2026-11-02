import Foundation
import PhotoCraftCore

enum PixelMaskTransformAPI {
  static let name="mask.transform"
  static func schema(_ key:String)->[String:Any]{SelectedPixelTransformAPI.schema(key)}
  static var stateSchema:[String:Any]{SelectionTransformAPI.stateSchema}
  static var resultSchema:[String:Any]{["type":"object","required":["revision","pixelMaskTransform"],"properties":["revision":["type":"string"],"pixelMaskTransform":stateSchema]]}
  static var capabilities:[String:Any]{[
    "command":name,"stateSchema":stateSchema,"resultSchema":resultSchema,"matrixSchema":schema("matrix"),
    "native":"Select an unlinked pixel-mask thumbnail with no pixel selection, then Command-T or Edit/Transform modes/fixed rotations/flips. Shared six modes, numeric controls, nine reference positions and captured modifier cursors. Return applies one Free Transform transaction; Escape/tool/focus/read/close cancel.",
    "sampling":"Row-major nine-coefficient matrix maps document coordinates. Immutable raw grayscale samples with independent mask exterior; Nearest Neighbor/Bilinear/Bicubic(default). No color/gamma conversion; source mask depth retained. Density/feather/inversion/enabled/link and layer pixels/geometry/content/profile are preserved. A new mask rectangle/placement retains off-canvas transformed coverage.",
    "preview":"Bounded1024-side coalesced off-main composition, including mask gray/overlay views. No source/history edits while adjusting. Final output uses original samples; cancel/stale/revoke/busy guards. No new8MP/36MP admission cap. Sparse300000-side coverage is tested separately from practical maximum dense editing.",
    "history":"Native83 unchanged. Portable semantic mask-transform Actions require35; older operations retain their prior minimum versions. Desktop/API share engine/Undo/Redo/state and target preservation.",
    "adobe":"No dedicated projective mask Free Transform route is present in the pinned published v2 contract. Pixel-mask source/offset/link resource operations are distinct; no route or unverified actionJSON is invented. Those contract gaps remain tracked independently.",
    "limits":"One unlocked unlinked whole pixel mask, static document, no selection. Selected mask regions, linked-mask combined transforms, filter/vector masks and channel/component transforms remain separate work. Exact Photoshop bytes/defaults/edge/kernel/mask bounds/live UI, supported platforms, full-current suite, maximum dense capacity and physical60fps remain unqualified."
  ]}
}
extension AutomationCommand {
  func pixelMaskTransformOptions()throws->PixelMaskTransformRequest{
    guard let id=UUID(uuidString:try string("layerID")) else{throw AutomationFailure(status:400,message:"Invalid layerID.")}
    let(matrix,method)=try selectionTransformOptions();return .init(layerID:id,matrix:matrix,interpolation:method)
  }
}
@MainActor extension EditorStore {
  var pixelMaskTransformState:[String:Any]{selectionTransformState.merging(["target":"pixelMask","available":canBeginPixelMaskTransform,"active":transformDraft?.pixelMask == true]){_,b in b}}
}
