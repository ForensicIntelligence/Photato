import Foundation
import PhotoCraftCore

enum ProceduralAPI {
  static func kind(_ command:String)->ProceduralRenderSettings.Kind? {
    guard command.hasPrefix("render.") else{return nil}
    return .init(rawValue:String(command.dropFirst(7)))
  }
  static func settings(_ kind:ProceduralRenderSettings.Kind)->[String:Any] {
    let n=BrushAPI.number,flag=BrushAPI.flag,color=BrushAPI.color
    var fields:[String:Any]=["seed":n(0,Double(UInt32.max),true)]
    switch kind {
    case .flame:
      fields.merge(["flameType":BrushAPI.enumeration(FlameSettings.Mode.allCases.map(\.rawValue)),"flameStyle":BrushAPI.enumeration(FlameSettings.Style.allCases.map(\.rawValue)),"flameShape":BrushAPI.enumeration(FlameSettings.Shape.allCases.map(\.rawValue)),"color":color,"quality":n(0,4,true),"angle":n(-180,180,false)],uniquingKeysWith:{$1})
      for k in ["length","width","interval"] {fields[k]=n(1,1000,false)}
      for k in ["turbulent","jag","opacity","flameBottomAlignment"] {fields[k]=n(0,100,false)}
      fields["flameLines"]=n(1,100,false)
      for k in ["randomizeLength","adjustIntervalForLoops","useCustomColor","randomizeShapes"] {fields[k]=flag}
    case .tree:
      fields.merge(["baseTreeType":n(1,34,true),"lightDirection":n(1,5,true),"leavesAmount":n(0,100,false),"leavesSize":n(0,200,false),"branchesHeight":n(50,300,false),"branchesThickness":n(50,200,false),"x":n(0,1,false),"y":n(0,1,false),"size":n(0.05,2,false),"leavesColor":color,"branchesColor":color],uniquingKeysWith:{$1})
      for k in ["defaultLeaves","customBranchColor","flatShading"] {fields[k]=flag}
    case .pictureFrame:
      fields.merge(["frame":n(1,16,true),"lines":n(1,5,true),"margin":n(0,30,false),"fade":n(0,100,false)],uniquingKeysWith:{$1})
      for k in ["size","arrangement","thickness"] {fields[k]=n(1,100,false)}
      for k in ["vineColor","flowerColor","leafColor"] {fields[k]=color}
    }
    var result=BrushAPI.object(fields);result["default"]=values(.init(kind));return result
  }
  static func values(_ value:ProceduralRenderSettings)->Any {
    switch value.kind {case .flame:BrushAPI.json(value.flame);case .tree:BrushAPI.json(value.tree);case .pictureFrame:BrushAPI.json(value.frame)}
  }
  static func decode(_ input:AutomationValue?,kind:ProceduralRenderSettings.Kind)throws->ProceduralRenderSettings {
    var value=ProceduralRenderSettings(kind)
    guard let input else{return value}
    let merged=try BrushAPI.merge(input,schema:settings(kind),base:values(value),path:"settings"),data=try JSONSerialization.data(withJSONObject:merged)
    switch kind {
    case .flame:value.flame=try JSONDecoder().decode(FlameSettings.self,from:data)
    case .tree:value.tree=try JSONDecoder().decode(TreeSettings.self,from:data)
    case .pictureFrame:value.frame=try JSONDecoder().decode(PictureFrameSettings.self,from:data)
    }
    try value.validate();return value
  }
  static func schema(_ key:String,kind:ProceduralRenderSettings.Kind)->[String:Any] {
    switch key {case "settings":settings(kind);case "newLayer":["type":"boolean","default":false];default:["type":"string","format":"uuid"]}
  }
  static var capabilities:[String:Any] {
    ["commands":ProceduralRenderSettings.Kind.allCases.map{"render."+$0.rawValue},"settings":Dictionary(uniqueKeysWithValues:ProceduralRenderSettings.Kind.allCases.map{($0.rawValue,settings($0))}),"treeTypes":TreeSettings.names,"frameStyles":PictureFrameSettings.styles,"maximumPixels":ProceduralRenderEngine.maximumPixels,"nativeActionsVersion":15,"smartFilters":false,"output":"Raster pixels, source-over with selection coverage and transparency locks; optional newLayer. Flame uses pathID, selected path, Work Path or first saved path, in that order.","limits":"Generation is cancellable and bounded to200,000 primitives and268,435,456 coverage samples. Source algorithms are not Photoshop pixel-equivalence evidence. Adobe actionJSON descriptors remain unsupported; no new Adobe routes."]
  }
  static var workspaceSchema:[String:Any] {
    ["oneOf":ProceduralRenderSettings.Kind.allCases.map {kind -> [String:Any] in
      var fields:[String:Any]=["kind":["const":kind.rawValue],"settings":settings(kind),"zoom":BrushAPI.number(0.125,8),"error":["type":["string","null"]]]
      for k in ["newLayer","hasPath","preview","fit","canUndo","canRedo"] {fields[k]=BrushAPI.flag}
      return BrushAPI.object(fields,required:Array(fields.keys))
    } + [["type":"null"]]]
  }
  static var stateSchema:[String:Any] {
    BrushAPI.object(["available":BrushAPI.object(Dictionary(uniqueKeysWithValues:ProceduralRenderSettings.Kind.allCases.map{($0.rawValue,BrushAPI.flag)}),required:ProceduralRenderSettings.Kind.allCases.map(\.rawValue)),"workspaceOpen":BrushAPI.flag,"previewBusy":BrushAPI.flag,"committing":BrushAPI.flag,"workspace":workspaceSchema],required:["available","workspaceOpen","previewBusy","committing","workspace"])
  }
}
extension AutomationCommand {
  func proceduralRequest(_ document:CraftDocument,selected:VectorPath?=nil)throws->ProceduralRenderRequest {
    guard let kind=ProceduralAPI.kind(name) else{throw AutomationFailure(status:400,message:"Unknown procedural renderer.")}
    let settings=try ProceduralAPI.decode(parameters["settings"],kind:kind)
    let id=try parameters["layerID"].map{_ in try actionUUID("layerID")}
    if let id,!document.layers.contains(where:{$0.id==id}) {throw AutomationFailure(status:404,message:"Render target layer not found.")}
    var path=kind == .flame ? selected:nil
    if parameters["pathID"] != nil {
      guard kind == .flame else{throw AutomationFailure(status:400,message:"Only Flame accepts pathID.")}
      let id=try actionUUID("pathID")
      guard let saved=document.paths?.first(where:{$0.id==id}) else{throw AutomationFailure(status:404,message:"Render path not found.")};path=saved.path
    }
    let request=ProceduralRenderRequest(settings,layerID:id,newLayer:try pathFlag("newLayer",false),path:path)
    try request.validate();return request
  }
}
extension EditorStore {
  var proceduralState:[String:Any] {
    ["available":Dictionary(uniqueKeysWithValues:ProceduralRenderSettings.Kind.allCases.map{($0.rawValue,canBeginProcedural($0))}),"workspaceOpen":proceduralWorkspace != nil,"previewBusy":proceduralWorkspace?.rendering ?? false,"committing":proceduralWorkspace?.committing ?? false,"workspace":proceduralWorkspace?.apiState as Any? ?? NSNull()]
  }
}
