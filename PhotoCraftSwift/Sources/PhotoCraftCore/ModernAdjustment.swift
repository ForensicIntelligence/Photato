import Foundation

/// Native editable counterparts of the current Photoshop adjustment workflows.
/// The transfer is shared with PhotoCraft's Camera Raw work-alike, not Adobe's proprietary kernel.
public struct ModernAdjustment: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case colorVibrance, light, clarityDehaze, grain
    public var title: String {
      switch self {
      case .colorVibrance: "Color and vibrance"
      case .light: "Light"
      case .clarityDehaze: "Clarity and dehaze"
      case .grain: "Grain"
      }
    }
    public var keys: [String] {
      switch self {
      case .colorVibrance: ["temperature","tint","vibrance","saturation"]
      case .light: ["exposure","contrast","highlights","shadows","whites","blacks"]
      case .clarityDehaze: ["clarity","dehaze"]
      case .grain: ["grainAmount","grainSize","grainRoughness"]
      }
    }
  }
  public var kind: Kind
  public var values: [String:Float]
  public var seed: UInt32 = 0
  public init(_ kind: Kind) {
    self.kind=kind
    values=Dictionary(uniqueKeysWithValues:Self.controls(for:kind).map {($0.key,$0.initial)})
  }
  public static func controls(for kind:Kind)->[CameraRawSettings.Control] {
    kind.keys.compactMap {key in CameraRawSettings.controls.first {$0.key==key}}
  }
  public var settings: CameraRawSettings {
    var result=CameraRawSettings();for (key,value) in values {result[key]=value};result.seed=seed;return result
  }
  public var isIdentity: Bool { settings.isIdentity }
  public var needsNeighborhood: Bool {
    (kind == .clarityDehaze && !isIdentity) || (kind == .light && (values["highlights",default:0] != 0 || values["shadows",default:0] != 0))
  }
  public var variesWithPosition: Bool {kind == .grain && values["grainAmount",default:0] != 0}
  public func validate() throws {
    guard Set(values.keys)==Set(kind.keys),values.values.allSatisfy(\.isFinite) else {throw CraftError.invalid("Modern adjustment fields do not match their kind.")}
    try settings.validate()
  }
  public func validate(in document:CraftDocument) throws {
    try validate()
    guard document.colorMode == .rgb,document.inkMode==nil,document.restrictedMode==nil else {throw CraftError.unsupported("Modern adjustment layers require RGB.")}
    if kind == .light,document.depth == .f32 {throw CraftError.unsupported("Current Light requires RGB8/16. Use the existing Brightness/Contrast adjustment for RGB32.")}
    if needsNeighborhood,document.width>RasterFilterEngine.maximumPixels/document.height {throw CraftError.unsupported("This neighborhood adjustment currently requires at most8,388,608 pixels; larger spatial processing remains unqualified.")}
  }
  public func layer(in document:CraftDocument,name:String? = nil) throws -> Layer {
    try validate(in:document)
    var layer=Layer(name:name ?? kind.title,content:.adjustment(.modern(self)))
    if let coverage=try document.coverageSelection() {
      layer.mask=try coverage.coverageSurface()
      var properties=MaskProperties();properties.outside=0;layer.maskProperties=properties
    } else {layer.mask=try Surface(width:document.width,height:document.height,depth:document.depth,fill:.white)}
    return layer
  }
  public func neighborhood(_ source:Surface) throws -> Surface {
    try validate();return try CameraRawEngine.develop(source,settings:settings)
  }
}

public struct ModernAdjustmentTransfer: Sendable {
  private let kind:ModernAdjustment.Kind
  private let s:CameraRawSettings
  private let identity:Bool
  private let gains:SIMD3<Float>
  public init(_ value:ModernAdjustment) {
    kind=value.kind;s=value.settings;identity=value.isIdentity
    var g=SIMD3<Float>(1+0.35*s.temperature/100,1-0.25*s.tint/100,1-0.35*s.temperature/100)
    g *= pow(2,s.exposure)/CameraRawMath.luma(g);gains=g
  }
  /// Document coordinates keep grain stable across regional renders and pans.
  public func apply(_ p:Pixel,x:Int,y:Int)->Pixel {
    guard !identity,p.a>0,p.isFinite else {return p}
    typealias M=CameraRawMath
    var c=p.rgb
    if kind == .colorVibrance || kind == .light {
      if s.temperature != 0 || s.tint != 0 || s.exposure != 0 {
        for i in 0..<3 {c[i]=SRGBTransfer.encoded(max(0,SRGBTransfer.linear(c[i])*gains[i]))}
      }
      if kind == .colorVibrance,s.vibrance != 0 || s.saturation != 0 {
        let hsv=M.hsv(c),l=M.luma(c),skin=max(0,1-abs(hsv.x-25)/25)*0.5
        let k=max(0,1+s.saturation/100+s.vibrance/100*(1-hsv.y)*(1-skin))
        c=SIMD3(repeating:l)+(c-SIMD3(repeating:l))*k
      }
      if kind == .light,s.contrast != 0 || s.whites != 0 || s.blacks != 0 {
        let l=max(M.luma(c),0),lc=min(l,1)
        var v=lc
        v += s.whites/100*0.25*M.smooth(0.4,1,v)
        v += s.blacks/100*0.15*(1-M.smooth(0,0.45,v))
        v -= s.contrast/100*0.6*sin(2*Float.pi*unit(v))/(2*Float.pi)
        v=max(0,v)+(l-lc)
        if l>1e-5 {c *= v/l} else {c += SIMD3(repeating:v-l)}
      }
    }
    if kind == .grain,s.grainAmount>0 {
      let cell=1+s.grainSize/25,fx=Float(x)/cell,fy=Float(y)/cell,rough=s.grainRoughness/100
      let n=M.noise(fx,fy,s.seed)*(1-rough)+M.noise(fx*2.3,fy*2.3,s.seed &+ 7)*rough,l=unit(M.luma(c))
      c += SIMD3(repeating:(n-0.5)*2*s.grainAmount/100*0.12*(0.4+2.4*l*(1-l)))
    }
    return Pixel(c.x,c.y,c.z,p.a)
  }
}
