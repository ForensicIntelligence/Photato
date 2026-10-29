import Foundation

public struct ToneColorStatistics:Codable,Equatable,Sendable {
  public var mean:[Float]
  public var standardDeviation:[Float]
  public init(mean:[Float],standardDeviation:[Float]) {self.mean=mean;self.standardDeviation=standardDeviation}
  public func validate()throws {
    guard mean.count==3,standardDeviation.count==3,mean.allSatisfy({$0.isFinite && abs($0)<=1e6}),standardDeviation.allSatisfy({$0.isFinite && (0...1e6).contains($0)}) else {throw CraftError.invalid("Invalid Match Color statistics.")}
  }
}
public struct ToneColorSample:Codable,Equatable,Sendable {
  public var color:Pixel
  public var point:PathPoint?
  public var subtract:Bool
  public init(color:Pixel,point:PathPoint?=nil,subtract:Bool=false){self.color=color;self.point=point;self.subtract=subtract}
}
/// Native tone/color workflows, with explicit portable source statistics for Match Color.
public struct ClassicToneSettings:Codable,Equatable,Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable {
    case shadowsHighlights,hdrToning,matchColor,replaceColor,equalize
    public var title:String {switch self {case .shadowsHighlights:"Shadows/Highlights";case .hdrToning:"HDR Toning";case .matchColor:"Match Color";case .replaceColor:"Replace Color";case .equalize:"Equalize"}}
  }
  private struct Values:Codable,Equatable,Sendable {
    var kind:Kind = .shadowsHighlights
    var shadowAmount:Double=35
    var shadowTone:Double=50
    var shadowRadius:Double=30
    var highlightAmount:Double=0
    var highlightTone:Double=50
    var highlightRadius:Double=30
    var colorCorrection:Double=20
    var midtone:Double=0
    var blackClip:Double=0.01
    var whiteClip:Double=0.01
    var fuzziness:Double=40
    var hue:Double=0
    var saturation:Double=0
    var lightness:Double=0
    var localRadius:Double=100
    var luminance:Double=100
    var intensity:Double=100
    var fade:Double=0
    var radius:Double=30
    var strength:Double=0.5
    var gamma:Double=1
    var exposure:Double=0
    var detail:Double=30
    var shadow:Double=0
    var highlight:Double=0
    var vibrance:Double=0
    var hdrSaturation:Double=20
    var localized:Bool=false
    var neutralize:Bool=false
    var ignoreSelection:Bool=false
    var useSelectionInTarget:Bool=false
    var equalizeEntireImage:Bool=false
    var method:HDRMergeSettings.Method = .localAdaptation
    var curve:[[Float]]=[]
    var samples:[ToneColorSample]=[ToneColorSample(color:Pixel.black)]
    var sourceStatistics:ToneColorStatistics?=nil
  }
  private indirect enum Storage:Equatable,Sendable {case value(Values)}
  private var storage:Storage = .value(Values())
  private var values:Values {get{switch storage{case .value(let v):return v}}set{storage = .value(newValue)}}
  public init(_ kind:Kind = .shadowsHighlights){self.kind=kind}
  public init(from decoder:Decoder)throws{storage = .value(try Values(from:decoder))}
  public func encode(to encoder:Encoder)throws{try values.encode(to:encoder)}
  public var kind:Kind {get{values.kind}set{var v=values;v.kind=newValue;values=v}}
  public var shadowAmount:Double {get{values.shadowAmount}set{var v=values;v.shadowAmount=newValue;values=v}}
  public var shadowTone:Double {get{values.shadowTone}set{var v=values;v.shadowTone=newValue;values=v}}
  public var shadowRadius:Double {get{values.shadowRadius}set{var v=values;v.shadowRadius=newValue;values=v}}
  public var highlightAmount:Double {get{values.highlightAmount}set{var v=values;v.highlightAmount=newValue;values=v}}
  public var highlightTone:Double {get{values.highlightTone}set{var v=values;v.highlightTone=newValue;values=v}}
  public var highlightRadius:Double {get{values.highlightRadius}set{var v=values;v.highlightRadius=newValue;values=v}}
  public var colorCorrection:Double {get{values.colorCorrection}set{var v=values;v.colorCorrection=newValue;values=v}}
  public var midtone:Double {get{values.midtone}set{var v=values;v.midtone=newValue;values=v}}
  public var blackClip:Double {get{values.blackClip}set{var v=values;v.blackClip=newValue;values=v}}
  public var whiteClip:Double {get{values.whiteClip}set{var v=values;v.whiteClip=newValue;values=v}}
  public var fuzziness:Double {get{values.fuzziness}set{var v=values;v.fuzziness=newValue;values=v}}
  public var hue:Double {get{values.hue}set{var v=values;v.hue=newValue;values=v}}
  public var saturation:Double {get{values.saturation}set{var v=values;v.saturation=newValue;values=v}}
  public var lightness:Double {get{values.lightness}set{var v=values;v.lightness=newValue;values=v}}
  public var localRadius:Double {get{values.localRadius}set{var v=values;v.localRadius=newValue;values=v}}
  public var luminance:Double {get{values.luminance}set{var v=values;v.luminance=newValue;values=v}}
  public var intensity:Double {get{values.intensity}set{var v=values;v.intensity=newValue;values=v}}
  public var fade:Double {get{values.fade}set{var v=values;v.fade=newValue;values=v}}
  public var radius:Double {get{values.radius}set{var v=values;v.radius=newValue;values=v}}
  public var strength:Double {get{values.strength}set{var v=values;v.strength=newValue;values=v}}
  public var gamma:Double {get{values.gamma}set{var v=values;v.gamma=newValue;values=v}}
  public var exposure:Double {get{values.exposure}set{var v=values;v.exposure=newValue;values=v}}
  public var detail:Double {get{values.detail}set{var v=values;v.detail=newValue;values=v}}
  public var shadow:Double {get{values.shadow}set{var v=values;v.shadow=newValue;values=v}}
  public var highlight:Double {get{values.highlight}set{var v=values;v.highlight=newValue;values=v}}
  public var vibrance:Double {get{values.vibrance}set{var v=values;v.vibrance=newValue;values=v}}
  public var hdrSaturation:Double {get{values.hdrSaturation}set{var v=values;v.hdrSaturation=newValue;values=v}}
  public var localized:Bool {get{values.localized}set{var v=values;v.localized=newValue;values=v}}
  public var neutralize:Bool {get{values.neutralize}set{var v=values;v.neutralize=newValue;values=v}}
  public var ignoreSelection:Bool {get{values.ignoreSelection}set{var v=values;v.ignoreSelection=newValue;values=v}}
  public var useSelectionInTarget:Bool {get{values.useSelectionInTarget}set{var v=values;v.useSelectionInTarget=newValue;values=v}}
  public var equalizeEntireImage:Bool {get{values.equalizeEntireImage}set{var v=values;v.equalizeEntireImage=newValue;values=v}}
  public var method:HDRMergeSettings.Method {get{values.method}set{var v=values;v.method=newValue;values=v}}
  public var curve:[[Float]] {get{values.curve}set{var v=values;v.curve=newValue;values=v}}
  public var samples:[ToneColorSample] {get{values.samples}set{var v=values;v.samples=newValue;values=v}}
  public var sourceStatistics:ToneColorStatistics? {get{values.sourceStatistics}set{var v=values;v.sourceStatistics=newValue;values=v}}
  public var keys:Set<String> {
    switch kind {
    case .shadowsHighlights:["shadowAmount","shadowTone","shadowRadius","highlightAmount","highlightTone","highlightRadius","colorCorrection","midtone","blackClip","whiteClip"]
    case .replaceColor:["samples","fuzziness","hue","saturation","lightness","localized","localRadius"]
    case .matchColor:["sourceStatistics","luminance","intensity","fade","neutralize","ignoreSelection","useSelectionInTarget"]
    case .equalize:["equalizeEntireImage"]
    case .hdrToning:["method","radius","strength","gamma","exposure","detail","shadow","highlight","vibrance","hdrSaturation","curve"]
    }
  }
  public func validate()throws {
    guard shadowAmount.isFinite,(0...100).contains(shadowAmount) else {throw CraftError.invalid("Invalid shadowAmount." )}
    guard shadowTone.isFinite,(0...100).contains(shadowTone) else {throw CraftError.invalid("Invalid shadowTone." )}
    guard shadowRadius.isFinite,(0...2500).contains(shadowRadius) else {throw CraftError.invalid("Invalid shadowRadius." )}
    guard highlightAmount.isFinite,(0...100).contains(highlightAmount) else {throw CraftError.invalid("Invalid highlightAmount." )}
    guard highlightTone.isFinite,(0...100).contains(highlightTone) else {throw CraftError.invalid("Invalid highlightTone." )}
    guard highlightRadius.isFinite,(0...2500).contains(highlightRadius) else {throw CraftError.invalid("Invalid highlightRadius." )}
    guard colorCorrection.isFinite,(-100...100).contains(colorCorrection) else {throw CraftError.invalid("Invalid colorCorrection." )}
    guard midtone.isFinite,(-100...100).contains(midtone) else {throw CraftError.invalid("Invalid midtone." )}
    guard blackClip.isFinite,(0...50).contains(blackClip) else {throw CraftError.invalid("Invalid blackClip." )}
    guard whiteClip.isFinite,(0...50).contains(whiteClip) else {throw CraftError.invalid("Invalid whiteClip." )}
    guard fuzziness.isFinite,(0...200).contains(fuzziness) else {throw CraftError.invalid("Invalid fuzziness." )}
    guard hue.isFinite,(-180...180).contains(hue) else {throw CraftError.invalid("Invalid hue." )}
    guard saturation.isFinite,(-100...100).contains(saturation) else {throw CraftError.invalid("Invalid saturation." )}
    guard lightness.isFinite,(-100...100).contains(lightness) else {throw CraftError.invalid("Invalid lightness." )}
    guard localRadius.isFinite,(1...16384).contains(localRadius) else {throw CraftError.invalid("Invalid localRadius." )}
    guard luminance.isFinite,(1...200).contains(luminance) else {throw CraftError.invalid("Invalid luminance." )}
    guard intensity.isFinite,(1...200).contains(intensity) else {throw CraftError.invalid("Invalid intensity." )}
    guard fade.isFinite,(0...100).contains(fade) else {throw CraftError.invalid("Invalid fade." )}
    guard radius.isFinite,(1...500).contains(radius) else {throw CraftError.invalid("Invalid radius." )}
    guard strength.isFinite,(0.1...4).contains(strength) else {throw CraftError.invalid("Invalid strength." )}
    guard gamma.isFinite,(0.1...2).contains(gamma) else {throw CraftError.invalid("Invalid gamma." )}
    guard exposure.isFinite,(-5...5).contains(exposure) else {throw CraftError.invalid("Invalid exposure." )}
    guard detail.isFinite,(-100...300).contains(detail) else {throw CraftError.invalid("Invalid detail." )}
    guard shadow.isFinite,(-100...100).contains(shadow) else {throw CraftError.invalid("Invalid shadow." )}
    guard highlight.isFinite,(-100...100).contains(highlight) else {throw CraftError.invalid("Invalid highlight." )}
    guard vibrance.isFinite,(-100...100).contains(vibrance) else {throw CraftError.invalid("Invalid vibrance." )}
    guard hdrSaturation.isFinite,(-100...100).contains(hdrSaturation) else {throw CraftError.invalid("Invalid hdrSaturation." )}
    try sourceStatistics?.validate()
    guard (1...64).contains(samples.count),samples.contains(where:{!$0.subtract}),samples.allSatisfy({$0.color.isFinite && $0.color.a==1 && (0...1).contains($0.color.r) && (0...1).contains($0.color.g) && (0...1).contains($0.color.b) && ($0.point.map{$0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y)} ?? true)}),curve.isEmpty || (2...32).contains(curve.count) else{throw CraftError.invalid("Invalid Replace Color samples or HDR curve.")}
    var previous:Float = -1
    for p in curve {guard p.count==2,p.allSatisfy({$0.isFinite && (0...1).contains($0)}),p[0]>previous else{throw CraftError.invalid("HDR curve points must have increasing inputs in0–1.")};previous=p[0]}
    let canonical=try Self.decodeFields(apiParameters,kind:kind)
    guard canonical==self else{throw CraftError.invalid("Settings contain controls for another adjustment.")}
  }
  private static func decodeFields(_ fields:[String:Any],kind:Kind)throws->Self {
    var base=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self(kind))) as! [String:Any]
    for(k,v) in fields{base[k]=v}
    return try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:base))
  }
  public static func decodeJSON(_ data:Data,kind:Kind)throws->Self {
    guard data.count<=65536,let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(fields.keys).isSubset(of:Self(kind).keys) else{throw CraftError.invalid("Unknown tone or color setting.")}
    if let stats=fields["sourceStatistics"] as? [String:Any],Set(stats.keys) != ["mean","standardDeviation"] {throw CraftError.invalid("Unknown source statistic.")}
    if let samples=fields["samples"] as? [[String:Any]] {
      for sample in samples {
        guard Set(sample.keys).isSubset(of:["color","point","subtract"]),let color=sample["color"] as? [String:Any],Set(color.keys)==["r","g","b","a"] else{throw CraftError.invalid("Unknown color sample field.")}
        if let point=sample["point"] as? [String:Any],Set(point.keys) != ["x","y"] {throw CraftError.invalid("Unknown sample point field.")}
      }
    }
    let s=try decodeFields(fields,kind:kind);try s.validate();return s
  }
  public var apiParameters:[String:Any] {((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:]).filter{keys.contains($0.key)}}
  public static var numericRanges:[String:ClosedRange<Double>] {[
    "shadowAmount":0...100,
    "shadowTone":0...100,
    "shadowRadius":0...2500,
    "highlightAmount":0...100,
    "highlightTone":0...100,
    "highlightRadius":0...2500,
    "colorCorrection":-100...100,
    "midtone":-100...100,
    "blackClip":0...50,
    "whiteClip":0...50,
    "fuzziness":0...200,
    "hue":-180...180,
    "saturation":-100...100,
    "lightness":-100...100,
    "localRadius":1...16384,
    "luminance":1...200,
    "intensity":1...200,
    "fade":0...100,
    "radius":1...500,
    "strength":0.1...4,
    "gamma":0.1...2,
    "exposure":-5...5,
    "detail":-100...300,
    "shadow":-100...100,
    "highlight":-100...100,
    "vibrance":-100...100,
    "hdrSaturation":-100...100  ]}
}
public struct ClassicToneRequest:Codable,Equatable,Sendable {
  public var layerID:UUID?
  public var settings:ClassicToneSettings
  public init(_ settings:ClassicToneSettings,layerID:UUID?=nil){self.settings=settings;self.layerID=layerID}
  public func validate()throws{try settings.validate()}
}
