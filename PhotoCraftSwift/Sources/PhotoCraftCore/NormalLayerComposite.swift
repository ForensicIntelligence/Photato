import Foundation

/// Normal raster-layer composition measured from original Photoshop 2026 merge probes.
/// Integer depths use encoded RGB. Float callers must supply linear RGB; this function
/// deliberately does not hide a potentially lossy sRGB transfer inside the arithmetic.
public enum NormalLayerComposite {
  public static func composite(
    backdrop b: Pixel, source s: Pixel, opacity: Float = 1, depth: PixelDepth
  ) -> Pixel {
    if depth == .f32 {
      let sa = unit(s.a) * unit(opacity)
      let ba = unit(b.a)
      // Fused multiply-add and this addition order are observable in saved RGB32 samples.
      let alpha = (sa + ba).addingProduct(-ba, sa)
      if sa == 1 { return Pixel(s.r, s.g, s.b, alpha) }
      let ratio: Float = alpha == 0 ? 1 : sa / alpha
      return Pixel(
        b.r.addingProduct(s.r - b.r, ratio),
        b.g.addingProduct(s.g - b.g, ratio),
        b.b.addingProduct(s.b - b.b, ratio), alpha)
    }
    let opacityByte = Int((unit(opacity) * 255).rounded())
    let sourceAlpha = (working(s.a, depth: depth) * opacityByte + 127) / 255
    return integerComposite(backdrop: b, source: s, sourceAlpha: sourceAlpha, depth: depth)
  }

  package static func compositeWithRGB16Opacity(backdrop: Pixel, source: Pixel, opacity: Int) -> Pixel {
    let alpha = clippingAlpha(source.a, opacity: opacity, depth: .u16)
    return integerComposite(backdrop: backdrop, source: source, sourceAlpha: alpha, depth: .u16)
  }

  package static func whiteMattedRGB16(_ sample: Pixel) -> SIMD3<UInt16> {
    let maximum = 32_768, half = maximum / 2
    let alpha = working(sample.a, depth: .u16)
    func channel(_ source: Float) -> UInt16 {
      let color = working(source, depth: .u16)
      let remainingDarkness = ((maximum - color) * alpha + half) / maximum
      return UInt16(((maximum - remainingDarkness) * 65_535 + half) / maximum)
    }
    return SIMD3(channel(sample.r), channel(sample.g), channel(sample.b))
  }

  private static func integerComposite(backdrop b: Pixel, source s: Pixel, sourceAlpha sa: Int, depth: PixelDepth) -> Pixel {
    let maximum = depth == .u8 ? 255 : 32768
    func working(_ value: Float) -> Int { Self.working(value, depth: depth) }
    func normalized(_ value: Int) -> Float { Self.normalized(value, depth: depth) }
    let ba = working(b.a)
    // a+b-round(a*b) differs from a+round(b*(1-a)) at exact RGB16 half ties.
    let alpha = sa + ba - (ba * sa + maximum / 2) / maximum
    let ratio = alpha == 0 ? 0 : min(maximum, (sa * maximum + alpha / 2) / alpha)
    func channel(_ back: Float, _ source: Float) -> Float {
      normalized(
        (working(source) * ratio + working(back) * (maximum - ratio) + maximum / 2)
          / maximum)
    }
    return Pixel(channel(b.r, s.r), channel(b.g, s.g), channel(b.b, s.b), normalized(alpha))
  }

  package static func blendClippedInteger(
    backdrop: Pixel, source: Pixel, mode: BlendMode, opacity: Float, depth: PixelDepth
  ) throws -> Pixel {
    precondition(depth != .f32)
    let maximum = depth == .u8 ? 255 : 32768
    let weight = clippingAlpha(source.a, opacity: clippingOpacity(opacity, depth: depth), depth: depth)
    func channel(_ backdrop: Float, _ source: Float) throws -> Float {
      let b = working(backdrop, depth: depth)
      let s = working(source, depth: depth)
      let blend: Int
      switch mode {
      case .normal: blend = s
      case .multiply: blend = (b * s + maximum / 2) / maximum
      case .screen: blend = maximum - ((maximum - b) * (maximum - s) + maximum / 2) / maximum
      case .darken: blend = min(b, s)
      case .lighten: blend = max(b, s)
      case .difference: blend = abs(b - s)
      case .linearDodge: blend = min(maximum, b + s)
      case .subtract: blend = max(0, b - s)
      case .divide:
        if b == 0 { blend = 0 }
        else if s == 0 { blend = maximum }
        else { blend = min(maximum, (b * maximum + s / 2) / s) }
      default: throw CraftError.unsupported("This blend mode has no prepared integer clipping path.")
      }
      // Round the working color sample before interpolating by coverage.
      let mixed = (blend * weight + b * (maximum - weight) + maximum / 2) / maximum
      return normalized(mixed, depth: depth)
    }
    return try Pixel(channel(backdrop.r, source.r), channel(backdrop.g, source.g),
      channel(backdrop.b, source.b), backdrop.a)
  }

