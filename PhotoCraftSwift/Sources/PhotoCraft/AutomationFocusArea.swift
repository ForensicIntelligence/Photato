import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum FocusAreaAPI {
  static var settingsSchema:[String:Any]{BrushAPI.object(["range":BrushAPI.number(0,10),"noise":BrushAPI.number(0,1),"autoRange":BrushAPI.flag,"autoNoise":BrushAPI.flag,"softenEdge":BrushAPI.flag])}
  static var strokesSchema:[String:Any]{["type":"array","maxItems":1024,"items":BrushAPI.object(["tool":BrushAPI.enumeration(["add","subtract"]),"size":BrushAPI.number(1,5000),"hardness":BrushAPI.number(0,1),"points":["type":"array","minItems":1,"maxItems":4096,"items":["type":"array","minItems":2,"maxItems":2,"items":BrushAPI.number(-1_000_000,1_000_000)]]],required:["points"])]}
  static func schema(_ key:String)->[String:Any]{switch key {
    case "settings":return settingsSchema
    case "strokes":return strokesSchema
    case "output":return BrushAPI.enumeration(SelectionRefinementOutput.allCases.map(\.rawValue))
    case "sampleAllLayers":return BrushAPI.flag
    default:return ["type":"string","format":"uuid"]
  }}
  static var stateSchema:[String:Any]{
    let optional:[String:Any]=["anyOf":[["type":"null"],settingsSchema]]
    let fields:[String:Any]=["available":BrushAPI.flag,"workspaceOpen":BrushAPI.flag,"previewBusy":BrushAPI.flag,"settings":optional,"effectiveSettings":optional,"strokeCount":BrushAPI.number(0,1024,integer:true),"output":schema("output"),"previewError":["anyOf":[["type":"null"],["type":"string"]]]]
    return BrushAPI.object(fields,required:Array(fields.keys).sorted())
  }
  static var resultSchema:[String:Any]{["type":"object","required":["revision","focusArea"],"properties":["revision":["type":"string"],"focusArea":stateSchema]]}
  static var capabilities:[String:Any]{["command":"selection.focus","settingsSchema":settingsSchema,"strokeSchema":strokesSchema,"stateSchema":stateSchema,"resultSchema":resultSchema,"defaults":BrushAPI.json(FocusAreaSettings()),"outputs":SelectionRefinementOutput.allCases.map(\.rawValue),"algorithm":"Native source-derived local Laplacian sharpness, percentile normalization, guided color refinement and cleanup. Auto uses Otsu threshold and a conservative noise floor. Not Adobe proprietary model/pixel equivalence.","range":"Native0–10 scale:0 with autoRange=false selects the whole image; increasing range narrows selection. Noise0–1. Auto settings override their manual values; desktop state exposes effective estimates.","input":"Ordinary raster layer; default current-layer colors with mask/style removed, sampleAllLayers=true uses visible composite. Analysis uses SDR/sRGB proxy. Existing document selection does not constrain focus analysis.","history":"selection/layerMask/newLayer/newLayerWithMask commit one native Undo. newDocument/newDocumentWithMask return201, require document transfers and leave source/history unchanged. Selection Actions save coverage in version4; other outputs remain explicitly unsupported for recording.","limits":"Native8,388,608 pixels;1MP working analysis. API shared-document4,194,304 pixels/64 layers/128MiB,4MiB request.1024 Add/Subtract strokes/4096 points per stroke/16384 total points/250000000 brush pixel visits. No dedicated Adobe route or focus actionJSON conformance claimed."]}
}
struct FocusAreaAPIOptions:Sendable {
  let layerID:UUID
  let settings:FocusAreaSettings
  let output:SelectionRefinementOutput
  let strokes:[SelectionRefinementStroke]
  let all:Bool
  func edit(_ original:CraftDocument)throws->SelectionRefinementEdit{try FocusAreaInput.prepare(original,layerID:layerID,sampleAllLayers:all).edit(settings:settings,output:output,strokes:strokes)}
}
extension AutomationCommand {
  func focusOptions()throws->FocusAreaAPIOptions {
    let id=try actionUUID("layerID")
    let raw=try parameters["settings"].map{try BrushAPI.merge($0,schema:FocusAreaAPI.settingsSchema,base:BrushAPI.json(FocusAreaSettings()),path:"focus settings")} ?? BrushAPI.json(FocusAreaSettings())
    let settings=try JSONDecoder().decode(FocusAreaSettings.self,from:JSONSerialization.data(withJSONObject:raw));try settings.validate()
    let output:SelectionRefinementOutput
    if parameters["output"]==nil{output = .selection}else{guard let value=SelectionRefinementOutput(rawValue:try string("output")) else{throw AutomationFailure(status:400,message:"Unknown focus output.")};output=value}
    var strokes:[SelectionRefinementStroke]=[]
    if let value=parameters["strokes"] {
      let raw=try BrushAPI.merge(value,schema:FocusAreaAPI.strokesSchema,path:"focus strokes") as! [[String:Any]]
      for item in raw{var fields=try JSONSerialization.jsonObject(with:JSONEncoder().encode(SelectionRefinementStroke())) as! [String:Any];for(k,v) in item{fields[k]=v};let stroke=try JSONDecoder().decode(SelectionRefinementStroke.self,from:JSONSerialization.data(withJSONObject:fields));try stroke.validate();strokes.append(stroke)}
    }
    guard strokes.reduce(0,{$0+$1.points.count})<=16384 else{throw AutomationFailure(status:400,message:"Focus brush point limit exceeded.")}
    return try .init(layerID:id,settings:settings,output:output,strokes:strokes,all:adjustmentBrushFlag("sampleAllLayers",false))
  }
}
@MainActor extension EditorStore {
  var focusAreaState:[String:Any]{
    let draft=selectMaskDraft?.isFocus == true ? selectMaskDraft:nil
    return ["available":canBeginSelectMask,"workspaceOpen":draft != nil,"previewBusy":draft?.rendering ?? false,"settings":draft?.state.focus.map{BrushAPI.json($0)} ?? NSNull(),"effectiveSettings":draft?.effectiveFocus.map{BrushAPI.json($0)} ?? NSNull(),"strokeCount":draft?.state.strokes.count ?? 0,"output":draft?.state.output.rawValue ?? "selection","previewError":draft?.error as Any? ?? NSNull()]
  }
}
