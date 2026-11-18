import Foundation

/// Retained, editable Gradient Map controls. Opacity stops belong to the preset,
/// but this adjustment maps RGB and preserves the source pixel's transparency.
public struct GradientMapAdjustment: Codable, Equatable, Sendable {
  public var gradient: GradientDefinition
  public var reverse: Bool
  public var dither: Bool
  public init(
    gradient: GradientDefinition = .blackToWhite, reverse: Bool = false, dither: Bool = false
  ) {
    self.gradient = gradient
    self.reverse = reverse
    self.dither = dither
  }
  public func validate() throws {
    try gradient.validate()
    for stop in gradient.colors {
      switch stop.color {
      case .foreground, .background:
        throw CraftError.invalid("Capture foreground and background before applying Gradient Map.")
      default: break
      }
    }
  }
}

public struct GradientMapTransfer: Sendable {
  private static let bayer: [Float] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
  private let ramp: GradientRamp
  private let toneSamples: [Pixel]?
  private let settings: GradientMapAdjustment
  private let depth: PixelDepth
  public init(_ settings: GradientMapAdjustment, depth: PixelDepth, pixelCount: Int = 0) throws {
    try settings.validate()
    let ramp = try GradientRamp(settings.gradient)
    self.ramp = ramp
    if depth == .u16 && settings.gradient.method == .classic {
      toneSamples = ClassicRGB16Gradient(settings.gradient).samples
    } else if depth != .f32 && pixelCount >= 65_536 {
      // Integer-depth tone coordinates already lie on this exact grid.
      toneSamples = (0...4096).map { ramp.sample(Float($0) / 4096) }
    } else {
      toneSamples = nil
    }
    self.settings = settings
    self.depth = depth
  }
  public func apply(_ pixel: Pixel, x: Int = 0, y: Int = 0) -> Pixel {
    guard pixel.isFinite, pixel.a > 0 else { return pixel }
    let working = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    guard working.isFinite else { return Pixel(.nan, .nan, .nan, pixel.a) }
    var tone: Float
    if depth == .u16 {
      // Independently qualified Photoshop RGB16 coordinates: reconstruct the
      // 0...32768 working samples, then round fixed-weight luma to 4097 positions.
      let r = Int((unit(working.r) * 32768).rounded())
      let g = Int((unit(working.g) * 32768).rounded())
      let b = Int((unit(working.b) * 32768).rounded())
      let index = (4915 * r + 9667 * g + 1802 * b + 65536) / 131072
      tone = Float(index) / 4096
    } else {
      // The Photoshop-authored RGB8 probe distinguishes these weights from Rec.709.
      tone = unit(0.3 * working.r + 0.59 * working.g + 0.11 * working.b)
      if depth == .u8 { tone = (tone * 4096).rounded() / 4096 }
    }
    if settings.reverse { tone = 1 - tone }
    var result = toneSamples?[Int((tone * 4096).rounded())] ?? ramp.sample(tone)
    if settings.dither {
      // Source PhotoCraft ordered dither; exact Photoshop noise remains unqualified.
      let noise = ((Self.bayer[(y & 3) * 4 + (x & 3)] + 0.5) / 16 - 0.5) / 255
      result = Pixel(unit(result.r + noise), unit(result.g + noise), unit(result.b + noise))
    }
    result.a = pixel.a
    return depth == .f32 ? SRGBTransfer.encoded(result) : result
  }
}
