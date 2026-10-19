import Foundation

public enum CraftError: Error, LocalizedError, Equatable, Sendable {
  case invalid(String)
  case unsupported(String)
  case unavailable(String)
  public var errorDescription: String? {
    switch self {
    case .invalid(let s), .unsupported(let s), .unavailable(let s): s
    }
  }
}
@inline(__always) public func unit(_ x: Float) -> Float { x.isFinite ? min(1, max(0, x)) : 0 }
public enum PixelDepth: String, Codable, CaseIterable, Sendable {
  case u8 = "8 bit"
  case u16 = "16 bit"
  case f32 = "32 bit"
  public func quantize(_ x: Float) -> Float {
    switch self {
    case .u8: (unit(x) * 255).rounded() / 255
    case .u16: (unit(x) * 65535).rounded() / 65535
    case .f32: x.isFinite ? x : 0
    }
  }
}
public struct Pixel: Codable, Equatable, Sendable {
  public var r: Float
  public var g: Float
  public var b: Float
  public var a: Float
  public init(_ r: Float, _ g: Float, _ b: Float, _ a: Float = 1) {
    self.r = r
    self.g = g
    self.b = b
    self.a = a
  }
  public static let clear = Pixel(0, 0, 0, 0)
  public static let white = Pixel(1, 1, 1)
  public static let black = Pixel(0, 0, 0)
  public var rgb: SIMD3<Float> { SIMD3(r, g, b) }
  public var isFinite: Bool { r.isFinite && g.isFinite && b.isFinite && a.isFinite }
  public func hasSameBits(as other: Pixel) -> Bool {
    r.bitPattern == other.r.bitPattern && g.bitPattern == other.g.bitPattern
      && b.bitPattern == other.b.bitPattern && a.bitPattern == other.a.bitPattern
  }
  public func quantized(_ depth: PixelDepth) -> Pixel {
    Pixel(depth.quantize(r), depth.quantize(g), depth.quantize(b), unit(depth.quantize(a)))
  }
}

/// Extended sRGB transfer between the editor's encoded color values and linear
/// HDR storage/compositing. Surface declares its stored sample representation.
public enum SRGBTransfer {
  public static func linear(_ value: Float) -> Float {
    if value == 0 || abs(value) == 1 { return value }
    let a = abs(value)
    let v = a <= 0.04045 ? a / 12.92 : pow((a + 0.055) / 1.055, 2.4)
    return value < 0 ? -v : v
  }
  public static func encoded(_ value: Float) -> Float {
    if value == 0 || abs(value) == 1 { return value }
    let a = abs(value)
    let v = a <= 0.0031308 ? a * 12.92 : 1.055 * pow(a, 1 / 2.4) - 0.055
    return value < 0 ? -v : v
  }
  public static func linear(_ p: Pixel) -> Pixel {
    Pixel(linear(p.r), linear(p.g), linear(p.b), p.a)
  }
  public static func encoded(_ p: Pixel) -> Pixel {
    Pixel(encoded(p.r), encoded(p.g), encoded(p.b), p.a)
  }
}

// Translated from PhotoCraft crates/color/src/blend.rs (MIT OR Apache-2.0).
public enum BlendMode: String, CaseIterable, Codable, Sendable {
  case normal = "Normal"
  case dissolve = "Dissolve"
  case darken = "Darken"
  case multiply = "Multiply"
  case colorBurn = "Color Burn"
  case linearBurn = "Linear Burn"
  case darkerColor = "Darker Color"
  case lighten = "Lighten"
  case screen = "Screen"
  case colorDodge = "Color Dodge"
  case linearDodge = "Linear Dodge"
  case lighterColor = "Lighter Color"
  case overlay = "Overlay"
  case softLight = "Soft Light"
  case hardLight = "Hard Light"
  case vividLight = "Vivid Light"
  case linearLight = "Linear Light"
  case pinLight = "Pin Light"
  case hardMix = "Hard Mix"
  case difference = "Difference"
  case exclusion = "Exclusion"
  case subtract = "Subtract"
  case divide = "Divide"
  case hue = "Hue"
  case saturation = "Saturation"
  case color = "Color"
  case luminosity = "Luminosity"

