import Foundation

public struct StylizeSettings: Codable, Equatable, Sendable {
  public enum DiffuseMode:String,Codable,CaseIterable,Sendable { case normal,darkenOnly,lightenOnly,anisotropic
    public var title:String { switch self {case .normal:"Normal";case .darkenOnly:"Darken Only";case .lightenOnly:"Lighten Only";case .anisotropic:"Anisotropic"} }
  }
  public enum ExtrudeType:String,Codable,CaseIterable,Sendable {case blocks,pyramids;public var title:String {rawValue.capitalized}}
  public enum DepthMode:String,Codable,CaseIterable,Sendable {case random,levelBased;public var title:String {self == .random ? "Random":"Level-based"}}
  public enum TileFill:String,Codable,CaseIterable,Sendable {case background,foreground,inverse,unaltered
    public var title:String {switch self {case .background:"Background Color";case .foreground:"Foreground Color";case .inverse:"Inverse Image";case .unaltered:"Unaltered Image"}}
  }
  public enum ContourEdge:String,Codable,CaseIterable,Sendable {case lower,upper;public var title:String {rawValue.capitalized}}
  public enum WindMethod:String,Codable,CaseIterable,Sendable {case wind,blast,stagger;public var title:String {rawValue.capitalized}}
  public enum WindDirection:String,Codable,CaseIterable,Sendable {case fromRight,fromLeft;public var title:String {self == .fromRight ? "From the Right":"From the Left"}}
  private struct Values:Codable,Equatable,Sendable {
    var mode=DiffuseMode.normal;var seed:UInt32=0
    var angle=135.0;var height=3.0;var amount=100.0
    var type=ExtrudeType.blocks;var size=30.0;var depth=30.0;var depthMode=DepthMode.random
    var solidFrontFaces=false;var maskIncompleteBlocks=false
    var stylization=4.0;var cleanliness=5.0;var scale=1.0;var bristleDetail=5.0;var lighting=true;var shine=1.0
    var count=10.0;var maxOffset=10.0;var fill=TileFill.background;var foreground=Pixel.black;var background=Pixel.white
    var level=128.0;var edge=ContourEdge.lower
    var method=WindMethod.wind;var direction=WindDirection.fromRight
  }
  private indirect enum Storage:Equatable,Sendable {case value(Values)}
  private var storage:Storage = .value(Values())
  private var values:Values {get {switch storage {case .value(let v):return v}} set {storage = .value(newValue)}}
  public init(kind:RasterFilter.Kind) {if kind == .oilPaint {angle = -60}}
  public init(from decoder:Decoder)throws {storage = .value(try Values(from:decoder))}
  public func encode(to encoder:Encoder)throws {try values.encode(to:encoder)}
  public var mode:DiffuseMode { get {values.mode} set {var v=values;v.mode=newValue;values=v} }
  public var seed:UInt32 { get {values.seed} set {var v=values;v.seed=newValue;values=v} }
  public var angle:Double { get {values.angle} set {var v=values;v.angle=newValue;values=v} }
  public var height:Double { get {values.height} set {var v=values;v.height=newValue;values=v} }
  public var amount:Double { get {values.amount} set {var v=values;v.amount=newValue;values=v} }
  public var type:ExtrudeType { get {values.type} set {var v=values;v.type=newValue;values=v} }
  public var size:Double { get {values.size} set {var v=values;v.size=newValue;values=v} }
  public var depth:Double { get {values.depth} set {var v=values;v.depth=newValue;values=v} }
  public var depthMode:DepthMode { get {values.depthMode} set {var v=values;v.depthMode=newValue;values=v} }
  public var solidFrontFaces:Bool { get {values.solidFrontFaces} set {var v=values;v.solidFrontFaces=newValue;values=v} }
  public var maskIncompleteBlocks:Bool { get {values.maskIncompleteBlocks} set {var v=values;v.maskIncompleteBlocks=newValue;values=v} }
  public var stylization:Double { get {values.stylization} set {var v=values;v.stylization=newValue;values=v} }
  public var cleanliness:Double { get {values.cleanliness} set {var v=values;v.cleanliness=newValue;values=v} }
  public var scale:Double { get {values.scale} set {var v=values;v.scale=newValue;values=v} }
  public var bristleDetail:Double { get {values.bristleDetail} set {var v=values;v.bristleDetail=newValue;values=v} }
  public var lighting:Bool { get {values.lighting} set {var v=values;v.lighting=newValue;values=v} }
  public var shine:Double { get {values.shine} set {var v=values;v.shine=newValue;values=v} }
  public var count:Double { get {values.count} set {var v=values;v.count=newValue;values=v} }
  public var maxOffset:Double { get {values.maxOffset} set {var v=values;v.maxOffset=newValue;values=v} }
  public var fill:TileFill { get {values.fill} set {var v=values;v.fill=newValue;values=v} }
  public var foreground:Pixel { get {values.foreground} set {var v=values;v.foreground=newValue;values=v} }
  public var background:Pixel { get {values.background} set {var v=values;v.background=newValue;values=v} }
  public var level:Double { get {values.level} set {var v=values;v.level=newValue;values=v} }
  public var edge:ContourEdge { get {values.edge} set {var v=values;v.edge=newValue;values=v} }
  public var method:WindMethod { get {values.method} set {var v=values;v.method=newValue;values=v} }
  public var direction:WindDirection { get {values.direction} set {var v=values;v.direction=newValue;values=v} }
  public static func keys(_ kind:RasterFilter.Kind)->Set<String> {
    switch kind {
    case .diffuse:["mode","seed"]
    case .emboss:["angle","height","amount"]
    case .extrude:["type","size","depth","depthMode","solidFrontFaces","maskIncompleteBlocks","seed"]
    case .oilPaint:["stylization","cleanliness","scale","bristleDetail","lighting","angle","shine"]
    case .tiles:["count","maxOffset","fill","foreground","background","seed"]
    case .traceContour:["level","edge"]
    case .wind:["method","direction","seed"]
    default:[]
    }
  }
  public func validate(kind:RasterFilter.Kind)throws {
    guard kind.isStylize else {throw CraftError.invalid("Stylize settings require a Stylize filter.")}
    func number(_ v:Double,_ r:ClosedRange<Double>,integer:Bool=true)throws {guard v.isFinite,r.contains(v),!integer || v.rounded()==v else {throw CraftError.invalid("Invalid Stylize numeric setting.")}}
    try number(angle,kind == .oilPaint ? -360...360 : -180...180)
    try number(height,1...100);try number(amount,1...500);try number(size,2...255);try number(depth,1...255)
    for v in [stylization,cleanliness,scale,bristleDetail,shine] {try number(v,0...10,integer:false)}
    try number(count,1...99);try number(maxOffset,1...99);try number(level,0...255)
    for p in [foreground,background] {guard p.isFinite,[p.r,p.g,p.b,p.a].allSatisfy({(0...1).contains($0)}) else {throw CraftError.invalid("Stylize colors require RGBA values between zero and one.")}}
  }
  public static func decodeJSON(_ data:Data,kind:RasterFilter.Kind)throws->Self {
    guard let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(fields.keys).isSubset(of:keys(kind)) else {throw CraftError.invalid("Unknown Stylize setting.")}
    for name in ["foreground","background"] {if let bg=fields[name] as? [String:Any],Set(bg.keys) != ["r","g","b","a"] {throw CraftError.invalid("Invalid Stylize color fields.")}}
    var complete=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self(kind:kind))) as! [String:Any]
    for (key,value) in fields {complete[key]=value}
    let result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:complete));try result.validate(kind:kind);return result
  }
  public func apiParameters(kind:RasterFilter.Kind)->[String:Any] {((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:]).filter{Self.keys(kind).contains($0.key)}}
  public static func apiSchema(kind:RasterFilter.Kind)->[String:Any] {
    let defaults=Self(kind:kind).apiParameters(kind:kind);var properties=[String:Any]()
    let enums:[String:[String]]=["mode":DiffuseMode.allCases.map(\.rawValue),"type":ExtrudeType.allCases.map(\.rawValue),"depthMode":DepthMode.allCases.map(\.rawValue),"fill":TileFill.allCases.map(\.rawValue),"edge":ContourEdge.allCases.map(\.rawValue),"method":WindMethod.allCases.map(\.rawValue),"direction":WindDirection.allCases.map(\.rawValue)]
    for key in keys(kind) {
      var schema:[String:Any]
      if let values=enums[key] {schema=["type":"string","enum":values]}
      else if ["lighting","solidFrontFaces","maskIncompleteBlocks"].contains(key) {schema=["type":"boolean"]}
      else if ["foreground","background"].contains(key) {schema=["type":"object","additionalProperties":false,"required":["r","g","b","a"],"properties":Dictionary(uniqueKeysWithValues:["r","g","b","a"].map{($0,["type":"number","minimum":0,"maximum":1])})]}
      else {
        let range:ClosedRange<Double>
        switch key {case "angle":range=kind == .oilPaint ? -360...360 : -180...180;case "height":range=1...100;case "amount":range=1...500;case "size":range=2...255;case "depth":range=1...255;case "count","maxOffset":range=1...99;case "level":range=0...255;case "seed":range=0...Double(UInt32.max);default:range=0...10}
        schema=["type":["stylization","cleanliness","scale","bristleDetail","shine"].contains(key) ? "number":"integer","minimum":range.lowerBound,"maximum":range.upperBound]
      }
      schema["default"]=defaults[key];properties[key]=schema
    }
    return ["type":"object","additionalProperties":false,"properties":properties]
  }
  public static var apiCapabilities:[String:Any] {
    ["kinds":RasterFilter.Kind.allCases.filter(\.isStylize).map(\.rawValue),"nativeVersion":41,"actionsVersion":13,"algorithm":"Licensed PhotoCraft Stylize/Oil Paint algorithms translated to Swift. Layer-local origins, deterministic seeds, clamped edges. RGB8/16 encoded and RGB32 linear. Exact Photoshop pixels/defaults/depth availability remain unqualified.","colors":"Tiles snapshots desktop foreground/background; API defaults to black/white and accepts RGBA colors.","interchange":"Emboss PSD mapping follows the upstream descriptor. Other editable PSD and Adobe actionJSON mappings remain unqualified."]
  }
}
extension RasterFilter.Kind {
  public var isStylize:Bool {[.diffuse,.emboss,.extrude,.findEdges,.oilPaint,.solarize,.tiles,.traceContour,.wind].contains(self)}
  public var isImmediateStylize:Bool {self == .findEdges || self == .solarize}
}
