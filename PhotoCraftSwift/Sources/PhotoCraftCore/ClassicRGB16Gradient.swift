import Foundation

/// RGB16 Gradient Map lookup derived from original Photoshop-saved probes.
/// This is deliberately separate from Gradient Fill/paint and other depths, whose
/// transfer functions have different qualification. See CLASSIC_GRADIENT_RESEARCH.
struct ClassicRGB16Gradient: Sendable {
  let samples: [Pixel]

  init(_ gradient: GradientDefinition) {
    struct Stop {
      let position: Int
      let midpoint: Int
      let value: [Double]
    }
    let stops = gradient.colors.enumerated().sorted {
      $0.element.position == $1.element.position
        ? $0.offset < $1.offset : $0.element.position < $1.element.position
    }.map { _, stop in
      let color = stop.color.resolved(foreground: .black, background: .white)
      return Stop(
        position: Int((stop.position * 4096).rounded()),
        midpoint: min(95, max(5, Int((stop.midpoint * 100).rounded()))),
        value: [color.r, color.g, color.b].map { component in
          let n = Int((unit(component) * 32768).rounded())
          // Keep the signed-fraction numerator exact. Halfway color buckets tie down.
          let center = ((n + 63) / 128) * 128
          return Double(256 * n - center)
        })
    }
    let smoothness = Double((gradient.smoothness * 4096).rounded()) / 4096
    var table: [Pixel] = []
    table.reserveCapacity(4097)
    var end = 0
    for t in 0...4096 {
      // The later stop wins at coincident positions, including both endpoints.
      while end < stops.count && stops[end].position <= t { end += 1 }
      let values: [Double]
      if end == 0 {
        values = stops[0].value
      } else if end == stops.count || stops[end - 1].position == t {
        values = stops[end - 1].value
      } else {
        let a = end - 1
        let b = end
        let span = stops[b].position - stops[a].position
        let offset = t - stops[a].position
        let midpoint = (span * stops[b].midpoint + 50) / 100
        // Exact stop positions were handled above. This also avoids division by
        // zero for a one-position segment whose midpoint rounds to an endpoint.
        let u =
          offset <= midpoint
          ? Double(offset) * (0.5 / Double(midpoint))
          : 0.5 + Double(offset - midpoint) / Double(span - midpoint) * 0.5
        let u2 = u * u
        let u3 = u2 * u
        values = (0..<3).map { c in
          let x = stops[a].value[c]
          let y = stops[b].value[c]
          // Uniform-parameter slopes do not rescale with neighboring stop spacing.
          let ta = (stops[b].value[c] - stops[max(0, a - 1)].value[c]) * 0.5
          let tb = (stops[min(stops.count - 1, b + 1)].value[c] - stops[a].value[c]) * 0.5
          // A single rounding for the second product and addition matches the
          // independently saved RGB16 linear ramp boundaries. Keep the first
          // product separate; fusing the opposite product changes other samples.
          let linear = (x * (1 - u)).addingProduct(y, u)
          let cubic =
            (2 * u3 - 3 * u2 + 1) * x + (u3 - 2 * u2 + u) * ta
            + (-2 * u3 + 3 * u2) * y + (u3 - u2) * tb
          let value = linear * (1 - smoothness) + cubic * smoothness
          return max(min(x, y), min(max(x, y), value))
        }
      }
      let rgb = values.map { value in
        let bucket = floor(value / 32640)
        let working = min(32768, max(0, floor((value + 128 * bucket) / 256)))
        return Float(working) / 32768
      }
      table.append(Pixel(rgb[0], rgb[1], rgb[2]))
    }
    samples = table
  }
}
