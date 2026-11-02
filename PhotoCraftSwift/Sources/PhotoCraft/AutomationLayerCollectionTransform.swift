import Foundation
import PhotoCraftCore

enum LayerCollectionTransformAPI{
  static let name="layers.transform"
  static func schema(_ key:String)->[String:Any]{key=="layerIDs" ? ["type":"array","minItems":1,"maxItems":LayerLimits.maximumLayers,"uniqueItems":true,"items":["type":"string","format":"uuid"]]:SelectionTransformAPI.schema(key)}
  static var stateSchema:[String:Any]{var result=SelectionTransformAPI.stateSchema,properties=result["properties"] as! [String:Any],required=result["required"] as! [String];properties["layerIDs"]=["type":"array","items":["type":"string","format":"uuid"]];properties["rootIDs"]=properties["layerIDs"];properties["affineOnly"]=BrushAPI.flag;properties["supportedModes"]=["type":"array","maxItems":6,"items":BrushAPI.enumeration(["Free Transform","Scale","Rotate","Skew","Distort","Perspective"])];required += ["layerIDs","rootIDs","affineOnly","supportedModes"];result["properties"]=properties;result["required"]=required;return result}
  static var capabilities:[String:Any]{[
    "command":name,"stateSchema":stateSchema,"resultSchema":["type":"object","required":["revision","layerCollectionTransform"],"properties":["revision":["type":"string"],"layerCollectionTransform":stateSchema]],
    "native":"Select multiple whole layers or a group and use Command-T. A shared bounding box/reference/numeric controls applies translate/scale/rotate/skew/fixed rotations/flips once to each descendant. Coalesced1024-side document proxy, original samples on Apply, one Undo. Return applies; Escape/tool/focus/read/close cancel. Ordinary RGB pixels, resolved Smart Objects and their groups also use Distort/Perspective and captured Command/Command-Option-Shift modifier modes; unsupported target modes show unavailable feedback.",
    "matrix":"Nine row-major document-coordinate coefficients; affine or projective; finite nonsingular placement without a horizon across the shared source bounding rectangle. Affine calls retain the existing exact path. Interpolation defaults Bicubic. Enabled linked partners and descendants expand transitively; parent+child targets normalize to root subtrees, with each member transformed once from the immutable source. Retain hierarchy/order/IDs/active selection, editable type/shapes/Smart Object source bytes, linked/unlinked mask coordinates, style parameters and profiles. No automatic effect scaling. Selection, position locks and unsupported artboard geometry fail atomically.",
    "history":"Semantic affine Actions37 and projective Actions38 retain portable layer references; older operation minimum versions and older native formats retained; linked graphs require native84. Native/API use shared geometry/preparation/history/source/revision/busy/stale/revoke/cancel validation. No additional8MP/36MP admission cap; existing raster/type/Smart/mode/format/resource budgets still apply.",
    "adobe":"Published per-layer resource transform operations share DocumentGeometry. There is no new joint document-coordinate affine-matrix collection route in the pinned contract; no invented route or unverified actionJSON. Existing resource/job and whole-layer operations keep their schemas/lifecycles; complete contract coverage remains open.",
    "limits":"Projective type/shape/fill/vector-mask/artboard/native-mode/temporal targets, unresolved linked caches and Puppet/Perspective Smart Filter controls remain open. Warp/repeat, persistent linked-layer relationships and multi-layer selected-pixel contexts remain open. Ordinary RGB pixel layers join the shared six-mode controls; other single targets retain existing controls. Exact Photoshop bounds/defaults/gestures/pixels/cursors/live/platform/max-dense/full-current-suite/physical60fps acceptance remains unqualified."
  ]}
}
extension AutomationCommand{
  func layerCollectionTransformOptions()throws->LayerCollectionTransformRequest{
    guard case .array(let values)=parameters["layerIDs"],(1...LayerLimits.maximumLayers).contains(values.count) else{throw AutomationFailure(status:400,message:"Supply1to8,000layer IDs.")}
    let ids=try values.map{value->UUID in guard case .string(let text)=value,let id=UUID(uuidString:text) else{throw AutomationFailure(status:400,message:"Invalid layer ID.")};return id};guard Set(ids).count==ids.count else{throw AutomationFailure(status:400,message:"Duplicate layer ID.")}
    let(matrix,method)=try selectionTransformOptions();if let affine=try matrix.affineValue(){return .init(layerIDs:ids,matrix:affine,interpolation:method)};return .init(layerIDs:ids,projection:matrix,interpolation:method)
  }
}
@MainActor extension EditorStore{
  var layerCollectionTransformState:[String:Any]{let draft=transformDraft?.collectionLayerIDs != nil ? transformDraft:nil,ids=draft?.collectionLayerIDs ?? layerCollectionIDs,roots=(try? LayerCollectionTransform.roots(document,layerIDs:ids)) ?? []
    return selectionTransformState.merging(["target":"layers","available":canBeginLayerCollectionTransform,"active":draft != nil,"layerIDs":ids.map(\.uuidString),"rootIDs":roots.map{$0.id.uuidString},"affineOnly":!(draft?.collectionProjective ?? canBeginProjectiveLayerTransform),"supportedModes":SelectionTransformMode.allCases.filter{draft?.supportsSelectionMode($0) ?? (canBeginProjectiveLayerTransform || [.free,.scale,.rotate,.skew].contains($0))}.map(\.rawValue)]){_,b in b}
  }
}
