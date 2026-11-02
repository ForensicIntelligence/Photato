import Foundation

/// Editable Exposure controls. The bounded RGB8/16 transfer follows the licensed
/// PhotoCraft Exposure approximation; independent Photoshop/ICC equality is open.
public struct ExposureAdjustment: Codable, Equatable, Sendable {
  public var exposure: Float
  public var offset: Float
  public var gammaCorrection: Float
  public init(exposure: Float = 0, offset: Float = 0, gammaCorrection: Float = 1) {
    self.exposure = exposure; self.offset = offset; self.gammaCorrection = gammaCorrection
  }
  public func validate() throws {
    guard exposure.isFinite, offset.isFinite, gammaCorrection.isFinite,
      (-20...20).contains(exposure), (-0.5...0.5).contains(offset),
      (0.01...9.99).contains(gammaCorrection) else {
      throw CraftError.invalid("Exposure requires -20…20 EV, -0.5…0.5 Offset and 0.01…9.99 Gamma Correction.")
    }
  }
  public var isIdentity: Bool { exposure == 0 && offset == 0 && gammaCorrection == 1 }
  /// The engine supplies encoded tone coordinates, including for linear RGB32.
  /// RGB32 retains finite HDR output; it is never clipped to an SDR preview.
  public func apply(_ pixel: Pixel, depth: PixelDepth) -> Pixel {
    guard !isIdentity, pixel.a > 0, pixel.isFinite else { return pixel }
    let input = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    let gain = pow(Float(2), exposure), exponent = 1 / gammaCorrection
    func channel(_ sample: Float) -> Float {
      let linear = depth == .f32 ? max(0, sample) : pow(max(0, sample), 2.2)
      let result = pow(max(0, linear * gain + offset), exponent)
      return depth == .f32 ? result : min(1, pow(result, 1 / 2.2))
    }
    let result = Pixel(channel(input.r), channel(input.g), channel(input.b), pixel.a)
    return depth == .f32 ? SRGBTransfer.encoded(result) : result
  }
}
