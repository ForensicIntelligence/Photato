import Foundation
import PhotoCraftCore

struct APIKeyframeClipboard {
  let id=UUID()
  let value:VideoKeyframeClipboard
  let session:UUID
  let transferGrant:UUID
  let shareID:UUID
  let lifecycle:UUID
}

enum VideoKeyframeSelectionAPI {
  static let operations=["select","selectAll","deselectAll","copy","paste","deleteSelected","moveSelected","duplicateSelected","interpolateSelected"]
  static var referencesSchema: [String:Any] { ["type":"array","maxItems":65536,"uniqueItems":true,"items":BrushAPI.object(["layerID":VariablesAPI.uuid,"keyframeID":VariablesAPI.uuid],required:["layerID","keyframeID"])] }
  static var clipboardSchema: [String:Any] { ["anyOf":[["type":"null"],BrushAPI.object(["count":["type":"integer","minimum":1,"maximum":65536],"layers":["type":"integer","minimum":1,"maximum":LayerLimits.maximumLayers],"origin":["type":"number"]],required:["count","layers","origin"])]] }
  static func clipboardState(_ value:VideoKeyframeClipboard?)->Any {
    guard let value else{return NSNull()}
    return ["count":value.count,"layers":value.tracks.count,"origin":value.origin] as [String:Any]
  }
  @MainActor static func selectionState(_ store:EditorStore)->[[String:String]] {
    store.validVideoKeyframeSelection.sorted { a,b in a.layerID==b.layerID ? a.keyframeID.uuidString<b.keyframeID.uuidString : a.layerID.uuidString<b.layerID.uuidString }
      .map{["layerID":$0.layerID.uuidString,"keyframeID":$0.keyframeID.uuidString]}
  }
  static var capabilities:[String:Any] {
    ["operations":operations,"selection":"video.keyframe select accepts keys=[{layerID,keyframeID}] and optional selectionMode=replace/add/toggle/remove; selectAll optionally scopes layerID/property; deselectAll clears view selection. View selection/copy add no content Undo.",
     "clipboard":"copy captures immutable selected property values and relative times. Native Copy uses an application-local clipboard across documents, without reading/writing the operating-system clipboard. HTTP Copy uses a separate clipboard bound to this actual share, API session, transfer grant and document lifecycle; it never reads the native clipboard. Transfer permission is required for HTTP copy/paste.",
     "paste":"paste uses layerIDs in explicit order (default active layer) and time in Timeline seconds (default playhead). One copied layer can populate several destinations; multiple copied layers require the same number of destinations. The earliest copied key starts at time; relative spacing, values and interpolation persist. Same-property/time keys are replaced. Other keys remain. New keys receive fresh IDs; replaced keys retain destination IDs. Pasted keys become selected.",
     "crossDocument":"Optional sourceDocumentID plus current sourceRevision selects the clipboard of another explicitly shared document; permissions, source share/revision/lifecycle and clipboard identity are rechecked at commit. Copy survives later ordinary source edits; it never survives a revoked share/session/grant/lifecycle.",
     "groupEditing":"deleteSelected, interpolateSelected(interpolation), moveSelected(delta) and duplicateSelected(delta) are atomic native transactions. Move/duplicate collisions reject the entire operation. Locks/property compatibility/metadata and timing budgets remain enforced. Native Move/Duplicate controls use explicit seconds; no unverified drag/shortcut binding is added.",
     "limits":"Full SP01 remains open. Colour/content paste requires matching depth and working profile; automatic cross-profile conversion, system/external clipboard interchange, Photoshop multi-layer mapping/default/collision qualification, marquee/graphical group retiming and portable Actions/Adobe animation descriptors remain open. No dedicated Firefly v2 keyframe endpoint is invented."]
  }
}

