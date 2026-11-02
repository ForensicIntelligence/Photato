import Foundation
import PhotoCraftCore

extension ClassicAdjustment {
  var apiObject: [String: Any] {
    if let e = exposureSettings { return ["kind":"exposure","exposure":e.exposure,"offset":e.offset,"gammaCorrection":e.gammaCorrection] }
    let all = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(self))) as? [String: Any] ?? [:]
    var result = all.filter { kind.parameters.contains($0.key) || $0.key == "kind" }
    if kind == .blackWhite, tint == nil { result["tint"] = NSNull() }
    return result
  }
  static var apiSchema: [String: Any] {
    func integer(_ low: Int, _ high: Int) -> [String: Any] { ["type":"integer","minimum":low,"maximum":high] }
    func array(_ count: Int, _ item: [String: Any]) -> [String: Any] { ["type":"array","minItems":count,"maxItems":count,"items":item] }
    let color: [String: Any] = ["type":"object","additionalProperties":false,"required":["r","g","b","a"],"properties":["r":["type":"number","minimum":0,"maximum":1],"g":["type":"number","minimum":0,"maximum":1],"b":["type":"number","minimum":0,"maximum":1],"a":["const":1]]]
    let fields: [String: Any] = ["exposure":["type":"number","minimum":-20,"maximum":20],"offset":["type":"number","minimum":-0.5,"maximum":0.5],"gammaCorrection":["type":"number","minimum":0.01,"maximum":9.99],"vibrance":integer(-100,100),"saturation":integer(-100,100),"weights":array(6,integer(-200,300)),"tint":["anyOf":[color,["type":"null"]]],"color":color,"density":integer(0,100),"preserveLuminosity":["type":"boolean"],"matrix":array(3,array(4,integer(-200,200))),"monochrome":["type":"boolean"],"relative":["type":"boolean"],"adjustments":array(9,array(4,integer(-100,100)))]
    return ["oneOf":Kind.allCases.map { kind -> [String: Any] in
      var properties = fields.filter { kind.parameters.contains($0.key) }; properties["kind"] = ["const":kind.rawValue]
      return ["type":"object","additionalProperties":false,"required":["kind"],"properties":properties]
    }]
  }
  static func decodeAPI(_ value: Any) throws -> Self {
    do {
      guard let raw = value as? [String: Any], let name = raw["kind"] as? String, let kind = Kind(rawValue:name), Set(raw.keys).isSubset(of:kind.parameters.union(["kind"])) else { throw CraftError.invalid("Unknown adjustment kind or parameters.") }
      if kind == .exposure {
        var fields = ["exposure":Float(0),"offset":Float(0),"gammaCorrection":Float(1)].mapValues { $0 as Any }
        for key in kind.parameters { if let value = raw[key] { fields[key] = value } }
        let settings = try JSONDecoder().decode(ExposureAdjustment.self,from:JSONSerialization.data(withJSONObject:fields))
        try settings.validate(); return .exposure(settings)
      }
      var defaults = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self(kind))) as! [String:Any]
      for (key,value) in raw { defaults[key] = value }
      // JSONDecoder rejects booleans-as-numbers, nonintegral counts and invalid array types.
      let result = try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:defaults))
      try result.validate(); return result
    } catch { throw AutomationFailure(status:400,message:error.localizedDescription) }
  }
  static var apiCapabilities: [String: Any] {
    ["commands":["adjustment.create","adjustment.set","adjustment.apply"],"schema":apiSchema,
      "defaults":Kind.allCases.map { Self($0).apiObject },
      "units":"Exposure uses EV, normalized linear Offset and Gamma Correction; the other kinds use integer percentages. Mixer rows: Red, Green, Blue outputs; columns: Red, Green, Blue inputs, Constant. Selective Color rows: Reds, Yellows, Greens, Cyans, Blues, Magentas, Whites, Neutrals, Blacks; columns: Cyan, Magenta, Yellow, Black. Colors are opaque normalized RGB.",
      "persistence":"Native17 retains existing classic values/masks; complete Exposure requires Native67. Set replaces all settings of the existing kind; unspecified values use defaults. Apply bakes selected pixels as one Undo transaction.",
      "limitations":"RGB composite targets only. PhotoCraft approximation; Photoshop exact transfer, skin protection, Auto and full preset libraries are unqualified."]
  }
}
extension AutomationCommand {
  func classicAdjustmentCommand(document: CraftDocument, lookup: ColorLookupAdjustment? = nil) throws -> Command {
    if let lookup {
      if name == "adjustment.create" { return .addLayer(try lookup.layer(in: document, name: parameters["name"] == nil ? "Color Lookup" : string("name"))) }
      guard let id = UUID(uuidString: try string("layerID")), let layer = document.layers.first(where: { $0.id == id }) else { throw AutomationFailure(status:404,message:"Layer not found.") }
      if name == "adjustment.set" {
        guard case .adjustment(.colorLookup) = layer.content else { throw AutomationFailure(status:422,message:"Adjustment type does not match the layer.") }
        return .replaceContent(id,.adjustment(.colorLookup(lookup)))
      }
      guard case .raster = layer.content, layer.smartObject == nil else { throw AutomationFailure(status:422,message:"Apply requires an ordinary pixel layer.") }
      return .applyAdjustment(id,.colorLookup(lookup))
    }
    guard let raw = parameters["adjustment"] else { throw AutomationFailure(status:400,message:"Missing adjustment.") }
    if let object=raw.jsonValue as? [String:Any],let kind=object["kind"] as? String,ModernAdjustment.Kind(rawValue:kind) != nil {return try modernAdjustmentCommand(document:document,raw:object)}
    if let object=raw.jsonValue as? [String:Any],object["kind"] as? String == "source" {return try sourceAdjustmentCommand(document:document,raw:object)}
    let value = try ClassicAdjustment.decodeAPI(raw.jsonValue)
    if name == "adjustment.create" {
      return .addLayer(try value.layer(in:document,name: parameters["name"] == nil ? nil : string("name")))
    }
    guard let id = UUID(uuidString:try string("layerID")), let layer = document.layers.first(where: { $0.id == id }) else { throw AutomationFailure(status:404,message:"Layer not found.") }
    if name == "adjustment.set" {
      guard case .adjustment(.classic(let old)) = layer.content, old.kind == value.kind else { throw AutomationFailure(status:422,message:"Adjustment type does not match the layer.") }
      return .replaceContent(id,.adjustment(.classic(value)))
    }
    guard case .raster = layer.content, layer.smartObject == nil else { throw AutomationFailure(status:422,message:"Apply requires an ordinary pixel layer.") }
    return .applyAdjustment(id,.classic(value))
  }
}
