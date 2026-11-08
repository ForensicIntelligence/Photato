import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ClipboardPlaneAPI {
  static var targetSchema:[String:Any] {
    ["oneOf":[BrushAPI.object(["kind":["const":"quickMask"]],required:["kind"]),BrushAPI.object(["kind":["enum":["alpha"],"type":"string"],"channelID":["type":"string","format":"uuid"]],required:["kind","channelID"]),BrushAPI.object(["kind":BrushAPI.enumeration(["layerMask","smartFilterMask"]),"layerID":["type":"string","format":"uuid"]],required:["kind","layerID"])]]
  }
  static func json(_ target:ClipboardPlaneTarget)->[String:Any] {switch target{case .quickMask:["kind":"quickMask"];case .alpha(let id):["kind":"alpha","channelID":id.uuidString];case .layerMask(let id):["kind":"layerMask","layerID":id.uuidString];case .smartFilterMask(let id):["kind":"smartFilterMask","layerID":id.uuidString]}}
  static func target(_ command:AutomationCommand)throws->ClipboardPlaneTarget {
    guard let raw=command.parameters["target"]else{throw AutomationFailure(status:400,message:"Supply an explicit channel/mask target.")}
    _ = try BrushAPI.merge(raw,schema:targetSchema,path:"target")
    guard case .object(let fields)=raw,case .string(let kind)=fields["kind"]else{throw AutomationFailure(status:400,message:"Invalid clipboard target.")}
    if kind=="quickMask"{return .quickMask}
    let key=kind=="alpha" ? "channelID":"layerID"
    guard case .string(let text)=fields[key],let id=UUID(uuidString:text)else{throw AutomationFailure(status:400,message:"Supply the target UUID.")}
    switch kind{case "alpha":return .alpha(id);case "layerMask":return .layerMask(id);case "smartFilterMask":return .smartFilterMask(id);default:throw AutomationFailure(status:400,message:"Unsupported clipboard plane.")}
  }
  @MainActor static func state(_ store:EditorStore)->[String:Any] {
    let target=store.clipboardPlaneTarget
    return ["target":target.map{json($0)}as Any? ?? NSNull(),"copyAvailable":target.map{store.canUseClipboardPlane($0)} ?? false,"writeAvailable":target.map{store.canUseClipboardPlane($0,writing:true)} ?? false,"operationID":store.clipboardPlaneOperationID?.uuidString as Any? ?? NSNull(),"systemClipboardAccess":false]
  }
  static var stateSchema:[String:Any]{BrushAPI.object(["target":["anyOf":[["type":"null"],targetSchema]],"copyAvailable":BrushAPI.flag,"writeAvailable":BrushAPI.flag,"operationID":["type":["string","null"]],"systemClipboardAccess":["const":false]],required:["target","copyAvailable","writeAvailable","operationID","systemClipboardAccess"])}
  static var capabilities:[String:Any]{["commands":["clipboard.copy","clipboard.cut","clipboard.paste"],"targetSchema":targetSchema,"stateSchema":stateSchema,"state":"clipboard.targetedPlane","native":"Existing Copy/Cut/Paste/Paste In Place menu and factory shortcuts follow the selected alpha/Quick Mask/layer/filter mask. Existing composite and Place Embedded/Linked admission unchanged; unsupported paths/components/Into/Outside remain explicit.","transport":"Existing grayscale native88 component planes/opacity in clipboard envelope1; envelopes1–2 remain. No Mac clipboard access through the API. Native private payload retains raw numeric gray independently of its RGB/TIFF/PNG display fallback.","numeric":"Plane-to-plane gray bypasses color management and keeps raw component precision. Other pixel/layer sources use existing native color conversion to the captured working Gray profile. Selection opacity blends numeric values; mask geometry/outside/properties and unrelated content are retained. Exact Photoshop profile/alpha/rounding/selection/placement behavior remains unqualified.","history":"Copy read-only; successful clipboard publication precedes native Cut. Cut/Paste one prepared source-checked Undo each; stale/cancelled/locked/hidden Quick Mask changes reject. Paste selects its covered destination area. Native/API share Core transaction and conversion. Recorded targeted clipboard steps are explicitly unsupported; no portable replay claim.","API":"target requires explicit existing channel/layer identity; layerIDs/merged/backgroundColor are incompatible. Targeted Cut optionally accepts backgroundValue0...1. Targeted Paste accepts centered/inPlace, center and payload; colorDecision is not a numeric-plane override. New Document accepts grayscale payloads independently of the current editing target, retaining transfer permission.","limits":"Existing512MiB native clipboard/2MiB API payload and4MP decoded API limits remain gaps, not Photoshop limits. Sparse scalar projection/storage retain300000document dimensions; complex/large workloads and physical60fps/platform qualification remain open.","Adobe":"No new dedicated Photoshopv2HTTP endpoint or actionJSON descriptor is claimed. Original D04 scope remains open."]}
}
extension AutomationService {
  func executeClipboardPlane(_ command:AutomationCommand,document:CraftNSDocument,share:Share)async throws->AutomationResponse {
    let target=try ClipboardPlaneAPI.target(command),store=document.store
    let copying=command.name=="clipboard.copy",cut=command.name=="clipboard.cut",pasting=command.name=="clipboard.paste"
    guard copying || cut || pasting else{throw AutomationFailure(status:400,message:"This command does not accept a scalar target.")}
    guard command.parameters["layerIDs"]==nil,command.parameters["merged"]==nil,command.parameters["backgroundColor"]==nil,command.parameters["colorDecision"]==nil else{throw AutomationFailure(status:400,message:"Targeted clipboard uses a plane target and numeric values, without layer/merged/RGB/color-policy overrides.")}
    guard ClipboardPlane.available(store.document,target:target,writing:!copying),copying || target != .quickMask || store.isQuickMaskVisible else{throw AutomationFailure(status:422,message:"The target channel/mask is missing, locked or hidden.")}
    let original=store.document,context=store.clipboardPlaneContext,settings=controller.colorSettings.value,epoch=generation,expectedToken=token,id=UUID()
    let background=try command.parameters["backgroundValue"].map{_ in Float(try command.number("backgroundValue",range:0...1))} ?? ClipboardPlaneIO.gray(store.backgroundColor)
    let payload=try pasting ? command.clipboardBytes():nil
    let options=try pasting ? command.clipboardPasteOptions():(.centered,nil)
    guard !pasting || options.0 == .centered || options.0 == .inPlace else{throw AutomationFailure(status:422,message:"Use Paste or Paste In Place for a channel/mask target.")}
    store.clipboardPlaneOperationID=id;store.geometryBusy=true
    defer{if store.clipboardPlaneOperationID==id{store.clipboardPlaneOperationID=nil;store.geometryBusy=false;store.geometryTask=nil}}
    let worker=Task.detached(priority:.userInitiated){()->(ClipboardContent?,Data?,PreparedEdit?)in
      if let payload {
        let content=try ClipboardAPI.decode(payload),image=try ClipboardPlaneIO.image(content,depth:original.depth,settings:settings)
        return(nil,nil,try PreparedEdit(clipboardPlane:ClipboardPlane.paste(image,into:original,target:target,placement:options.0,center:options.1)))
      }
      let profile=try settings.profile(.grayscale,depth:original.depth),content=try ClipboardPlane.copy(original,target:target,grayProfile:profile)
      try ClipboardAPI.validate(content);let bytes=try content.encoded()
      guard bytes.count<=ClipboardAPI.maximumBytes else{throw AutomationFailure(status:413,message:"Clipboard payload exceeds2MiB; nothing was cut.")}
      return(content,bytes,try cut ? PreparedEdit(clipboardPlane:ClipboardPlane.cut(original,target:target,background:background)):nil)
    }
    store.geometryTask=Task{await withTaskCancellationHandler{_ = try? await worker.value}onCancel:{worker.cancel()}}
    let (content,bytes,prepared)=try await withTaskCancellationHandler{try await worker.value}onCancel:{worker.cancel()}
    try Task.checkCancellation();prune()
    guard isRunning,token==expectedToken,generation==epoch,shares.contains(where:{$0.id==share.id && $0.document === document}),revision(store)==command.revision,store.document==original,store.clipboardPlaneContext==context,store.geometryTask?.isCancelled != true,store.clipboardPlaneOperationID==id else{throw AutomationFailure(status:409,message:"Clipboard target/source changed, operation cancelled or sharing ended.")}
    // Recheck desktop modal admission without treating this operation's own busy flag as another edit.
    store.geometryBusy=false;try preflight(document);store.geometryBusy=true
    if let prepared{try store.commitClipboardPlane(prepared);store.render()}
    else if store.session.actionRecording != nil{store.session.recordActionOperation(.unsupported("Copy mask/channel is not yet recordable."),name:"Copy");store.actionRevision += 1}
    store.clipboardPlaneOperationID=nil;store.geometryBusy=false;store.geometryTask=nil
    if let content,let bytes {
      var result:[String:Any]=["payloadBase64":bytes.base64EncodedString(),"sourceMode":content.document.colorMode.rawValue,"kind":content.kind.rawValue,"width":content.bounds.width,"height":content.bounds.height,"revision":revision(store)]
      if cut{result["document"]=state(share,document:document)}
      return .json(result)
    }
    return .json(state(share,document:document))
  }
}
