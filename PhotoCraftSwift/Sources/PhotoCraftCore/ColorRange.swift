import Foundation

/// Independent native selection model. These formulas are not qualified as Adobe's kernel.
public struct ColorRangeSettings: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case sampled, reds, yellows, greens, cyans, blues, magentas, highlights, midtones, shadows
    public var title: String { switch self {
      case .sampled: "Sampled Colors"; case .reds: "Reds"; case .yellows: "Yellows"
      case .greens: "Greens"; case .cyans: "Cyans"; case .blues: "Blues"; case .magentas: "Magentas"
      case .highlights: "Highlights"; case .midtones: "Midtones"; case .shadows: "Shadows"
    } }
  }
  public var kind: Kind = .sampled
  public var fuzziness: Double = 40
  public var localized: Bool = false
  public var range: Double = 100
  public var minimum: Double = 105
  public var maximum: Double = 150
  public var invert: Bool = false
  public var samples: [ToneColorSample] = [.init(color: .black)]
  public init() {}
  public func validate() throws {
    guard fuzziness.isFinite, (0...200).contains(fuzziness), range.isFinite, (0...100).contains(range),
      minimum.isFinite, maximum.isFinite, (0...255).contains(minimum), (0...255).contains(maximum), minimum <= maximum,
      samples.count <= 128, samples.allSatisfy({ sample in
        let p=sample.color
        return p.isFinite && (0...1).contains(p.r) && (0...1).contains(p.g) && (0...1).contains(p.b) && (0...1).contains(p.a)
          && (sample.point.map { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } ?? true)
      }), kind != .sampled || samples.contains(where: { !$0.subtract }),
      !localized || kind != .sampled || samples.allSatisfy({ $0.point != nil }) else {
      throw CraftError.invalid("Invalid Color Range settings. Samples use sRGB colors and normalized image positions; localized samples require positions.")
    }
  }
  public func presetData() throws -> Data {
    try validate(); return try JSONEncoder().encode(Preset(version:1,settings:self))
  }
  public static func preset(_ data:Data) throws -> Self {
    guard data.count <= 131_072 else { throw CraftError.invalid("Color Range preset exceeds128KiB.") }
    let value=try JSONDecoder().decode(Preset.self,from:data)
    guard value.version==1 else { throw CraftError.unsupported("Unknown Photato Color Range preset version.") }
    try value.settings.validate(); return value.settings
  }
  private struct Preset: Codable { let version:Int; let settings:ColorRangeSettings }
}

