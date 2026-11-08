import PhotoCraftCore

/// Photoshop's merged transparency uses white-matted color channels. Layer channels stay straight.
/// Integer composites are quantized before matting, as observed in pinned Photoshop fixtures.
/// Matting occurs in the stored color space (linear sRGB for RGB/32).
enum PSDMergedSample {
  static func encode(_ pixel: Pixel, depth: Int) -> Pixel {
    if depth == 16 {
      // Photoshop uses 0...32768 working samples and subtracts the rounded
      // distance from white. Rounding the final sum reverses exact half ties.
      // Integer products also avoid Float losing low bits in the matte step.
      func working(_ value: Float) -> Int { Int((Double(unit(value)) * 32768).rounded()) }
      func stored(_ value: Int) -> Float {
        // Expand with integer arithmetic: Float multiplication at the midpoint
        // can turn a value just below .5 into an incorrect rounding tie.
        Float((value * 65535 + 16384) / 32768) / 65535
      }
      let alpha = working(pixel.a)
      func matte(_ color: Float) -> Float {
        stored(32768 - ((32768 - working(color)) * alpha + 16384) / 32768)
      }
      return Pixel(matte(pixel.r), matte(pixel.g), matte(pixel.b), stored(alpha))
    }
    if depth == 32 { return encodeLinear(SRGBTransfer.linear(pixel)) }
    let p = pixel.quantized(depth == 8 ? .u8 : .u16)
    let white = 1 - p.a
    return Pixel(p.r * p.a + white, p.g * p.a + white, p.b * p.a + white, p.a)
  }
  static func encodeLinear(_ p: Pixel,transparency:Bool=true) -> Pixel {
    // A three-channel Background composite has no white-matted transparency plane.
    if !transparency{return p}
    // Original Photoshop RGB32 references round each distance-from-white operation
    // separately, including opaque samples. Do not fuse these operations or apply
    // them to the straight layer planes, which retain their original sample bits.
    func matte(_ color: Float) -> Float { 1 - (1 - color) * p.a }
    return Pixel(matte(p.r), matte(p.g), matte(p.b), p.a)
  }
  static func decode(_ p: Pixel) -> Pixel {
    guard p.a > 0 else { return Pixel(1, 1, 1, 0) }
    let white = 1 - p.a
    return Pixel((p.r - white) / p.a, (p.g - white) / p.a, (p.b - white) / p.a, p.a)
  }
}
