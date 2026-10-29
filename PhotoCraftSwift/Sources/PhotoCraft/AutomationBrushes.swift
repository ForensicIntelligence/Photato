import Foundation
import PhotoCraftCore
import PhotoCraftImaging

enum BrushAPI {
  static func number(_ lo:Double=0,_ hi:Double=1,integer:Bool=false)->[String:Any] { ["type":integer ? "integer":"number","minimum":lo,"maximum":hi] }
  static var flag:[String:Any] { ["type":"boolean"] }
  static func enumeration(_ values:[String])->[String:Any] { ["type":"string","enum":values] }
  static func object(_ fields:[String:Any],required:[String]=[])->[String:Any] { ["type":"object","additionalProperties":false,"properties":fields,"required":required] }
  static var bitmap:[String:Any] { var s=object(["width":number(1,2500,integer:true),"height":number(1,2500,integer:true),"bytes":["type":"string","contentEncoding":"base64","maxLength":8_333_336]],required:["width","height","bytes"]);s["type"]=["object","null"];return s }
  static var color:[String:Any] { object(Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,number())}),required:["r","g","b","a"]) }
  static func dynamic(maximum:Double=1)->[String:Any] { object(["jitter":number(0,maximum),"control":enumeration(BrushControl.allCases.map(\.rawValue)),"fadeSteps":number(1,10000,integer:true),"minimum":number()]) }
  static var settings:[String:Any] {
    let unit=number(),angle=number(-360,360),spacing=number(0.01,10),mask=enumeration(BrushMaskMode.allCases.map(\.rawValue))
    var fields:[String:Any]=["tip":bitmap,"spacing":spacing,"angle":angle,"roundness":number(0.01,1),"flow":unit,"mode":enumeration(BlendMode.allCases.map(\.rawValue)),"seed":number(0,9_007_199_254_740_991,integer:true),"zoom":number(0.01,64),"buildUpRate":number(0.1,1000),"lockedSections":["type":"array","maxItems":BrushSettings.sections.count,"uniqueItems":true,"items":enumeration(BrushSettings.sections)]]
    for k in ["spacingEnabled","flipX","flipY","pressureSize","pressureOpacity","aliased","noise","wetEdges","buildUp","protectTexture"] { fields[k]=flag }
    fields["shape"]=object(["enabled":flag,"size":dynamic(),"angle":dynamic(),"roundness":dynamic(),"tiltScale":number(0,2),"flipX":flag,"flipY":flag,"projection":flag])
    fields["scattering"]=object(["enabled":flag,"amount":dynamic(maximum:10),"bothAxes":flag,"count":number(1,16,integer:true),"countJitter":dynamic()])
    fields["texture"]=object(["enabled":flag,"pattern":enumeration(BrushTexture.Pattern.allCases.map(\.rawValue)),"bitmap":bitmap,"scale":spacing,"brightness":number(-1,1),"contrast":number(-1,1),"invert":flag,"eachTip":flag,"mode":mask,"depth":unit,"depthJitter":dynamic(),"seed":number(0,9_007_199_254_740_991,integer:true)])
    fields["dual"]=object(["enabled":flag,"mode":mask,"tip":bitmap,"size":number(0.5,2048),"hardness":unit,"roundness":number(0.01,1),"angle":angle,"spacing":spacing,"scatter":number(0,10),"bothAxes":flag,"count":number(1,16,integer:true),"flip":flag])
    fields["colorDynamics"]=object(["enabled":flag,"perTip":flag,"foregroundBackground":dynamic(),"hue":unit,"saturation":unit,"brightness":unit,"purity":number(-1,1)])
    fields["transfer"]=object(["enabled":flag,"opacity":dynamic(),"flow":dynamic()])
    fields["pose"]=object(["enabled":flag,"tiltX":number(-90,90),"tiltY":number(-90,90),"rotation":angle,"pressure":unit,"overrideTilt":flag,"overrideRotation":flag,"overridePressure":flag])
    fields["smoothing"]=object(["amount":unit,"pulledString":flag,"catchUp":flag,"catchUpOnEnd":flag,"adjustForZoom":flag])
    fields["symmetry"]=object(["mode":enumeration(BrushSymmetry.Mode.allCases.map(\.rawValue)),"center":object(["x":number(-1_000_000,1_000_000),"y":number(-1_000_000,1_000_000)]),"count":number(2,12,integer:true)])
    return object(fields)
  }
  static var brush:[String:Any] { object(["size":number(0.5,2048),"hardness":number(),"opacity":number(),"color":color,"backgroundColor":color,"erase":flag,"settings":settings]) }
  static var point:[String:Any] { object(["x":number(-1_000_000,1_000_000),"y":number(-1_000_000,1_000_000),"pressure":number(),"tiltX":number(-90,90),"tiltY":number(-90,90),"rotation":number(-360,360),"wheel":number(),"time":number(0,3_600_000)],required:["x","y"]) }
  static let operations=["list","select","save","define","rename","delete","move","import","export"]
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "brush":return brush
    case "points":return ["type":"array","minItems":1,"maxItems":4096,"items":point]
    case "operation":return enumeration(operations)
    case "target":return enumeration(["pixels","layerMask","smartFilterMask","alpha","quickMask"])
    case "format":return enumeration(["photatobrushes","abr"])
    case "index":return number(0,511,integer:true)
    case "includeSize","includeToolSettings","includeColor":return flag
    case "data":return ["type":"string","contentEncoding":"base64","maxLength":3_000_000]
    case "layerID","presetID","channelID":return ["type":"string","format":"uuid"]
    default:return ["type":"string","minLength":1,"maxLength":255]
    }
  }
  static func json<T:Encodable>(_ value:T)->Any { (try? JSONSerialization.jsonObject(with:JSONEncoder().encode(value))) ?? NSNull() }
  /// Validate against the published tree before merging defaults; JSONDecoder alone ignores unknown keys.
  static func merge(_ value:AutomationValue,schema:[String:Any],base:Any?=nil,path:String="brush")throws->Any {
    func fail()->AutomationFailure { .init(status:400,message:"Invalid or unknown \(path).") }
    if let constant=schema["const"] {
      switch value {
      case .number(let n):guard let c=constant as? NSNumber,CFGetTypeID(c) != CFBooleanGetTypeID(),n==c.doubleValue else{throw fail()}
      case .bool(let b):guard let c=constant as? NSNumber,CFGetTypeID(c)==CFBooleanGetTypeID(),b==c.boolValue else{throw fail()}
      case .string(let v):guard let c=constant as? String,c==v else{throw fail()}
      default:throw fail()
      }
      return value.jsonValue
    }
    if let variants=(schema["anyOf"] ?? schema["oneOf"]) as? [[String:Any]] {
      let matches=variants.compactMap { variant -> Any? in
        var selectedBase=base
        if schema["oneOf"] != nil,let old=base as? [String:Any],let fields=variant["properties"] as? [String:Any],!Set(old.keys).isSubset(of:Set(fields.keys)){selectedBase=nil}
        return try? merge(value,schema:variant,base:selectedBase,path:path)
      }
      guard !matches.isEmpty,schema["oneOf"]==nil || matches.count==1 else{throw fail()};return matches[0]
    }
    if case .null=value,schema["type"] as? String == "null" {return NSNull()}
    if case .null=value,(schema["type"] as? [String])?.contains("null")==true { return NSNull() }
    switch (schema["type"] as? String) ?? (schema["type"] as? [String])?.first {
    case "object":
      guard case .object(let fields)=value,let properties=schema["properties"] as? [String:[String:Any]],Set(fields.keys).isSubset(of:Set(properties.keys)) else { throw fail() }
      var output=base as? [String:Any] ?? [:]
      for (key,v) in fields { output[key]=try merge(v,schema:properties[key]!,base:output[key],path:path+"."+key) }
      guard Set(schema["required"] as? [String] ?? []).isSubset(of:Set(output.keys)) else { throw fail() };return output
    case "array":
      guard case .array(let values)=value,values.count >= (schema["minItems"] as? Int ?? 0),values.count <= (schema["maxItems"] as? Int ?? 4096),let item=schema["items"] as? [String:Any] else { throw fail() }
      let array=try values.map{try merge($0,schema:item,path:path+"[]")}
      if schema["uniqueItems"] as? Bool == true,let strings=array as? [String],Set(strings).count != strings.count { throw fail() };return array
    case "number","integer":
      guard case .number(let n)=value,n.isFinite,n >= (schema["minimum"] as? Double ?? -Double.greatestFiniteMagnitude),n <= (schema["maximum"] as? Double ?? Double.greatestFiniteMagnitude),schema["type"] as? String != "integer" || n.rounded()==n else { throw fail() };return n
    case "boolean":guard case .bool(let b)=value else { throw fail() };return b
    case "string":
      guard case .string(let s)=value,s.count >= (schema["minLength"] as? Int ?? 0),s.count <= (schema["maxLength"] as? Int ?? 8_400_000) else { throw fail() }
      if let allowed=schema["enum"] as? [String],!allowed.contains(s) { throw fail() };return s
    default:throw fail()
    }
  }
  static func decode(_ value:AutomationValue?,base:Brush)throws->Brush {
    var base=base;base.settings=base.settings ?? .init()
    guard let value else { try BrushPainter.validate(base,points:[]);return base }
    do { let raw=try merge(value,schema:brush,base:json(base));let b=try JSONDecoder().decode(Brush.self,from:JSONSerialization.data(withJSONObject:raw));try BrushPainter.validate(b,points:[]);return b }
    catch let e as AutomationFailure { throw e } catch { throw AutomationFailure(status:400,message:"Invalid brush: \(error.localizedDescription)") }
  }
  static var capabilities:[String:Any] { ["commands":["brush.configure","brush.presets","paint.stroke"],"brushSchema":brush,"pointSchema":point,"presetFormat":"photatobrushes","presetVersion":1,"targets":["pixels","layerMask","smartFilterMask","alpha","quickMask"],"coordinates":"Document pixels; time is milliseconds since stroke start. Optional pressure/tilt in degrees/rotation/wheel. Seed gives reproducible dynamics. Configure patches the current tool; paint snapshots it and creates one Undo step.","limits":"4096 samples per API stroke, 100000 native samples, 200000 generated dabs, 134217728 raster visits; each sparse coverage map at most128MiB. Command body4MiB; inline preset import base64 at most3000000 characters. Native preset files64MiB/512 brushes. API resource limits may be narrower than desktop.","adobe":"No dedicated freehand brush endpoint in the pinned v2 contract. ABR import/export is a native transport subset. Unqualified brush action descriptors/resources currently reject explicitly; this is not a claim of complete execute-actions brush support.","fidelity":"Physical bristle simulation, Photoshop exact pixel kernels, full ABR fields and live tablet qualification remain open."] }
}
@MainActor extension EditorStore {
  var brushState:[String:Any] { ["brush":BrushAPI.json(brush),"selectedPresetID":selectedBrushID?.uuidString as Any? ?? NSNull(),"libraryRevision":brushes.revision,"gestureActive":brushGesture != nil,"loadError":brushes.loadError as Any? ?? NSNull(),"presets":brushes.file.presets.map{["id":$0.id.uuidString,"name":$0.name,"group":$0.group,"includeSize":$0.includeSize,"includeToolSettings":$0.includeToolSettings,"includeColor":$0.includeColor]}] }
}
extension AutomationCommand {
  func brushStroke(document:CraftDocument,current:Brush,library:BrushPresetFile)throws->Command {
    let target=try parameters["target"].map{_ in try string("target")} ?? "pixels"
    var base=current
    if parameters["presetID"] != nil { let id=try actionUUID("presetID");guard let p=library.presets.first(where:{$0.id==id}) else {throw AutomationFailure(status:404,message:"Unknown preset.")};base=p.applying(to:base) }
    let b=try BrushAPI.decode(parameters["brush"],base:base)
    guard let input=parameters["points"] else {throw AutomationFailure(status:400,message:"points required.")}
    let array=try BrushAPI.merge(input,schema:BrushAPI.schema("points")) as! [[String:Any]]
    let points:[StrokePoint]
    do { points=try array.map{raw in var raw=raw;if raw["pressure"]==nil{raw["pressure"]=1};return try JSONDecoder().decode(StrokePoint.self,from:JSONSerialization.data(withJSONObject:raw))};try BrushPainter.validate(b,points:points) }
    catch {throw AutomationFailure(status:400,message:"Invalid stroke: \(error.localizedDescription)")}
    if target=="alpha" || target=="quickMask" {
      guard parameters["layerID"]==nil,target=="alpha" || parameters["channelID"]==nil else {throw AutomationFailure(status:400,message:"Irrelevant stroke target fields.")}
      let plane:ChannelPlaneTarget=target=="quickMask" ? .quickMask:try .alpha(actionUUID("channelID"));return .channel(.stroke(plane,points,b))
    }
    guard parameters["channelID"]==nil,let id=try parameters["layerID"].map({_ in try actionUUID("layerID")}) ?? document.activeLayerID,document.layers.contains(where:{$0.id==id}) else {throw AutomationFailure(status:400,message:"Choose a valid layer target.")}
    switch target {
    case "pixels":
      let layer=document.layers.first{$0.id==id}!
      let ordinary:Bool;if case .raster=layer.content {ordinary=layer.smartObject==nil}else{ordinary=false}
      if !ordinary && !b.erase {return .painting(try PaintingPreparation.prepare(.init(tool:.brush,target:.pixels(id),points:points,brush:b),in:document))}
      return .stroke(id,points,b)
    case "layerMask":return .maskStroke(id,points,b)
    case "smartFilterMask":return .smartFilterMask(id,.maskStroke(id,points,b))
    default:throw AutomationFailure(status:400,message:"Unknown paint target.")
    }
  }
}
extension AutomationService {
  func manageBrushes(_ command:AutomationCommand,store:EditorStore,shareID:UUID)async throws->[String:Any] {
    if command.name=="brush.configure" { store.brush=try BrushAPI.decode(command.parameters["brush"],base:store.brush);return ["state":store.brushState,"revision":revision(store)] }
    let op=try command.string("operation")
    let allowed:[String:Set<String>]=["list":[],"select":["presetID"],"save":["name","group","includeSize","includeToolSettings","includeColor"],"define":["name","group"],"rename":["presetID","name","group"],"delete":["presetID"],"move":["presetID","index"],"import":["data","format"],"export":["presetID","format"]]
    guard let fields=allowed[op],Set(command.parameters.keys).subtracting(["operation"]).isSubset(of:fields) else {throw AutomationFailure(status:400,message:"Unknown or irrelevant brush preset parameter.")}
    func flag(_ key:String,_ fallback:Bool)throws->Bool { guard let v=command.parameters[key] else{return fallback};guard case .bool(let b)=v else{throw AutomationFailure(status:400,message:"\(key) must be boolean.")};return b }
    func format()throws->Bool { guard command.parameters["format"] != nil else{return false};let s=try command.string("format");guard ["abr","photatobrushes"].contains(s) else{throw AutomationFailure(status:400,message:"Unknown brush format.")};return s=="abr" }
    var warnings:[String]=[]
    switch op {
    case "select":try store.selectBrush(command.actionUUID("presetID"))
    case "save":_ = try store.saveBrush(name:command.string("name"),group:command.parameters["group"]==nil ? "My Brushes":command.string("group"),includeSize:flag("includeSize",true),includeToolSettings:flag("includeToolSettings",true),includeColor:flag("includeColor",false))
    case "define":
      let expectedToken=token,expectedRevision=command.revision
      _ = try await store.defineBrush(name:command.string("name"),group:command.parameters["group"]==nil ? "My Brushes":command.string("group")) {
        self.prune()
        guard self.isRunning,self.token==expectedToken,self.shares.contains(where:{$0.id==shareID}),self.revision(store)==expectedRevision else {throw AutomationFailure(status:409,message:"Brush definition cancelled because document sharing or state changed.")}
      }
    case "rename":var p=try store.brushes.preset(command.actionUUID("presetID"));p.name=try command.string("name");if command.parameters["group"] != nil{p.group=try command.string("group")};try store.brushes.save(p)
    case "delete":let id=try command.actionUUID("presetID");try store.brushes.remove(id);if store.selectedBrushID==id{store.selectedBrushID=nil}
    case "move":try store.brushes.move(command.actionUUID("presetID"),to:command.integer("index",range:0...511))
    case "import":
      guard case .string(let text)=command.parameters["data"],text.utf8.count<=3_000_000,let data=Data(base64Encoded:text) else {throw AutomationFailure(status:400,message:"Supply bounded base64 brush data.")};warnings=try store.brushes.importData(data,abr:format())
    case "export":let abr=try format();let id=try command.parameters["presetID"].map{_ in try command.actionUUID("presetID")};return ["state":store.brushState,"revision":revision(store),"format":abr ? "abr":"photatobrushes","data":try store.brushes.exportData(id,abr:abr).base64EncodedString()]
    default:break
    }
    return ["state":store.brushState,"revision":revision(store),"warnings":warnings]
  }
}
