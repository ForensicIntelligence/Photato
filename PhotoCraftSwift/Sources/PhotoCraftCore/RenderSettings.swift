import Foundation

public struct RenderSettings: Codable, Equatable, Sendable {
  public enum Lens: String, Codable, CaseIterable, Sendable {
    case zoom, prime35, prime105, moviePrime
    public var title: String {
      switch self {
      case .zoom: "50–300mm Zoom"
      case .prime35: "35mm Prime"
      case .prime105: "105mm Prime"
      case .moviePrime: "Movie Prime"
      }
    }
  }
  private struct Values: Codable, Equatable, Sendable {
    var seed: UInt32 = 0
    var foreground = Pixel.black
    var background = Pixel.white
    var variance = 16.0
    var strength = 4.0
    var brightness = 100.0
    var centerX = 0.5
    var centerY = 0.5
    var lens = Lens.zoom
  }
  private indirect enum Storage: Equatable, Sendable { case value(Values) }
  private var storage: Storage = .value(Values())
  private var values: Values {
    get { switch storage {case .value(let value):return value} }
    set { storage = .value(newValue) }
  }
  public init(kind: RasterFilter.Kind) {}
  public init(from decoder: Decoder) throws {storage = .value(try Values(from:decoder))}
  public func encode(to encoder: Encoder) throws {try values.encode(to:encoder)}
  public var seed: UInt32 {get {values.seed} set {var v=values;v.seed=newValue;values=v}}
  public var foreground: Pixel {get {values.foreground} set {var v=values;v.foreground=newValue;values=v}}
  public var background: Pixel {get {values.background} set {var v=values;v.background=newValue;values=v}}
  public var variance: Double {get {values.variance} set {var v=values;v.variance=newValue;values=v}}
  public var strength: Double {get {values.strength} set {var v=values;v.strength=newValue;values=v}}
  public var brightness: Double {get {values.brightness} set {var v=values;v.brightness=newValue;values=v}}
  public var centerX: Double {get {values.centerX} set {var v=values;v.centerX=newValue;values=v}}
  public var centerY: Double {get {values.centerY} set {var v=values;v.centerY=newValue;values=v}}
  public var lens: Lens {get {values.lens} set {var v=values;v.lens=newValue;values=v}}
  public static func keys(_ kind: RasterFilter.Kind) -> Set<String> {
    switch kind {
    case .clouds,.differenceClouds: ["seed","foreground","background"]
    case .fibers: ["seed","foreground","background","variance","strength"]
    case .lensFlare: ["brightness","centerX","centerY","lens"]
    default: []
    }
  }
  public func validate(kind: RasterFilter.Kind) throws {
    guard kind.isRender else {throw CraftError.invalid("Render settings require a Render filter.")}
    for p in [foreground,background] {
      guard p.isFinite,[p.r,p.g,p.b,p.a].allSatisfy({(0...1).contains($0)}) else {throw CraftError.invalid("Render color components must be between zero and one.")}
    }
    for (value,range) in [(variance,1.0...64.0),(strength,1.0...64.0),(brightness,10.0...300.0),(centerX,-0.5...1.5),(centerY,-0.5...1.5)] {
      guard value.isFinite,range.contains(value) else {throw CraftError.invalid("Render setting is outside its supported range.")}
    }
  }
  public static func decodeJSON(_ data: Data, kind: RasterFilter.Kind) throws -> Self {
    guard let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(fields.keys).isSubset(of:keys(kind)) else {throw CraftError.invalid("Unknown Render setting.")}
    for key in ["foreground","background"] {
      if let color=fields[key] as? [String:Any],Set(color.keys) != ["r","g","b","a"] {throw CraftError.invalid("Invalid Render color fields.")}
    }
    var complete=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self(kind:kind))) as! [String:Any]
    for (key,value) in fields {complete[key]=value}
    let result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:complete));try result.validate(kind:kind);return result
  }
  public func apiParameters(kind: RasterFilter.Kind) -> [String:Any] {
    ((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:]).filter{Self.keys(kind).contains($0.key)}
  }
  public static func apiSchema(kind: RasterFilter.Kind) -> [String:Any] {
    let defaults=Self(kind:kind).apiParameters(kind:kind);var properties=[String:Any]()
    for key in keys(kind) {
      switch key {
      case "foreground","background": properties[key]=["type":"object","additionalProperties":false,"required":["r","g","b","a"],"properties":Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,["type":"number","minimum":0,"maximum":1] as [String:Any])}),"default":defaults[key]!]
      case "lens": properties[key]=["type":"string","enum":Lens.allCases.map(\.rawValue),"default":defaults[key]!]
      case "seed": properties[key]=["type":"integer","minimum":0,"maximum":Double(UInt32.max),"default":defaults[key]!]
      default:
        let range=key.hasPrefix("center") ? -0.5...1.5:key == "brightness" ? 10.0...300.0:1.0...64.0
        properties[key]=["type":"number","minimum":range.lowerBound,"maximum":range.upperBound,"default":defaults[key]!]
      }
    }
    return ["type":"object","additionalProperties":false,"properties":properties]
  }
  public static var apiCapabilities: [String:Any] {
    ["kinds":RasterFilter.Kind.allCases.filter(\.isRender).map(\.rawValue),"nativeVersion":42,"actionsVersion":14,
     "algorithm":"Licensed PhotoCraft extra_cmds.rs/render.rs translated to native Swift. Deterministic seeds, document-space patterns and bounded generation. Exact Photoshop pixels/defaults and actionJSON/PSD interchange remain unqualified.",
     "colors":"Desktop captures foreground/background. API defaults to opaque black/white; generated Clouds/Fibers are opaque before selection/transparency clipping. Difference Clouds and Lens Flare preserve alpha.",
     "coordinates":"centerX/centerY are normalized document coordinates, including the supported off-canvas range -0.5...1.5. This is the Photato schema, not Adobe's pixel-coordinate descriptor.",
     "targets":"Native generators expand cropped pixel storage within the canvas/selection; existing off-canvas pixels and mask placement are retained. Smart Filters keep their source and captured settings."]
  }
}

extension RasterFilter.Kind {
  public var isRender: Bool {[.clouds,.differenceClouds,.fibers,.lensFlare].contains(self)}
  public var isImmediateRender: Bool {self == .clouds || self == .differenceClouds}
}
