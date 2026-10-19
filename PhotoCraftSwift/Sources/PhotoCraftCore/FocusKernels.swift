import Foundation

/// Numerical kernels translated from PhotoCraft's algo/retouch.rs and paint/retouch.rs.
/// These are source-reference equations, not a Photoshop output qualification.
public enum FocusKernels {
  public static let maxPixels = 40_000_000
  static func validate(
    _ data: [Float], _ w: Int, _ h: Int, _ ch: Int, _ alpha: Int?, _ win: IntRect
  ) throws {
    try Task.checkCancellation()
    guard w > 0, h > 0, w <= 36_864, h <= 36_864, w <= maxPixels / h,
      (1...4).contains(ch), data.count == w * h * ch,
      alpha == nil || (0..<ch).contains(alpha!),
      win.x >= 0, win.y >= 0, win.width >= 0, win.height >= 0,
      win.x <= w, win.y <= h, win.width <= w - win.x, win.height <= h - win.y
    else { throw CraftError.invalid("Invalid focus buffer or window.") }
    for i in data.indices {
      if i % 65_536 == 0 { try Task.checkCancellation() }
      guard data[i].isFinite, abs(data[i]) <= 1e12 else {
        throw CraftError.invalid("Invalid focus sample.")
      }
    }
  }
  public static func blur(
    _ data: [Float], width w: Int, height h: Int, channels ch: Int,
    alpha: Int?, window: IntRect, sigma: Float
  ) throws -> [Float] {
    try validate(data, w, h, ch, alpha, window)
    guard sigma.isFinite, (0.01...16).contains(sigma) else {
      throw CraftError.invalid("Invalid blur radius.")
    }
    return try blurUnchecked(data, w, h, ch, alpha, window, sigma)
  }
  static func blurUnchecked(
    _ data: [Float], _ w: Int, _ h: Int, _ ch: Int,
    _ alpha: Int?, _ win: IntRect, _ sigma: Float
  ) throws -> [Float] {
    let ow = win.width
    let oh = win.height
    if ow == 0 || oh == 0 { return [] }
    let r = max(1, Int(ceil(sigma * 3)))
    var kernel: [Float] = (-r...r).map { exp(-Float($0 * $0) / max(1e-6, 2 * sigma * sigma)) }
    let sum = kernel.reduce(Float(0), +)
    for i in kernel.indices { kernel[i] /= sum }
    let th = oh + 2 * r
    var tmp = [Float](repeating: 0, count: ow * th * ch)
    for ty in 0..<th {
      try Task.checkCancellation()
      let y = min(h - 1, max(0, win.y + ty - r))
      for ox in 0..<ow {
        let o = (ty * ow + ox) * ch
        for j in kernel.indices {
          let x = min(w - 1, max(0, win.x + ox + j - r))
          let at = (y * w + x) * ch
          let a = alpha.map { data[at + $0] } ?? 1
          for c in 0..<ch {
            tmp[o + c] += (c == alpha ? data[at + c] : data[at + c] * a) * kernel[j]
          }
        }
      }
    }
    var out = [Float](repeating: 0, count: ow * oh * ch)
    for oy in 0..<oh {
      try Task.checkCancellation()
      for ox in 0..<ow {
        let o = (oy * ow + ox) * ch
        for j in kernel.indices {
          let at = ((oy + j) * ow + ox) * ch
          for c in 0..<ch { out[o + c] += tmp[at + c] * kernel[j] }
        }
        if let alpha {
          let a = out[o + alpha]
          for c in 0..<ch where c != alpha {
            out[o + c] = a > 1e-6 ? out[o + c] / a : data[((win.y + oy) * w + win.x + ox) * ch + c]
          }
        }
      }
    }
    return out
  }
  public static func sharpen(
    _ data: [Float], width w: Int, height h: Int, channels ch: Int,
    alpha: Int?, window: IntRect, amount: Float, protectDetail: Bool
  ) throws -> [Float] {
    try validate(data, w, h, ch, alpha, window)
    guard amount.isFinite, (0...10).contains(amount) else {
      throw CraftError.invalid("Invalid sharpening amount.")
    }
    return try sharpenUnchecked(data, w, h, ch, alpha, window, amount, protectDetail)
  }
  static func sharpenUnchecked(
    _ data: [Float], _ w: Int, _ h: Int, _ ch: Int,
    _ alpha: Int?, _ win: IntRect, _ amount: Float, _ protect: Bool
  ) throws -> [Float] {
    let blur = try blurUnchecked(data, w, h, ch, alpha, win, 1)
    var out = [Float](repeating: 0, count: blur.count)
    for y in win.y..<win.y + win.height {
      try Task.checkCancellation()
      for x in win.x..<win.x + win.width {
        let o = ((y - win.y) * win.width + x - win.x) * ch
        let i = (y * w + x) * ch
        for c in 0..<ch {
          let v = data[i + c]
          if c == alpha {
            out[o + c] = v
            continue
          }
          var s = v + amount * (v - blur[o + c])
          if protect {
            var lo = v
            var hi = v
            for dy in -1...1 {
              for dx in -1...1 where dx != 0 || dy != 0 {
                let nx = min(w - 1, max(0, x + dx))
                let ny = min(h - 1, max(0, y + dy))
                let n = data[(ny * w + nx) * ch + c]
                lo = min(lo, n)
                hi = max(hi, n)
              }
            }
            s = min(hi, max(lo, s))
          }
          out[o + c] = s
        }
      }
    }
    return out
  }
  static func mix(_ before: Pixel, _ after: Pixel, _ k: Float) -> Pixel {
    if k <= 0 { return before }
    let a = before.a + (after.a - before.a) * k
    func c(_ b: Float, _ s: Float) -> Float {
      a > 1e-6 ? (b * before.a + (s * after.a - b * before.a) * k) / a : b + (s - b) * k
    }
    return Pixel(c(before.r, after.r), c(before.g, after.g), c(before.b, after.b), a)
  }
}

