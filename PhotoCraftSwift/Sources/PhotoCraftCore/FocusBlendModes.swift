import Foundation

/// Output blend modes for the Blur, Sharpen and Smudge tools. The neighborhood
/// and pickup engines remain independent; this combines their processed sample
/// with the original target before stroke opacity and selection are applied.
public enum FocusBlendModes {
  public static let supported: [BlendMode] = [
    .normal, .darken, .lighten, .hue, .saturation, .color, .luminosity,
  ]

  static func processed(_ effect: Pixel, over before: Pixel, mode: BlendMode,
    depth: PixelDepth, mask: Bool, preserveTransparency: Bool) -> Pixel {
    if mode == .normal { return effect }
    if mask {
      let value: Float
      switch mode {
      case .darken: value = min(before.r, effect.r)
      case .lighten: value = max(before.r, effect.r)
      case .hue, .saturation, .color: value = before.r
      case .luminosity: value = effect.r
      default: preconditionFailure("Validate focus blend mode before rendering")
      }
      return Pixel(value, value, value)
    }
    // Hidden RGB must not tint pixels newly revealed by the effect. This is the
    // usual uncovered-source / overlapping-blend decomposition, with the effect's
    // alpha retained instead of incorrectly adding a second source-over layer.
    if before.a <= 0 { return effect }
    let linear = depth == .f32
    let base = linear ? SRGBTransfer.linear(before) : before
    let source = linear ? SRGBTransfer.linear(effect) : effect
    let overlap: Float = preserveTransparency ? 1 : unit(before.a)
    let rgb = source.rgb * (1 - overlap) + mode.rgb(base.rgb, source.rgb) * overlap
    let result = Pixel(rgb.x, rgb.y, rgb.z, effect.a)
    return linear ? SRGBTransfer.encoded(result) : result
  }
}
