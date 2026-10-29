import Foundation

/// Native Swift translation of PhotoCraft camera_raw.rs (MIT OR Apache-2.0).
/// RGB development settings; sensor decoding and Adobe pixel equivalence are separate qualifications.
public struct CameraRawSettings: Codable, Equatable, Sendable {
  public struct Control: Sendable, Identifiable {
    public let key: String, title: String, group: String
    public let minimum: Float, maximum: Float, initial: Float
    public var id: String { key }
  }
  public struct Wheel: Codable, Equatable, Sendable {
    public var hue: Float = 0, sat: Float = 0, lum: Float = 0
    public init() {}
  }
  public var exposure: Float = 0
  public var contrast: Float = 0
  public var highlights: Float = 0
  public var shadows: Float = 0
  public var whites: Float = 0
  public var blacks: Float = 0
  public var temperature: Float = 0
  public var tint: Float = 0
  public var vibrance: Float = 0
  public var saturation: Float = 0
  public var texture: Float = 0
  public var clarity: Float = 0
  public var dehaze: Float = 0
  public var vignetteAmount: Float = 0
  public var vignetteMidpoint: Float = 50
  public var vignetteRoundness: Float = 0
  public var vignetteFeather: Float = 50
  public var vignetteHighlights: Float = 0
  public var grainAmount: Float = 0
  public var grainSize: Float = 25
  public var grainRoughness: Float = 50
  public var curveHighlights: Float = 0
  public var curveLights: Float = 0
  public var curveDarks: Float = 0
  public var curveShadows: Float = 0
  public var sharpenAmount: Float = 0
  public var sharpenRadius: Float = 1
  public var sharpenDetail: Float = 25
  public var sharpenMasking: Float = 0
  public var noiseLuminance: Float = 0
  public var noiseLuminanceDetail: Float = 50
  public var noiseColor: Float = 0
  public var noiseColorDetail: Float = 50
  public var gradeBlending: Float = 50
  public var gradeBalance: Float = 0
  public var curveSplits: [Float] = [25,50,75]
  public var pointCurve: [[Float]] = [], pointCurveRed: [[Float]] = [], pointCurveGreen: [[Float]] = [], pointCurveBlue: [[Float]] = []
  public var hslHue = [Float](repeating:0,count:8), hslSat = [Float](repeating:0,count:8), hslLum = [Float](repeating:0,count:8)
  public var gradeShadows = Wheel(), gradeMidtones = Wheel(), gradeHighlights = Wheel(), gradeGlobal = Wheel()
  public var vignetteStyle = "highlightPriority"
  public var seed: UInt32 = 0
  public var pixelScale: Float = 1
  public init() {}
  public static let controls: [Control] = [
    .init(key:"exposure",title:"Exposure",group:"Light",minimum:-5,maximum:5,initial:0),
    .init(key:"contrast",title:"Contrast",group:"Light",minimum:-100,maximum:100,initial:0),
    .init(key:"highlights",title:"Highlights",group:"Light",minimum:-100,maximum:100,initial:0),
    .init(key:"shadows",title:"Shadows",group:"Light",minimum:-100,maximum:100,initial:0),
    .init(key:"whites",title:"Whites",group:"Light",minimum:-100,maximum:100,initial:0),
    .init(key:"blacks",title:"Blacks",group:"Light",minimum:-100,maximum:100,initial:0),
    .init(key:"temperature",title:"Temperature",group:"Color",minimum:-100,maximum:100,initial:0),
    .init(key:"tint",title:"Tint",group:"Color",minimum:-100,maximum:100,initial:0),
    .init(key:"vibrance",title:"Vibrance",group:"Color",minimum:-100,maximum:100,initial:0),
    .init(key:"saturation",title:"Saturation",group:"Color",minimum:-100,maximum:100,initial:0),
    .init(key:"texture",title:"Texture",group:"Effects",minimum:-100,maximum:100,initial:0),
    .init(key:"clarity",title:"Clarity",group:"Effects",minimum:-100,maximum:100,initial:0),
    .init(key:"dehaze",title:"Dehaze",group:"Effects",minimum:-100,maximum:100,initial:0),
    .init(key:"vignetteAmount",title:"Vignette",group:"Effects",minimum:-100,maximum:100,initial:0),
    .init(key:"vignetteMidpoint",title:"Midpoint",group:"Effects",minimum:0,maximum:100,initial:50),
    .init(key:"vignetteRoundness",title:"Roundness",group:"Effects",minimum:-100,maximum:100,initial:0),
    .init(key:"vignetteFeather",title:"Feather",group:"Effects",minimum:0,maximum:100,initial:50),
    .init(key:"vignetteHighlights",title:"Highlight protection",group:"Effects",minimum:0,maximum:100,initial:0),
    .init(key:"grainAmount",title:"Grain",group:"Effects",minimum:0,maximum:100,initial:0),
    .init(key:"grainSize",title:"Grain size",group:"Effects",minimum:0,maximum:100,initial:25),
    .init(key:"grainRoughness",title:"Grain roughness",group:"Effects",minimum:0,maximum:100,initial:50),
    .init(key:"curveHighlights",title:"Highlights",group:"Curve",minimum:-100,maximum:100,initial:0),
    .init(key:"curveLights",title:"Lights",group:"Curve",minimum:-100,maximum:100,initial:0),
    .init(key:"curveDarks",title:"Darks",group:"Curve",minimum:-100,maximum:100,initial:0),
    .init(key:"curveShadows",title:"Shadows",group:"Curve",minimum:-100,maximum:100,initial:0),
    .init(key:"sharpenAmount",title:"Sharpening",group:"Detail",minimum:0,maximum:150,initial:0),
    .init(key:"sharpenRadius",title:"Radius",group:"Detail",minimum:0.5,maximum:3,initial:1),
    .init(key:"sharpenDetail",title:"Detail",group:"Detail",minimum:0,maximum:100,initial:25),
    .init(key:"sharpenMasking",title:"Masking",group:"Detail",minimum:0,maximum:100,initial:0),
    .init(key:"noiseLuminance",title:"Luminance noise reduction",group:"Detail",minimum:0,maximum:100,initial:0),
    .init(key:"noiseLuminanceDetail",title:"Luminance detail",group:"Detail",minimum:0,maximum:100,initial:50),
    .init(key:"noiseColor",title:"Color noise reduction",group:"Detail",minimum:0,maximum:100,initial:0),
    .init(key:"noiseColorDetail",title:"Color detail",group:"Detail",minimum:0,maximum:100,initial:50),
    .init(key:"gradeBlending",title:"Blending",group:"Color Grading",minimum:0,maximum:100,initial:50),
    .init(key:"gradeBalance",title:"Balance",group:"Color Grading",minimum:-100,maximum:100,initial:0),
  ]
  public subscript(_ key: String) -> Float {
    get { switch key {
    case "exposure": exposure
    case "contrast": contrast
    case "highlights": highlights
    case "shadows": shadows
    case "whites": whites
    case "blacks": blacks
    case "temperature": temperature
    case "tint": tint
    case "vibrance": vibrance
    case "saturation": saturation
    case "texture": texture
    case "clarity": clarity
    case "dehaze": dehaze
    case "vignetteAmount": vignetteAmount
    case "vignetteMidpoint": vignetteMidpoint
    case "vignetteRoundness": vignetteRoundness
    case "vignetteFeather": vignetteFeather
    case "vignetteHighlights": vignetteHighlights
    case "grainAmount": grainAmount
    case "grainSize": grainSize
    case "grainRoughness": grainRoughness
    case "curveHighlights": curveHighlights
    case "curveLights": curveLights
    case "curveDarks": curveDarks
    case "curveShadows": curveShadows
    case "sharpenAmount": sharpenAmount
    case "sharpenRadius": sharpenRadius
    case "sharpenDetail": sharpenDetail
    case "sharpenMasking": sharpenMasking
    case "noiseLuminance": noiseLuminance
    case "noiseLuminanceDetail": noiseLuminanceDetail
    case "noiseColor": noiseColor
    case "noiseColorDetail": noiseColorDetail
    case "gradeBlending": gradeBlending
    case "gradeBalance": gradeBalance
    default: 0
    } }
    set { switch key {
    case "exposure": exposure = newValue
    case "contrast": contrast = newValue
    case "highlights": highlights = newValue
    case "shadows": shadows = newValue
    case "whites": whites = newValue
    case "blacks": blacks = newValue
    case "temperature": temperature = newValue
    case "tint": tint = newValue
    case "vibrance": vibrance = newValue
    case "saturation": saturation = newValue
    case "texture": texture = newValue
    case "clarity": clarity = newValue
    case "dehaze": dehaze = newValue
    case "vignetteAmount": vignetteAmount = newValue
    case "vignetteMidpoint": vignetteMidpoint = newValue
    case "vignetteRoundness": vignetteRoundness = newValue
    case "vignetteFeather": vignetteFeather = newValue
    case "vignetteHighlights": vignetteHighlights = newValue
    case "grainAmount": grainAmount = newValue
    case "grainSize": grainSize = newValue
    case "grainRoughness": grainRoughness = newValue
    case "curveHighlights": curveHighlights = newValue
    case "curveLights": curveLights = newValue
    case "curveDarks": curveDarks = newValue
    case "curveShadows": curveShadows = newValue
    case "sharpenAmount": sharpenAmount = newValue
    case "sharpenRadius": sharpenRadius = newValue
    case "sharpenDetail": sharpenDetail = newValue
    case "sharpenMasking": sharpenMasking = newValue
    case "noiseLuminance": noiseLuminance = newValue
    case "noiseLuminanceDetail": noiseLuminanceDetail = newValue
    case "noiseColor": noiseColor = newValue
    case "noiseColorDetail": noiseColorDetail = newValue
    case "gradeBlending": gradeBlending = newValue
    case "gradeBalance": gradeBalance = newValue
    default: break
    } }
  }
  public func validate() throws {
    for c in Self.controls {
      let v = self[c.key]
      guard v.isFinite, (c.minimum...c.maximum).contains(v) else { throw CraftError.invalid("Invalid Camera Raw \(c.title).") }
    }
    guard pixelScale.isFinite, (0.01...16).contains(pixelScale),
      ["highlightPriority","colorPriority","paintOverlay"].contains(vignetteStyle),
      curveSplits.count == 3, curveSplits.allSatisfy({ $0.isFinite && (5...95).contains($0) }),
      curveSplits[0] < curveSplits[1], curveSplits[1] < curveSplits[2] else { throw CraftError.invalid("Invalid Camera Raw curve, scale or vignette settings.") }
    for values in [hslHue,hslSat,hslLum] {
      guard values.count == 8, values.allSatisfy({ $0.isFinite && (-100...100).contains($0) }) else { throw CraftError.invalid("Color Mixer requires eight values in -100...100.") }
    }
    for points in [pointCurve,pointCurveRed,pointCurveGreen,pointCurveBlue] {
      guard points.isEmpty || (2...16).contains(points.count) else { throw CraftError.invalid("Point curves require 2...16 points.") }
      var previous: Float = -1
      for p in points {
        guard p.count == 2, p.allSatisfy({ $0.isFinite && (0...255).contains($0) }), p[0]-previous >= 1 else { throw CraftError.invalid("Curve inputs must increase by at least one level.") }
        previous = p[0]
      }
    }
    for w in [gradeShadows,gradeMidtones,gradeHighlights,gradeGlobal] {
      guard w.hue.isFinite,w.sat.isFinite,w.lum.isFinite,(0...360).contains(w.hue),(0...100).contains(w.sat),(-100...100).contains(w.lum) else { throw CraftError.invalid("Invalid color grading wheel.") }
    }
  }
  public var isIdentity: Bool {
    let active = [temperature,tint,exposure,contrast,highlights,shadows,whites,blacks,texture,clarity,dehaze,vibrance,saturation,curveHighlights,curveLights,curveDarks,curveShadows,sharpenAmount,noiseLuminance,noiseColor,grainAmount,vignetteAmount]
    return active.allSatisfy({ $0 == 0 }) && [hslHue,hslSat,hslLum].joined().allSatisfy({ $0 == 0 }) &&
      [pointCurve,pointCurveRed,pointCurveGreen,pointCurveBlue].allSatisfy({ $0.isEmpty || ($0.first == [0,0] && $0.last == [255,255] && $0.allSatisfy({ $0[0] == $0[1] })) }) &&
      [gradeShadows,gradeMidtones,gradeHighlights,gradeGlobal].allSatisfy({ $0.sat == 0 && $0.lum == 0 })
  }
  /// Partial public settings merge defaults. Reject unknown keys and booleans in numeric fields.
  public static func decodeJSON(_ data: Data) throws -> Self {
    guard data.count <= 32768, let values = try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw CraftError.invalid("Camera Raw settings must be a bounded object.") }
    var defaults = try JSONSerialization.jsonObject(with:JSONEncoder().encode(Self())) as! [String:Any]
    func matches(_ value: Any,_ model: Any) -> Bool {
      if let template = model as? [String:Any] {
        guard let object = value as? [String:Any], Set(object.keys).isSubset(of:Set(template.keys)) else { return false }
        return object.allSatisfy { matches($0.value,template[$0.key]!) }
      }
      if model is [Any] {
        guard let array = value as? [Any] else { return false }
        return array.allSatisfy { item in
          if let nested = item as? [Any] { return nested.allSatisfy { matches($0,NSNumber(value:0)) } }
          return matches(item,NSNumber(value:0))
        }
      }
      if model is NSNumber { return (value as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite } ?? false }
      return value is String
    }
    for (key,value) in values {
      guard let model = defaults[key], matches(value,model) else { throw CraftError.invalid("Unknown or invalid Camera Raw parameter: \(key).") }
      if var wheel = model as? [String:Any], let supplied = value as? [String:Any] { wheel.merge(supplied) { _,new in new }; defaults[key] = wheel }
      else { defaults[key] = value }
    }
    let result = try JSONDecoder().decode(Self.self,from:JSONSerialization.data(withJSONObject:defaults))
    try result.validate(); return result
  }
}
