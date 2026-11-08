import Foundation

public struct HueSaturationValues: Codable, Equatable, Sendable {
  public var hue: Int
  public var saturation: Int
  public var lightness: Int
  public init(hue: Int = 0, saturation: Int = 0, lightness: Int = 0) {
    self.hue = hue
    self.saturation = saturation
    self.lightness = lightness
  }
  public var isNeutral: Bool { hue == 0 && saturation == 0 && lightness == 0 }
  public func validate(colorize: Bool = false) throws {
    guard (colorize ? -180...360 : -180...180).contains(hue), (-100...100).contains(lightness),
      (colorize ? 0...100 : -100...100).contains(saturation)
    else { throw CraftError.invalid("Hue/Saturation values are out of range.") }
  }
}

public struct HueRange: Codable, Equatable, Sendable {
  public var values: HueSaturationValues
  /// Optional sampled H/S/L swatch from Photoshop hue2; never used by the pixel transfer.
  public var displayColor: HueRangeColor?
  /// Unwrapped, ordered degrees: fade-in edge, full strength start/end, fade-out edge.
  public var bounds: [Int] {
    didSet {
      if bounds != oldValue, var color = displayColor {
        color.hue = representativeHue
        displayColor = color
      }
    }
  }
  public init(values: HueSaturationValues = .init(), bounds: [Int], displayColor: HueRangeColor? = nil) {
    self.values = values
    self.displayColor = displayColor
    self.bounds = bounds
  }
  public var swatchColor: HueRangeColor {
    displayColor ?? HueRangeColor(hue: representativeHue, saturation: 100, lightness: 50)
  }
  public static func neutral(_ index: Int) -> Self {
    let center = min(5, max(0, index)) * 60
    return .init(bounds: [center - 45, center - 15, center + 15, center + 45])
  }
  public static var defaults: [Self] { (0..<6).map(Self.neutral) }
  /// Representative swatch hue observed in Photoshop's hue2 range-color trailer:
  /// the wrapped inner-band midpoint, rounded down to a whole degree.
  public var representativeHue: Int {
    guard bounds.count == 4 else { return 0 }
    let sum = bounds[1] % 720 + bounds[2] % 720
    return ((sum % 720 + 720) % 720) / 2
  }
  public func validate() throws {
    try values.validate()
    try displayColor?.validate()
    guard bounds.count == 4, bounds.allSatisfy({ (-360...720).contains($0) }),
      zip(bounds, bounds.dropFirst()).allSatisfy({ $0 <= $1 }), bounds[3] - bounds[0] < 360
    else {
      throw CraftError.invalid(
        "Hue range edges must be ordered within one turn of the color wheel.")
    }
  }
  /// Unlike the upstream parser, reject impossible ordering instead of silently
  /// collapsing edges. Equivalent wrapped encodings share one canonical form.
  public static func fromWrapped(_ bounds: [Int]) throws -> [Int] {
    guard bounds.count == 4, bounds.allSatisfy({ (0...360).contains($0) }) else {
      throw CraftError.invalid("Invalid Hue/Saturation range angles.")
    }
    var result = [bounds[0] % 360]
    for value in bounds.dropFirst() {
      let previous = result.last!
      result.append(previous + ((value - previous) % 360 + 360) % 360)
    }
    let center = Double(result[1] + result[2]) / 2
    let shift = Int(floor((center + 30) / 360)) * 360
    result = result.map { $0 - shift }
    try HueRange(bounds: result).validate()
    return result
  }
  public mutating func moveEdge(_ index: Int, to degrees: Int) {
    guard (try? validate()) != nil, bounds.indices.contains(index) else { return }
    let low = index == 0 ? max(-360, bounds[3] - 359) : bounds[index - 1]
    let high = index == 3 ? min(720, bounds[0] + 359) : bounds[index + 1]
    bounds[index] = min(high, max(low, degrees))
  }
  /// PhotoCraft HueRange::weight, using the range origin to handle reds wrapping at 0°.
  public func weight(_ degrees: Float) -> Float {
    guard bounds.count == 4 else { return 0 }
    let a = Float(bounds[0])
    func relative(_ value: Float) -> Float { HSLColor.wrap(value - a, period: 360) }
    let b = relative(Float(bounds[1]))
    let c = max(b, relative(Float(bounds[2])))
    let d = max(c, relative(Float(bounds[3])))
    let h = relative(degrees)
    if h <= b { return b <= 0 ? 1 : h / b }
    if h <= c { return 1 }
    if h <= d { return d <= c ? 1 : (d - h) / (d - c) }
    return 0
  }
}