extension AutomationCommand {
  func selectedVideoKeyReferences()throws->Set<VideoKeyframeReference> {
    guard case .array(let values)=parameters["keys"],values.count<=65536 else{throw AutomationFailure(status:400,message:"Provide keyframe layer/key UUID pairs.")}
    let refs=try values.map { value -> VideoKeyframeReference in
      guard case .object(let fields)=value,Set(fields.keys)==["layerID","keyframeID"],case .string(let layer)=fields["layerID"],case .string(let key)=fields["keyframeID"],let l=UUID(uuidString:layer),let k=UUID(uuidString:key) else{throw AutomationFailure(status:400,message:"Invalid keyframe selection reference.")}
      return .init(layerID:l,keyframeID:k)
    }
    guard Set(refs).count==refs.count else{throw AutomationFailure(status:400,message:"Duplicate keyframe reference.")}
    return Set(refs)
  }
}

extension AutomationService {
  func currentKeyframeClipboard(_ store:EditorStore,shareID:UUID)->APIKeyframeClipboard? {
    guard documentTransfersEnabled,let value=store.apiVideoKeyframeClipboard,value.session==generation,value.transferGrant==documentTransferGeneration,value.shareID==shareID,value.lifecycle==store.layerPanelGeneration else{return nil}
    return value
  }
  func videoState(shareID:UUID,store:EditorStore)->[String:Any] {
    var state=store.videoState
    state["keyframeClipboard"]=VideoKeyframeSelectionAPI.clipboardState(currentKeyframeClipboard(store,shareID:shareID)?.value)
    return state
  }
  func editVideoKeyframeSelection(_ command:AutomationCommand,document:CraftNSDocument,shareID:UUID)async throws {
    let store=document.store,op=try command.string("operation")
    guard store.canUseTimeline,store.document.videoTimeline != nil else{throw AutomationFailure(status:409,message:"Create an idle video Timeline first.")}
    let required:Set<String>,optional:Set<String>
    switch op {
    case "select":required=["keys"];optional=["selectionMode"]
    case "selectAll":required=[];optional=["layerID","property"]
    case "deselectAll","copy","deleteSelected":required=[];optional=[]
    case "moveSelected","duplicateSelected":required=["delta"];optional=[]
    case "interpolateSelected":required=["interpolation"];optional=[]
    case "paste":required=[];optional=["layerIDs","time","sourceDocumentID","sourceRevision"]
    default:throw AutomationFailure(status:400,message:"Unknown keyframe selection operation.")
    }
    let actual=Set(command.parameters.keys).subtracting(["operation"])
    guard required.isSubset(of:actual),actual.isSubset(of:required.union(optional))else{throw AutomationFailure(status:400,message:"Missing or irrelevant keyframe selection parameters.")}
    let selected=store.validVideoKeyframeSelection
    if op=="select" {
      let refs=try command.selectedVideoKeyReferences()
      if !refs.isEmpty {_ = try VideoKeyframeClipboard.capture(refs,in:store.document)}
      let mode=try command.parameters["selectionMode"].map{_ in try command.string("selectionMode")} ?? "replace"
      switch mode {case "replace":store.videoKeyframeSelection=refs;case "add":store.videoKeyframeSelection=selected.union(refs);case "toggle":store.videoKeyframeSelection=selected.symmetricDifference(refs);case "remove":store.videoKeyframeSelection=selected.subtracting(refs);default:throw AutomationFailure(status:400,message:"Choose replace, add, toggle or remove selection.")}
      return
    }
    if op=="selectAll" {
      let layer=try command.parameters["layerID"].map{_ in try command.actionUUID("layerID")}
      guard layer==nil || store.document.layers.contains(where:{$0.id==layer})else{throw AutomationFailure(status:400,message:"Unknown keyframe layer.")}
      let property:VideoProperty?
      if command.parameters["property"] != nil {guard let p=VideoProperty(rawValue:try command.string("property"))else{throw AutomationFailure(status:400,message:"Unknown video property.")};property=p}else{property=nil}
      store.selectAllVideoKeyframes(layerID:layer,property:property);return
    }
    if op=="deselectAll" {store.videoKeyframeSelection=[];return}
    if op=="copy" {
      guard documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Enable document transfers before copying keyframe values.")}
      store.apiVideoKeyframeClipboard=APIKeyframeClipboard(value:try VideoKeyframeClipboard.capture(selected,in:store.document),session:generation,transferGrant:documentTransferGeneration,shareID:shareID,lifecycle:store.layerPanelGeneration);return
    }
    let edit:VideoKeyframeEdit
    switch op {
    case "deleteSelected":edit = .delete(selected)
    case "moveSelected","duplicateSelected":edit = .move(selected,seconds:try command.number("delta",range:-86400...86400),duplicate:op=="duplicateSelected")
    case "interpolateSelected":guard let value=KeyframeInterpolation(rawValue:try command.string("interpolation"))else{throw AutomationFailure(status:400,message:"Choose linear or hold.")};edit = .interpolation(selected,value)
    default:
      guard documentTransfersEnabled else{throw AutomationFailure(status:403,message:"Enable document transfers before pasting keyframe values.")}
      let sourceID=try command.parameters["sourceDocumentID"].map{_ in try command.actionUUID("sourceDocumentID")} ?? shareID
      guard let source=shares.first(where:{$0.id==sourceID})?.document else{throw AutomationFailure(status:404,message:"Shared clipboard source not found.")}
      if sourceID != shareID || command.parameters["sourceRevision"] != nil {
        guard try command.string("sourceRevision")==revision(source.store)else{throw AutomationFailure(status:409,message:"Clipboard source revision changed.")}
      }
      guard let clipboard=currentKeyframeClipboard(source.store,shareID:sourceID)else{throw AutomationFailure(status:409,message:"Copy keyframes in this authorized API session first.")}
      let destinations:[UUID]
      if case .array(let values)=command.parameters["layerIDs"] {
        guard !values.isEmpty,values.count<=LayerLimits.maximumLayers else{throw AutomationFailure(status:400,message:"Choose destination layer UUIDs.")}
        destinations=try values.map{guard case .string(let raw)=$0,let id=UUID(uuidString:raw)else{throw AutomationFailure(status:400,message:"Invalid destination layer UUID.")};return id}
      }else if command.parameters["layerIDs"] != nil {throw AutomationFailure(status:400,message:"layerIDs must be an array.")}
      else{destinations=store.document.activeLayerID.map{[$0]} ?? []}
      let time=try command.parameters["time"].map{_ in try command.number("time",range:0...86400)} ?? store.document.videoTimeline!.seconds
      let sourceRevision=revision(source.store)
      edit = .paste(clipboard.value,layers:destinations,time:time)
      try await executePreparedOperation(document:document,shareID:shareID,revision:command.revision,validateCommit:{
        guard self.shares.contains(where:{$0.id==sourceID && $0.document===source}),self.revision(source.store)==sourceRevision,self.currentKeyframeClipboard(source.store,shareID:sourceID)?.id==clipboard.id else{throw AutomationFailure(status:409,message:"Clipboard authorization or source changed during preparation.")}
      }){_ in .video(.keyframes(edit))}
      store.selectPastedVideoKeyframes(clipboard.value,layers:destinations,time:time);return
    }
    let before=Set(store.document.layers.flatMap{($0.videoKeyframes ?? []).map(\.id)})
    try await executePreparedOperation(document:document,shareID:shareID,revision:command.revision){_ in .video(.keyframes(edit))}
    if op=="duplicateSelected" {store.videoKeyframeSelection=Set(store.document.layers.flatMap{layer in (layer.videoKeyframes ?? []).filter{!before.contains($0.id)}.map{VideoKeyframeReference(layerID:layer.id,keyframeID:$0.id)}})}
    else{store.videoKeyframeSelection=store.validVideoKeyframeSelection}
  }
}
