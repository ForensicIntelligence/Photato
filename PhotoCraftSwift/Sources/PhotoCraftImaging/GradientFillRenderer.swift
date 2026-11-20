import Foundation
import PhotoCraftCore

struct GradientFillSampler {
  let ramp: GradientRamp
  let field: GradientField
  let dither: Bool
  private let classicOverlay: ClassicOverlay8?
  init(_ fill: GradientFill, layer: Layer, document: CraftDocument, alignedFrame: IntRect? = nil,
    isOverlay: Bool = false
  ) throws {
    try fill.validate()
    ramp = try GradientRamp(fill.gradient)
    let frame = try (fill.aligned ? alignedFrame : nil) ?? fill.frame(for: layer, in: document)
    field = try GradientField(fill.placement, frame: frame)
    classicOverlay = isOverlay && document.colorMode == .rgb && document.depth == .u8
      ? ClassicOverlay8(fill, frame: frame) : nil
    dither = fill.dither
  }
  func sample(x: Int, y: Int) -> Pixel {
    if let classicOverlay { return classicOverlay.sample(x: x, y: y) }
    let pixel = ramp.sample(field.parameter(x: Float(x) + 0.5, y: Float(y) + 0.5))
    return dither ? GradientRamp.dither(pixel, x: x, y: y) : pixel
  }
  func batch(pixelCount: Int) -> (Int, Int) -> Pixel {
    var samples = GradientRamp.Sampler(ramp, pixelCount: pixelCount)
    return { x, y in
      let pixel = samples.sample(field.parameter(x: Float(x) + 0.5, y: Float(y) + 0.5))
      return dither ? GradientRamp.dither(pixel, x: x, y: y) : pixel
    }
  }
}

/// Classic two-stop overlays in the verified axis-aligned RGB8 cases use
/// 0...32768 working RGB stops. The result and transparency enter the blend
/// on the byte grid. Integer fractions keep endpoint and halfway ties exact.
private struct ClassicOverlay8 {
  let horizontal: Bool
  let reversed: Bool
  let start: Int
  let span: Int
  let from: SIMD3<Int>
  let to: SIMD3<Int>
  let alphaFrom: Int
  let alphaTo: Int

  init?(_ fill: GradientFill, frame: IntRect) {
    let gradient = fill.gradient, placement = fill.placement
    let angle = placement.angle.truncatingRemainder(dividingBy: 360)
    guard gradient.method == .classic, gradient.smoothness == 0, placement.style == .linear, !fill.dither,
      angle == 0 || abs(angle) == 90 || abs(angle) == 180,
      gradient.colors.count == 2, gradient.colors[0].position == 0, gradient.colors[1].position == 1,
      gradient.colors[0].midpoint == 0.5, case .rgb(let a) = gradient.colors[0].color,
      case .rgb(let b) = gradient.colors[1].color, a.a == 1, b.a == 1 else { return nil }
    let stops = gradient.opacity
    guard stops.isEmpty || (stops.count == 2 && stops[0].position == 0 && stops[1].position == 1
      && stops[0].midpoint == 0.5) else { return nil }
    horizontal = angle == 0 || abs(angle) == 180
    reversed = (angle == 90 || abs(angle) == 180) != placement.reverse
    let extent = Double(horizontal ? frame.width : frame.height)
    let center = Double(horizontal ? frame.x : frame.y) + extent / 2
      + Double(horizontal ? placement.offsetX : placement.offsetY) * extent
    let half = extent * Double(max(0.001, placement.scale)) / 2
    start = Int(floor(center - half + 0.0001))
    span = Int(floor(center + half + 0.0001)) - start
    guard span > 0 else { return nil }
    func working(_ pixel: Pixel) -> SIMD3<Int> {
      func channel(_ value: Float) -> Int { Int((Double(unit(value)) * 32768).rounded(.toNearestOrEven)) }
      return SIMD3(channel(pixel.r), channel(pixel.g), channel(pixel.b))
    }
    from = working(a); to = working(b)
    alphaFrom = stops.isEmpty ? 255 : Int((Double(stops[0].opacity) * 255).rounded())
    alphaTo = stops.isEmpty ? 255 : Int((Double(stops[1].opacity) * 255).rounded())
  }

  func sample(x: Int, y: Int) -> Pixel {
    let offset = min(span, max(0, (horizontal ? x : y) - start))
    let position = reversed ? span - offset : offset
    let remaining = span - position
    let denominator = span * 32768
    func channel(_ a: Int, _ b: Int) -> Float {
      let numerator = (a * remaining + b * position) * 255
      let value = numerator / denominator, remainder = (numerator % denominator) * 2
      let roundUp = remainder > denominator || (remainder == denominator && value % 2 != 0)
      return Float(value + (roundUp ? 1 : 0)) / 255
    }
    let alpha = (2 * (alphaFrom * remaining + alphaTo * position) + span) / (2 * span)
    return Pixel(channel(from.x, to.x), channel(from.y, to.y), channel(from.z, to.z), Float(alpha) / 255)
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
    let surface = try Surface(width: document.width, height: document.height, depth: .f32)
    let area = IntRect(x: 0, y: 0, width: surface.width, height: surface.height)
    let sample = sampler.batch(pixelCount: area.width * area.height)
    return try (consume surface).compositingPixels(in: area) { x, y, _ in
      sample(x, y)
    }
  }
}
