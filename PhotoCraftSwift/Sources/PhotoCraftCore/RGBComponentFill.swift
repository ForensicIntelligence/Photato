import Foundation

/// Color-plane targets, distinct from composite RGB editing and display visibility.
/// Even selecting all three planes here preserves the stored alpha plane.
public struct RGBComponents: OptionSet, Equatable, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }
  public static let red = Self(rawValue: 1)
  public static let green = Self(rawValue: 2)
  public static let blue = Self(rawValue: 4)
  public static let all: Self = [.red, .green, .blue]
}

/// Internal editing foundation for component Fill. UI and both API adapters must
/// share this transaction before the app advertises component editing support.
/// RGB8 Normal arithmetic is measured against original Photoshop 2026 PSDs.
/// Other depths, blend modes and color-to-gray conversion require separate work.
public struct RGBComponentFill: Equatable, Sendable {
  public var components: RGBComponents
  public var value: Float
  public var opacity: Float

  public init(components: RGBComponents, value: Float, opacity: Float = 1) {
    self.components = components
    self.value = value
    self.opacity = opacity
  }

  public func validate() throws {
    guard !components.isEmpty, components.isSubset(of: .all),
      value.isFinite, (0...1).contains(value),
      opacity.isFinite, (0...1).contains(opacity)
    else { throw CraftError.invalid("Invalid component Fill target, value or opacity.") }
  }

  /// Photoshop's RGB8 Fill quantizes opacity to a byte before blending. Alpha
  /// never enters this calculation, including when editing hidden color at A=0.
  /// Fractional selection combination is native behavior, not yet an independent
  /// Photoshop qualification; the reference fixture covers full coverage only.
  func applying(to pixel: Pixel, coverage: Float) -> Pixel {
    let opacityByte = Int((opacity * 255).rounded())
    let selectionByte = Int((unit(coverage) * 255).rounded())
    let weight = (opacityByte * selectionByte + 127) / 255
    guard weight > 0 else { return pixel }
    let fill = Int((value * 255).rounded())
    func mix(_ source: Float) -> Float {
      let sample = Int((unit(source) * 255).rounded())
      return Float((sample * (255 - weight) + fill * weight + 127) / 255) / 255
    }
    var result = pixel
    if components.contains(.red) { result.r = mix(pixel.r) }
    if components.contains(.green) { result.g = mix(pixel.g) }
    if components.contains(.blue) { result.b = mix(pixel.b) }
    return result
  }
}