public enum ColorRangeSelection {
  private static func lab(_ p:Pixel)->SIMD3<Double> {
    func linear(_ x:Float)->Double { let x=Double(x); return x<=0.04045 ? x/12.92:pow((x+0.055)/1.055,2.4) }
    let r=linear(p.r),g=linear(p.g),b=linear(p.b)
    func f(_ t:Double)->Double { t>216/24389 ? cbrt(t):(24389/27*t+16)/116 }
    let x=f((0.4124564*r+0.3575761*g+0.1804375*b)/0.95047)
    let y=f(0.2126729*r+0.7151522*g+0.0721750*b)
    let z=f((0.0193339*r+0.1191920*g+0.9503041*b)/1.08883)
    return SIMD3(116*y-16,500*(x-y),200*(y-z))
  }
  private static func unit(_ v:Double)->Double { min(1,max(0,v)) }
  public static func mask(_ source:Surface,settings s:ColorRangeSettings) throws -> SelectionMask {
    try s.validate(); try Task.checkCancellation()
    let samples=s.samples.map { ($0,lab($0.color)) }
    func colorWeight(_ p:Pixel)->Double {
      let rgb=[Double(p.r),Double(p.g),Double(p.b)],lo=rgb.min()!,hi=rgb.max()!,chroma=hi-lo
      if s.kind == .sampled {
        let v=lab(p);var add=0.0,subtract=0.0
        for (sample,target) in samples {
          let d=v-target,distance=sqrt(d.x*d.x+d.y*d.y+d.z*d.z)
          let a=s.fuzziness==0 ? (distance<0.000001 ? 1.0:0.0):unit(1-distance/s.fuzziness)
          if sample.subtract { subtract=max(subtract,a) } else { add=max(add,a) }
        }
        return min(add,1-subtract)
      }
      if [.highlights,.midtones,.shadows].contains(s.kind) {
        let l=(0.2126*rgb[0]+0.7152*rgb[1]+0.0722*rgb[2])*255
        let distance=s.kind == .shadows ? max(0,l-s.maximum):s.kind == .highlights ? max(0,s.minimum-l):max(0,s.minimum-l,l-s.maximum)
        return distance==0 ? 1:(s.fuzziness==0 ? 0:unit(1-distance/s.fuzziness))
      }
      guard chroma>0.000001 else { return 0 }
      var h:Double
      if hi==rgb[0] { h=(rgb[1]-rgb[2])/chroma; if h<0 { h+=6 } }
      else if hi==rgb[1] { h=(rgb[2]-rgb[0])/chroma+2 }
      else { h=(rgb[0]-rgb[1])/chroma+4 }
      let centers:[ColorRangeSettings.Kind:Double] = [.reds:0,.yellows:1,.greens:2,.cyans:3,.blues:4,.magentas:5]
      let center=centers[s.kind]!
      let d=min(abs(h-center),6-abs(h-center)),width=0.5+s.fuzziness/200
      return unit(1-d/width)*unit(chroma*4)
    }
    func finish(_ weight:Double,_ p:Pixel)->Pixel {
      let a=unit(Double(p.a)),v=Float((unit((s.invert ? 1-weight:weight)*a)*255).rounded()/255)
      return Pixel(v,v,v)
    }
    let coverage:Surface
    if s.localized && s.kind == .sampled {
      // Coordinate-dependent work is restricted to the sample support bounds.
      let radius=max(0.5,s.range/100*hypot(Double(source.width),Double(source.height)))
      var bounds:IntRect?
      for (sample,_) in samples where !sample.subtract {
        let p=sample.point!,x=p.x*Double(source.width),y=p.y*Double(source.height)
        let x0=max(0,Int(floor(x-radius))),y0=max(0,Int(floor(y-radius)))
        let x1=min(source.width,Int(ceil(x+radius))),y1=min(source.height,Int(ceil(y+radius)))
        let rect=IntRect(x:x0,y:y0,width:max(0,x1-x0),height:max(0,y1-y0))
        if let b=bounds {let xx=min(b.x,rect.x),yy=min(b.y,rect.y);bounds=IntRect(x:xx,y:yy,width:max(b.x+b.width,rect.x+rect.width)-xx,height:max(b.y+b.height,rect.y+rect.height)-yy)} else {bounds=rect}
      }
      var out=try source.mappedStoredSamples(encoding:.sRGB) { finish(0,$0) }
      if let bounds { for y in bounds.y..<(bounds.y+bounds.height) { try Task.checkCancellation();for x in bounds.x..<(bounds.x+bounds.width) {
        let p=source.pixel(x:x,y:y),v=lab(p);var add=0.0,subtract=0.0
        for (sample,target) in samples {
          let d=v-target,distance=sqrt(d.x*d.x+d.y*d.y+d.z*d.z),q=sample.point!
          let color=s.fuzziness==0 ? (distance<0.000001 ? 1.0:0.0):unit(1-distance/s.fuzziness)
          let spatial=unit(1-hypot(Double(x)+0.5-q.x*Double(source.width),Double(y)+0.5-q.y*Double(source.height))/radius)
          let a=color*spatial
          if sample.subtract { subtract=max(subtract,a) } else { add=max(add,a) }
        }
        out.setPixel(x:x,y:y,finish(min(add,1-subtract),p))
      } } }
      coverage=out
    } else {
      coverage=try source.mappedStoredSamples(encoding:.sRGB) { finish(colorWeight($0),$0) }
    }
    return try SelectionMask(coverage:coverage.converted(to:.u8))
  }
}
