import Foundation

public struct TonalStepsAdjustment: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable {
    case threshold = "Threshold"
    case posterize = "Posterize"
    public var range: ClosedRange<Int> { self == .threshold ? 1...255 : 2...255 }
    public var defaultLevel: Int { self == .threshold ? 128 : 4 }
  }
  public var kind: Kind
  public var level: Int
  public init(kind: Kind, level: Int? = nil) {
    self.kind = kind
    self.level = level ?? kind.defaultLevel
  }
  public func validate() throws {
    guard kind.range.contains(level) else {
      throw CraftError.invalid("\(kind.rawValue) must be between \(kind.range.lowerBound) and 255.")
    }
  }
}

/// Source RGB/8 Posterize, extended with the measured Photoshop RGB/16 working
/// grid. Threshold's luminance and depth behavior are pinned by independent PSDs.
public struct TonalStepsTransfer: Sendable {
  let adjustment: TonalStepsAdjustment
  let depth: PixelDepth
  public init(_ adjustment: TonalStepsAdjustment, depth: PixelDepth) {
    self.adjustment = adjustment
    self.depth = depth
  }
  public static func luminance(_ pixel: Pixel) -> Float {
    0.3 * pixel.r + 0.59 * pixel.g + 0.11 * pixel.b
  }
  public func apply(_ pixel: Pixel) -> Pixel {
    guard pixel.a > 0, pixel.isFinite else { return pixel }
    let p = depth == .f32 ? SRGBTransfer.linear(pixel) : pixel
    guard p.isFinite else { return Pixel(.nan, .nan, .nan, pixel.a) }
    let rgb: SIMD3<Float>
    switch adjustment.kind {
    case .threshold:
      let gray = Self.luminance(p) * 255
      // RGB/8 half-level ties round to even, including the independent PSD's
      // (131, 109, 99) -> 114.5 at threshold 115. Higher depths retain fractions.
      let value: Float =
        (depth == .u8 ? gray.rounded(.toNearestOrEven) : gray) >= Float(adjustment.level) ? 1 : 0
      rgb = SIMD3(repeating: value)
    case .posterize:
      let count = Float(min(255, max(2, adjustment.level)))
      func channel(_ v: Float) -> Float {
        if depth == .f32 { return min(count - 1, floor(unit(v) * count)) / (count - 1) }
        let quantum: Float = depth == .u8 ? 255 : 32768
        let x = (unit(v) * quantum).rounded()
        let bin = min(count - 1, floor(x * count / (quantum + 1)))
        return floor(bin * quantum / (count - 1)) / quantum
      }
      rgb = SIMD3(channel(p.r), channel(p.g), channel(p.b))
    }
    let result = Pixel(rgb.x, rgb.y, rgb.z, pixel.a)
    return depth == .f32 ? SRGBTransfer.encoded(result) : result
  }
}