/// Stateful premultiplied pickup/laydown buffer. Each stroke owns one instance.
public struct SmudgeKernel: Sendable {
  let strength: Float
  let finger: [Float]?
  let radius: Int
  let alpha: Int?
  var carry: [Float]?
  public init(strength: Float, finger: [Float]? = nil, maxBrushSize: Float, alpha: Int?) throws {
    guard strength.isFinite, (0...1).contains(strength), maxBrushSize.isFinite,
      (1...2048).contains(maxBrushSize), alpha == nil || (0..<4).contains(alpha!),
      finger == nil
        || (!finger!.isEmpty && finger!.count <= 4
          && finger!.allSatisfy({ $0.isFinite && abs($0) <= 1e12 }))
    else { throw CraftError.invalid("Invalid Smudge settings.") }
    self.strength = strength
    self.finger = finger
    radius = Int(ceil(maxBrushSize / 2)) + 2
    self.alpha = alpha
  }
  public mutating func apply(
    to data: inout [Float], width w: Int, height h: Int, channels ch: Int,
    center: PathPoint, window: IntRect, coverage: [Float]
  ) throws {
    try FocusKernels.validate(data, w, h, ch, alpha, window)
    guard center.x.isFinite, center.y.isFinite, abs(center.x) <= 1_000_000,
      abs(center.y) <= 1_000_000,
      coverage.count == window.width * window.height,
      coverage.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
      carry == nil || carry!.count == (2 * radius + 1) * (2 * radius + 1) * ch
    else { throw CraftError.invalid("Invalid Smudge footprint.") }
    // Public entry point has strong exception safety for cancellation.
    var result = data
    var state = self
    try state.applyUnchecked(to: &result, w, h, ch, center, window, coverage)
    try Task.checkCancellation()
    data = result
    self = state
  }
  mutating func applyUnchecked(
    to data: inout [Float], _ w: Int, _ h: Int, _ ch: Int,
    _ center: PathPoint, _ win: IntRect, _ coverage: [Float]
  ) throws {
    let r = radius
    let side = 2 * r + 1
    let cx = Int(floor(center.x))
    let cy = Int(floor(center.y))
    func pm(_ x: Int, _ y: Int, _ c: Int) -> Float {
      let at = (min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))) * ch
      let a = alpha.map { data[at + $0] } ?? 1
      return data[at + c] * (alpha != nil && c != alpha ? a : 1)
    }
    if carry == nil {
      var start = [Float](repeating: 0, count: side * side * ch)
      for y in 0..<side {
        try Task.checkCancellation()
        for x in 0..<side {
          for c in 0..<ch {
            if let finger {
              let v = c < finger.count ? finger[c] : 1
              let a = alpha.map { $0 < finger.count ? finger[$0] : 1 } ?? 1
              start[(y * side + x) * ch + c] = v * (alpha != nil && c != alpha ? a : 1)
            } else {
              start[(y * side + x) * ch + c] = pm(cx + x - r, cy + y - r, c)
            }
          }
        }
      }
      carry = start
    }
    for y in win.y..<win.y + win.height {
      try Task.checkCancellation()
      for x in win.x..<win.x + win.width {
        let k = coverage[(y - win.y) * win.width + x - win.x] * strength
        let qx = x - cx + r
        let qy = y - cy + r
        if k <= 0 || qx < 0 || qy < 0 || qx >= side || qy >= side { continue }
        let q = (qy * side + qx) * ch
        let at = (y * w + x) * ch
        if let alpha {
          let ca = carry![q + alpha]
          let da = data[at + alpha]
          let oa = da + (ca - da) * k
          for c in 0..<ch where c != alpha {
            let s = ca > 1e-6 ? carry![q + c] / ca : carry![q + c]
            let b = data[at + c]
            data[at + c] = oa > 1e-6 ? (b * da + (s * ca - b * da) * k) / oa : b + (s - b) * k
          }
          data[at + alpha] = oa
        } else {
          for c in 0..<ch { data[at + c] += (carry![q + c] - data[at + c]) * k }
        }
      }
    }
    for y in 0..<side {
      try Task.checkCancellation()
      for x in 0..<side {
        let px = cx + x - r
        let py = cy + y - r
        if px < 0 || py < 0 || px >= w || py >= h { continue }
        let q = (y * side + x) * ch
        let at = (py * w + px) * ch
        let a = alpha.map { data[at + $0] } ?? 1
        for c in 0..<ch {
          let v = data[at + c] * (alpha != nil && c != alpha ? a : 1)
          carry![q + c] = carry![q + c] * strength + v * (1 - strength)
        }
      }
    }
  }
}