public struct HueSaturationAdjustment: Codable, Equatable, Sendable {
  public var master: HueSaturationValues
  public var colorization: HueSaturationValues
  public var colorize: Bool
  public var ranges: [HueRange]
  public init(
    master: HueSaturationValues = .init(),
    colorization: HueSaturationValues = .init(saturation: 25),
    colorize: Bool = false, ranges: [HueRange] = HueRange.defaults
  ) {
    self.master = master
    self.colorization = colorization
    self.colorize = colorize
    self.ranges = ranges
  }
  public enum Channel: String, CaseIterable, Sendable {
    case master = "Master"
    case reds = "Reds"
    case yellows = "Yellows"
    case greens = "Greens"
    case cyans = "Cyans"
    case blues = "Blues"
    case magentas = "Magentas"
    public var rangeIndex: Int? {
      switch self {
      case .master: nil
      case .reds: 0
      case .yellows: 1
      case .greens: 2
      case .cyans: 3
      case .blues: 4
      case .magentas: 5
      }
    }
  }
  public subscript(_ channel: Channel) -> HueSaturationValues {
    get {
      if colorize { return colorization }
      guard let index = channel.rangeIndex, ranges.indices.contains(index) else { return master }
      return ranges[index].values
    }
    set {
      if colorize {
        colorization = newValue
      } else if let index = channel.rangeIndex, ranges.indices.contains(index) {
        ranges[index].values = newValue
      } else {
        master = newValue
      }
    }
  }
  public func validate() throws {
    try master.validate()
    try colorization.validate(colorize: true)
    guard ranges.count == 6 else {
      throw CraftError.invalid("Hue/Saturation requires six color ranges.")
    }
    for range in ranges { try range.validate() }
  }
}

/// Native port of the source's RGB/HSL conversion, also used to draw the hue controls.
public enum HSLColor {
  static func wrap(_ value: Float, period: Float) -> Float {
    guard value.isFinite else { return 0 }
    let remainder = value.truncatingRemainder(dividingBy: period)
    return remainder < 0 ? remainder + period : remainder
  }
  public static func components(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
    let high = max(rgb.x, max(rgb.y, rgb.z))
    let low = min(rgb.x, min(rgb.y, rgb.z))
    let lightness = (high + low) / 2
    if abs(high - low) < 1e-7 { return SIMD3(0, 0, lightness) }
    let delta = high - low
    let saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
    let hue: Float
    if high == rgb.x {
      hue = wrap((rgb.y - rgb.z) / delta, period: 6)
    } else if high == rgb.y {
      hue = (rgb.z - rgb.x) / delta + 2
    } else {
      hue = (rgb.x - rgb.y) / delta + 4
    }
    return SIMD3(hue / 6, saturation, lightness)
  }
  public static func rgb(hue: Float, saturation: Float, lightness: Float) -> SIMD3<Float> {
    guard saturation > 0 else { return SIMD3(repeating: lightness) }
    let q =
      lightness < 0.5
      ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
    let p = 2 * lightness - q
    func channel(_ value: Float) -> Float {
      let t = wrap(value, period: 1)
      if t < 1.0 / 6 { return p + (q - p) * 6 * t }
      if t < 0.5 { return q }
      if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
      return p
    }
    return SIMD3(channel(hue + 1.0 / 3), channel(hue), channel(hue - 1.0 / 3))
  }
}

