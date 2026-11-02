import Foundation

/// Closed nested schemas for newly editable style records. Codable supplies the
/// numeric/enum/shape validation; unknown fields never disappear on an API edit.
enum AdvancedEffectJSON {
  static func object(_ value:Any,_ keys:Set<String>)throws->[String:Any] {
    guard let fields=value as? [String:Any],Set(fields.keys).isSubset(of:keys) else {throw CraftError.invalid("Unknown or invalid advanced effect field.")};return fields
  }
  static func keys<T:Encodable>(_ value:T)throws->Set<String> {
    Set((try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) as! [String:Any]).keys)
  }
  static func point(_ value:Any)throws {_ = try object(value,["x","y"])}
  static func color(_ value:Any)throws {_ = try object(value,["r","g","b","a"])}
  static func contour(_ value:Any)throws {_ = try object(value,["name","points"])}
  static func pattern(_ value:Any)throws {
    let v=try object(value,["patternID","sourceName","sourceID","scale","angle","linked","phase"])
    if let phase=v["phase"] {try point(phase)}
  }
  static func gradient(_ value:Any)throws {
    let v=try object(value,["stops","opacityStops","placement","aligned","dither"])
    if let placement=v["placement"] {_ = try object(placement,keys(GradientPlacement()))}
    if let stops=v["stops"] {
      guard let stops=stops as? [Any] else {throw CraftError.invalid("Invalid effect gradient stops.")}
      for stop in stops {let row=try object(stop,["location","color"]);if let c=row["color"]{try color(c)}}
    }
  }
  static func validate(_ value:Any)throws {
    if value is NSNull {return}
    let v=try object(value,keys(LayerEffectAdvanced()).union(["bevelContour","texture","paint"]))
    for key in ["contour","glossContour"] {if let c=v[key] {try contour(c)}}
    if let c=v["bevelContour"],!(c is NSNull) {let fields=try object(c,["contour","range","antiAlias"]);if let c=fields["contour"]{try contour(c)}}
    if let t=v["texture"],!(t is NSNull) {let fields=try object(t,["pattern","depth","inverted"]);if let p=fields["pattern"]{try pattern(p)}}
    if let p=v["paint"],!(p is NSNull) {
      let fields=try object(p,["kind","gradient","pattern"])
      if let g=fields["gradient"],!(g is NSNull){try gradient(g)}
      if let p=fields["pattern"],!(p is NSNull){try pattern(p)}
    }
  }
}
