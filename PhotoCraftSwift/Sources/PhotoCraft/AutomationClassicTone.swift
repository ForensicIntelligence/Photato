import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ClassicToneAPI {
  static let commands=["tone.apply","tone.statistics"]
  static var statisticsSchema:[String:Any] {
    func array(_ low:Double)->[String:Any]{["type":"array","minItems":3,"maxItems":3,"items":BrushAPI.number(low,1e6)]}
    return BrushAPI.object(["mean":array(-1e6),"standardDeviation":array(0)],required:["mean","standardDeviation"])
  }
  static func settings(_ kind:ClassicToneSettings.Kind)->[String:Any] {
    var fields:[String:Any]=[:];let s=ClassicToneSettings(kind)
    for key in s.keys {
      if let range=ClassicToneSettings.numericRanges[key]{fields[key]=BrushAPI.number(range.lowerBound,range.upperBound);continue}
      switch key {
      case "method":fields[key]=BrushAPI.enumeration(HDRMergeSettings.Method.allCases.map(\.rawValue))
      case "sourceStatistics":var schema=statisticsSchema;schema["type"]=["object","null"];fields[key]=schema
      case "curve":fields[key]=["type":"array","maxItems":32,"items":["type":"array","minItems":2,"maxItems":2,"items":BrushAPI.number()]]
      case "samples":
        var point=BrushAPI.object(["x":BrushAPI.number(),"y":BrushAPI.number()],required:["x","y"]);point["type"]=["object","null"]
        fields[key]=["type":"array","minItems":1,"maxItems":64,"items":BrushAPI.object(["color":BrushAPI.color,"point":point,"subtract":BrushAPI.flag],required:["color","subtract"])]
      default:fields[key]=BrushAPI.flag
      }
    }
    var schema=BrushAPI.object(fields);schema["default"]=s.apiParameters;return schema
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "kind":BrushAPI.enumeration(ClassicToneSettings.Kind.allCases.map(\.rawValue))
    case "settings":["anyOf":ClassicToneSettings.Kind.allCases.map(settings)]
    case "useSelection":BrushAPI.flag
    default:["type":"string","format":"uuid"]
    }
  }
  static var capabilities:[String:Any] {
    ["commands":commands,"kinds":ClassicToneSettings.Kind.allCases.map(\.rawValue),"settings":Dictionary(uniqueKeysWithValues:ClassicToneSettings.Kind.allCases.map{($0.rawValue,settings($0))}),"statisticsSchema":statisticsSchema,"statisticsResultSchema":BrushAPI.object(["statistics":statisticsSchema,"revision":["type":"string"],"sourceDepth":["type":"string","enum":PixelDepth.allCases.map(\.rawValue)]],required:["statistics","revision","sourceDepth"]),"maximumPixels":ClassicToneEngine.maximumPixels,"nativeArchive":45,"actionsArchive":18,"smartFilters":["shadowsHighlights"],"behavior":"tone.statistics reads this shared document/layer and optional selection. Supply its statistics in Match Color sourceStatistics for deterministic cross-document matching. HDR Toning composites and replaces layers with one background as one Undo. Equalize can apply only to selection or entire target based on selected samples.","limits":"Native RGB8/16/32; exact Photoshop depth/default/output and ICC-specific tone behavior remain unqualified. Native JSON settings/statistics presets; Adobe STA/preset/ActionJSON/ATN/editable PSD descriptors and semantic HDR Actions remain unsupported."]
  }
  static var stateSchema:[String:Any] {
    BrushAPI.object(["available":BrushAPI.object(Dictionary(uniqueKeysWithValues:ClassicToneSettings.Kind.allCases.map{($0.rawValue,BrushAPI.flag)})),"workspaceOpen":BrushAPI.flag,"previewBusy":BrushAPI.flag,"committing":BrushAPI.flag,"workspace":["type":["object","null"],"properties":["kind":schema("kind"),"settings":schema("settings"),"preview":BrushAPI.flag,"fit":BrushAPI.flag,"zoom":BrushAPI.number(0.125,8),"canUndo":BrushAPI.flag,"canRedo":BrushAPI.flag,"error":["type":["string","null"]]]]],required:["available","workspaceOpen","previewBusy","committing","workspace"])
  }
}
extension AutomationCommand {
  func classicToneRequest(_ document:CraftDocument)throws->ClassicToneRequest {
    guard let kind=ClassicToneSettings.Kind(rawValue:try string("kind")) else{throw AutomationFailure(status:400,message:"Unknown tone adjustment.")}
    let settings:ClassicToneSettings
    if let input=parameters["settings"] {
      _=try BrushAPI.merge(input,schema:ClassicToneAPI.settings(kind),path:"settings")
      do {settings=try ClassicToneSettings.decodeJSON(JSONSerialization.data(withJSONObject:input.jsonValue),kind:kind)}catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    }else{settings = .init(kind)}
    let id=try parameters["layerID"].map{_ in try actionUUID("layerID")}
    if let id,!document.layers.contains(where:{$0.id==id}){throw AutomationFailure(status:404,message:"Adjustment target not found.")}
    if kind == .hdrToning,id != nil {throw AutomationFailure(status:400,message:"HDR Toning acts on the whole document; omit layerID.")}
    return .init(settings,layerID:id)
  }
}
extension EditorStore {
  var classicToneState:[String:Any] {
    ["available":Dictionary(uniqueKeysWithValues:ClassicToneSettings.Kind.allCases.map{($0.rawValue,canBeginClassicTone($0))}),"workspaceOpen":activeClassicToneWorkspace != nil || filterDraft?.filter.kind == .shadowsHighlights,"previewBusy":activeClassicToneWorkspace?.rendering ?? false,"committing":activeClassicToneWorkspace?.committing ?? false,"workspace":activeClassicToneWorkspace?.apiState as Any? ?? NSNull()]
  }
}
