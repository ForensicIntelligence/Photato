import Foundation
import PhotoCraftCore

enum LayerLinksAPI {
  static let linkCommand="layer.links",moveCommand="layers.move"
  static var commands:[String]{[linkCommand,moveCommand]}
  static var uuid:[String:Any]{["type":"string","format":"uuid"]}
  static var ids:[String:Any]{["type":"array","items":uuid,"uniqueItems":true,"maxItems":LayerLimits.maximumLayers]}
  static func schema(_ key:String)->[String:Any]{switch key{case "operation":return BrushAPI.enumeration(["link","unlink","enable","disable","select"]);case "layerIDs":return LayerCollectionTransformAPI.schema(key);case "copy":return BrushAPI.flag;default:return ["type":"integer","minimum":-1_000_000,"maximum":1_000_000]}}
  static var stateSchema:[String:Any]{BrushAPI.object(["groups":["type":"array","maxItems":LayerLimits.maximumLayers,"items":BrushAPI.object(["id":uuid,"layerIDs":ids,"disabledLayerIDs":ids],required:["id","layerIDs","disabledLayerIDs"])],"selection":ids,"effectiveMoveLayerIDs":ids,"canToggle":BrushAPI.flag,"toggleOperation":BrushAPI.enumeration(["link","unlink"]),"canSelectLinked":BrushAPI.flag,"canMove":BrushAPI.flag],required:["groups","selection","effectiveMoveLayerIDs","canToggle","toggleOperation","canSelectLinked","canMove"])}
  static var moveResultSchema:[String:Any]{var schema=BrushAPI.object(["revision":["type":"string"],"createdLayerIDs":ids,"movedLayerIDs":ids],required:["revision","createdLayerIDs","movedLayerIDs"]);schema["additionalProperties"]=true;return schema}
  static var capabilities:[String:Any]{[
    "commands":commands,"stateSchema":stateSchema,"moveResultSchema":moveResultSchema,"linkResultSchema":["type":"object","required":["revision","layerLinks"],"properties":["revision":["type":"string"],"layerLinks":stateSchema]],
    "linking":"Persistent links join regular layers/groups without merging or flattening. link merges existing relationships; unlink removes requested members and prunes singletons; enable/disable temporarily changes participation. Select includes disabled partners without history/dirty changes. Background requires conversion before linking.",
    "motion":"Enabled peers and group descendants expand transitively once. Native Move/V, arrows/Shift10px, numeric positions and layers.move/layer.move share exact translations without resampling; Option-drag copies with independent internal copy links. Coalesced1024-side proxy, immutable original and one Undo. Option copy is captured at pointer-down; Shift constrains dynamically and Command suppresses guide snap.",
    "transforms":"Free Transform and legacy whole-layer transforms expand links and descendants once; linked position locks fail atomically. Selection/mask/channel targets keep their distinct semantics. Native expanded/raw targets are captured and rechecked at commit. General whole-layer Move does not perform the selected-pixel move operation.",
    "storage":"Linked layer fields require native84, including retained Timeline sources; older feature minima/readers retained. Link metadata Actions39 and common Move/copy Actions40 retain portable targets; generic discovery advertises1–\(ActionLibraryFile.maximumVersion).",
    "copies":"New copied layers get independent link groups only among at least two copied members; single copied members are unlinked. Removing layers prunes singleton relationships. Original data/Smart source sharing/hierarchy/masks/styles/profiles remain editable.",
    "photoshop":"PSD/PSB resources1026/1072 use physical layer-record order including group dividers. Existing numeric IDs, names and padding are reused where valid; edited payloads regenerate. Nonzero divider link IDs are explicitly unsupported pending qualification. Flat serializers omit layer-index resources.",
    "adobe":"Pinned published v2 has no dedicated persistent-link operation or descriptor conformance evidence; none is invented. Existing resource jobs carry supported PSD/PSB link metadata through the common serializer. Per-layer server resource positioning keeps its contract; native link/Action semantics do not claim complete Adobe job equivalence.",
    "limits":"Copy/move on selected pixels, mask/channel/component targets, unsupported fill/artboard/native-mode/temporal presentations, every layout/reorder/merge/link-copy interaction, Transform Again and complete PSD/Photoshop/live/platform/dense/physical60fps fidelity remain open. Existing document/scratch/API layer and byte budgets apply; no new megapixel cap."
  ]}
}
extension AutomationCommand {
  func linkLayerIDs()throws->[UUID]{guard case .array(let raw)=parameters["layerIDs"],(1...LayerLimits.maximumLayers).contains(raw.count) else{throw AutomationFailure(status:400,message:"Supply1–8,000distinct layer IDs.")};let ids=try raw.map{value->UUID in guard case .string(let text)=value,let id=UUID(uuidString:text) else{throw AutomationFailure(status:400,message:"Invalid layer UUID.")};return id};guard Set(ids).count==ids.count else{throw AutomationFailure(status:400,message:"Duplicate layer UUID.")};return ids}
  func layerLinkCommand()throws->LayerLinkCommand{let ids=try linkLayerIDs();switch try string("operation"){case "link":return .link(ids);case "unlink":return .unlink(ids);case "enable":return .enabled(ids,true);case "disable":return .enabled(ids,false);default:throw AutomationFailure(status:400,message:"Select is a view operation.")}}
  func wholeLayerMoveOptions()throws->LayerMoveRequest{.init(layerIDs:try linkLayerIDs(),dx:try integer("dx",range:-1_000_000...1_000_000),dy:try integer("dy",range:-1_000_000...1_000_000),copy:try pathFlag("copy",false))}
}
@MainActor extension EditorStore {
  var layerLinkState:[String:Any]{
    var seen=Set<UUID>(),groups:[[String:Any]]=[]
    for layer in document.layers{if let group=layer.linkID,seen.insert(group).inserted{let members=document.layers.filter{$0.linkID==group};if members.count<2{continue};groups.append(["id":group.uuidString,"layerIDs":members.map{$0.id.uuidString},"disabledLayerIDs":members.filter{$0.linkDisabled == true}.map{$0.id.uuidString}])}}
    return ["groups":groups,"selection":linkTargets().map(\.uuidString),"effectiveMoveLayerIDs":wholeLayerMoveIDs.map(\.uuidString),"canToggle":canToggleLayerLinks(),"toggleOperation":linkMenuUnlinks(linkTargets()) ? "unlink":"link","canSelectLinked":canSelectLinkedLayers(),"canMove":canBeginWholeLayerMove()]
  }
}
