import Foundation

/// Swift port of PhotoCraft's cascadic membrane solver (algo/src/poisson.rs).
/// Pérez, Gangnet and Blake, Poisson Image Editing, SIGGRAPH 2003.
/// This is source-port compatibility, not a claim about Adobe's proprietary solver.
public enum HealingSolver {
  /// Bounds temporary storage and work for one repair. Larger strokes fail atomically.
  public static let maxPixels = 4_194_304

  public static func membrane(width: Int, height: Int, unknown: [Bool], values: [Float])
    throws -> [Float]
  {
    try validate(width, height, channels: 1, mask: unknown, buffers: [values])
    var result = values
    try solve(width, height, unknown, &result, depth: 0)
    guard result.allSatisfy(\.isFinite) else {
      throw CraftError.invalid("Healing values exceed the supported numeric range.")
    }
    return result
  }

  /// Channels are independent, including alpha. Known pixels retain their exact bits.
  public static func seamlessClone(
    width: Int, height: Int, channels: Int,
    source: [Float], destination: [Float], mask: [Bool]
  ) throws -> [Float] {
    try validate(width, height, channels: channels, mask: mask, buffers: [source, destination])
    var result = destination
    for c in 0..<channels {
      try Task.checkCancellation()
      var v = mask.indices.map {
        mask[$0] ? Float(0) : destination[$0 * channels + c] - source[$0 * channels + c]
      }
      guard v.allSatisfy(\.isFinite) else { throw CraftError.invalid("Healing boundary overflow.") }
      try solve(width, height, mask, &v, depth: 0)
      for i in mask.indices where mask[i] {
        let value = source[i * channels + c] + v[i]
        guard value.isFinite else { throw CraftError.invalid("Healing solution overflow.") }
        result[i * channels + c] = value
      }
    }
    try Task.checkCancellation()
    return result
  }

  private static func validate(_ w: Int, _ h: Int, channels: Int, mask: [Bool], buffers: [[Float]])
    throws
  {
    try Task.checkCancellation()
    guard w > 0, h > 0, w <= Surface.maxDimension, h <= Surface.maxDimension, w <= maxPixels / h,
      (1...4).contains(channels), mask.count == w * h,
      buffers.allSatisfy({ $0.count == w * h * channels && $0.allSatisfy(\.isFinite) })
    else { throw CraftError.invalid("Invalid or oversized Healing Brush region.") }
  }

  private static func solve(_ w: Int, _ h: Int, _ unknown: [Bool], _ v: inout [Float], depth: Int)
    throws
  {
    try Task.checkCancellation()
    let count = unknown.filter { $0 }.count
    guard count > 0 && count < unknown.count else { return }
    if w >= 8 && h >= 8 && count > 64 && depth < 16 {
      let cw = (w + 1) / 2
      let ch = (h + 1) / 2
      var cu = [Bool](repeating: true, count: cw * ch)
      var cv = [Float](repeating: 0, count: cw * ch)
      for cy in 0..<ch {
        try Task.checkCancellation()
        for cx in 0..<cw {
          var sum: Float = 0
          var n: Float = 0
          for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
            let x = cx * 2 + dx
            let y = cy * 2 + dy
            if x < w && y < h && !unknown[y * w + x] {
              sum += v[y * w + x]
              n += 1
            }
          }
          if n > 0 {
            cu[cy * cw + cx] = false
            cv[cy * cw + cx] = sum / n
          }
        }
      }
      try solve(cw, ch, cu, &cv, depth: depth + 1)
      for y in 0..<h {
        try Task.checkCancellation()
        let fy = min(Float(ch - 1), max(0, (Float(y) + 0.5) / 2 - 0.5))
        let y0 = Int(floor(fy))
        let y1 = min(y0 + 1, ch - 1)
        let ty = fy - Float(y0)
        for x in 0..<w where unknown[y * w + x] {
          let fx = min(Float(cw - 1), max(0, (Float(x) + 0.5) / 2 - 0.5))
          let x0 = Int(floor(fx))
          let x1 = min(x0 + 1, cw - 1)
          let tx = fx - Float(x0)
          let a = cv[y0 * cw + x0] + (cv[y0 * cw + x1] - cv[y0 * cw + x0]) * tx
          let b = cv[y1 * cw + x0] + (cv[y1 * cw + x1] - cv[y1 * cw + x0]) * tx
          v[y * w + x] = a + (b - a) * ty
        }
      }
      try sor(w, h, unknown, &v, iterations: 30, omega: 1.7)
    } else {
      var sum: Float = 0
      for i in v.indices where !unknown[i] { sum += v[i] }
      let mean = sum / Float(unknown.count - count)
      for i in v.indices where unknown[i] { v[i] = mean }
      try sor(w, h, unknown, &v, iterations: 2000, omega: 1.85)
    }
  }

  private static func sor(
    _ w: Int, _ h: Int, _ unknown: [Bool], _ v: inout [Float], iterations: Int, omega: Float
  ) throws {
    let cells: [(Int, UInt8)] = unknown.indices.compactMap { i in
      guard unknown[i] else { return nil }
      let x = i % w
      let y = i / w
      let mask: UInt8 =
        (x > 0 ? 1 : 0) | (x + 1 < w ? 2 : 0) | (y > 0 ? 4 : 0) | (y + 1 < h ? 8 : 0)
      return (i, mask)
    }
    for _ in 0..<iterations {
      try Task.checkCancellation()
      var maxDelta: Float = 0
      for (i, m) in cells {
        var sum: Float = 0
        var n: Float = 0
        if m == 15 {
          sum = v[i - 1] + v[i + 1] + v[i - w] + v[i + w]
          n = 4
        } else {
          if m & 1 != 0 {
            sum += v[i - 1]
            n += 1
          }
          if m & 2 != 0 {
            sum += v[i + 1]
            n += 1
          }
          if m & 4 != 0 {
            sum += v[i - w]
            n += 1
          }
          if m & 8 != 0 {
            sum += v[i + w]
            n += 1
          }
          if n == 0 { continue }
        }
        let delta = omega * (sum / n - v[i])
        v[i] += delta
        maxDelta = max(maxDelta, abs(delta))
      }
      if maxDelta < 2e-5 { break }
    }
  }
}
