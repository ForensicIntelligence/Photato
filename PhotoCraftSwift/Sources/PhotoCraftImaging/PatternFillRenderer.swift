import Foundation
import PhotoCraftCore

struct PatternFillSampler {
  let sampler: PatternSampler
  let inverse: Transform2D
  init(_ fill: PatternFill, in document: CraftDocument) throws {
    guard let pattern = document.pattern(fill.patternID) else {
      throw CraftError.invalid("Missing embedded pattern.")
    }
    sampler = try PatternSampler(pattern, placement: fill.placement)
    inverse = try (fill.geometry ?? .identity).inverted()
  }
  func sample(x: Double, y: Double) -> Pixel {
    let p = inverse.point(x, y)
    return sampler.sample(x: p.x, y: p.y)
  }
}

extension Renderer {
  /// One stored content pixel, for layer picking without allocating a canvas.
  public static func patternPixel(_ fill: PatternFill, in document: CraftDocument, x: Int, y: Int)
    throws -> Pixel
  {
    guard x >= 0, y >= 0, x < document.width, y < document.height else { return .clear }
    return try PatternFillSampler(fill, in: document).sample(x: Double(x) + 0.5, y: Double(y) + 0.5)
      .quantized(.f32)
  }
  static func patternSurface(_ fill: PatternFill, in document: CraftDocument) throws -> Surface {
    let sampler = try PatternFillSampler(fill, in: document)
    var surface = try Surface(width: document.width, height: document.height, depth: .f32)
    for y in 0..<document.height {
      try Task.checkCancellation()
      for x in 0..<document.width {
        surface.setPixel(x: x, y: y, sampler.sample(x: Double(x) + 0.5, y: Double(y) + 0.5))
      }
    }
    return surface
  }
}
