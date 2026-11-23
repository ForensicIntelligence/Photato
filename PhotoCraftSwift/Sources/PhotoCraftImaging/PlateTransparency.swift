import Foundation
import PhotoCraftCore

/// Estimates local transmission where the reference photograph has a distinct
/// color change. Differences across a single pixel largely cancel the subject
/// color in smooth regions such as clear glass.
enum PlateTransparency {
  private typealias Color = SIMD3<Double>

  static func refine(_ bytes: inout [UInt8], inside mask: SelectionMask, bounds: IntRect, guide: Surface,
    plate: Surface, linear: Bool, protected: [UInt8]) throws {
    let tileSize = 128, radius = 6, halo = radius + 1
    for top in stride(from: bounds.y, to: bounds.y + bounds.height, by: tileSize) {
      for left in stride(from: bounds.x, to: bounds.x + bounds.width, by: tileSize) {
        try Task.checkCancellation()
        let bottom = min(bounds.y + bounds.height, top + tileSize)
        let right = min(bounds.x + bounds.width, left + tileSize)
        let x0 = max(bounds.x, left - halo), x1 = min(bounds.x + bounds.width, right + halo)
        let y0 = max(bounds.y, top - halo), y1 = min(bounds.y + bounds.height, bottom + halo)
        let w = x1 - x0, h = y1 - y0
        var observed = [Color](repeating: .zero, count: w * h)
        var backing = observed
        var valid = [Bool](repeating: false, count: w * h)
        for y in y0..<y1 {
          for x in x0..<x1 {
            guard mask.byte(at: y * mask.width + x) > 0 else { continue }
            let current = SelectionTransparency.Background.pixel(guide, x: x, y: y, linear: linear)
            let reference = SelectionTransparency.Background.pixel(plate, x: x, y: y, linear: linear)
            guard current.a >= 0.999, reference.a >= 0.999 else { continue }
            let i = (y - y0) * w + x - x0
            observed[i] = Color(current.rgb); backing[i] = Color(reference.rgb); valid[i] = true
          }
        }
        var moments = [SIMD8<Double>](repeating: .zero, count: w * h)
        for y in 0..<h {
          for x in 0..<w {
            let i = y * w + x
            guard valid[i] else { continue }
            if x + 1 < w, valid[i + 1] {
              let value = measure(observed[i + 1] - observed[i], backing[i + 1] - backing[i])
              moments[i] += value; moments[i + 1] += value
            }
            if y + 1 < h, valid[i + w] {
              let value = measure(observed[i + w] - observed[i], backing[i + w] - backing[i])
              moments[i] += value; moments[i + w] += value
            }
          }
        }
        let stride = w + 1
        var integral = [SIMD8<Double>](repeating: .zero, count: stride * (h + 1))
        for y in 0..<h {
          var row = SIMD8<Double>.zero
          for x in 0..<w {
            row += moments[y * w + x]
            integral[(y + 1) * stride + x + 1] = row + integral[y * stride + x + 1]
          }
        }
        for y in top..<bottom {
          try Task.checkCancellation()
          for x in left..<right {
            let documentIndex = y * mask.width + x
            let initial = bytes[documentIndex], hold = protected[documentIndex]
            let localX = x - x0, localY = y - y0, localIndex = localY * w + localX
            guard initial >= 8, hold < 255, valid[localIndex] else { continue }
            let l = max(0, localX - radius), r = min(w, localX + radius + 1)
            let t = max(0, localY - radius), b = min(h, localY + radius + 1)
            let sum = integral[b * stride + r] - integral[b * stride + l]
              - integral[t * stride + r] + integral[t * stride + l]
            guard sum[0] > 0.000_01 else { continue }
            let estimate = sum[1] / sum[0]
            let variation = sqrt(max(0, sum[2] / sum[0] - estimate * estimate))
            let texture = sqrt(max(0, sum[3]) / max(1, sum[4]))
            // Keep the color projection when the local measurements disagree
            // or the subject itself has a finely textured surface.
            let confidence = min(1, sum[0] / 0.3) * max(0, 1 - variation / 0.25)
              * max(0, 1 - texture / 0.10) * (1 - Double(hold) / 255)
            guard confidence > 0 else { continue }
            let initialAlpha = Double(initial) / 255
            let mixed = initialAlpha + confidence * (estimate - initialAlpha)
            let floor = linear ? 0 : SelectionTransparency.minimumCoverage(
              difference: observed[localIndex] - backing[localIndex], background: backing[localIndex])
            let alpha = UInt8((min(1, max(mixed, floor)) * 255).rounded(.up))
            bytes[documentIndex] = min(alpha, mask.byte(at: documentIndex))
          }
        }
      }
    }
  }

  private static func dot(_ a: Color, _ b: Color) -> Double {
    let v = a * b
    return v.x + v.y + v.z
  }

  private static func measure(_ observed: Color, _ reference: Color) -> SIMD8<Double> {
    let energy = dot(reference, reference)
    if energy < 0.0015 { return .init(0, 0, 0, dot(observed, observed), 1, 0, 0, 0) }
    guard energy > 0.015 else { return .zero }
    let transmission = dot(reference, observed) / energy
    guard (-0.08...1.08).contains(transmission) else { return .zero }
    let difference = observed - reference * transmission
    let weight = max(0, 1 - dot(difference, difference) / (0.028 * 0.028)) * sqrt(energy)
    let alpha = 1 - min(1, max(0, transmission))
    return .init(weight, weight * alpha, weight * alpha * alpha, 0, 0, 0, 0, 0)
  }
}
