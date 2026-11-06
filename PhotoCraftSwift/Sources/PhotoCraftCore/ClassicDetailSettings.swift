import Foundation

/// Shared settings for the remaining Blur, Noise and Sharpen workflows.
public struct ClassicDetailSettings: Codable, Equatable, Sendable {
  public enum Method:String,Codable,CaseIterable,Sendable {case spin,zoom}
  public enum RadialQuality:String,Codable,CaseIterable,Sendable {case draft,good,best}
  public enum Quality:String,Codable,CaseIterable,Sendable {case low,medium,high}
  public enum Mode:String,Codable,CaseIterable,Sendable {case normal,edgeOnly,overlayEdge}
  public enum Shape:String,Codable,CaseIterable,Sendable {case circle,ring,square,diamond,triangle,hexagon,star,heart,cross}
  private struct Values:Codable,Equatable,Sendable {
    var radius:Double=1
    var threshold:Double=0
    var amount:Double=10
    var method:Method = .spin
    var radialQuality:RadialQuality = .good
    var centerX:Double=0.5
    var centerY:Double=0.5
    var quality:Quality = .high
    var mode:Mode = .normal
    var shape:Shape = .circle
    var kernel:ShapeBlurKernel?
  }
  private indirect enum Storage:Equatable,Sendable {case value(Values)}
  private var storage:Storage = .value(Values())
  private var values:Values {get{switch storage{case .value(let v):return v}}set{storage = .value(newValue)}}
  public init(kind:RasterFilter.Kind = .radialBlur) {
    if kind == .smartBlur {radius=3;threshold=25}
    if kind == .surfaceBlur {radius=5;threshold=15}
    if kind == .shapeBlur {radius=10}
  }
  public init(from decoder:Decoder)throws{storage = .value(try Values(from:decoder))}
  public func encode(to encoder:Encoder)throws{try values.encode(to:encoder)}
  public var radius:Double {get{values.radius}set{var v=values;v.radius=newValue;values=v}}
  public var threshold:Double {get{values.threshold}set{var v=values;v.threshold=newValue;values=v}}
  public var amount:Double {get{values.amount}set{var v=values;v.amount=newValue;values=v}}
  public var method:Method {get{values.method}set{var v=values;v.method=newValue;values=v}}
  public var radialQuality:RadialQuality {get{values.radialQuality}set{var v=values;v.radialQuality=newValue;values=v}}
  public var centerX:Double {get{values.centerX}set{var v=values;v.centerX=newValue;values=v}}
  public var centerY:Double {get{values.centerY}set{var v=values;v.centerY=newValue;values=v}}
  public var quality:Quality {get{values.quality}set{var v=values;v.quality=newValue;values=v}}
  public var mode:Mode {get{values.mode}set{var v=values;v.mode=newValue;values=v}}
  public var shape:Shape {get{values.shape}set{var v=values;v.shape=newValue;values=v}}
  public var kernel:ShapeBlurKernel? {get{values.kernel}set{var v=values;v.kernel=newValue;values=v}}
  public static func keys(_ kind:RasterFilter.Kind)->Set<String> {
    switch kind {
    case .radialBlur:["amount","method","radialQuality","centerX","centerY"]
    case .shapeBlur:["radius","shape","kernel"]
    case .smartBlur:["radius","threshold","quality","mode"]
    case .surfaceBlur,.dustAndScratches:["radius","threshold"]
    case .median:["radius"]
    default:[]
    }
  }
  public static func depths(_ kind:RasterFilter.Kind)->[PixelDepth] {
    if kind == .smartBlur {return [.u8]}
    if [.despeckle,.dustAndScratches,.median,.sharpenEdges].contains(kind){return [.u8,.u16]}
    return [.u8,.u16,.f32]
  }
  public func validate(kind:RasterFilter.Kind)throws {
    guard kind.isClassicDetail,[radius,threshold,amount,centerX,centerY].allSatisfy(\.isFinite),
      (0.1...1000).contains(radius),(0...255).contains(threshold),(1...100).contains(amount),amount.rounded()==amount,
      (0...1).contains(centerX),(0...1).contains(centerY) else {throw CraftError.invalid("Invalid Blur, Noise or Sharpen settings.")}
    switch kind {
    case .shapeBlur:guard (5...1000).contains(radius),radius.rounded()==radius else {throw CraftError.invalid("Shape Blur radius must be a whole pixel from5 to1000.")}
    case .smartBlur:guard radius<=100,(0.1...100).contains(threshold) else {throw CraftError.invalid("Smart Blur radius and threshold must be0.1–100.")}
    case .surfaceBlur:guard (1...100).contains(radius),radius.rounded()==radius,(2...255).contains(threshold),threshold.rounded()==threshold else {throw CraftError.invalid("Surface Blur needs radius1–100 and threshold2–255 in whole units.")}
    case .dustAndScratches,.median:guard (1...(kind == .median ? 500:100)).contains(radius),radius.rounded()==radius,threshold.rounded()==threshold else {throw CraftError.invalid("Invalid Median or Dust & Scratches radius/threshold.")}
    default:break
    }
    if let kernel {guard kind == .shapeBlur,shape == .circle else {throw CraftError.invalid("A custom kernel requires Shape Blur with no built-in shape override.")};try kernel.validate()}
    let decoded=try Self.decodeFields(apiParameters(kind:kind),kind:kind)
    guard self==decoded else {throw CraftError.invalid("Settings contain controls that do not apply to this filter.")}
  }
  private static func decodeFields(_ fields:[String:Any],kind:RasterFilter.Kind)throws->Self {
    var base=try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self(kind:kind))) as! [String:Any]
    for(k,v) in fields{base[k]=v}
    return try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:base))
  }
  public static func decodeJSON(_ data:Data,kind:RasterFilter.Kind)throws->Self {
    guard data.count<=(kind == .shapeBlur ? 2*1024*1024:16384),let fields=try JSONSerialization.jsonObject(with:data) as? [String:Any],Set(fields.keys).isSubset(of:keys(kind)) else {throw CraftError.invalid("Unknown Blur, Noise or Sharpen setting.")}
    if let kernel=fields["kernel"],!(kernel is NSNull) {try ShapeBlurKernel.validateAPI(kernel)}
    let result=try decodeFields(fields,kind:kind);try result.validate(kind:kind);return result
  }
  public func apiParameters(kind:RasterFilter.Kind)->[String:Any] {
    ((try? JSONSerialization.jsonObject(with:JSONEncoder().encode(self))) as? [String:Any] ?? [:]).filter{Self.keys(kind).contains($0.key)}
  }
  public static func apiSchema(kind:RasterFilter.Kind)->[String:Any] {
    let defaults=Self(kind:kind).apiParameters(kind:kind);var fields=[String:Any]()
    for key in keys(kind) {
      var f:[String:Any]
      switch key {
      case "method":f=["type":"string","enum":Method.allCases.map(\.rawValue)]
      case "radialQuality":f=["type":"string","enum":RadialQuality.allCases.map(\.rawValue)]
      case "quality":f=["type":"string","enum":Quality.allCases.map(\.rawValue)]
      case "mode":f=["type":"string","enum":Mode.allCases.map(\.rawValue)]
      case "kernel":f=["anyOf":[ShapeBlurKernel.apiSchema,["type":"null"]]]
      case "shape":f=["type":"string","enum":Shape.allCases.map(\.rawValue)]
      case "centerX","centerY":f=["type":"number","minimum":0,"maximum":1]
      case "amount":f=["type":"integer","minimum":1,"maximum":100]
      case "radius":f=["type":kind == .smartBlur ? "number":"integer","minimum":kind == .smartBlur ? 0.1:kind == .shapeBlur ? 5:1,"maximum":kind == .shapeBlur ? 1000:kind == .median ? 500:100]
      default:f=["type":kind == .smartBlur ? "number":"integer","minimum":kind == .smartBlur ? 0.1:kind == .surfaceBlur ? 2:0,"maximum":kind == .smartBlur ? 100:255]
      };f["default"]=defaults[key];fields[key]=f
    }
    return ["type":"object","additionalProperties":false,"properties":fields]
  }
  public static var apiCapabilities:[String:Any] {
    ["kinds":RasterFilter.Kind.allCases.filter(\.isClassicDetail).map(\.rawValue),"nativeVersion":44,"actionsVersion":17,"customShapeNativeVersion":87,"customShapeActionsVersion":52,"customShapeKernels":true,"customShapeSnapshot":"Embedded vector geometry, independent of preset library after selection; aspect ratio retained, odd-sized antialiased coverage,32levels and true convolution. Core Graphics edge rounding has measured Photoshop residuals; exact sampling remains unqualified.",
     "depthsByKind":Dictionary(uniqueKeysWithValues:RasterFilter.Kind.allCases.filter(\.isClassicDetail).map{kind in (kind.rawValue,depths(kind).map{$0 == .u8 ? 8:$0 == .u16 ? 16:32})}),
     "algorithm":"Licensed PhotoCraft blur/noise/sharpen kernels in Swift; exact Photoshop output/defaults and Adobe descriptors remain unqualified. Radial Good/Draft reduce the source Best sample budget.",
     "limits":"8,388,608 pixels and268,435,456 estimated neighborhood visits. Nine built-in Shape Blur kernels plus saved native custom vector shapes; Adobe CSH preset transport remains unsupported. Custom-kernel geometry sampling also uses the268,435,456work budget."]
  }
}
extension RasterFilter.Kind {
  public var isClassicDetail:Bool {[.blur,.blurMore,.radialBlur,.shapeBlur,.smartBlur,.surfaceBlur,.despeckle,.dustAndScratches,.median,.sharpen,.sharpenEdges,.sharpenMore].contains(self)}
  public var isImmediateClassicDetail:Bool {[.blur,.blurMore,.despeckle,.sharpen,.sharpenEdges,.sharpenMore].contains(self)}
}
