import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension FrameDefinition {
  var apiState: Any { (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) ?? NSNull() }
  static var apiSchema: [String: Any] {
    let point: [String: Any] = ["type":"object", "additionalProperties":false, "required":["x","y"], "properties":Dictionary(uniqueKeysWithValues:["x","y"].map { ($0,["type":"number","minimum":-10,"maximum":10] as [String:Any]) })]
    let knot: [String: Any] = ["type":"object", "additionalProperties":false, "required":["anchor","incoming","outgoing","smooth"], "properties":["anchor":point,"incoming":point,"outgoing":point,"smooth":["type":"boolean"]]]
    let component: [String: Any] = ["type":"object", "additionalProperties":false, "required":["knots","closed","operation"], "properties":["knots":["type":"array","maxItems":4096,"items":knot],"closed":["const":true],"operation":["type":"string","enum":PathOperation.allCases.map(\.rawValue)]]]
    let path: [String: Any] = ["type":"object", "additionalProperties":false,"required":["components","fillRule","inverted"],"properties":["fillRule":["type":"string","enum":PathFillRule.allCases.map(\.rawValue)],"components":["type":"array","minItems":1,"maxItems":256,"items":component],"inverted":["const":false]]]
    return ["type":"object","additionalProperties":false,"required":["width","height"],"properties":[
      "width":["type":"integer","minimum":1,"maximum":32768],"height":["type":"integer","minimum":1,"maximum":32768],
      "shape":["type":"string","enum":Shape.allCases.map(\.rawValue),"default":"rectangle"],"sides":["type":"integer","minimum":3,"maximum":64,"default":5],
      "customPath":path,"strokeWidth":["type":"number","minimum":0,"maximum":1000,"default":0],"strokeColor":AutomationCommand.artboardSchema("background"),"strokeAlignment":["type":"string","enum":Alignment.allCases.map(\.rawValue),"default":"inside"]]]
  }
  static var apiCapabilities: [String: Any] {
    ["commands":["frame.edit","frame.place"],"nativeArchiveVersion":28,"definitionSchema":apiSchema,
     "operations":["create","fromLayers","convert","configure","transform","contents.transform","fit","clear"],
     "coordinates":"Physical document pixels; custom paths are normalized to the frame dimensions. Transform is a delta in document coordinates. Content transforms retain embedded source bytes.",
     "placement":"frame.place replaces children with an embedded snapshot from an explicitly shared sourceDocumentID/sourceRevision. fill covers the frame, fit contains the image, original uses source pixels. Each operation is one native Undo.",
     "limits":"4,194,304 pixels/64 layers/128MiB per shared document, 64MiB/8MP per Smart Object. Editable PSD frames, linked contents and generative frame fill are not supported. No dedicated frame route in the pinned Adobe v2 contract."]
  }
}
extension AutomationCommand {
  static func frameSchema(_ key: String) -> [String: Any] {
    switch key {
    case "operation": return ["type":"string","enum":["create","fromLayers","convert","configure","transform","contents.transform","fit","clear"]]
    case "definition": return FrameDefinition.apiSchema
    case "fit": return ["type":"string","enum":FrameFit.allCases.map(\.rawValue),"default":"fill"]
    case "contents": return ["type":"boolean","default":true]
    case "sourceDocumentID": return ["type":"string","format":"uuid"]
    case "sourceRevision": return ["type":"string","minLength":1]
    case "transform": return ["type":"object","additionalProperties":false,"required":["a","b","c","d","tx","ty"],"properties":Dictionary(uniqueKeysWithValues:["a","b","c","d","tx","ty"].map { ($0,["type":"number","minimum":-1_000_000,"maximum":1_000_000] as [String:Any]) })]
    default: return artboardSchema(key)
    }
  }
  func frameFit() throws -> FrameFit {
    guard let value = parameters["fit"] else { return .fill }
    guard case .string(let string) = value, let fit = FrameFit(rawValue:string) else { throw AutomationFailure(status:400,message:"Unknown frame fit.") }; return fit
  }
  func frameDefinition() throws -> FrameDefinition {
    guard case .object(let fields) = parameters["definition"], Set(fields.keys).isSubset(of:["width","height","shape","sides","customPath","strokeWidth","strokeColor","strokeAlignment"]) else { throw AutomationFailure(status:400,message:"Invalid frame definition fields.") }
    var object: [String:Any] = ["shape":"rectangle","sides":5,"strokeWidth":0,"strokeColor":["r":0,"g":0,"b":0,"a":1],"strokeAlignment":"inside"]
    for (key,value) in fields { object[key] = value.jsonValue }
    do {
      let result = try JSONDecoder().decode(FrameDefinition.self,from:JSONSerialization.data(withJSONObject:object))
      try result.validate()
      // Reject silently ignored nested keys, including custom vector geometry.
      let canonical = try JSONSerialization.jsonObject(with:JSONEncoder().encode(result))
      func known(_ value: Any, _ template: Any) -> Bool {
        if let dict = value as? [String:Any], let expected = template as? [String:Any] { return dict.allSatisfy { key,v in expected[key].map { known(v,$0) } ?? false } }
        if let array = value as? [Any], let expected = template as? [Any] { return array.count == expected.count && zip(array,expected).allSatisfy { known($0.0,$0.1) } }
        return true
      }
      guard known(object,canonical) else { throw CraftError.invalid("Unknown frame geometry fields.") };return result
    } catch { throw AutomationFailure(status:400,message:"Invalid frame definition: \(error.localizedDescription)") }
  }
  func frameCommand(_ document: CraftDocument) throws -> Command {
    let op = try string("operation"), required: Set<String>, optional: Set<String>
    switch op {
    case "create": required = ["name","bounds","definition"]; optional = ["layerIDs"]
    case "fromLayers": required = ["name","layerIDs"]; optional = []
    case "configure": required = ["layerID","definition"]; optional = []
    case "transform": required = ["layerID","transform"]; optional = ["contents"]
    case "contents.transform": required = ["layerID","transform"]; optional = []
    case "fit": required = ["layerID"]; optional = ["fit"]
    case "convert","clear": required = ["layerID"]; optional = []
    default: throw AutomationFailure(status:400,message:"Unknown frame operation.")
    }
    let keys = Set(parameters.keys).subtracting(["operation"])
    guard required.isSubset(of:keys), keys.isSubset(of:required.union(optional)) else { throw AutomationFailure(status:400,message:"Missing or irrelevant frame parameters.") }
    if op == "fromLayers" { return try FrameRenderer.fromLayers(artboardIDs(),name:string("name"),in:document) }
    if op == "create" {
      guard case .object(let fields) = parameters["bounds"], Set(fields.keys) == ["x","y","width","height"] else { throw AutomationFailure(status:400,message:"bounds requires x,y,width,height.") }
      func integer(_ key:String) throws -> Int { guard case .number(let value) = fields[key],value.isFinite,value.rounded() == value,abs(value) <= 1_000_000 else { throw AutomationFailure(status:400,message:"Invalid bounds.") }; return Int(value) }
      return try .frame(.create(name:string("name"),bounds:.init(x:integer("x"),y:integer("y"),width:integer("width"),height:integer("height")),definition:frameDefinition(),children:parameters["layerIDs"] == nil ? [] : artboardIDs()))
    }
    let id = try actionUUID("layerID")
    guard document.layers.contains(where: { $0.id == id }) else { throw AutomationFailure(status:404,message:"Layer not found.") }
    if op == "convert" { return try FrameRenderer.conversion(id,in:document) }
    if op == "configure" { return try .frame(.configure(id,frameDefinition())) }
    if op == "clear" { return .frame(.clear(id)) }
    if op == "fit" { return try .frame(.fit(id,frameFit())) }
    guard case .object(let fields) = parameters["transform"], Set(fields.keys) == ["a","b","c","d","tx","ty"] else { throw AutomationFailure(status:400,message:"Transform requires a,b,c,d,tx,ty.") }
    let numbers = try ["a","b","c","d","tx","ty"].map { key -> Double in guard case .number(let n) = fields[key],n.isFinite,abs(n) <= 1_000_000 else { throw AutomationFailure(status:400,message:"Invalid transform component.") }; return n }
    let t = Transform2D(a:numbers[0],b:numbers[1],c:numbers[2],d:numbers[3],tx:numbers[4],ty:numbers[5]);try t.validated()
    if op == "contents.transform" { return .frame(.transformContents(id,t)) }
    var contents = true
    if let value = parameters["contents"] { guard case .bool(let b) = value else { throw AutomationFailure(status:400,message:"contents must be boolean.") }; contents = b }
    return .frame(.transform(id,t,contents:contents))
  }
}
