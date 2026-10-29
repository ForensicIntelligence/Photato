import Foundation

/// Immutable, embedded 8-bit map channels; alpha is never a displacement channel.
public struct DisplacementMap: Codable, Equatable, Sendable {
  public static let maximumPixels = 1_048_576
  public var width: Int, height: Int, channels: Int
  public var samples: Data
  public var name: String
  public init(width: Int, height: Int, channels: Int, samples: Data, name: String = "Displacement Map") {
    self.width=width;self.height=height;self.channels=channels;self.samples=samples;self.name=name
  }
  public func validate() throws {
    guard width>0,height>0,width<=Self.maximumPixels/height,(1...2).contains(channels),
      samples.count==width*height*channels,name.utf8.count<=256 else { throw CraftError.invalid("Invalid displacement map: use one or two 8-bit channels, up to 1,048,576 pixels.") }
  }
}

/// Indirect storage keeps command values small while retaining copy-on-write value semantics.
public struct DistortionSettings: Codable, Equatable, Sendable {
  public enum Edge: String, Codable, CaseIterable, Sendable { case repeatEdge, wrapAround
    public var title:String { self == .repeatEdge ? "Repeat Edge Pixels" : "Wrap Around" }
  }
  public enum Fit: String, Codable, CaseIterable, Sendable { case stretchToFit, tile }
  public enum Sphere: String, Codable, CaseIterable, Sendable { case normal, horizontalOnly, verticalOnly }
  public enum Ripple: String, Codable, CaseIterable, Sendable { case small, medium, large }
  public enum Polar: String, Codable, CaseIterable, Sendable { case rectangularToPolar, polarToRectangular }
  public enum Wave: String, Codable, CaseIterable, Sendable { case sine, triangle, square }
  public enum ZigZag: String, Codable, CaseIterable, Sendable { case aroundCenter, outFromCenter, pondRipples }
  public struct Point: Codable, Equatable, Sendable {
    public var position:Double, offset:Double
    public init(_ position:Double,_ offset:Double) { self.position=position;self.offset=offset }
  }
  private struct Values: Codable, Equatable, Sendable {
    var amount:Double = 50
    var angle:Double = 50
    var horizontalScale:Double = 10
    var verticalScale:Double = 10
    var generators:Int = 5
    var wavelengthMin:Double = 10
    var wavelengthMax:Double = 120
    var amplitudeMin:Double = 5
    var amplitudeMax:Double = 35
    var ridges:Double = 5
    var seed:UInt32 = 1
    var edge:Edge = .repeatEdge
    var fit:Fit = .stretchToFit
    var sphereMode:Sphere = .normal
    var rippleSize:Ripple = .medium
    var polarMode:Polar = .rectangularToPolar
    var waveType:Wave = .sine
    var zigzagStyle:ZigZag = .pondRipples
    var points:[Point] = [Point(0,0),Point(1,0)]
    var map:DisplacementMap? = nil
  }
  private indirect enum Storage: Equatable, Sendable { case value(Values) }
  private var storage:Storage = .value(Values())
  private var values:Values { get { switch storage { case .value(let v):return v } } set { storage = .value(newValue) } }
  public init(kind:RasterFilter.Kind) {
    if kind == .wave { horizontalScale=100;verticalScale=100 }
    if kind == .shear { edge = .wrapAround }
    if kind == .ripple || kind == .spherize { amount=100 }
    if kind == .zigzag { amount=10 }
  }
  public init(from decoder:Decoder)throws { storage = .value(try Values(from:decoder)) }
  public func encode(to encoder:Encoder)throws { try values.encode(to:encoder) }
  public var amount:Double { get { values.amount } set { var v=values;v.amount=newValue;values=v } }
  public var angle:Double { get { values.angle } set { var v=values;v.angle=newValue;values=v } }
  public var horizontalScale:Double { get { values.horizontalScale } set { var v=values;v.horizontalScale=newValue;values=v } }
  public var verticalScale:Double { get { values.verticalScale } set { var v=values;v.verticalScale=newValue;values=v } }
  public var generators:Int { get { values.generators } set { var v=values;v.generators=newValue;values=v } }
  public var wavelengthMin:Double { get { values.wavelengthMin } set { var v=values;v.wavelengthMin=newValue;values=v } }
  public var wavelengthMax:Double { get { values.wavelengthMax } set { var v=values;v.wavelengthMax=newValue;values=v } }
  public var amplitudeMin:Double { get { values.amplitudeMin } set { var v=values;v.amplitudeMin=newValue;values=v } }
  public var amplitudeMax:Double { get { values.amplitudeMax } set { var v=values;v.amplitudeMax=newValue;values=v } }
  public var ridges:Double { get { values.ridges } set { var v=values;v.ridges=newValue;values=v } }
  public var seed:UInt32 { get { values.seed } set { var v=values;v.seed=newValue;values=v } }
  public var edge:Edge { get { values.edge } set { var v=values;v.edge=newValue;values=v } }
  public var fit:Fit { get { values.fit } set { var v=values;v.fit=newValue;values=v } }
  public var sphereMode:Sphere { get { values.sphereMode } set { var v=values;v.sphereMode=newValue;values=v } }
  public var rippleSize:Ripple { get { values.rippleSize } set { var v=values;v.rippleSize=newValue;values=v } }
  public var polarMode:Polar { get { values.polarMode } set { var v=values;v.polarMode=newValue;values=v } }
  public var waveType:Wave { get { values.waveType } set { var v=values;v.waveType=newValue;values=v } }
  public var zigzagStyle:ZigZag { get { values.zigzagStyle } set { var v=values;v.zigzagStyle=newValue;values=v } }
  public var points:[Point] { get { values.points } set { var v=values;v.points=newValue;values=v } }
  public var map:DisplacementMap? { get { values.map } set { var v=values;v.map=newValue;values=v } }
  public var estimatedBytes:Int { (map?.samples.count ?? 0)+points.count*16+512 }
  public static func keys(_ kind:RasterFilter.Kind)->Set<String> {
    switch kind {
    case .displace: ["horizontalScale","verticalScale","fit","edge","map"]
    case .shear: ["points","edge"]
    case .wave: ["generators","wavelengthMin","wavelengthMax","amplitudeMin","amplitudeMax","horizontalScale","verticalScale","waveType","seed","edge"]
    case .pinch: ["amount"]
    case .spherize: ["amount","sphereMode"]
    case .twirl: ["angle"]
    case .ripple: ["amount","rippleSize"]
    case .polarCoordinates: ["polarMode"]
    case .zigzag: ["amount","ridges","zigzagStyle"]
    default: []
    }
  }
  public func validate(kind:RasterFilter.Kind, requireMap:Bool = true)throws {
    guard kind.isDistortion else { throw CraftError.invalid("Distortion settings require a distortion filter.") }
    func number(_ value:Double,_ range:ClosedRange<Double>)throws {
      guard value.isFinite,range.contains(value),value.rounded()==value else { throw CraftError.invalid("Distortion numeric settings must be whole numbers in their supported ranges.") }
    }
    switch kind {
    case .displace:
      try number(horizontalScale,-999...999);try number(verticalScale,-999...999)
      if requireMap && map == nil { throw CraftError.invalid("Choose a displacement map first.") };try map?.validate()
    case .wave:
      guard (1...999).contains(generators),wavelengthMin<wavelengthMax,amplitudeMin<amplitudeMax else { throw CraftError.invalid("Wave requires 1–999 generators and minimum values below maximum values.") }
      for v in [wavelengthMin,wavelengthMax,amplitudeMin,amplitudeMax] { try number(v,1...999) }
      try number(horizontalScale,1...100);try number(verticalScale,1...100)
    case .shear:
      guard (2...64).contains(points.count),points.first?.position==0,points.last?.position==1 else { throw CraftError.invalid("Shear requires 2–64 curve points from top to bottom.") }
      for i in points.indices { let p=points[i];guard p.position.isFinite,p.offset.isFinite,(0...1).contains(p.position),(-1...1).contains(p.offset),i==0 || p.position-points[i-1].position>=0.000001 else { throw CraftError.invalid("Invalid or duplicate Shear point.") } }
    case .twirl: try number(angle,-999...999)
    case .ripple: try number(amount,-999...999)
    case .pinch,.spherize,.zigzag: try number(amount,-100...100);if kind == .zigzag { try number(ridges,0...20) }
    default: break
    }
    if kind != .displace && map != nil { throw CraftError.invalid("Map data belongs only to Displace.") }
  }
  public func isIdentity(_ kind:RasterFilter.Kind)->Bool {
    switch kind {
    case .displace: horizontalScale==0 && verticalScale==0
    case .pinch,.spherize,.ripple,.zigzag: amount==0
    case .twirl: angle==0
    case .shear: points.allSatisfy{$0.offset==0}
    default:false
    }
  }
  public static func decodeJSON(_ data:Data,kind:RasterFilter.Kind)throws->Self {
    guard let d=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(d.keys).isSubset(of:keys(kind)) else { throw CraftError.invalid("Unknown distortion setting.") }
    var result=Self(kind:kind)
    var complete=try JSONSerialization.jsonObject(with:JSONEncoder().encode(result)) as! [String:Any]
    for (key,value) in d { complete[key]=value }
    // JSONDecoder rejects fractional integers, invalid enums, non-booleans and malformed data.
    if let map=d["map"] as? [String:Any] {
      guard Set(map.keys).isSubset(of:["width","height","channels","samples","name"]),let text=map["samples"] as? String,text.utf8.count<=2_796_204 else { throw CraftError.invalid("Invalid displacement map payload.") }
      var m=map;if m["name"]==nil { m["name"]="Displacement Map" };complete["map"]=m
    }
    if let points=d["points"] as? [[String:Any]] { guard points.count<=64,points.allSatisfy({Set($0.keys)==["position","offset"]}) else { throw CraftError.invalid("Invalid Shear point fields.") } }
    result=try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:complete))
    try result.validate(kind:kind);return result
  }
  public func apiParameters(kind:RasterFilter.Kind)->[String:Any] {
    ((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:]).filter{Self.keys(kind).contains($0.key)}
  }
  public static func apiSchema(kind:RasterFilter.Kind)->[String:Any] {
    var p:[String:Any]=[:]
    let base=Self(kind:kind)
    let values=base.apiParameters(kind:kind)
    let enums:[String:[String]]=["edge":Edge.allCases.map(\.rawValue),"fit":Fit.allCases.map(\.rawValue),"sphereMode":Sphere.allCases.map(\.rawValue),"rippleSize":Ripple.allCases.map(\.rawValue),"polarMode":Polar.allCases.map(\.rawValue),"waveType":Wave.allCases.map(\.rawValue),"zigzagStyle":ZigZag.allCases.map(\.rawValue)]
    for key in keys(kind) {
      if let choices=enums[key] { p[key] = ["type":"string","enum":choices,"default":values[key]!] }
      else if key=="map" { p[key] = ["type":"object","additionalProperties":false,"required":["width","height","channels","samples"],"properties":["width":["type":"integer","minimum":1,"maximum":1048576],"height":["type":"integer","minimum":1,"maximum":1048576],"channels":["type":"integer","enum":[1,2]],"samples":["type":"string","contentEncoding":"base64","maxLength":2796204],"name":["type":"string","maxLength":256]],"description":"Row-major interleaved 8-bit channels: first horizontal, second vertical (or first if monochrome), neutral128. Product width×height <=1048576; exact byte count required."] }
      else if key=="points" { p[key] = ["type":"array","minItems":2,"maxItems":64,"items":["type":"object","additionalProperties":false,"required":["position","offset"],"properties":["position":["type":"number","minimum":0,"maximum":1],"offset":["type":"number","minimum":-1,"maximum":1]]],"description":"Strictly ascending position from0 to1; offset in half-widths. Endpoints required."] }
      else {
        let lo:Double=key=="seed" || key=="ridges" ? 0 : key=="amount" ? (kind == .ripple ? -999:-100) : key=="angle" || kind == .displace ? -999:1
        let hi:Double=key=="seed" ? Double(UInt32.max) : key=="ridges" ? 20 : key=="amount" && kind != .ripple ? 100 : kind == .wave && (key=="horizontalScale" || key=="verticalScale") ? 100:999
        p[key] = ["type":"integer","minimum":lo,"maximum":hi,"default":values[key]!]
      }
    }
    return ["type":"object","additionalProperties":false,"properties":p,"required":kind == .displace ? ["map"]:[],"description":"Wave min must be strictly below max; Shear positions strictly increase. Invalid combinations reject."]
  }
  public static var apiCapabilities:[String:Any] {
    ["kinds":RasterFilter.Kind.allCases.filter(\.isDistortion).map(\.rawValue),"mapStorage":"Embedded immutable8-bit data; no filesystem paths. Import through desktop or supply map samples in filter.apply/smartFilter.set.","nativeVersion":39,"actionsVersion":11,"maximumMapPixels":DisplacementMap.maximumPixels,"algorithm":"PhotoCraft inverse maps ported to Swift with premultiplied sampling. Wave evaluates all1–999 generators with row/column precomputation; Displace uses neutral128. Exact Photoshop output and Adobe actionJSON/PSD mappings remain unqualified."]
  }
}

extension RasterFilter.Kind {
  public var isDistortion:Bool { [.displace,.shear,.wave,.pinch,.spherize,.twirl,.ripple,.polarCoordinates,.zigzag].contains(self) }
}
