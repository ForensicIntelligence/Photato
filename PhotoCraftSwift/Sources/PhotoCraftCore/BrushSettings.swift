import Foundation

/// Additional brush data is optional on legacy Brush values. Old actions retain their original painter.
public struct BrushBitmap: Codable, Equatable, Sendable {
  public var width: Int
  public var height: Int
  public var bytes: Data
  public init(width: Int, height: Int, bytes: Data) { self.width=width; self.height=height; self.bytes=bytes }
  public func validate() throws {
    guard width>0,height>0,width<=2500,height<=2500,bytes.count==width*height else { throw CraftError.invalid("A brush bitmap needs 1–2500 pixels per side and one byte per pixel.") }
  }
  public func sample(_ x:Double,_ y:Double, wrap:Bool=false)->Double {
    func value(_ x:Int,_ y:Int)->Double {
      if wrap { return Double(bytes[((y % height + height) % height)*width+(x % width + width) % width])/255 }
      guard x>=0,y>=0,x<width,y<height else { return 0 };return Double(bytes[y*width+x])/255
    }
    let ix=Int(floor(x)),iy=Int(floor(y)),fx=x-floor(x),fy=y-floor(y)
    let a=value(ix,iy)*(1-fx)+value(ix+1,iy)*fx,b=value(ix,iy+1)*(1-fx)+value(ix+1,iy+1)*fx
    return a*(1-fy)+b*fy
  }
}
public enum BrushControl:String,Codable,CaseIterable,Sendable {
  case off,fade,penPressure,penTilt,stylusWheel,rotation,initialDirection,direction
}
public struct BrushDynamic:Codable,Equatable,Sendable {
  public var jitter=0.0
  public var control:BrushControl = .off
  public var fadeSteps=25
  public var minimum=0.0
  public init() {}
  public func validate(maximum:Double=1) throws {
    guard jitter.isFinite,(0...maximum).contains(jitter),minimum.isFinite,(0...1).contains(minimum),(1...10000).contains(fadeSteps) else { throw CraftError.invalid("Invalid brush dynamics.") }
  }
}
public struct BrushShape:Codable,Equatable,Sendable {
  public var enabled=false
  public var size=BrushDynamic()
  public var angle=BrushDynamic()
  public var roundness=BrushDynamic()
  public var tiltScale=0.0
  public var flipX=false
  public var flipY=false
  public var projection=false
  public init() {}
}
public struct BrushScatter:Codable,Equatable,Sendable {
  public var enabled=false
  public var amount=BrushDynamic()
  public var bothAxes=false
  public var count=1
  public var countJitter=BrushDynamic()
  public init() {}
}
public enum BrushMaskMode:String,Codable,CaseIterable,Sendable {
  case multiply,subtract,darken,overlay,colorDodge,colorBurn,linearBurn,hardMix,linearHeight,height
  public func combine(_ v:Double,_ t:Double,_ d:Double)->Double {
    guard v>0 else { return 0 };func lerp(_ x:Double)->Double { v+(x-v)*d };let r:Double
    switch self {
    case .multiply:r=v*(1-d+d*t)
    case .subtract:r=max(0,v-d*(1-t))
    case .darken:r=min(v,1-d+d*t)
    case .overlay:r=lerp(v<0.5 ? 2*v*t:1-2*(1-v)*(1-t))
    case .colorDodge:r=lerp(min(1,v/max(0.001,1-t)))
    case .colorBurn:r=lerp(1-min(1,(1-v)/max(0.001,t)))
    case .linearBurn:r=lerp(max(0,v+t-1))
    case .hardMix:r=lerp(v+t>1 ? 1:0)
    case .linearHeight:r=v*min(1,max(0,(t-(1-d*v))*4+0.5))
    case .height:r=t>=1-d*v ? v:0
    }
    return min(1,max(0,r))
  }
}
public struct BrushTexture:Codable,Equatable,Sendable {
  public enum Pattern:String,Codable,CaseIterable,Sendable { case paper,canvas,noise,dots }
  public var enabled=false
  public var pattern:Pattern = .paper
  public var bitmap:BrushBitmap?
  public var scale=1.0
  public var brightness=0.0
  public var contrast=0.0
  public var invert=false
  public var eachTip=false
  public var mode:BrushMaskMode = .multiply
  public var depth=1.0
  public var depthJitter=BrushDynamic()
  public var seed:UInt64=1
  public init() {}
}
public struct BrushDual:Codable,Equatable,Sendable {
  public var enabled=false
  public var mode:BrushMaskMode = .multiply
  public var tip:BrushBitmap?
  public var size=20.0
  public var hardness=1.0
  public var roundness=1.0
  public var angle=0.0
  public var spacing=0.25
  public var scatter=0.0
  public var bothAxes=false
  public var count=1
  public var flip=false
  public init() {}
}
public struct BrushColorDynamics:Codable,Equatable,Sendable {
  public var enabled=false
  public var perTip=true
  public var foregroundBackground=BrushDynamic()
  public var hue=0.0
  public var saturation=0.0
  public var brightness=0.0
  public var purity=0.0
  public init() {}
}
public struct BrushTransfer:Codable,Equatable,Sendable {
  public var enabled=false
  public var opacity=BrushDynamic()
  public var flow=BrushDynamic()
  public init() {}
}
public struct BrushPose:Codable,Equatable,Sendable {
  public var enabled=false
  public var tiltX=0.0
  public var tiltY=0.0
  public var rotation=0.0
  public var pressure=1.0
  public var overrideTilt=false
  public var overrideRotation=false
  public var overridePressure=false
  public init() {}
}
public struct BrushSmoothing:Codable,Equatable,Sendable {
  public var amount=0.0
  public var pulledString=false
  public var catchUp=true
  public var catchUpOnEnd=true
  public var adjustForZoom=true
  public init() {}
}
public struct BrushSymmetry:Codable,Equatable,Sendable {
  public enum Mode:String,Codable,CaseIterable,Sendable { case off,vertical,horizontal,dual,radial,mandala }
  public var mode:Mode = .off
  public var center=PathPoint(0,0)
  public var count=4
  public init() {}
}
public struct BrushSettings:Codable,Equatable,Sendable {
  public var tip:BrushBitmap?
  public var spacing=0.25
  public var spacingEnabled=true
  public var angle=0.0
  public var roundness=1.0
  public var flipX=false
  public var flipY=false
  public var flow=1.0
  public var mode:BlendMode = .normal
  public var pressureSize=false
  public var pressureOpacity=false
  public var aliased=false
  public var shape=BrushShape()
  public var scattering=BrushScatter()
  public var texture=BrushTexture()
  public var dual=BrushDual()
  public var colorDynamics=BrushColorDynamics()
  public var transfer=BrushTransfer()
  public var pose=BrushPose()
  public var smoothing=BrushSmoothing()
  public var symmetry=BrushSymmetry()
  public var noise=false
  public var wetEdges=false
  public var buildUp=false
  public var buildUpRate=20.0
  public var protectTexture=false
  public var lockedSections:[String]=[]
  public var seed:UInt64=1
  public var zoom=1.0
  public init() {}
  public static let sections=["tip","shape","scattering","texture","dual","colorDynamics","transfer","pose","noise","wetEdges","buildUp","smoothing","protectTexture"]
  public var bitmapBytes:Int { (tip?.bytes.count ?? 0)+(dual.tip?.bytes.count ?? 0)+(texture.bitmap?.bytes.count ?? 0) }
  public func validate() throws {
    func check(_ x:Double,_ r:ClosedRange<Double>)throws { guard x.isFinite,r.contains(x) else { throw CraftError.invalid("Brush setting outside its supported range.") } }
    try tip?.validate();try dual.tip?.validate();try texture.bitmap?.validate()
    guard bitmapBytes<=16*1024*1024,Set(lockedSections).count==lockedSections.count,Set(lockedSections).isSubset(of:Set(Self.sections)),(1...16).contains(scattering.count),(1...16).contains(dual.count),(2...12).contains(symmetry.count),symmetry.center.x.isFinite,symmetry.center.y.isFinite,abs(symmetry.center.x)<=1_000_000,abs(symmetry.center.y)<=1_000_000 else { throw CraftError.invalid("Invalid brush resources, section locks or counts.") }
    for v in [roundness,dual.roundness] { try check(v,0.01...1) };for v in [angle,dual.angle] { try check(v,-360...360) }
    for v in [spacing,dual.spacing] { try check(v,0.01...10) };try check(flow,0...1);try check(dual.size,0.5...2048);try check(dual.hardness,0...1);try check(dual.scatter,0...10)
    try shape.size.validate();try shape.angle.validate();try shape.roundness.validate();try check(shape.tiltScale,0...2)
    try scattering.amount.validate(maximum:10);try scattering.countJitter.validate();try texture.depthJitter.validate();try colorDynamics.foregroundBackground.validate();try transfer.opacity.validate();try transfer.flow.validate()
    for v in [texture.depth,colorDynamics.hue,colorDynamics.saturation,colorDynamics.brightness,pose.pressure,smoothing.amount] { try check(v,0...1) }
    for v in [texture.brightness,texture.contrast,colorDynamics.purity] { try check(v,-1...1) }
    try check(texture.scale,0.01...10);try check(pose.tiltX,-90...90);try check(pose.tiltY,-90...90);try check(pose.rotation,-360...360);try check(buildUpRate,0.1...1000);try check(zoom,0.01...64)
  }
  public func picked(over current:Self)->Self {
    var b=self
    b.smoothing=current.smoothing;b.symmetry=current.symmetry;b.zoom=current.zoom;b.seed=current.seed;b.lockedSections=current.lockedSections
    for section in current.lockedSections {
      switch section {
      case "tip":b.tip=current.tip;b.angle=current.angle;b.roundness=current.roundness;b.flipX=current.flipX;b.flipY=current.flipY;b.spacing=current.spacing;b.spacingEnabled=current.spacingEnabled
      case "shape":b.shape=current.shape
      case "scattering":b.scattering=current.scattering
      case "texture":b.texture=current.texture
      case "dual":b.dual=current.dual
      case "colorDynamics":b.colorDynamics=current.colorDynamics
      case "transfer":b.transfer=current.transfer
      case "pose":b.pose=current.pose
      case "noise":b.noise=current.noise
      case "wetEdges":b.wetEdges=current.wetEdges
      case "buildUp":b.buildUp=current.buildUp;b.buildUpRate=current.buildUpRate
      case "protectTexture":b.protectTexture=current.protectTexture
      default:break
      }
    }
    if current.protectTexture && b.texture.enabled { b.texture.bitmap=current.texture.bitmap;b.texture.pattern=current.texture.pattern;b.texture.scale=current.texture.scale;b.texture.seed=current.texture.seed }
    return b
  }
}
