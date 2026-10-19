import Foundation

public enum GradientMethod: String, CaseIterable, Codable, Sendable {
  case perceptual = "Perceptual"
  case linear = "Linear"
  case classic = "Classic"
  case stripes = "Stripes"
}

/// Dynamic foreground/background references are resolved once when a gradient is applied.
public enum GradientColor: Codable, Equatable, Sendable {
  case rgb(Pixel)
  case hsb(hue: Float, saturation: Float, brightness: Float)
  case gray(ink: Float)
  case foreground
  case background

  public func resolved(foreground: Pixel, background: Pixel) -> Pixel {
    let p: Pixel
    switch self {
    case .rgb(let value): p = value
    case .gray(let ink): p = Pixel(1 - ink, 1 - ink, 1 - ink)
    case .hsb(let hue, let saturation, let brightness):
      guard hue.isFinite, saturation.isFinite, brightness.isFinite else { return .clear }
      let remainder = hue.truncatingRemainder(dividingBy: 360)
      let h = (remainder < 0 ? remainder + 360 : remainder) / 60
      let c = brightness * saturation
      let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
      let rgb: SIMD3<Float>
      switch Int(h) {
      case 0: rgb = SIMD3(c, x, 0)
      case 1: rgb = SIMD3(x, c, 0)
      case 2: rgb = SIMD3(0, c, x)
      case 3: rgb = SIMD3(0, x, c)
      case 4: rgb = SIMD3(x, 0, c)
      default: rgb = SIMD3(c, 0, x)
      }
      let m = brightness - c
      p = Pixel(rgb.x + m, rgb.y + m, rgb.z + m)
    case .foreground: p = foreground
    case .background: p = background
    }
    return Pixel(p.r, p.g, p.b)
  }
}

public struct GradientColorStop: Codable, Equatable, Sendable {
  public var position: Float
  public var color: GradientColor
  /// Relative midpoint of the segment ending at this stop, matching the PSD descriptor.
  public var midpoint: Float
  public init(_ position: Float, _ color: GradientColor, midpoint: Float = 0.5) {
    self.position = position
    self.color = color
    self.midpoint = midpoint
  }
}

public struct GradientOpacityStop: Codable, Equatable, Sendable {
  public var position: Float
  public var opacity: Float
  public var midpoint: Float
  public init(_ position: Float, _ opacity: Float, midpoint: Float = 0.5) {
    self.position = position
    self.opacity = opacity
    self.midpoint = midpoint
  }
}

/// Retains editable controls, rather than replacing a gradient with densely baked stops.
public struct GradientDefinition: Codable, Equatable, Sendable {
  public static let maxStops = 1000
  public var name: String
  public var colors: [GradientColorStop]
  public var opacity: [GradientOpacityStop]
  public var smoothness: Float
  public var method: GradientMethod
  public init(
    name: String = "Custom", colors: [GradientColorStop],
    opacity: [GradientOpacityStop] = [], smoothness: Float = 1,
    method: GradientMethod = .perceptual
  ) {
    self.name = name
    self.colors = colors
    self.opacity = opacity
    self.smoothness = smoothness
    self.method = method
  }
  public static var foregroundToBackground: Self {
    .init(name: "Foreground to Background", colors: [.init(0, .foreground), .init(1, .background)])
  }
  public static var foregroundToTransparent: Self {
    .init(
      name: "Foreground to Transparent", colors: [.init(0, .foreground), .init(1, .foreground)],
      opacity: [.init(0, 1), .init(1, 0)])
  }
  public static var blackToWhite: Self {
    .init(name: "Black, White", colors: [.init(0, .rgb(.black)), .init(1, .rgb(.white))])
  }
  public func validate() throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      name.utf16.count <= 65_535, !colors.isEmpty, colors.count <= Self.maxStops,
      opacity.count <= Self.maxStops, smoothness.isFinite, (0...1).contains(smoothness)
    else { throw CraftError.invalid("Invalid gradient name, stop count or smoothness.") }
    func valid(_ position: Float, _ midpoint: Float) -> Bool {
      position.isFinite && (0...1).contains(position)
        && midpoint.isFinite && (0...1).contains(midpoint)
    }
    for stop in colors {
      guard valid(stop.position, stop.midpoint) else {
        throw CraftError.invalid("Invalid gradient color stop.")
      }
      switch stop.color {
      case .rgb(let p):
        guard p.isFinite, (0...1).contains(p.r), (0...1).contains(p.g),
          (0...1).contains(p.b), p.a == 1
        else {
          throw CraftError.invalid(
            "Gradient colors must be opaque RGB; use opacity stops for transparency.")
        }
      case .hsb(let h, let s, let b):
        guard h.isFinite, abs(h) <= 360_000, s.isFinite, b.isFinite,
          (0...1).contains(s), (0...1).contains(b)
        else { throw CraftError.invalid("Invalid gradient HSB color.") }
      case .gray(let ink):
        guard ink.isFinite, (0...1).contains(ink) else {
          throw CraftError.invalid("Invalid gradient grayscale color.")
        }
      case .foreground, .background: break
      }
    }
    for stop in opacity {
      guard valid(stop.position, stop.midpoint), stop.opacity.isFinite,
        (0...1).contains(stop.opacity)
      else { throw CraftError.invalid("Invalid gradient opacity stop.") }
    }
  }
  public func resolved(foreground: Pixel, background: Pixel) throws -> Self {
    try validate()
    var result = self
    result.colors = colors.map { stop in
      switch stop.color {
      case .foreground, .background:
        return .init(
          stop.position, .rgb(stop.color.resolved(foreground: foreground, background: background)),
          midpoint: stop.midpoint)
      default: return stop
      }
    }
    try result.validate()
    return result
  }
}

