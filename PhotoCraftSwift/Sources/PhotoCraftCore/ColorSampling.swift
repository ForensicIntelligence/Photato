import Foundation

public enum ColorSampleSource: String, CaseIterable, Codable, Sendable {
  case current = "Current Layer"
  case currentAndBelow = "Current & Below"
  case all = "All Layers"
  case allNoAdjustments = "All Layers no Adjustments"
  case currentAndBelowNoAdjustments = "Current & Below no Adjustments"
}
public enum ColorSampleTarget: String, CaseIterable, Codable, Sendable { case none, foreground, background }
public struct ColorSampleSettings: Equatable, Codable, Sendable {
  public static let sizes = [1,3,5,11,31,51,101]
  public var size = 1
  public var source: ColorSampleSource = .all
  public var showRing = true
  public init() {}
  public func validate() throws {
    guard Self.sizes.contains(size) else { throw CraftError.invalid("Choose Point Sample or a supported average size.") }
  }
}
public struct ColorSampleResult: Equatable, Sendable {
  public let color: Pixel
  public let region: IntRect
  public let visitedPixels: Int
  public let contributingPixels: Int
  public let coverage: Float
  public init(color:Pixel,region:IntRect,visitedPixels:Int,contributingPixels:Int,coverage:Float) {
    self.color=color;self.region=region;self.visitedPixels=visitedPixels;self.contributingPixels=contributingPixels;self.coverage=coverage
  }
}
public enum ColorAveraging {
  public static func region(x:Double,y:Double,width:Int,height:Int,size:Int)throws->IntRect {
    guard x.isFinite,y.isFinite,x>=0,y>=0,x<Double(width),y<Double(height),ColorSampleSettings.sizes.contains(size) else {throw CraftError.invalid("Sample inside the image with a supported sample size.")}
    let radius=size/2
    return IntRect(x:Int(floor(x))-radius,y:Int(floor(y))-radius,width:size,height:size).clipped(toWidth:width,height:height)
  }
  /// Integer documents average encoded values; RGB32 averages linear values.
  /// Alpha weights exclude hidden RGB. The paint color is opaque; coverage is
  /// returned separately. Photoshop precision/profile/alpha equivalence needs
  /// independent reference qualification.
  public static func sample(region:IntRect,depth:PixelDepth,pixel:(Int,Int)throws->Pixel)throws->ColorSampleResult {
    guard region.width>0,region.height>0,region.width<=101,region.height<=101 else {throw CraftError.invalid("Invalid color sample region.")}
    var r=0.0,g=0.0,b=0.0,a=0.0,contributors=0
    var point:Pixel?
    for y in region.y..<(region.y+region.height) {
      try Task.checkCancellation()
      for x in region.x..<(region.x+region.width) {
        let raw=try pixel(x,y);guard [raw.r,raw.g,raw.b,raw.a].allSatisfy({$0.isFinite}) else {throw CraftError.invalid("Sample colors must be finite.")};let alpha=Double(unit(raw.a));guard alpha>0 else {continue}
        contributors += 1;point=raw
        let p=depth == .f32 ? SRGBTransfer.linear(raw):raw
        r += Double(p.r)*alpha;g += Double(p.g)*alpha;b += Double(p.b)*alpha;a += alpha
      }
    }
    guard a>0,let point else {throw CraftError.invalid("The sample area has no visible color.")}
    let color:Pixel
    if region.width==1 && region.height==1 {color=Pixel(point.r,point.g,point.b)}
    else {
      let p=Pixel(Float(r/a),Float(g/a),Float(b/a))
      color=depth == .f32 ? SRGBTransfer.encoded(p):p
    }
    return .init(color:color,region:region,visitedPixels:region.width*region.height,contributingPixels:contributors,coverage:Float(a/Double(region.width*region.height)))
  }
  public static func sample(_ surface:Surface,x:Double,y:Double,size:Int)throws->ColorSampleResult {
    let area=try region(x:x,y:y,width:surface.width,height:surface.height,size:size)
    return try sample(region:area,depth:surface.depth){surface.pixel(x:$0,y:$1)}
  }
}
