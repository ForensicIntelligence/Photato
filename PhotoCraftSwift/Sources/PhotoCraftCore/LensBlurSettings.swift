import Foundation

public struct LensBlurSettings:Codable,Equatable,Sendable {
  public enum DepthSource:String,Codable,CaseIterable,Sendable { case none,transparency,layerMask,alphaChannel }
  public var radius=15.0, bladeCurvature=0.0, rotation=0.0, focalDistance=0.0
  public var brightness=0.0, threshold=0.0, noiseAmount=0.0
  public var blades=6
  public var depthSource:DepthSource = .none
  public var depthChannelID:UUID?
  public var invert=false,monochromatic=false
  public var distribution:RasterFilter.Distribution = .uniform
  public var seed:UInt32=1
  public init() {}
  public static let controls=[DetailControl("radius","Radius (pixels)",0...100,15),DetailControl("bladeCurvature","Blade Curvature (%)",0...100,0),DetailControl("rotation","Rotation (degrees)",0...360,0),DetailControl("focalDistance","Blur Focal Distance",0...255,0),DetailControl("brightness","Brightness (%)",0...100,0),DetailControl("threshold","Threshold",0...255,0),DetailControl("noiseAmount","Noise Amount (%)",0...100,0)]
  public var isIdentity:Bool { radius==0 && brightness==0 && noiseAmount==0 }
  public func validate()throws {
    for (v,c) in zip([radius,bladeCurvature,rotation,focalDistance,brightness,threshold,noiseAmount],Self.controls) { guard v.isFinite,c.bounds.contains(v) else { throw CraftError.invalid("Invalid Lens Blur \(c.title).") } }
    guard (3...8).contains(blades),(depthSource == .alphaChannel) == (depthChannelID != nil) else { throw CraftError.invalid("Lens Blur requires 3–8 iris blades and a channel ID only for an alpha-channel depth source.") }
  }
  public func validateSources(layer:Layer,document:CraftDocument)throws {
    try validate()
    guard document.depth != .f32 else { throw CraftError.unsupported("Lens Blur supports 8-bit and 16-bit RGB documents.") }
    if depthSource == .layerMask,layer.mask == nil { throw CraftError.invalid("Lens Blur depth source layer mask is missing.") }
    if depthSource == .alphaChannel,!(document.alphaChannels ?? []).contains(where:{$0.id==depthChannelID}) { throw CraftError.invalid("Lens Blur depth source alpha channel is missing.") }
  }
  public static func decodeJSON(_ data:Data)throws->Self {
    guard let d=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(d.keys).isSubset(of:Set(controls.map(\.key)).union(["blades","depthSource","depthChannelID","invert","monochromatic","distribution","seed"])) else { throw CraftError.invalid("Unknown Lens Blur setting.") }
    var s=Self()
    func number(_ key:String,_ fallback:Double)throws->Double { guard let v=d[key] else{return fallback};guard let n=v as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite else { throw CraftError.invalid("\(key) must be numeric.") };return n.doubleValue }
    s.radius=try number("radius",s.radius);s.bladeCurvature=try number("bladeCurvature",s.bladeCurvature);s.rotation=try number("rotation",s.rotation);s.focalDistance=try number("focalDistance",s.focalDistance);s.brightness=try number("brightness",s.brightness);s.threshold=try number("threshold",s.threshold);s.noiseAmount=try number("noiseAmount",s.noiseAmount)
    let blades=try number("blades",6),seed=try number("seed",1)
    guard (3...8).contains(blades),blades.rounded()==blades,(0...Double(UInt32.max)).contains(seed),seed.rounded()==seed else { throw CraftError.invalid("Invalid iris blades or noise seed.") };s.blades=Int(blades);s.seed=UInt32(seed)
    for key in ["invert","monochromatic"] { if let v=d[key] { guard let n=v as? NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID() else { throw CraftError.invalid("\(key) must be Boolean.") };if key=="invert" { s.invert=n.boolValue } else { s.monochromatic=n.boolValue } } }
    if let v=d["depthSource"] { guard let text=v as? String,let mode=DepthSource(rawValue:text) else { throw CraftError.invalid("Unknown Lens Blur depth source.") };s.depthSource=mode }
    if let v=d["distribution"] { guard let text=v as? String,let mode=RasterFilter.Distribution(rawValue:text) else { throw CraftError.invalid("Unknown Lens Blur noise distribution.") };s.distribution=mode }
    if let v=d["depthChannelID"] { guard let text=v as? String,let id=UUID(uuidString:text) else { throw CraftError.invalid("Invalid Lens Blur depth channel ID.") };s.depthChannelID=id }
    try s.validate();return s
  }
  public static var apiSchema:[String:Any] {
    var p=Dictionary(uniqueKeysWithValues:controls.map{($0.key,$0.schema)});p["blades"]=["type":"integer","minimum":3,"maximum":8,"default":6];p["depthSource"]=["type":"string","enum":DepthSource.allCases.map(\.rawValue),"default":"none"];p["depthChannelID"]=["type":"string","format":"uuid"];p["invert"]=["type":"boolean","default":false];p["monochromatic"]=["type":"boolean","default":false];p["distribution"]=["type":"string","enum":["uniform","gaussian"],"default":"uniform"];p["seed"]=["type":"integer","minimum":0,"maximum":UInt32.max,"default":1]
    return ["type":"object","additionalProperties":false,"properties":p,"allOf":[["if":["required":["depthSource"],"properties":["depthSource":["const":"alphaChannel"]]],"then":["required":["depthChannelID"]],"else":["not":["required":["depthChannelID"]]]]]]
  }
  public static var apiCapabilities:[String:Any] { ["schema":apiSchema,"depthSources":DepthSource.allCases.map(\.rawValue),"depthLifecycle":"Live layer mask/alpha-channel references. Raw grayscale mask samples follow mask transforms; display density/feather/visibility do not change depth. Transparency uses the current filter input. Referenced source deletion rejects; edit settings first. Alpha UUID references require matching channels when replayed in another document.","persistence":"Native 38 and Actions 10 preserve editable Lens Blur. Exact Adobe actionJSON and editable PSD are unqualified and unsupported.","limits":["layerPixels":8388608,"depths":[8,16],"blades":[3,8]],"algorithm":"Original Rust polygon-to-circle iris spans, Double prefix sums, nine depth levels, highlight gain and deterministic noise. Exact Photoshop kernels and occlusion rendering remain unqualified.","defaults":"Numeric defaults follow Adobe's current UXP Lens Blur reference; threshold 0 differs from original Rust 255. Desktop factory-default parity remains unqualified."] }
}
