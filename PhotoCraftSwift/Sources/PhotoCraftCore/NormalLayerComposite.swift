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
    let maximum = depth == .u8 ? 255 : 32768
    func working(_ value: Float) -> Int { Self.working(value, depth: depth) }
    func normalized(_ value: Int) -> Float { Self.normalized(value, depth: depth) }
    let opacityByte = Int((unit(opacity) * 255).rounded())
    let sa = (working(s.a) * opacityByte + 127) / 255
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

  package static func screenClipping(
    backdrop: Pixel, source: Pixel, opacity: Float, depth: PixelDepth
  ) -> Pixel {
    precondition(depth != .f32)
    let maximum = depth == .u8 ? 255 : 32768
    let opacityByte = Int((unit(opacity) * 255).rounded())
    let sourceAlpha = working(source.a, depth: depth)
    // At 16 bits the clip opacity is promoted before multiplying by pixel alpha.
    let weight = depth == .u8
      ? (sourceAlpha * opacityByte + 127) / 255
      : (sourceAlpha * ((opacityByte * maximum + 127) / 255) + maximum / 2) / maximum
    func channel(_ backdrop: Float, _ source: Float) -> Float {
      let b = working(backdrop, depth: depth)
      let s = working(source, depth: depth)
      let screen = maximum - ((maximum - b) * (maximum - s) + maximum / 2) / maximum
      // Round the complementary color product before interpolating by coverage.
      let mixed = (screen * weight + b * (maximum - weight) + maximum / 2) / maximum
      return normalized(mixed, depth: depth)
    }
    return Pixel(channel(backdrop.r, source.r), channel(backdrop.g, source.g),
      channel(backdrop.b, source.b), backdrop.a)
  }

  private static func working(_ value: Float, depth: PixelDepth) -> Int {
    if depth == .u8 { return Int((unit(value) * 255).rounded()) }
    let stored = Int((unit(value) * 65535).rounded())
    return (stored * 32768 + 32767) / 65535
  }

  private static func normalized(_ value: Int, depth: PixelDepth) -> Float {
    if depth == .u8 { return Float(value) / 255 }
    return Float((value * 65535 + 16384) / 32768) / 65535
  }
}
