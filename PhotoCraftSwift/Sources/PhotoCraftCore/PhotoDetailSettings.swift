import Foundation

public struct DetailControl: Sendable {
  public let key: String, title: String, bounds: ClosedRange<Double>, value: Double
  public init(_ key:String,_ title:String,_ bounds:ClosedRange<Double>,_ value:Double) { self.key=key;self.title=title;self.bounds=bounds;self.value=value }
  public var schema:[String:Any] { ["type":"number","minimum":bounds.lowerBound,"maximum":bounds.upperBound,"default":value] }
}
public struct TonalSharpenSettings: Codable, Equatable, Sendable {
  public var fadeAmount=0.0, tonalWidth=50.0, radius=1.0
  public init() {}
  public static let controls=[DetailControl("fadeAmount","Fade Amount (%)",0...100,0),DetailControl("tonalWidth","Tonal Width (%)",1...100,50),DetailControl("radius","Radius (pixels)",0.1...1000,1)]
  public func validate() throws { try DetailSettingsJSON.validate([fadeAmount,tonalWidth,radius],Self.controls) }
  static func decode(_ value:Any)throws->Self { let d=try DetailSettingsJSON.object(value,keys:Set(controls.map(\.key)));var s=Self();s.fadeAmount=try DetailSettingsJSON.number(d,"fadeAmount",s.fadeAmount);s.tonalWidth=try DetailSettingsJSON.number(d,"tonalWidth",s.tonalWidth);s.radius=try DetailSettingsJSON.number(d,"radius",s.radius);try s.validate();return s }
}
public struct SmartSharpenSettings: Codable, Equatable, Sendable {
  public enum Removal:String,Codable,CaseIterable,Sendable { case gaussian,lens,motion;public var title:String { switch self { case .gaussian:"Gaussian Blur";case .lens:"Lens Blur";case .motion:"Motion Blur" } } }
  public var amount=100.0, radius=1.0, reduceNoise=10.0, angle=0.0
  public var remove:Removal = .gaussian
  public var shadows=TonalSharpenSettings(), highlights=TonalSharpenSettings()
  public init() {}
  public static let controls=[DetailControl("amount","Amount (%)",0...500,100),DetailControl("radius","Radius (pixels)",0.1...64,1),DetailControl("reduceNoise","Reduce Noise (%)",0...100,10),DetailControl("angle","Angle (degrees)",-180...180,0)]
  public var isIdentity:Bool { amount==0 }
  public func validate()throws { try DetailSettingsJSON.validate([amount,radius,reduceNoise,angle],Self.controls);try shadows.validate();try highlights.validate() }
  public static func decodeJSON(_ data:Data)throws->Self {
    let d=try DetailSettingsJSON.object(JSONSerialization.jsonObject(with:data),keys:Set(controls.map(\.key)).union(["remove","shadows","highlights"]));var s=Self()
    s.amount=try DetailSettingsJSON.number(d,"amount",s.amount);s.radius=try DetailSettingsJSON.number(d,"radius",s.radius);s.reduceNoise=try DetailSettingsJSON.number(d,"reduceNoise",s.reduceNoise);s.angle=try DetailSettingsJSON.number(d,"angle",s.angle)
    if let v=d["remove"] { guard let text=v as? String,let r=Removal(rawValue:text) else { throw CraftError.invalid("Unknown blur removal mode.") };s.remove=r }
    if let v=d["shadows"] { s.shadows=try TonalSharpenSettings.decode(v) };if let v=d["highlights"] { s.highlights=try TonalSharpenSettings.decode(v) };try s.validate();return s
  }
  public static var apiSchema:[String:Any] { var p=DetailSettingsJSON.properties(controls);p["remove"]=["type":"string","enum":Removal.allCases.map(\.rawValue),"default":"gaussian"];let tonal=DetailSettingsJSON.schema(DetailSettingsJSON.properties(TonalSharpenSettings.controls));p["shadows"]=tonal;p["highlights"]=tonal;return DetailSettingsJSON.schema(p) }
  public static var apiCapabilities:[String:Any] { ["schema":apiSchema,"removalModes":Removal.allCases.map(\.rawValue),"algorithm":"Source-derived Gaussian residual sharpening; native regularized disk/line deconvolution for Lens/Motion. Tonal fade masks and noise suppression. Photoshop numeric equality remains unqualified.","persistence":"Native37 and Actions9 retain editable settings. Adobe descriptors and editable PSD are not yet qualified.","maximumLayerPixels":8388608,"processing":"RGB8/16 encoded samples; RGB32 linear unclipped samples. Alpha retained; 256-pixel tiles with padded FFT for deconvolution."] }
}
public struct ChannelNoiseSettings:Codable,Equatable,Sendable {
  public var strength=0.0, preserveDetails=60.0
  public init(strength:Double=0,preserveDetails:Double=60) { self.strength=strength;self.preserveDetails=preserveDetails }
  public func validate()throws { try DetailSettingsJSON.validate([strength,preserveDetails],Array(ReduceNoiseSettings.controls.prefix(2))) }
}
public struct ReduceNoiseSettings:Codable,Equatable,Sendable {
  public var strength=6.0, preserveDetails=60.0, reduceColorNoise=45.0, sharpenDetails=25.0
  public var removeJpegArtifact=false
  /// Additional channel-specific smoothing after the overall pass; omitted channels are unchanged.
  public var perChannel:[String:ChannelNoiseSettings]=[:]
  public init() {}
  public static let channels=["red","green","blue"]
  public static let controls=[DetailControl("strength","Strength",0...10,6),DetailControl("preserveDetails","Preserve Details (%)",0...100,60),DetailControl("reduceColorNoise","Reduce Color Noise (%)",0...100,45),DetailControl("sharpenDetails","Sharpen Details (%)",0...100,25)]
  public var isIdentity:Bool { strength==0 && reduceColorNoise==0 && sharpenDetails==0 && !removeJpegArtifact && perChannel.values.allSatisfy{$0.strength==0} }
  public func validate()throws { try DetailSettingsJSON.validate([strength,preserveDetails,reduceColorNoise,sharpenDetails],Self.controls);guard Set(perChannel.keys).isSubset(of:Set(Self.channels)) else { throw CraftError.invalid("Unknown noise-reduction channel.") };for c in perChannel.values { try c.validate() } }
  public static func decodeJSON(_ data:Data)throws->Self {
    let d=try DetailSettingsJSON.object(JSONSerialization.jsonObject(with:data),keys:Set(controls.map(\.key)).union(["removeJpegArtifact","perChannel"]));var s=Self()
    s.strength=try DetailSettingsJSON.number(d,"strength",s.strength);s.preserveDetails=try DetailSettingsJSON.number(d,"preserveDetails",s.preserveDetails);s.reduceColorNoise=try DetailSettingsJSON.number(d,"reduceColorNoise",s.reduceColorNoise);s.sharpenDetails=try DetailSettingsJSON.number(d,"sharpenDetails",s.sharpenDetails)
    if let v=d["removeJpegArtifact"] { guard let n=v as? NSNumber,CFGetTypeID(n)==CFBooleanGetTypeID() else { throw CraftError.invalid("removeJpegArtifact must be Boolean.") };s.removeJpegArtifact=n.boolValue }
    if let v=d["perChannel"] { let channels=try DetailSettingsJSON.object(v,keys:Set(Self.channels));for (key,value) in channels { let c=try DetailSettingsJSON.object(value,keys:["strength","preserveDetails"]);s.perChannel[key]=try .init(strength:DetailSettingsJSON.number(c,"strength",0),preserveDetails:DetailSettingsJSON.number(c,"preserveDetails",60)) } }
    try s.validate();return s
  }
  public static var apiSchema:[String:Any] { var p=DetailSettingsJSON.properties(controls);p["removeJpegArtifact"]=["type":"boolean","default":false];var channel=DetailSettingsJSON.properties(Array(controls.prefix(2)));channel["strength"]=["type":"number","minimum":0,"maximum":10,"default":0];p["perChannel"]=DetailSettingsJSON.schema(Dictionary(uniqueKeysWithValues:channels.map{($0,DetailSettingsJSON.schema(channel))}));return DetailSettingsJSON.schema(p) }
  public static var apiCapabilities:[String:Any] { ["schema":apiSchema,"channels":channels,"algorithm":"Original Rust guided luma/chroma smoothing, JPEG-grid softening and detail sharpening; additional independent RGB channel controls. Source defaults retained; Photoshop numeric/default equality remains unqualified.","persistence":"Native37 and Actions9 retain editable settings. Adobe descriptors and editable PSD are not yet qualified.","maximumLayerPixels":8388608,"processing":"RGB8/16 encoded samples; RGB32 linear unclipped samples. Alpha retained. JPEG grid follows transformed document coordinates."] }
}
enum DetailSettingsJSON {
  static func object(_ value:Any,keys:Set<String>)throws->[String:Any] { guard let d=value as? [String:Any],Set(d.keys).isSubset(of:keys) else { throw CraftError.invalid("Unknown photo detail setting.") };return d }
  static func number(_ d:[String:Any],_ key:String,_ fallback:Double)throws->Double { guard let v=d[key] else{return fallback};guard let n=v as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite else{throw CraftError.invalid("\(key) must be finite and numeric.")};return n.doubleValue }
  static func validate(_ values:[Double],_ controls:[DetailControl])throws { for (v,c) in zip(values,controls) { guard v.isFinite,c.bounds.contains(v) else { throw CraftError.invalid("Invalid \(c.title).") } } }
  static func properties(_ controls:[DetailControl])->[String:[String:Any]] { Dictionary(uniqueKeysWithValues:controls.map{($0.key,$0.schema)}) }
  static func schema(_ properties:[String:[String:Any]])->[String:Any] { ["type":"object","additionalProperties":false,"properties":properties] }
}
