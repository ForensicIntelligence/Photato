import Foundation
import PhotoCraftCore

struct GradientFillSampler {
  let ramp: GradientRamp
  let field: GradientField
  let dither: Bool
  init(_ fill: GradientFill, layer: Layer, document: CraftDocument) throws {
    try fill.validate()
    ramp = try GradientRamp(fill.gradient)
    field = try GradientField(
      fill.placement, frame: fill.frame(for: layer, in: document))
    dither = fill.dither
  }
  func sample(x: Int, y: Int) -> Pixel {
    let pixel = ramp.sample(field.parameter(x: Float(x) + 0.5, y: Float(y) + 0.5))
    return dither ? GradientRamp.dither(pixel, x: x, y: y) : pixel
  }
}

extension Renderer {
  public static func gradientPixel(_ layer: Layer, in document: CraftDocument, x: Int, y: Int)
    throws -> Pixel
  {
    guard case .gradientFill(let fill) = layer.content else {
      throw CraftError.invalid("Expected a gradient fill.")
    }
    guard x >= 0, y >= 0, x < document.width, y < document.height else { return .clear }
    return try GradientFillSampler(fill, layer: layer, document: document).sample(x: x, y: y)
  }
  static func gradientSurface(_ fill: GradientFill, layer: Layer, in document: CraftDocument) throws
    -> Surface
  {
    let sampler = try GradientFillSampler(fill, layer: layer, document: document)
    var surface = try Surface(width: document.width, height: document.height, depth: .f32)
    for y in 0..<document.height {
      try Task.checkCancellation()
      for x in 0..<document.width { surface.setPixel(x: x, y: y, sampler.sample(x: x, y: y)) }
    }
    return surface
  }
}
