import Foundation
import PhotoCraftCore

/// Region-aware CPU rendering shared by forthcoming live fills, classic painting and previews.
/// `frame` stays fixed while `region` changes; dither is anchored in document coordinates.
public enum GradientRasterizer {
  public static func render(
    _ gradient: GradientDefinition, placement: GradientPlacement, frame: IntRect,
    region: IntRect? = nil, depth: PixelDepth = .f32, dither: Bool = false,
    foreground: Pixel = .black, background: Pixel = .white, snapEndpoints: Bool = true
  ) throws -> Surface {
    try Task.checkCancellation()
    let area = region ?? frame
    guard (-1_000_000...1_000_000).contains(area.x), (-1_000_000...1_000_000).contains(area.y)
    else {
      throw CraftError.invalid("Invalid gradient render region.")
    }
    let ramp = try GradientRamp(gradient, foreground: foreground, background: background)
    let field = try GradientField(placement, frame: frame, snapEndpoints: snapEndpoints)
    var result = try Surface(width: area.width, height: area.height, depth: depth)
    for y in 0..<area.height {
      try Task.checkCancellation()
      let py = area.y + y
      for x in 0..<area.width {
        let px = area.x + x
        let sample = ramp.sample(field.parameter(x: Float(px) + 0.5, y: Float(py) + 0.5))
        result.setPixel(x: x, y: y, dither ? GradientRamp.dither(sample, x: px, y: py) : sample)
      }
    }
    return result
  }
}
