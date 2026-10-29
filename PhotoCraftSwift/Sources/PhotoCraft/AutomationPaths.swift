import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum PathAPI {
  static let commands=["path.configure","path.draw","path.edit","path.trace","path.paint"]
  static var point:[String:Any]{BrushAPI.object(["x":BrushAPI.number(-1_000_000,1_000_000),"y":BrushAPI.number(-1_000_000,1_000_000)],required:["x","y"])}
  static var path:[String:Any]{
    let knot=BrushAPI.object(["anchor":point,"incoming":point,"outgoing":point,"smooth":BrushAPI.flag],required:["anchor","incoming","outgoing","smooth"])
    let part=BrushAPI.object(["knots":ShapeAPI.array(knot,4096),"closed":BrushAPI.flag,"operation":BrushAPI.enumeration(PathOperation.allCases.map(\.rawValue))],required:["knots","closed","operation"])
    return BrushAPI.object(["components":ShapeAPI.array(part,256),"fillRule":BrushAPI.enumeration(PathFillRule.allCases.map(\.rawValue)),"inverted":BrushAPI.flag],required:["components","fillRule","inverted"])
  }
  static func schema(_ key:String)->[String:Any]{switch key {
    case "path":return path
    case "points":return ShapeAPI.array(point,4096,2)
    case "corners":return ShapeAPI.array(BrushAPI.number(0,4095,integer:true),4096)
    case "tolerance":return BrushAPI.number(0.5,10)
    case "closed","workPath","stroke","simulatePressure","antiAlias":return BrushAPI.flag
    case "brush":return BrushAPI.brush
    case "pathID","layerID":return ["type":"string","format":"uuid"]
    case "operation":return BrushAPI.enumeration(["save","delete","selection","vectorMask"])
    case "method":return BrushAPI.enumeration(["freeform","curvature"])
    case "tool":return BrushAPI.enumeration(["pen","freeformPen","curvaturePen","pathSelection","directSelection"])
    case "combine":return BrushAPI.enumeration(PathOperation.allCases.map(\.rawValue))
    case "selectionMode":return BrushAPI.enumeration(SelectionMode.allCases.map(\.rawValue))
    case "feather":return BrushAPI.number(0,100)
    default:return ["type":"string","minLength":1,"maxLength":255]
  }}
  static var stateSchema:[String:Any]{
    let named=BrushAPI.object(["id":schema("pathID"),"name":schema("name"),"isWorkPath":BrushAPI.flag,"path":path],required:["id","name","isWorkPath","path"])
    let fields:[String:Any]=["paths":ShapeAPI.array(named,256),"selectedID":["anyOf":[["type":"null"],schema("pathID")]],"target":BrushAPI.enumeration(["none","saved","vectorMask"]),"selectedPath":["anyOf":[["type":"null"],path]],"tolerance":schema("tolerance"),"operation":schema("combine"),"gestureActive":BrushAPI.flag,"editable":BrushAPI.flag,"tool":["type":"string"]]
    return BrushAPI.object(fields,required:Array(fields.keys))
  }
  static var capabilities:[String:Any]{["commands":commands,"pathSchema":path,"stateSchema":stateSchema,"resultSchema":["type":"object","required":["revision","paths"],"properties":["revision":["type":"string"],"paths":stateSchema]],"coordinates":"Document pixels, y downward. Full cubic handles retained. draw writes one path transaction; freeform fits sampled points, curvature interpolates anchors. pathID edits an existing saved path; omitted pathID creates/replaces Work Path when workPath=true. paint uses the selected path unless pathID is provided and paints layerID or the active raster layer.","limits":"4096 knots,256 components,100000 native input samples; API draw4096 samples. Trace/paint16MP. Existing API sharing/body limits also apply.","defaults":["tolerance":2,"method":"freeform","closed":false,"workPath":true,"stroke":false,"simulatePressure":false],"qualification":"Native geometry and brush rendering. Exact Adobe curvature/fitting/brush kernels, magnetic pen, multi-anchor editing, clipping-path export, advanced Fill Path dialog options and live interaction remain open. No dedicated path route in the pinned Adobe v2 contract; unsupported action descriptors remain explicit errors."]}
}
extension AutomationCommand {
  func pathFlag(_ key:String,_ fallback:Bool)throws->Bool{guard let value=parameters[key] else{return fallback};guard case .bool(let flag)=value else{throw AutomationFailure(status:400,message:"\(key) must be boolean.")};return flag}
  func pathFields(_ required:Set<String>=[],_ optional:Set<String>)throws{let keys=Set(parameters.keys);guard required.isSubset(of:keys),keys.isSubset(of:required.union(optional)) else{throw AutomationFailure(status:400,message:"Missing or irrelevant path parameters.")}}
  func pathCommand(_ document:CraftDocument,selected:VectorPath?,brush:Brush,selectedIsVectorMask:Bool=false)throws->Command {
    let tolerance=try parameters["tolerance"].map{_ in try number("tolerance",range:0.5...10)} ?? 2
    if name=="path.trace"{try pathFields([], ["tolerance"]);return try PathTracing.command(document,tolerance:tolerance)}
    func resolved()throws->VectorPath {
      if parameters["pathID"] != nil{let id=try actionUUID("pathID");guard let saved=document.paths?.first(where:{$0.id==id}) else{throw AutomationFailure(status:404,message:"Path not found.")};return saved.path}
      guard let selected else{throw AutomationFailure(status:400,message:"Choose a path or supply pathID.")};return selected
    }
    if name=="path.paint" {
      try pathFields([], ["pathID","layerID","brush","stroke","simulatePressure"])
      guard let id=try parameters["layerID"].map({_ in try actionUUID("layerID")}) ?? document.activeLayerID else{throw AutomationFailure(status:400,message:"Choose a raster layer.")}
      let stroke=try pathFlag("stroke",false),pressure=try pathFlag("simulatePressure",false)
      guard stroke || !pressure else{throw AutomationFailure(status:400,message:"Simulate Pressure requires Stroke Path.")}
      return try PathPainting.command(resolved(),document:document,layerID:id,brush:BrushAPI.decode(parameters["brush"],base:brush),stroke:stroke,simulatePressure:pressure)
    }
    var output:VectorPath
    if name=="path.draw" {
      try pathFields(["points"],["method","closed","corners","tolerance","pathID","name","workPath"])
      let raw=try BrushAPI.merge(parameters["points"]!,schema:PathAPI.schema("points")),points=try JSONDecoder().decode([PathPoint].self,from:JSONSerialization.data(withJSONObject:raw)),closed=try pathFlag("closed",false),method=try parameters["method"].map{_ in try string("method")} ?? "freeform"
      if method=="freeform"{guard parameters["corners"]==nil else{throw AutomationFailure(status:400,message:"Corner indices require Curvature Pen.")};output=VectorPath(components:[try PathConstruction.fitted(points,tolerance:tolerance,closed:closed)])}
      else if method=="curvature"{
        guard parameters["tolerance"]==nil else{throw AutomationFailure(status:400,message:"Curve Fit applies to Freeform Pen only.")}
        let corners=try parameters["corners"].map{try BrushAPI.merge($0,schema:PathAPI.schema("corners")) as! [Double]} ?? []
        guard corners.allSatisfy({Int($0)<points.count}),!closed || points.count>=3 else{throw AutomationFailure(status:400,message:"Invalid curvature corner index or closed path.")}
        output=VectorPath(components:[try PathConstruction.curvature(.init(knots:points.enumerated().map{.init($0.element,smooth:!corners.contains(Double($0.offset)))},closed:closed))])
      }else{throw AutomationFailure(status:400,message:"Unknown path drawing method.")}
    }else {
      let operation=try string("operation")
      switch operation {
      case "save":try pathFields(["operation","path"],["pathID","name","workPath"]);output=try ShapeAPI.decode(VectorPath.self,parameters["path"],schema:PathAPI.path,base:VectorPath())
      case "delete":try pathFields(["operation","pathID"],[]);_ = try resolved();return .deletePath(try actionUUID("pathID"))
      case "selection":
        try pathFields(["operation"],["pathID","selectionMode","feather","antiAlias"])
        let mode=try ShapeAPI.decode(SelectionMode.self,parameters["selectionMode"],schema:PathAPI.schema("selectionMode"),base:.replace),feather=try parameters["feather"].map{_ in try number("feather",range:0...100)} ?? 0
        return .selectionCoverage(try VectorRasterizer.coverage(resolved(),width:document.width,height:document.height,antiAlias:pathFlag("antiAlias",true),emptyRevealsAll:selectedIsVectorMask && parameters["pathID"]==nil).feathered(radius:feather),mode)
      case "vectorMask":try pathFields(["operation","layerID"],["pathID"]);return .vectorMask(try actionUUID("layerID"),VectorMask(path:try resolved()))
      default:throw AutomationFailure(status:400,message:"Unknown path operation.")
      }
    }
    try output.validate()
    let explicit=try parameters["pathID"].map{_ in try actionUUID("pathID")},old=explicit.flatMap{id in document.paths?.first{$0.id==id}}
    guard explicit==nil || old != nil else{throw AutomationFailure(status:404,message:"Path not found.")}
    var saved=old ?? NamedPath();saved.path=output
    if parameters["name"] != nil{saved.name=try string("name")}
    saved.isWorkPath=try pathFlag("workPath",old?.isWorkPath ?? true)
    if saved.isWorkPath,explicit==nil,let work=document.paths?.first(where:\.isWorkPath){saved.id=work.id}
    return .savePath(saved)
  }
}
extension EditorStore {
  var pathState:[String:Any]{
    let target:String,id:UUID?
    switch pathTarget{case .saved(let value):target="saved";id=value;case .vectorMask(let value):target="vectorMask";id=value;case nil:target="none";id=nil}
    return ["paths":(document.paths ?? []).map{BrushAPI.json($0)},"selectedID":id?.uuidString as Any? ?? NSNull(),"target":target,"selectedPath":selectedVectorPath.map{BrushAPI.json($0)} ?? NSNull(),"tolerance":pathCurveFit,"operation":pathOperation.rawValue,"gestureActive":freeformGesture != nil || pathGesture != nil,"editable":pathIsEditable,"tool":selectedTool.id]
  }
  func configurePath(_ command:AutomationCommand)throws{
    try command.pathFields([], ["tool","tolerance","combine","pathID"])
    let tolerance=try command.parameters["tolerance"].map{_ in try command.number("tolerance",range:0.5...10)} ?? pathCurveFit
    let operation=try ShapeAPI.decode(PathOperation.self,command.parameters["combine"],schema:PathAPI.schema("combine"),base:pathOperation)
    var selected:WorkspaceTool?
    if command.parameters["tool"] != nil{let name=try command.string("tool");guard ["pen","freeformPen","curvaturePen","pathSelection","directSelection"].contains(name) else{throw AutomationFailure(status:400,message:"Unknown path tool.")};selected=WorkspaceCatalog.tool(name)}
    let id=try command.parameters["pathID"].map{_ in try command.actionUUID("pathID")}
    if let id,!((document.paths ?? []).contains{$0.id==id}){throw AutomationFailure(status:404,message:"Path not found.")}
    pathCurveFit=tolerance;pathOperation=operation;if let selected{tool=selected.native!};if let id{selectPath(.saved(id))};revision += 1
  }
}
