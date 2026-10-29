import Foundation

/// Settings for Other/Video workflows; licensed PhotoCraft algorithms, independently qualified.
public struct OtherVideoSettings: Codable, Equatable, Sendable {
  public enum ColorModel:String,Codable,CaseIterable,Sendable {case rgb,hsb,hsl}
  public enum Preserve:String,Codable,CaseIterable,Sendable {case squareness,roundness}
  public enum UndefinedAreas:String,Codable,CaseIterable,Sendable {case wrap,repeatEdge,transparent}
  public enum Field:String,Codable,CaseIterable,Sendable {case odd,even}
  public enum Creation:String,Codable,CaseIterable,Sendable {case duplication,interpolation}
  private struct Values:Codable,Equatable,Sendable {
    var kernel:[Int]=(0..<25).map{$0 == 12 ? 1:0}
    var scale:Double=1
    var offset:Double=0
    var inputMode:ColorModel = .rgb
    var outputMode:ColorModel = .hsb
    var radius:Double=1
    var preserve:Preserve = .squareness
    var horizontal:Int=0
    var vertical:Int=0
    var undefinedAreas:UndefinedAreas = .wrap
    var eliminate:Field = .odd
    var createBy:Creation = .interpolation
  }
  private indirect enum Storage:Equatable,Sendable {case value(Values)}
  private var storage:Storage = .value(Values())
  private var values:Values {get {switch storage {case .value(let v):return v}} set {storage = .value(newValue)}}
  public init() {}
  public init(from decoder:Decoder)throws {storage = .value(try Values(from:decoder))}
  public func encode(to encoder:Encoder)throws {try values.encode(to:encoder)}
  public var kernel:[Int] {get {values.kernel} set {var v=values;v.kernel=newValue;values=v}}
  public var scale:Double {get {values.scale} set {var v=values;v.scale=newValue;values=v}}
  public var offset:Double {get {values.offset} set {var v=values;v.offset=newValue;values=v}}
  public var inputMode:ColorModel {get {values.inputMode} set {var v=values;v.inputMode=newValue;values=v}}
  public var outputMode:ColorModel {get {values.outputMode} set {var v=values;v.outputMode=newValue;values=v}}
  public var radius:Double {get {values.radius} set {var v=values;v.radius=newValue;values=v}}
  public var preserve:Preserve {get {values.preserve} set {var v=values;v.preserve=newValue;values=v}}
  public var horizontal:Int {get {values.horizontal} set {var v=values;v.horizontal=newValue;values=v}}
  public var vertical:Int {get {values.vertical} set {var v=values;v.vertical=newValue;values=v}}
  public var undefinedAreas:UndefinedAreas {get {values.undefinedAreas} set {var v=values;v.undefinedAreas=newValue;values=v}}
  public var eliminate:Field {get {values.eliminate} set {var v=values;v.eliminate=newValue;values=v}}
  public var createBy:Creation {get {values.createBy} set {var v=values;v.createBy=newValue;values=v}}
  public static func keys(_ kind:RasterFilter.Kind)->Set<String> {
    switch kind {
    case .customFilter:["kernel","scale","offset"]
    case .hsbHsl:["inputMode","outputMode"]
    case .maximum,.minimum:["radius","preserve"]
    case .offset:["horizontal","vertical","undefinedAreas"]
    case .deInterlace:["eliminate","createBy"]
    default:[]
    }
  }
  public func validate(kind:RasterFilter.Kind)throws {
    guard kind.isOtherVideo,kernel.count==25,kernel.allSatisfy({(-999...999).contains($0)}),
      scale.isFinite,(1...9999).contains(scale),offset.isFinite,(-9999...9999).contains(offset),
      radius.isFinite,(0.2...500).contains(radius),(-600_000...600_000).contains(horizontal),(-600_000...600_000).contains(vertical),
      ![RasterFilter.Kind.maximum,.minimum].contains(kind) || preserve == .roundness || (radius>=1 && radius.rounded()==radius)
    else {throw CraftError.invalid("Invalid Other/Video filter settings.")}
  }
  public static func decodeJSON(_ data:Data,kind:RasterFilter.Kind)throws->Self {
    guard data.count<=16_384,let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(fields.keys).isSubset(of:keys(kind)) else {throw CraftError.invalid("Unknown Other/Video setting.")}
    var complete=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    for (k,v) in fields {complete[k]=v}
    let value=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:complete));try value.validate(kind:kind);return value
  }
  public func apiParameters(kind:RasterFilter.Kind)->[String:Any] {
    ((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:]).filter{Self.keys(kind).contains($0.key)}
  }
  public static func apiSchema(kind:RasterFilter.Kind)->[String:Any] {
    let defaults=Self().apiParameters(kind:kind);var p=[String:Any]()
    for k in keys(kind) {
      var v:[String:Any]
      switch k {
      case "kernel":v=["type":"array","minItems":25,"maxItems":25,"items":["type":"integer","minimum":-999,"maximum":999]]
      case "inputMode","outputMode":v=["type":"string","enum":ColorModel.allCases.map(\.rawValue)]
      case "preserve":v=["type":"string","enum":Preserve.allCases.map(\.rawValue)]
      case "undefinedAreas":v=["type":"string","enum":UndefinedAreas.allCases.map(\.rawValue)]
      case "eliminate":v=["type":"string","enum":Field.allCases.map(\.rawValue)]
      case "createBy":v=["type":"string","enum":Creation.allCases.map(\.rawValue)]
      case "radius":v=["type":"number","minimum":0.2,"maximum":500,"description":"Squareness requires an integer1–500; Roundness supports0.2–500. Source disc below1 pixel is unchanged; exact Adobe fractional morphology remains unqualified."]
      case "scale":v=["type":"number","minimum":1,"maximum":9999]
      case "offset":v=["type":"number","minimum":-9999,"maximum":9999]
      default:v=["type":"integer","minimum":-600000,"maximum":600000,"description":"Also bounded to twice the document width/height at execution."]
      };v["default"]=defaults[k];p[k]=v
    }
    return ["type":"object","additionalProperties":false,"properties":p]
  }
  public static var apiCapabilities:[String:Any] {
    ["kinds":RasterFilter.Kind.allCases.filter(\.isOtherVideo).map(\.rawValue),"nativeVersion":43,"actionsVersion":16,
     "algorithm":"PhotoCraft other.rs/other2.rs/video.rs translated to Swift. Exact Photoshop output/defaults and Adobe ActionJSON/PSD descriptor interchange remain unqualified.",
     "customPreset":"UTF-8 Photato JSON containing kind:customFilter and otherVideo settings. Desktop Save/Load uses the same strict payload as filter.apply. Adobe ACF interchange remains open.",
     "coordinates":"Document pixels. Offset wraps/repeats/clears within selection bounds or canvas. De-Interlace counts odd/even rows from that bounds top (one-based). Cropped storage expands while retaining mask placement and off-canvas pixels.",
     "limits":"8,388,608 pixels; Roundness work bounded to268,435,456 row-window samples. RGB8/16 encoded and RGB32 linear processing. HSB/HSL clamps input channels to0–1 as in original source; original all-zero Custom is a no-op."]
  }
  public func encodedCustomPreset()throws->Data {
    try validate(kind:.customFilter)
    return try JSONSerialization.data(withJSONObject:["kind":"customFilter","otherVideo":apiParameters(kind:.customFilter)],options:[.prettyPrinted,.sortedKeys])
  }
  public static func decodeCustomPreset(_ data:Data)throws->Self {
    guard data.count<=16_384 else {throw CraftError.invalid("Custom preset exceeds16KiB.")}
    let f=try RasterFilter.decodeJSON(data);guard f.kind == .customFilter,let s=f.otherVideo else {throw CraftError.invalid("Choose a Photato Custom filter preset.")};return s
  }
}
extension RasterFilter.Kind {
  public var isOtherVideo:Bool {[.customFilter,.hsbHsl,.maximum,.minimum,.offset,.deInterlace,.ntscColors].contains(self)}
}