/// Native port of PhotoCraft's gradient ramp and gradient_bake interpolation math.
/// Continuous interpolation and discrete Stripes retain their controls without a stop bake.
public struct GradientRamp: Sendable {
  private struct Stop: Sendable {
    var position: Float
    var midpoint: Float
    var value: SIMD3<Float>
    var tangent = SIMD3<Float>.zero
  }
  private let colors: [Stop]
  private let opacity: [Stop]
  private let smoothness: Float
  private let method: GradientMethod
  public init(
    _ gradient: GradientDefinition, foreground: Pixel = .black, background: Pixel = .white
  ) throws {
    let gradient = try gradient.resolved(foreground: foreground, background: background)
    method = gradient.method
    smoothness = gradient.smoothness
    opacity = Self.prepare(
      gradient.opacity.sorted { $0.position < $1.position }.map {
        Stop(position: $0.position, midpoint: $0.midpoint, value: SIMD3(repeating: $0.opacity))
      })
    let prepared = gradient.colors.sorted { $0.position < $1.position }.map {
      Stop(
        position: $0.position, midpoint: $0.midpoint,
        value: Self.intoSpace(
          $0.color.resolved(foreground: foreground, background: background).rgb,
          method: gradient.method))
    }
    colors = Self.prepare(prepared)
  }
  private static func prepare(_ input: [Stop]) -> [Stop] {
    var prepared = input
    if prepared.count > 1 {
      for i in prepared.indices {
        let a = max(0, i - 1)
        let b = min(prepared.count - 1, i + 1)
        let distance = max(1e-6, prepared[b].position - prepared[a].position)
        let half: Float = i == 0 || i == prepared.count - 1 ? 0.5 : 1
        prepared[i].tangent = (prepared[b].value - prepared[a].value) / distance * half
      }
    }
    return prepared
  }
  public static func midpoint(_ u: Float, _ midpoint: Float) -> Float {
    let m = min(0.95, max(0.05, midpoint))
    if abs(m - 0.5) < 1e-6 { return u }
    return u <= m ? 0.5 * u / m : 0.5 + 0.5 * (u - m) / (1 - m)
  }
  /// First stop at or after t. Stable ordering preserves coincident hard color transitions.
  private static func colorEnd(_ t: Float, stops colors: [Stop]) -> Int {
    var low = 0
    var high = colors.count - 1
    while low < high {
      let mid = (low + high) / 2
      if colors[mid].position < t { low = mid + 1 } else { high = mid }
    }
    return low
  }
  public func sample(_ t: Float) -> Pixel {
    guard t.isFinite else { return .clear }
    let t = unit(t)
    if method == .stripes {
      let rgb = Self.held(colors, t: t)
      let alpha = opacity.isEmpty ? 1 : Self.held(opacity, t: t).x
      return Pixel(rgb.x, rgb.y, rgb.z, alpha)
    }
    let rgb = Self.outOfSpace(Self.sample(colors, t: t, smoothness: smoothness), method: method)
    let alpha = opacity.isEmpty ? 1 : unit(Self.sample(opacity, t: t, smoothness: smoothness).x)
    return Pixel(rgb.x, rgb.y, rgb.z, alpha)
  }
  /// Photoshop Stripes holds each stop until the next position. Midpoints and
  /// smoothness do not change the bands. Stable coincident stops use the last value.
  private static func held(_ stops: [Stop], t: Float) -> SIMD3<Float> {
    var low = 0
    var high = stops.count
    while low < high {
      let middle = (low + high) / 2
      if stops[middle].position <= t { low = middle + 1 } else { high = middle }
    }
    return stops[max(0, low - 1)].value
  }
  private static func sample(_ colors: [Stop], t: Float, smoothness: Float) -> SIMD3<Float> {
    let value: SIMD3<Float>
    if t <= colors[0].position {
      value = colors[0].value
    } else if t >= colors[colors.count - 1].position {
      value = colors[colors.count - 1].value
    } else {
      let i = colorEnd(t, stops: colors)
      let a = colors[i - 1]
      let b = colors[i]
      let h = max(1e-6, b.position - a.position)
      let u = Self.midpoint((t - a.position) / h, b.midpoint)
      let linear = a.value + (b.value - a.value) * u
      if smoothness == 0 {
        value = linear
      } else {
        let u2 = u * u
        let u3 = u * u * u
        let h00 = 2 * u3 - 3 * u2 + 1
        let h10 = u3 - 2 * u2 + u
        let h01 = -2 * u3 + 3 * u2
        let h11 = u3 - u2
        let spline = h00 * a.value + h10 * h * a.tangent + h01 * b.value + h11 * h * b.tangent
        value = linear + (spline - linear) * smoothness
      }
    }
    return value
  }
  // Keep the original scalar ordering and constants for executable Rust oracle comparisons.
  static func linear(_ c: Float) -> Float {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
  }
  static func encoded(_ c: Float) -> Float {
    let c = unit(c)
    return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
  }
  static func intoSpace(_ p: SIMD3<Float>, method: GradientMethod) -> SIMD3<Float> {
    if method == .classic || method == .stripes { return p }
    let r = linear(p.x)
    let g = linear(p.y)
    let b = linear(p.z)
    if method == .linear { return SIMD3(r, g, b) }
    let l = cbrt(0.41222146 * r + 0.53633255 * g + 0.051445995 * b)
    let m = cbrt(0.2119035 * r + 0.6806995 * g + 0.10739696 * b)
    let s = cbrt(0.08830246 * r + 0.28171885 * g + 0.6299787 * b)
    return SIMD3(
      0.21045426 * l + 0.7936178 * m - 0.004072047 * s,
      1.9779985 * l - 2.4285922 * m + 0.4505937 * s,
      0.025904037 * l + 0.78277177 * m - 0.80867577 * s)
  }
  static func outOfSpace(_ p: SIMD3<Float>, method: GradientMethod) -> SIMD3<Float> {
    if method == .classic || method == .stripes {
      return SIMD3(unit(p.x), unit(p.y), unit(p.z))
    }
    if method == .linear { return SIMD3(encoded(p.x), encoded(p.y), encoded(p.z)) }
    func cube(_ v: Float) -> Float { v * v * v }
    let l = cube(p.x + 0.39633778 * p.y + 0.21580376 * p.z)
    let m = cube(p.x - 0.105561346 * p.y - 0.06385417 * p.z)
    let s = cube(p.x - 0.08948418 * p.y - 1.2914855 * p.z)
    return SIMD3(
      encoded(4.0767417 * l - 3.3077116 * m + 0.23096994 * s),
      encoded(-1.268438 * l + 2.6097574 * m - 0.34131938 * s),
      encoded(-0.0041960863 * l - 0.7034186 * m + 1.7076147 * s))
  }
  public static func dither(_ pixel: Pixel, x: Int, y: Int) -> Pixel {
    var hash =
      (UInt32(truncatingIfNeeded: x) &* 0x9E37_79B1)
      ^ (UInt32(truncatingIfNeeded: y) &* 0x85EB_CA77)
    hash ^= hash >> 15
    hash = hash &* 0x2C1B_3C6D
    hash ^= hash >> 12
    let noise = (Float(hash & 0xFFFF) / 65535 - 0.5) / 255
    return Pixel(unit(pixel.r + noise), unit(pixel.g + noise), unit(pixel.b + noise), pixel.a)
  }
}
