import Foundation

public struct ColorBalanceValues: Codable, Equatable, Sendable {
  public var cyanRed: Int
  public var magentaGreen: Int
  public var yellowBlue: Int
  public init(cyanRed: Int = 0, magentaGreen: Int = 0, yellowBlue: Int = 0) {
    self.cyanRed = cyanRed
    self.magentaGreen = magentaGreen
    self.yellowBlue = yellowBlue
  }
  public var isNeutral: Bool { cyanRed == 0 && magentaGreen == 0 && yellowBlue == 0 }
  public func validate() throws {
    guard [cyanRed, magentaGreen, yellowBlue].allSatisfy({ (-100...100).contains($0) }) else {
      throw CraftError.invalid("Color Balance values must be between −100 and +100.")
    }
  }
  var vector: SIMD3<Float> { SIMD3(Float(cyanRed), Float(magentaGreen), Float(yellowBlue)) }
}

public struct ColorBalanceAdjustment: Codable, Equatable, Sendable {
  public var shadows: ColorBalanceValues
  public var midtones: ColorBalanceValues
  public var highlights: ColorBalanceValues
  public var preserveLuminosity: Bool
  public init(
    shadows: ColorBalanceValues = .init(), midtones: ColorBalanceValues = .init(),
    highlights: ColorBalanceValues = .init(), preserveLuminosity: Bool = true
  ) {
    self.shadows = shadows
    self.midtones = midtones
    self.highlights = highlights
    self.preserveLuminosity = preserveLuminosity
  }
  public enum Tone: String, CaseIterable, Sendable {
    case shadows = "Shadows"
    case midtones = "Midtones"
    case highlights = "Highlights"
  }
  public subscript(_ tone: Tone) -> ColorBalanceValues {
    get {
      switch tone {
      case .shadows: shadows
      case .midtones: midtones
      case .highlights: highlights
      }
    }
    set {
      switch tone {
      case .shadows: shadows = newValue
      case .midtones: midtones = newValue
      case .highlights: highlights = newValue
      }
    }
  }
  public func validate() throws {
    try shadows.validate()
    try midtones.validate()
    try highlights.validate()
  }
}

/// PhotoCraft's luminance-weighted color balance approximation. The source uses
/// Rec.601 luma, triangular tonal weights and a final luminosity ratio. This is
/// source-port evidence, not qualification of Photoshop's proprietary transfer.
public struct ColorBalanceTransfer: Sendable {
  let shadows, midtones, highlights: SIMD3<Float>
  let preserveLuminosity, identity: Bool
  let depth: PixelDepth
  public init(_ adjustment: ColorBalanceAdjustment, depth: PixelDepth) {
    shadows = adjustment.shadows.vector
    midtones = adjustment.midtones.vector
    highlights = adjustment.highlights.vector
    preserveLuminosity = adjustment.preserveLuminosity
    identity =
      adjustment.shadows.isNeutral && adjustment.midtones.isNeutral
      && adjustment.highlights.isNeutral
    self.depth = depth
  }
  public func apply(_ pixel: Pixel) -> Pixel {
    // Avoid the source's unconditional gamut clamp for a neutral edit, and
    // retain hidden color/alpha exactly through encoded-float round trips.
    guard !identity, pixel.a > 0, pixel.isFinite else { return pixel }
    let input = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    guard input.isFinite else { return Pixel(.nan, .nan, .nan, pixel.a) }
    func luma(_ rgb: SIMD3<Float>) -> Float { 0.299 * rgb.x + 0.587 * rgb.y + 0.114 * rgb.z }
    func clamp(_ value: Float) -> Float { min(1, max(0, value)) }
    let light = luma(input.rgb)
    let low = clamp(1 - light * 2)
    let high = clamp(light * 2 - 1)
    let middle = 1 - low - high
    var output = SIMD3<Float>.zero
    for channel in 0..<3 {
      output[channel] = clamp(
        input.rgb[channel]
          + (shadows[channel] * low + midtones[channel] * middle + highlights[channel] * high) / 100
          * 0.5)
    }
    if preserveLuminosity {
      let after = max(luma(output), 1e-6)
      for channel in 0..<3 { output[channel] = clamp(output[channel] * light / after) }
    }
    let result = Pixel(output.x, output.y, output.z, pixel.a)
    return depth == .f32 ? SRGBTransfer.encoded(result) : result
  }
}
