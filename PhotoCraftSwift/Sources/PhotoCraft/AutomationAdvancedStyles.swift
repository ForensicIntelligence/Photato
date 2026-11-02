import Foundation
import PhotoCraftCore

enum AdvancedStyleAPI {
  static let commands:Set<String>=["layer.style","layer.style.patch","document.globalLight"]
  static func nullable(_ schema:[String:Any])->[String:Any]{var s=schema;s["type"]=["object","null"];return s}
  static func number(_ low:Double,_ high:Double)->[String:Any]{["type":"number","minimum":low,"maximum":high]}
  static func object(_ properties:[String:Any],required:[String]=[])->[String:Any]{["type":"object","additionalProperties":false,"properties":properties,"required":required]}
  static var point:[String:Any] {object(["x":number(-1e9,1e9),"y":number(-1e9,1e9)],required:["x","y"])}
  static var light:[String:Any] {object(["angle":number(-360,360),"altitude":number(0,90)],required:["angle","altitude"])}
  static var contour:[String:Any] {object(["name":["type":"string","maxLength":2048],"points":["type":"array","maxItems":256,"items":["type":"array","minItems":2,"maxItems":2,"items":number(0,1)]]],required:["name","points"])}
  static var pattern:[String:Any] {object(["patternID":["type":["string","null"],"maxLength":1024],"sourceID":["type":["string","null"],"maxLength":4096],"sourceName":["type":["string","null"],"maxLength":4096],"scale":number(0,100),"angle":number(-360,360),"linked":["type":"boolean"],"phase":point],required:["scale","angle","linked","phase"])}
  static var gradient:[String:Any] {
    let color=object(["r":number(0,1),"g":number(0,1),"b":number(0,1),"a":number(0,1)],required:["r","g","b","a"])
    let placement=object(["style":["type":"string","enum":GradientStyle.allCases.map(\.rawValue)],"angle":number(-360,360),"scale":number(0,100),"reverse":["type":"boolean"],"offsetX":number(-100,100),"offsetY":number(-100,100)],required:["style","angle","scale","reverse","offsetX","offsetY"])
    return object(["stops":["type":"array","maxItems":4096,"items":object(["location":number(0,1),"color":color],required:["location","color"])],"opacityStops":["type":"array","maxItems":4096,"items":["type":"array","minItems":2,"maxItems":2,"items":number(0,1)]],"placement":placement,"aligned":["type":"boolean"],"dither":["type":"boolean"]],required:["stops","opacityStops","placement","aligned","dither"])
  }
  static var defaults:[String:Any] {(try? JSONSerialization.jsonObject(with:JSONEncoder().encode(LayerEffectAdvanced()))) as? [String:Any] ?? [:]}
  static var advanced:[String:Any] {
    var p:[String:Any]=[:]
    for key in ["antiAlias","knocksOut","satinInverted","directionUp","highlightEnabled","shadowEnabled"]{p[key]=["type":"boolean"]}
    for key in ["noise","range","jitter"]{p[key]=number(0,1)}
    for key in ["contour","glossContour"]{p[key]=contour}
    p["altitude"]=number(0,90);p["glowTechnique"]=["type":"string","enum":LayerEffectAdvanced.GlowTechnique.allCases.map(\.rawValue)];p["glowSource"]=["type":"string","enum":LayerEffectAdvanced.GlowSource.allCases.map(\.rawValue)]
    p["bevelStyle"]=["type":"string","enum":LayerEffectAdvanced.BevelStyle.allCases.map(\.rawValue)];p["bevelTechnique"]=["type":"string","enum":LayerEffectAdvanced.BevelTechnique.allCases.map(\.rawValue)]
    for key in ["highlightBlendMode","shadowBlendMode"]{p[key]=["type":"string","enum":BlendMode.allCases.map(\.rawValue)]}
    p["bevelContour"]=object(["contour":contour,"range":number(0,1),"antiAlias":["type":"boolean"]],required:["contour","range","antiAlias"])
    p["texture"]=object(["pattern":pattern,"depth":number(-10,10),"inverted":["type":"boolean"]],required:["pattern","depth","inverted"])
    p["paint"]=object(["kind":["type":"string","enum":EffectPaint.Kind.allCases.map(\.rawValue)],"gradient":gradient,"pattern":pattern],required:["kind"])
    for key in ["bevelContour","texture","paint"] {p[key]=nullable(p[key] as! [String:Any])}
    return object(p,required:Array(defaults.keys).sorted())
  }
  static func schema(_ key:String)->[String:Any] {
    switch key {
    case "style":return LayerStyle.apiSchema
    case "globalLight":return light
    case "angle":return number(-360,360)
    case "altitude":return number(0,90)
    case "layerIDs":return ["type":"array","minItems":1,"maxItems":LayerLimits.maximumLayers,"uniqueItems":true,"items":["type":"string","format":"uuid"]]
    case "effectIndex":return ["type":"integer","minimum":0,"maximum":31]
    case "effect":let properties=LayerStyle.apiSchema["properties"] as! [String:Any],effects=properties["effects"] as! [String:Any];return partial(effects["items"] as! [String:Any])
    case "patch":var schema=partial(LayerStyle.apiSchema);schema["type"]="object";return schema
    default:return [:]
    }
  }
  static func partial(_ schema:[String:Any])->[String:Any] {
    var result=schema;if (schema["type"] as? [String])?.contains("null") != true {result["type"]="object"};result.removeValue(forKey:"required")
    if var properties=result["properties"] as? [String:Any] {
      for(key,value)in properties {if let object=value as? [String:Any],object["properties"] != nil {properties[key]=partial(object)}}
      result["properties"]=properties
    }
    return result
  }
  static func readLight(_ value:AutomationValue?)throws->GlobalLight? {
    guard let value else{return nil}
    do {
      guard case .object(let fields)=value,Set(fields.keys)==["angle","altitude"] else{throw CraftError.invalid("Provide angle and altitude only.")}
      let result=try JSONDecoder().decode(GlobalLight.self,from:JSONSerialization.data(withJSONObject:value.jsonValue));try result.validate();return result
    }catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
  }
  static func merge(_ base:[String:Any],_ patch:[String:Any])->[String:Any] {
    var result=base
    for(key,value)in patch {if let object=value as? [String:Any],let existing=result[key] as? [String:Any]{result[key]=merge(existing,object)}else{result[key]=value}}
    return result
  }
}
extension AutomationCommand {
  func advancedStyleCommand(document:CraftDocument)throws->Command {
    if name=="document.globalLight" {return .globalLight(try requestedGlobalLight())}
    guard case .array(let values)=parameters["layerIDs"],(1...LayerLimits.maximumLayers).contains(values.count) else{throw AutomationFailure(status:400,message:"Choose one to8,000 layerIDs.")}
    let ids=try values.map{value -> UUID in guard case .string(let text)=value,let id=UUID(uuidString:text)else{throw AutomationFailure(status:400,message:"Invalid layer UUID.")};return id}
    guard Set(ids).count==ids.count else{throw AutomationFailure(status:400,message:"Duplicate layer UUID.")}
    let light=try AdvancedStyleAPI.readLight(parameters["globalLight"])
    let patch:[String:Any]
    if let value=parameters["patch"] {guard case .object = value,let p=value.jsonValue as? [String:Any]else{throw AutomationFailure(status:400,message:"Style patch must be an object.")};patch=p}else{patch=[:]}
    var effectIndex:Int?,effectPatch:[String:Any]?
    if let index=parameters["effectIndex"] {
      guard case .number(let n)=index,n.isFinite,n.rounded()==n,(0...31).contains(n),let value=parameters["effect"],case .object = value,let p=value.jsonValue as? [String:Any] else{throw AutomationFailure(status:400,message:"Provide effectIndex and an effect object together.")};effectIndex=Int(n);effectPatch=p
    }else if parameters["effect"] != nil {throw AutomationFailure(status:400,message:"Missing effectIndex.")}
    guard !patch.isEmpty || effectPatch != nil || light != nil else{throw AutomationFailure(status:400,message:"The style patch is empty.")}
    var styles:[UUID:LayerStyle?]=[:]
    for id in ids {
      guard let layer=document.layers.first(where:{$0.id==id})else{throw AutomationFailure(status:404,message:"Layer not found.")}
      do {
        var object=AdvancedStyleAPI.merge((layer.style ?? LayerStyle()).apiObject as! [String:Any],patch)
        if let index=effectIndex,let patch=effectPatch {guard var effects=object["effects"] as? [[String:Any]],effects.indices.contains(index)else{throw CraftError.invalid("Effect index is absent from a target style.")};effects[index]=AdvancedStyleAPI.merge(effects[index],patch);object["effects"]=effects}
        let style=try LayerStyle.decodeJSON(JSONSerialization.data(withJSONObject:object));try style.validate(in:document);styles.updateValue(style,forKey:id)
      }catch{throw AutomationFailure(status:400,message:error.localizedDescription)}
    }
    return .layerStyles(LayerStyleEdit(styles:styles,globalLight:light))
  }
  private func requestedGlobalLight()throws->GlobalLight {
    guard let angle=parameters["angle"],let altitude=parameters["altitude"],let light=try AdvancedStyleAPI.readLight(.object(["angle":angle,"altitude":altitude]))else{throw AutomationFailure(status:400,message:"Missing shared light.")};return light
  }
}
