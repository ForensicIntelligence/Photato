import Foundation

/// Paint colour into the existing opacity stencil. Explicit Clear/Cut deliberately
/// use their ordinary removal path, as observed in Photoshop's selection commands.
enum ProtectedPixels {
  static func composite(_ mode: BlendMode, backdrop: Pixel, source: Pixel,
    opacity: Float = 1, x: Int = 0, y: Int = 0) -> Pixel {
    guard backdrop.a > 0 else { return backdrop }
    var opaque = backdrop
    opaque.a = 1
    var result = mode.composite(backdrop: opaque, source: source, opacity: opacity, x: x, y: y)
    result.a = backdrop.a
    return result
  }
  static func fill(_ before: Pixel, color: Pixel, coverage: Float) -> Pixel {
    guard before.a > 0 else { return before }
    var target = color
    target.a = before.a
    var result = before.mixing(target, coverage: coverage)
    result.a = before.a
    return result
  }
}
