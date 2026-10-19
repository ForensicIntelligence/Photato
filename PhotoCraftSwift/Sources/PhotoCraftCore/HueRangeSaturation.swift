import Foundation

/// Empirical hue-range saturation approximation adapted from MIT psd-tools.
/// Copyright (c) 2019 Kota Yamaguchi. See LICENSE-psd-tools and ATTRIBUTION.md.
/// Pinned source: 1b8c1d404d1b976748e7dbbca33ed5898663371b/composite/adjustments.py.
/// This sampled surface is not a byte-exact Photoshop transfer function.
enum HueRangeSaturation {
  static func contribution(_ adjustment: Float, weight: Float) -> Float {
    guard adjustment > 0 else { return adjustment * weight }
    return adjustment * (1 - pow(1 - weight, 1.5 / (1 - pow(adjustment, 4) + 0.05)))
  }

  static func combine(_ first: Float, _ second: Float) -> Float {
    // Preserve exact neutral axes instead of interpolating their empirical noise.
    if first == 0 { return second }
    if second == 0 { return first }
    let x = min(20, max(0, (1 - first) * 10))
    let y = min(20, max(0, (1 - second) * 10))
    let ix = min(19, Int(x))
    let iy = min(19, Int(y))
    let fx = x - Float(ix)
    let fy = y - Float(iy)
    let low = grid[ix][iy] * (1 - fy) + grid[ix][iy + 1] * fy
    let high = grid[ix + 1][iy] * (1 - fy) + grid[ix + 1][iy + 1] * fy
    return (low * (1 - fx) + high * fx) / 100
  }

  static func apply(_ saturation: Float, adjustment: Float) -> Float {
    if adjustment == 0 { return min(1, max(0, saturation)) }
    if adjustment < 0 { return min(1, max(0, saturation * (1 + adjustment))) }
    // Keep positive boost finite at +100. A 100x ceiling improves the pinned
    // Photoshop references without the reference implementation's +0.01 bias
    // at every positive setting. Exact high-saturation behavior remains open.
    return min(1, max(0, saturation / max(0.01, 1 - adjustment)))
  }

  // Axes run from +100 to -100 in ten-point steps. Bilinear interpolation is
  // performed only while preparing the hue LUT, never per document pixel.
  private static let grid: [[Float]] = [
    [
      100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100, 100,
      100, 100,
    ],
    [100, 94, 92, 91, 91, 90, 90, 90, 90, 90, 90, 89, 89, 89, 89, 89, 89, 89, 88, 88, 88],
    [100, 92, 89, 86, 84, 83, 82, 81, 81, 80, 80, 79, 79, 78, 78, 77, 77, 76, 76, 75, 74],
    [100, 91, 86, 82, 79, 77, 74, 73, 71, 70, 70, 68, 67, 66, 65, 64, 62, 61, 59, 58, 56],
    [100, 91, 84, 79, 75, 71, 68, 65, 63, 61, 60, 58, 56, 54, 52, 49, 47, 44, 41, 36, 32],
    [100, 90, 83, 77, 71, 66, 62, 59, 55, 52, 50, 47, 44, 41, 37, 33, 28, 22, 17, 9, -1],
    [100, 90, 82, 74, 68, 62, 57, 52, 47, 43, 40, 36, 31, 26, 21, 13, 5, -5, -15, -25, -35],
    [100, 90, 81, 73, 65, 59, 52, 46, 39, 35, 30, 24, 19, 11, 2, -8, -18, -28, -38, -48, -58],
    [100, 90, 81, 71, 63, 55, 47, 39, 33, 26, 20, 13, 4, -6, -16, -26, -36, -46, -56, -66, -76],
    [100, 90, 80, 70, 61, 52, 43, 35, 26, 17, 10, 1, -9, -19, -29, -39, -49, -59, -69, -79, -89],
    [
      100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0, -10, -20, -30, -40, -49, -60, -70, -80, -90, -100,
    ],
    [
      100, 89, 79, 68, 58, 47, 36, 24, 13, 1, -10, -19, -30, -40, -50, -60, -70, -79, -89, -99,
      -100,
    ],
    [
      100, 89, 79, 67, 56, 44, 31, 19, 4, -9, -20, -30, -40, -50, -60, -70, -79, -90, -99, -100,
      -100,
    ],
    [
      100, 89, 78, 66, 54, 41, 26, 11, -6, -19, -30, -40, -50, -59, -70, -79, -89, -99, -100, -100,
      -100,
    ],
    [
      100, 89, 78, 65, 52, 37, 21, 2, -16, -29, -40, -50, -60, -70, -79, -90, -99, -100, -100, -100,
      -100,
    ],
    [
      100, 89, 77, 64, 49, 33, 13, -8, -26, -39, -49, -60, -70, -79, -90, -99, -100, -100, -100,
      -100, -100,
    ],
    [
      100, 89, 77, 62, 47, 28, 5, -18, -36, -49, -60, -70, -79, -89, -99, -100, -100, -100, -100,
      -100, -100,
    ],
    [
      100, 89, 76, 61, 44, 22, -5, -28, -46, -59, -70, -79, -90, -99, -100, -100, -100, -100, -100,
      -100, -100,
    ],
    [
      100, 88, 76, 59, 41, 17, -15, -38, -56, -69, -80, -89, -99, -100, -100, -100, -100, -100,
      -100, -100, -100,
    ],
    [
      100, 88, 75, 58, 36, 9, -25, -48, -66, -79, -90, -99, -100, -100, -100, -100, -100, -100,
      -100, -100, -100,
    ],
    [
      100, 88, 74, 56, 32, -1, -35, -58, -76, -89, -100, -100, -100, -100, -100, -100, -100, -100,
      -100, -100, -100,
    ],
  ]
}