public struct HueSaturationTransfer: Sendable {
  let settings: HueSaturationValues
  let colorize: Bool
  let identity: Bool
  let depth: PixelDepth
  let tables: [[Float]]
  public init(_ adjustment: HueSaturationAdjustment, depth: PixelDepth) {
    settings = adjustment.colorize ? adjustment.colorization : adjustment.master
    colorize = adjustment.colorize
    self.depth = depth
    let ranges = adjustment.ranges.filter { !$0.values.isNeutral }
    identity = !colorize && settings.isNeutral && ranges.isEmpty
    if !colorize && !ranges.isEmpty {
      // Prepare the nonlinear overlap once per edit, outside the pixel loop.
      // The saved Photoshop references contradict the Rust additive S/L model.
      let rows: [SIMD3<Float>] = (0..<4096).map { index in
        let degrees = Float(index) / 4095 * 360
        return ranges.reduce(SIMD3<Float>.zero) { acc, range in
          let weight = range.weight(degrees)
          let saturation = Float(range.values.saturation) / 100
          let contribution = HueRangeSaturation.contribution(saturation, weight: weight)
          return SIMD3(
            acc.x + weight * Float(range.values.hue),
            HueRangeSaturation.combine(acc.y, contribution),
            min(1, max(-1, acc.z + weight * Float(range.values.lightness) / 100)))
        }
      }
      tables = (0..<3).map { channel in rows.map { $0[channel] } }
    } else {
      tables = []
    }
  }
  public func apply(_ pixel: Pixel) -> Pixel {
    guard !identity, pixel.a > 0, pixel.isFinite else { return pixel }
    let input = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    guard input.isFinite else { return Pixel(.nan, .nan, .nan, pixel.a) }
    let masterLightness = Float(settings.lightness) / 100
    var rgb = input.rgb
    // Master changes the RGB endpoints before hue/saturation operations.
    // A color range contracts towards this pixel's extrema instead.
    if !colorize {
      if masterLightness > 0 {
        rgb += (SIMD3(repeating: 1) - rgb) * masterLightness
      } else if masterLightness < 0 {
        rgb *= 1 + masterLightness
      }
    }
    var components = HSLColor.components(rgb)
    guard components.x.isFinite, components.y.isFinite, components.z.isFinite else {
      return Pixel(.nan, .nan, .nan, pixel.a)
    }
    var shift = SIMD3<Float>.zero
    if !tables.isEmpty && components.y != 0 {
      for i in 0..<3 { shift[i] = CurvesTransfer.lookup(tables[i], components.x) }
    }
    let hue = Float(settings.hue) + shift.x
    let masterSaturation = Float(settings.saturation) / 100
    if !colorize && masterLightness == 0 && shift.z == 0
      && (components.y == 0 || (hue == 0 && masterSaturation == 0 && shift.y == 0))
    {
      return pixel
    }
    let h =
      colorize
      ? HSLColor.wrap(hue, period: 360) / 360
      : HSLColor.wrap(components.x + hue / 360, period: 1)
    if colorize {
      // Colorize uses literal saturation and changes HSL lightness before tinting.
      if masterLightness > 0 {
        components.z += (1 - components.z) * masterLightness
      } else if masterLightness < 0 {
        components.z *= 1 + masterLightness
      }
      rgb = HSLColor.rgb(hue: h, saturation: masterSaturation, lightness: components.z)
    } else {
      if shift.z != 0 {
        let endpoint = shift.z > 0 ? max(rgb.x, max(rgb.y, rgb.z)) : min(rgb.x, min(rgb.y, rgb.z))
        // Algebraic RGB form of HSV chroma contraction; no divisions near gray.
        let amount = abs(shift.z)
        rgb = rgb * (1 - amount) + SIMD3(repeating: endpoint * amount)
        let contracted = HSLColor.components(rgb)
        components.y = contracted.y
        components.z = contracted.z
      }
      let saturation = HueRangeSaturation.apply(
        HueRangeSaturation.apply(components.y, adjustment: masterSaturation), adjustment: shift.y)
      // Avoid a lossy HSL round trip for a pure lightness edit.
      if hue != 0 || saturation != components.y {
        rgb = HSLColor.rgb(hue: h, saturation: saturation, lightness: components.z)
      }
    }
    guard rgb.x.isFinite, rgb.y.isFinite, rgb.z.isFinite else {
      return Pixel(.nan, .nan, .nan, pixel.a)
    }
    // HDR and byte-identical Photoshop behavior remain unqualified; see the
    // measured saved-composite residuals in the reference tests.
    let output = Pixel(rgb.x, rgb.y, rgb.z, pixel.a)
    return depth == .f32 ? SRGBTransfer.encoded(output) : output
  }
}