  package static func adjacentClips(
    lower: Pixel?, upper: Pixel?, lowerOpacity: Int, upperOpacity: Int, depth: PixelDepth
  ) -> Pixel {
    precondition(depth != .f32)
    let maximum = depth == .u8 ? 255 : 32768
    let ba = lower.map { clippingAlpha($0.a, opacity: lowerOpacity, depth: depth) } ?? 0
    let sa = upper.map { clippingAlpha($0.a, opacity: upperOpacity, depth: depth) } ?? 0
    let alpha = sa + ba - (ba * sa + maximum / 2) / maximum
    let coverage = normalized(alpha, depth: depth)
    guard let lower else {
      if let upper, sa > 0 { return Pixel(upper.r, upper.g, upper.b, coverage) }
      return Pixel(1, 1, 1, 0)
    }
    guard let upper else { return Pixel(lower.r, lower.g, lower.b, coverage) }
    let ratio = alpha == 0 ? 0 : min(maximum, (sa * maximum + alpha / 2) / alpha)
    func channel(_ b: Float, _ s: Float) -> Float {
      let result = (working(s, depth: depth) * ratio + working(b, depth: depth) * (maximum - ratio)
        + maximum / 2) / maximum
      return normalized(result, depth: depth)
    }
    return Pixel(channel(lower.r, upper.r), channel(lower.g, upper.g), channel(lower.b, upper.b), coverage)
  }

  package static func clippedMaskCoverage(_ sample: Float, density: Float, depth: PixelDepth) -> Float {
    let value = unit(sample)
    if density == 1 { return value }
    if density == 0 { return 1 }
    if depth == .f32 {
      let byte = (unit(density) * 255).rounded()
      if byte == 255 { return value }
      // Multiplication by the rounded reciprocal matches Photoshop's saved HDR coverage.
      let weight = byte * (Float(1) / 255)
      return 1 - weight * (1 - value)
    }
    let maximum = depth == .u8 ? 255 : 32768
    let complement = maximum - working(value, depth: depth)
    let amount = clippingOpacity(density, depth: depth)
    let covered = maximum - (complement * amount + maximum / 2) / maximum
    return normalized(covered, depth: depth)
  }

  package static func applyClippedPixelMask(_ coverage: Float, to alpha: Float, depth: PixelDepth) -> Float {
    normalized(clippingAlpha(alpha, opacity: working(coverage, depth: depth), depth: depth), depth: depth)
  }

  package static func clippingOpacity(_ opacity: Float, depth: PixelDepth) -> Int {
    let byte = Int((unit(opacity) * 255).rounded())
    // The 16-bit clip paths promote layer opacity before applying it to alpha.
    return depth == .u8 ? byte : (byte * 32768 + 127) / 255
  }

  private static func clippingAlpha(_ alpha: Float, opacity: Int, depth: PixelDepth) -> Int {
    let maximum = depth == .u8 ? 255 : 32768
    return (working(alpha, depth: depth) * opacity + maximum / 2) / maximum
  }

  static func working(_ value: Float, depth: PixelDepth) -> Int {
    if depth == .u8 { return Int((unit(value) * 255).rounded()) }
    let stored = Int((unit(value) * 65535).rounded())
    return (stored * 32768 + 32767) / 65535
  }

  static func normalized(_ value: Int, depth: PixelDepth) -> Float {
    if depth == .u8 { return Float(value) / 255 }
    return Float((value * 65535 + 16384) / 32768) / 65535
  }
}
