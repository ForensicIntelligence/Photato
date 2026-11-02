import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum CanvasEdgesAPI {
  static let commands=["document.trim","document.revealAll"]
  static func schema(_ key:String)->[String:Any]{
    if key=="basis"{return ["type":"string","enum":TrimOptions.Basis.allCases.map(\.rawValue),"default":"topLeft"]}
    if key=="backgroundColor"{return ["type":"array","minItems":3,"maxItems":3,"items":["type":"number","minimum":0,"maximum":1]]}
    return ["type":"boolean","default":true]
  }
  static var stateSchema:[String:Any]{BrushAPI.object(["trimAvailable":BrushAPI.flag,"revealAllAvailable":BrushAPI.flag,"trimDialogOpen":BrushAPI.flag,"trimReason":["type":["string","null"]],"revealAllReason":["type":["string","null"]]],required:["trimAvailable","revealAllAvailable","trimDialogOpen","trimReason","revealAllReason"])}
  static var capabilities:[String:Any]{["commands":commands,"stateSchema":stateSchema,"result":"Updated shared document state through the existing state schema; one undoable source-bound native transaction. No-op leaves history unchanged.","trim":"basis=topLeft(default),bottomRight,transparent; top/left/bottom/right default true. Uses the full visible RGB composite or exact aligned native component values; ignores current selection for bounds. Crop deletes ordinary outside raster storage and clears current selection; channels, guides and paths follow geometry. Empty result rejects atomically.","revealAll":"Expand current canvas to include retained nontransparent layer content, including hidden leaves. Current canvas is always retained. Layers are translated without resampling; numerical Background planes and existing pixels retain their bits. Captured optional backgroundColor fills newly exposed Background area. Auxiliary state and saved comp positions rebase.","limits":"Temporal rebasing, ink-mode edges, layered native component Trim, advanced effect/mask bounds and full independent Photoshop defaults/output/live/platform/dense/60fps remain open. Existing specialized mode budgets apply; RGB logical canvas allows300000per side. Native semantic Actions44; native84 unchanged.","adobe":"No dedicated Trim/Reveal All route exists in the pinned Firefly contract. Document.trim/revealAll are public desktop UXP methods; they are not Firefly endpoints. Generic actionJSON descriptors still need documented descriptor provenance and conformance; they remain unsupported rather than inventing routes or claiming equivalence."]}
}
extension AutomationCommand {
  func canvasEdgeOperation()throws->CanvasEdgeOperation {
    if name=="document.revealAll"{return .revealAll}
    var options=TrimOptions()
    if parameters["basis"] != nil {guard let basis=TrimOptions.Basis(rawValue:try string("basis")) else{throw AutomationFailure(status:400,message:"Unknown Trim basis.")};options.basis=basis}
    options.top=try pathFlag("top",true);options.left=try pathFlag("left",true);options.bottom=try pathFlag("bottom",true);options.right=try pathFlag("right",true)
    return .trim(options)
  }
}
extension EditorStore {
  var canvasEdgesState:[String:Any]{["trimAvailable":canUseCanvasEdges(.trim(.init())),"revealAllAvailable":canUseCanvasEdges(.revealAll),"trimDialogOpen":trimDraft != nil,"trimReason":CanvasEdgePreparation.unavailableReason(document,operation:.trim(.init())) as Any? ?? NSNull(),"revealAllReason":CanvasEdgePreparation.unavailableReason(document,operation:.revealAll) as Any? ?? NSNull()]}
}
