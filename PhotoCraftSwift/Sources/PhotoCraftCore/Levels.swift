import Foundation

/// RGB Levels records use Photoshop's 0...255 control scale at every document depth.
public struct LevelsChannel: Codable, Equatable, Sendable {
  public var inputBlack: Int
  public var inputWhite: Int
  public var gamma: Float
  public var outputBlack: Int
  public var outputWhite: Int
  public init(
    inputBlack: Int = 0, inputWhite: Int = 255, gamma: Float = 1,
    outputBlack: Int = 0, outputWhite: Int = 255
  ) {
    self.inputBlack = inputBlack
    self.inputWhite = inputWhite
    self.gamma = gamma
    self.outputBlack = outputBlack
    self.outputWhite = outputWhite
  }
  public func validate() throws {
    guard (0...253).contains(inputBlack), (2...255).contains(inputWhite),
      inputBlack < inputWhite, gamma.isFinite, (0.1...9.99).contains(gamma),
      (0...255).contains(outputBlack), (0...255).contains(outputWhite)
    else { throw CraftError.invalid("Levels values are out of range.") }
  }

  // Ported from photocraft crates/compose/src/adjust.rs, levels_q/levels_float.
  // The integer gamma > 1 shadow toe is an upstream approximation, not an exact
  // Photoshop algorithm. Keep its independent Rust oracle until live qualification.
  public func evaluate(_ value: Float, depth: PixelDepth) -> Float {
    let black = Float(inputBlack) / 255
    let range = max(1e-6, Float(inputWhite) / 255 - black)
    let t: Float
    if depth == .f32 {
      let v = (value - black) / range
      t = copysign(pow(abs(v), 1 / max(0.01, gamma)), v)
    } else {
      let q: Float = depth == .u8 ? 255 : 32768
      let v = (value * q).rounded() / q
      let u = floor(unit((v - black) / range) * q + 0.5 + 1e-3) / q
      let power = pow(u, 1 / max(0.01, gamma))
      if gamma > 1 {
        let line = 0.93 * pow(Float(2), gamma) * u
        t =
          power <= 1e-6 || line <= 1e-6
          ? min(power, line) : pow(pow(power, -10) + pow(line, -10), -0.1)
      } else {
        t = power
      }
    }
    return Float(outputBlack) / 255 + t * (Float(outputWhite) / 255 - Float(outputBlack) / 255)
  }
}

public struct LevelsAdjustment: Codable, Equatable, Sendable {
  public var rgb: LevelsChannel
  public var red: LevelsChannel
  public var green: LevelsChannel
  public var blue: LevelsChannel
  public init(
    rgb: LevelsChannel = .init(), red: LevelsChannel = .init(),
    green: LevelsChannel = .init(), blue: LevelsChannel = .init()
  ) {
    self.rgb = rgb
    self.red = red
    self.green = green
    self.blue = blue
  }
  public enum Channel: String, CaseIterable, Sendable {
    case rgb = "RGB"
    case red = "Red"
    case green = "Green"
    case blue = "Blue"
  }
  public subscript(_ channel: Channel) -> LevelsChannel {
    get {
      switch channel {
      case .rgb: rgb
      case .red: red
      case .green: green
      case .blue: blue
      }
    }
    set {
      switch channel {
      case .rgb: rgb = newValue
      case .red: red = newValue
      case .green: green = newValue
      case .blue: blue = newValue
      }
    }
  }
  public func validate() throws {
    for channel in Channel.allCases { try self[channel].validate() }
  }
}

/// Construct once per rendering operation, rather than computing tone curves per pixel.
public struct LevelsTransfer: Sendable {
  /// Levels preserves alpha; fractional masks/selections mix RGB in the document's
  /// compositing space. Preserve endpoint bits and hidden colors for an identity edit.
  public static func mix(_ original: Pixel, with edited: Pixel, coverage: Float, depth: PixelDepth)
    -> Pixel
  {
    let amount = unit(coverage)
    if amount == 0 || original == edited { return original }
    if amount == 1 { return edited }
    let before = depth == .f32 ? SRGBTransfer.linear(original) : original
    let after = depth == .f32 ? SRGBTransfer.linear(edited) : edited
    let rgb = before.rgb + (after.rgb - before.rgb) * amount
    let result = Pixel(rgb.x, rgb.y, rgb.z, original.a)
    return depth == .f32 ? SRGBTransfer.encoded(result) : result
  }
  let levels: LevelsAdjustment
  let depth: PixelDepth
  let tables: [[Float]]
  public init(_ levels: LevelsAdjustment, depth: PixelDepth) {
    self.levels = levels
    self.depth = depth
    tables =
      depth == .f32
      ? []
      : [levels.red, levels.green, levels.blue].map { channel in
        // Match the Rust compositor's 4096-entry, master-then-channel LUT.
        (0..<4096).map {
          channel.evaluate(levels.rgb.evaluate(Float($0) / 4095, depth: depth), depth: depth)
        }
      }
  }
  public func apply(_ pixel: Pixel) -> Pixel {
    guard levels != LevelsAdjustment(), pixel.a > 0 else { return pixel }
    func channel(_ value: Float, _ record: LevelsChannel, _ index: Int) -> Float {
      if levels.rgb == LevelsChannel(), record == LevelsChannel() { return value }
      if depth == .f32 {
        // Native float pixels are encoded sRGB; Photoshop's RGB/32 Levels operates
        // on linear samples. Unlike the Rust display LUT, preserve extended values.
        let linear = SRGBTransfer.linear(value)
        let result = record.evaluate(levels.rgb.evaluate(linear, depth: .f32), depth: .f32)
        return SRGBTransfer.encoded(result)
      }
      let x = unit(value) * 4095
      let i = Int(floor(x))
      let fraction = x - Float(i)
      return tables[index][i] * (1 - fraction) + tables[index][min(i + 1, 4095)] * fraction
    }
    return Pixel(
      channel(pixel.r, levels.red, 0), channel(pixel.g, levels.green, 1),
      channel(pixel.b, levels.blue, 2), pixel.a)
  }
}