  private func burn(_ b: Float, _ s: Float) -> Float {
    b >= 1 ? 1 : s <= 0 ? 0 : 1 - min(1, (1 - b) / s)
  }
  private func dodge(_ b: Float, _ s: Float) -> Float {
    b <= 0 ? 0 : s >= 1 ? 1 : min(1, b / (1 - s))
  }
  private func hard(_ b: Float, _ s: Float) -> Float {
    s <= 0.5 ? b * 2 * s : b + (2 * s - 1) - b * (2 * s - 1)
  }
  public func channel(_ b: Float, _ s: Float) -> Float {
    switch self {
    case .normal, .dissolve: return s
    case .darken: return min(b, s)
    case .multiply: return b * s
    case .colorBurn: return burn(b, s)
    case .linearBurn: return max(0, b + s - 1)
    case .lighten: return max(b, s)
    case .screen: return b + s - b * s
    case .colorDodge: return dodge(b, s)
    case .linearDodge: return min(1, b + s)
    case .overlay: return hard(s, b)
    case .hardLight: return hard(b, s)
    case .softLight:
      return s <= 0.5
        ? 2 * b * s + b * b * (1 - 2 * s) : 2 * b * (1 - s) + sqrt(max(0, b)) * (2 * s - 1)
    case .vividLight:
      return s <= 0 ? 0 : s >= 1 ? 1 : s <= 0.5 ? burn(b, 2 * s) : dodge(b, 2 * (s - 0.5))
    case .linearLight: return unit(b + 2 * s - 1)
    case .pinLight: return s <= 0.5 ? min(b, 2 * s) : max(b, 2 * s - 1)
    case .hardMix:
      let v: Float
      if s <= 0.5 {
        v = b >= 1 - 1e-4 ? 1 : s <= 0 ? 0 : 1 - min(1, (1 - b) / (2 * s))
      } else {
        v = b <= 1e-4 ? 0 : s >= 1 ? 1 : min(1, b / (2 * (1 - s)))
      }
      return v >= 0.5 - 1e-6 ? 1 : 0
    case .difference: return abs(b - s)
    case .exclusion: return b + s - 2 * b * s
    case .subtract: return max(0, b - s)
    case .divide: return s <= 0 ? (b <= 0 ? 0 : 1) : min(1, b / s)
    default: return s
    }
  }
  public func rgb(_ b: SIMD3<Float>, _ s: SIMD3<Float>) -> SIMD3<Float> {
    func lum(_ c: SIMD3<Float>) -> Float { 0.3 * c.x + 0.59 * c.y + 0.11 * c.z }
    func sat(_ c: SIMD3<Float>) -> Float { c.max() - c.min() }
    func setLum(_ c: SIMD3<Float>, _ l: Float) -> SIMD3<Float> {
      var o = c + SIMD3(repeating: l - lum(c))
      let n = o.min()
      let x = o.max()
      if n < 0 {
        o =
          abs(l - n) < 1e-12
          ? SIMD3(repeating: l) : SIMD3(repeating: l) + (o - SIMD3(repeating: l)) * l / (l - n)
      }
      if x > 1 {
        o =
          abs(x - l) < 1e-12
          ? SIMD3(repeating: l)
          : SIMD3(repeating: l) + (o - SIMD3(repeating: l)) * (1 - l) / (x - l)
      }
      return o
    }
    func setSat(_ c: SIMD3<Float>, _ s: Float) -> SIMD3<Float> {
      let i = [0, 1, 2].sorted { c[$0] < c[$1] }
      var o = SIMD3<Float>.zero
      if c[i[2]] > c[i[0]] {
        o[i[1]] = (c[i[1]] - c[i[0]]) * s / (c[i[2]] - c[i[0]])
        o[i[2]] = s
      }
      return o
    }
    switch self {
    case .hue: return setLum(setSat(s, sat(b)), lum(b))
    case .saturation: return setLum(setSat(b, sat(s)), lum(b))
    case .color: return setLum(s, lum(b))
    case .luminosity: return setLum(b, lum(s))
    case .darkerColor: return lum(s) < lum(b) ? s : b
    case .lighterColor: return lum(s) > lum(b) ? s : b
    default: return SIMD3(channel(b.x, s.x), channel(b.y, s.y), channel(b.z, s.z))
    }
  }
  public func composite(
    backdrop b: Pixel, source s: Pixel, opacity: Float = 1, x: Int = 0, y: Int = 0
  ) -> Pixel {
    var a = unit(s.a * opacity)
    if self == .dissolve {
      var h =
        UInt64(truncatingIfNeeded: x) &* 0x9e37_79b1_85eb_ca87 ^ UInt64(truncatingIfNeeded: y)
        &* 0xc2b2_ae3d_27d4_eb4f
      h ^= h >> 33
      h &*= 0xff51_afd7_ed55_8ccd
      h ^= h >> 33
      a = Float(h & 0xffffff) / 16_777_216 < a ? 1 : 0
    }
    if a <= 0 { return b }
    let ab = unit(b.a)
    let ao = a + ab * (1 - a)
    let c = ((1 - a) * ab * b.rgb + (1 - ab) * a * s.rgb + a * ab * rgb(b.rgb, s.rgb)) / ao
    return Pixel(c.x, c.y, c.z, ao)
  }
}
