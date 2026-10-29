import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum ShapeAPI {
  static let commands=["shape.edit","shape.configure","shape.library"]
  static var path:[String:Any]{(FrameDefinition.apiSchema["properties"] as! [String:[String:Any]])["customPath"]!}
  static var transform:[String:Any]{AutomationCommand.frameSchema("transform")}
  static func array(_ item:[String:Any],_ maximum:Int,_ minimum:Int=0)->[String:Any]{["type":"array","minItems":minimum,"maxItems":maximum,"items":item]}
  static var geometry:[String:Any]{
    var fields:[String:Any]=["kind":BrushAPI.enumeration(ShapeGeometry.Kind.allCases.map(\.rawValue)),"width":BrushAPI.number(0,32768),"height":BrushAPI.number(0,32768),"radii":array(BrushAPI.number(0,32768),4,4),"sides":BrushAPI.number(3,100,integer:true),"starRatio":BrushAPI.number(0.01,1),"cornerRadius":BrushAPI.number(0,32768),"lineWeight":BrushAPI.number(0.001,1000),"arrowStart":BrushAPI.flag,"arrowEnd":BrushAPI.flag,"arrowWidth":BrushAPI.number(0,2000),"arrowLength":BrushAPI.number(0,2000),"arrowConcavity":BrushAPI.number(0,0.9)]
    let required=Array(fields.keys);fields["customPath"]=path;return BrushAPI.object(fields,required:required)
  }
  static var component:[String:Any]{BrushAPI.object(["geometry":geometry,"transform":transform,"operation":BrushAPI.enumeration(PathOperation.allCases.map(\.rawValue))],required:["geometry","transform","operation"])}
  static var gradient:[String:Any]{
    let unit=BrushAPI.number(0,1),color:[String:Any]=["oneOf":[BrushAPI.object(["rgb":BrushAPI.object(["_0":BrushAPI.color],required:["_0"])],required:["rgb"]),BrushAPI.object(["hsb":BrushAPI.object(["hue":BrushAPI.number(-360000,360000),"saturation":unit,"brightness":unit],required:["hue","saturation","brightness"])],required:["hsb"]),BrushAPI.object(["gray":BrushAPI.object(["ink":unit],required:["ink"])],required:["gray"])]]
    let stop=BrushAPI.object(["position":unit,"color":color,"midpoint":unit],required:["position","color","midpoint"]),opacity=BrushAPI.object(["position":unit,"opacity":unit,"midpoint":unit],required:["position","opacity","midpoint"])
    let definition=BrushAPI.object(["name":["type":"string","minLength":1,"maxLength":65535],"colors":array(stop,1000,1),"opacity":array(opacity,1000),"smoothness":unit,"method":BrushAPI.enumeration(GradientMethod.allCases.map(\.rawValue))],required:["name","colors","opacity","smoothness","method"])
    let placement=BrushAPI.object(["style":BrushAPI.enumeration(GradientStyle.allCases.map(\.rawValue)),"angle":BrushAPI.number(-360000,360000),"scale":BrushAPI.number(0.000001,100000),"offsetX":BrushAPI.number(-1000000,1000000),"offsetY":BrushAPI.number(-1000000,1000000),"reverse":BrushAPI.flag],required:["style","angle","scale","offsetX","offsetY","reverse"])
    return BrushAPI.object(["gradient":definition,"placement":placement,"aligned":BrushAPI.flag,"dither":BrushAPI.flag],required:["gradient","placement","aligned","dither"])
  }
  static var pattern:[String:Any]{BrushAPI.object(["patternID":["type":"string","minLength":1,"maxLength":255],"linked":BrushAPI.flag,"geometry":transform,"placement":BrushAPI.object(["scale":BrushAPI.number(1,1000),"angle":BrushAPI.number(-360000,360000),"phaseX":BrushAPI.number(-1000000,1000000),"phaseY":BrushAPI.number(-1000000,1000000)],required:["scale","angle","phaseX","phaseY"])],required:["patternID","linked","placement"])}
  static var paint:[String:Any]{BrushAPI.object(["kind":BrushAPI.enumeration(ShapePaint.Kind.allCases.map(\.rawValue)),"color":BrushAPI.color,"gradient":gradient,"pattern":pattern],required:["kind","color"])}
  static var stroke:[String:Any]{BrushAPI.object(["paint":paint,"width":BrushAPI.number(0,1000),"alignment":BrushAPI.enumeration(ShapeStroke.Alignment.allCases.map(\.rawValue)),"cap":BrushAPI.enumeration(ShapeStroke.Cap.allCases.map(\.rawValue)),"join":BrushAPI.enumeration(ShapeStroke.Join.allCases.map(\.rawValue)),"miterLimit":BrushAPI.number(1,20),"dash":array(BrushAPI.number(0.000001,10000),32),"phase":BrushAPI.number(-10000,10000)],required:["paint","width","alignment","cap","join","miterLimit","dash","phase"])}
  static var definition:[String:Any]{BrushAPI.object(["components":array(component,64,1),"fill":paint,"stroke":stroke,"fillRule":BrushAPI.enumeration(PathFillRule.allCases.map(\.rawValue))],required:["components","fill","stroke","fillRule"])}
  static func schema(_ key:String)->[String:Any]{switch key{
    case "definition":return definition
    case "component":return component
    case "transform":return transform
    case "mode":return BrushAPI.enumeration(ShapeOutputMode.allCases.map(\.rawValue))
    case "combine":return ["anyOf":[["type":"null"],BrushAPI.enumeration(PathOperation.allCases.map(\.rawValue))]]
    case "operation":return BrushAPI.enumeration(["create","configure","append","list","define","import","export","rename","delete"])
    case "layerID","presetID":return ["type":"string","format":"uuid"]
    case "data":return ["type":"string","contentEncoding":"base64","maxLength":3000000]
    default:return ["type":"string","minLength":1,"maxLength":255]
  }}
  static var stateSchema:[String:Any]{
    let fields:[String:Any]=["available":BrushAPI.flag,"mode":schema("mode"),"combine":schema("combine"),"template":definition,"draftOpen":BrushAPI.flag,"gestureActive":BrushAPI.flag,"libraryRevision":BrushAPI.number(0,Double(Int32.max),integer:true),"library":array(BrushAPI.object(["id":schema("presetID"),"name":schema("name"),"path":path],required:["id","name","path"]),128),"selectedPresetID":["anyOf":[["type":"null"],schema("presetID")]],"libraryError":["anyOf":[["type":"null"],["type":"string"]]]]
    return BrushAPI.object(fields,required:Array(fields.keys))
  }
  static var capabilities:[String:Any]{["commands":commands,"definitionSchema":definition,"componentSchema":component,"stateSchema":stateSchema,"resultSchema":["type":"object","required":["revision","shapes"],"properties":["revision":["type":"string"],"shapes":stateSchema]],"libraryResultSchema":["type":"object","required":["revision","state"],"properties":["revision":["type":"string"],"state":stateSchema,"presetID":schema("presetID"),"data":["type":"string","contentEncoding":"base64","maxLength":22369624]]],"defaults":BrushAPI.json(ShapeDefinition(geometry:.init())),"nativeArchiveVersion":33,"actionLibraryVersion":5,"coordinates":"Physical local pixels. transform places the logical shape origin in document coordinates. Component transforms are local to that origin. Dash lengths/phase are local pixels. Gradients capture fixed colors; patterns reference embedded document or native preset IDs.","limits":"1–64 parametric components, 8MP shape rasterization budget. Native presets128/16MiB; API requests4MiB, preset import base64<=3000000 characters. API sharing4MP/64 layers/128MiB. Complete components required; omitted top-level definition fields use native defaults.","qualification":"Native shape/path/pixels outputs and native presets. Editable PSD shapes, Adobe .csh transport, exact stroke/corner/pixel/default equivalence and live/platform checks remain open. The pinned Adobe v2 contract has no dedicated shape route; none is invented."]}
  static func decode<T:Codable>(_ type:T.Type,_ value:AutomationValue?,schema:[String:Any],base:T)throws->T {
    guard let value else{return base}
    do{let old=try JSONSerialization.jsonObject(with:JSONEncoder().encode(base),options:.fragmentsAllowed),raw=try BrushAPI.merge(value,schema:schema,base:old,path:"shape")
      return try JSONDecoder().decode(type,from:JSONSerialization.data(withJSONObject:raw,options:.fragmentsAllowed))
    }catch{throw AutomationFailure(status:400,message:"Invalid shape value: \(error.localizedDescription)")}
  }
}
extension AutomationCommand {
  func shapeDefinition()throws->ShapeDefinition{let result=try ShapeAPI.decode(ShapeDefinition.self,parameters["definition"],schema:ShapeAPI.definition,base:.init(geometry:.init()));try result.validate();return result}
  func shapeCommand(_ document:CraftDocument,patterns:[RasterPattern])throws->Command{
    let operation=try string("operation"),required:Set<String>,optional:Set<String>
    switch operation{case "create":required=["definition"];optional=["name","mode","transform","layerID"];case "configure":required=["definition","layerID"];optional=[];case "append":required=["component","layerID"];optional=[];default:throw AutomationFailure(status:400,message:"Unknown shape operation.")}
    let keys=Set(parameters.keys).subtracting(["operation"]);guard required.isSubset(of:keys),keys.isSubset(of:required.union(optional)) else{throw AutomationFailure(status:400,message:"Missing or irrelevant shape parameters.")}
    if operation == "append"{let value=try ShapeAPI.decode(ShapeComponent.self,parameters["component"],schema:ShapeAPI.component,base:.init(geometry:.init()));return .shape(.append(try actionUUID("layerID"),value))}
    let definition=try shapeDefinition(),ids=Set([definition.fill.pattern?.patternID,definition.stroke.paint.pattern?.patternID].compactMap{$0}),resources=patterns.filter{ids.contains($0.id) && document.pattern($0.id)==nil}
    if operation == "configure"{return .shape(.configure(try actionUUID("layerID"),definition,patterns:resources))}
    let mode=try ShapeAPI.decode(ShapeOutputMode.self,parameters["mode"],schema:ShapeAPI.schema("mode"),base:.shape)
    let placement=try ShapeAPI.decode(Transform2D.self,parameters["transform"],schema:ShapeAPI.transform,base:.identity)
    let target=try parameters["layerID"].map{_ in try actionUUID("layerID")} ?? document.activeLayerID
    let name=try parameters["name"].map{_ in try string("name")} ?? "Shape"
    return try ShapeRenderer.creation(definition,name:name,placement:placement,mode:mode,target:target,document:document,patterns:resources)
  }
}
extension EditorStore {
  var shapeState:[String:Any]{["available":canDrawShapes,"mode":shapeMode.rawValue,"combine":shapeOperation?.rawValue as Any? ?? NSNull(),"template":BrushAPI.json(shapeTemplate),"draftOpen":shapeDraft != nil,"gestureActive":shapeGesture != nil,"libraryRevision":shapes.revision,"library":shapes.shapes.map{BrushAPI.json($0)},"selectedPresetID":selectedShapeID?.uuidString as Any? ?? NSNull(),"libraryError":shapes.loadError as Any? ?? NSNull()]}
  func configureShape(_ command:AutomationCommand)throws{
    var definition=shapeTemplate,mode=shapeMode,operation=shapeOperation,presetID=selectedShapeID
    if command.parameters["definition"] != nil{definition=try command.shapeDefinition();guard definition.components.count==1 else{throw AutomationFailure(status:400,message:"Tool settings use one primitive.")}}
    if let value=command.parameters["mode"]{mode=try ShapeAPI.decode(ShapeOutputMode.self,value,schema:ShapeAPI.schema("mode"),base:mode)}
    if let value=command.parameters["combine"]{if case .null=value{operation=nil}else{operation=try ShapeAPI.decode(PathOperation.self,value,schema:ShapeAPI.schema("combine"),base:.combine)}}
    if command.parameters["presetID"] != nil{presetID=try command.actionUUID("presetID");definition.components[0].geometry.kind = .custom;definition.components[0].geometry.customPath=try shapes.preset(presetID!).path}
    try definition.validate();shapeTemplate=definition;shapeMode=mode;shapeOperation=operation;selectedShapeID=presetID
    if let selected=EditorTool.allCases.first(where:{$0.shapeKind==definition.components[0].geometry.kind}){tool=selected}
  }
}
extension AutomationService {
  func manageShapes(_ command:AutomationCommand,store:EditorStore)throws->[String:Any]{
    let operation=try command.string("operation"),fields:[String:Set<String>]=["list":[],"define":["name"],"import":["data"],"export":["presetID"],"rename":["presetID","name"],"delete":["presetID"]]
    guard let allowed=fields[operation],Set(command.parameters.keys).subtracting(["operation"]).isSubset(of:allowed) else{throw AutomationFailure(status:400,message:"Unknown or irrelevant shape library parameters.")}
    var id:UUID?,data:Data?
    switch operation {
    case "define":id=try store.defineShape(name:command.string("name"))
    case "import":guard case .string(let text)=command.parameters["data"],text.count<=3000000,let decoded=Data(base64Encoded:text) else{throw AutomationFailure(status:400,message:"Supply bounded base64 native shape presets.")};try store.shapes.importData(decoded)
    case "export":data=try store.shapes.export(command.parameters["presetID"].map{_ in try command.actionUUID("presetID")})
    case "rename":try store.shapes.rename(command.actionUUID("presetID"),command.string("name"))
    case "delete":let deleted=try command.actionUUID("presetID");try store.shapes.remove(deleted);if store.selectedShapeID==deleted{store.selectedShapeID=nil}
    default:break
    }
    var result:[String:Any]=["revision":revision(store),"state":store.shapeState];if let id{result["presetID"]=id.uuidString};if let data{result["data"]=data.base64EncodedString()};return result
  }
}

extension Layer {
  var shapeAPIState:Any {shape.map{BrushAPI.json($0.editableDefinition)} ?? NSNull()}
  var shapeTransformAPIState:Any {guard shape != nil,let transform=try? shapeTransform() else{return NSNull()};return BrushAPI.json(transform)}
}
