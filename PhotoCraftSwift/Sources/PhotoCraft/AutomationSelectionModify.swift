import Foundation
import PhotoCraftCore

enum SelectionModifyAPI {
  static let commands=["selection.modify","selection.reselect"]
  static func schema(_ key:String)->[String:Any] {switch key {
    case "operation":BrushAPI.enumeration(SelectionModification.Kind.allCases.map(\.rawValue))
    case "amount":BrushAPI.number(1,200,integer:true)
    default:BrushAPI.flag
  }}
  static var stateSchema:[String:Any] {let fields:[String:Any]=["available":BrushAPI.flag,"reselectAvailable":BrushAPI.flag,"previousSelectionRetained":BrushAPI.flag,"workspaceOpen":BrushAPI.flag,"busy":BrushAPI.flag,"error":["anyOf":[["type":"null"],["type":"string"]]]];return BrushAPI.object(fields,required:Array(fields.keys).sorted())}
  static var resultSchema:[String:Any] {["type":"object","required":["revision","selectionModify"],"properties":["revision":["type":"string"],"selectionModify":stateSchema]]}
  static var capabilities:[String:Any] {[
    "commands":commands,"operationSchema":schema("operation"),"amountSchema":schema("amount"),"stateSchema":stateSchema,"resultSchema":resultSchema,
    "limits":"Border1–200 pixels; Smooth/Expand/Contract1–100. Amount is an integer. No additional document-dimension or dense coverage admission cap; tiled halo buffers. Existing API shared-document/request limits remain.",
    "algorithm":"Independent GRAY8 disc extrema/median. Binary Smooth is strict disc-majority; gray median retains coverage ranks. Border subtracts contraction from expansion at half the requested width, interpolating odd widths symmetrically. Exact Photoshop kernel/gray/antialias/default behavior unqualified.",
    "bounds":"atCanvasBounds=false clamps samples to the canvas edge; true uses zero outside the canvas. This parameter is explicit; complete Photoshop dialog/default/edge behavior remains a qualification gate.",
    "recall":"Reselect restores the last deselected selection in this open document. Available with no current selection; retains original rectangle or coverage without copying the full plane on the main actor. Document identity/size/read/close changes clear recall. Recall is session state, not a new native archive field.",
    "history":"One named native transaction per accepted edit; source pixels/channels/profile/depth unchanged. Actions records explicit final coverage in the existing selection format. Cancel/invalid/busy/stale/revoked work commits nothing.",
    "targets":"Document selection coverage only, including channel/component/mask/color-mode editing contexts; targeted pixels/plates are never edited. The shared prepared transaction uses a strict selection-only command allow-list.",
    "cursor":"Dialog commands create no new canvas tool or modifier action; existing cursor policies remain unchanged.",
    "adobe":"No dedicated published Modify/Reselect endpoint. Unverified semantic actionJSON descriptors remain unsupported; native coverage Actions is a distinct interface."
  ]}
}
extension AutomationCommand {
  func selectionModification()throws->SelectionModification {
    guard let kind=SelectionModification.Kind(rawValue:try string("operation")) else {throw AutomationFailure(status:400,message:"Unknown selection modification.")}
    let amount=try number("amount",range:1...Double(kind.maximum));guard amount.rounded()==amount else {throw AutomationFailure(status:400,message:"Selection amount must be an integer.")}
    return try .init(kind,amount:Int(amount),atCanvasBounds:adjustmentBrushFlag("atCanvasBounds",false))
  }
}
@MainActor extension EditorStore {
  var selectionModifyState:[String:Any] {[
    "available":canModifySelection,"reselectAvailable":canReselect,"previousSelectionRetained":selectionRecall != nil,"workspaceOpen":selectionModifyDraft != nil,"busy":selectionModifyDraft?.busy ?? false,"error":selectionModifyDraft?.error as Any? ?? NSNull()
  ]}
}
