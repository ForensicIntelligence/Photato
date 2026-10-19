import Foundation

/// Native port of PhotoCraft's deterministic inpaint.rs algorithms. No learned model or network.
/// Wexler et al. (2007), Barnes et al. (2009), Efros and Freeman (2001).
public enum Inpainting {
  public static let maxPixels = 4_194_304
  struct Grid {
    var w: Int, h: Int, ch: Int
    var image: [Float]
    var hole: [Bool]
  }
  struct Point: Equatable {
    var x: Int
    var y: Int
  }
  struct RNG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed ^ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
    mutating func range(_ lo: Int, _ hi: Int) -> Int {
      hi <= lo ? lo : lo + Int(next() % UInt64(hi - lo + 1))
    }
  }
  static func validate(_ g: Grid) throws {
    try Task.checkCancellation()
    guard g.w > 0, g.h > 0, g.w <= Surface.maxDimension, g.h <= Surface.maxDimension,
      g.w <= maxPixels / g.h, (1...4).contains(g.ch), g.hole.count == g.w * g.h,
      g.image.count == g.w * g.h * g.ch, g.image.allSatisfy({ $0.isFinite && abs($0) <= 1e12 })
    else { throw CraftError.invalid("Invalid, oversized or out-of-range repair data.") }
  }
  static func bbox(_ w: Int, _ h: Int, _ hole: [Bool]) -> IntRect? {
    var x0 = w
    var y0 = h
    var x1 = 0
    var y1 = 0
    for i in hole.indices where hole[i] {
      x0 = min(x0, i % w)
      y0 = min(y0, i / w)
      x1 = max(x1, i % w + 1)
      y1 = max(y1, i / w + 1)
    }
    return x1 > x0 && y1 > y0 ? IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) : nil
  }
  struct Integral {
    let w: Int, h: Int
    var data: [Int]
    init(_ w: Int, _ h: Int, _ mask: [Bool]) {
      self.w = w
      self.h = h
      data = [Int](repeating: 0, count: (w + 1) * (h + 1))
      for y in 0..<h {
        var row = 0
        for x in 0..<w {
          if mask[y * w + x] { row += 1 }
          data[(y + 1) * (w + 1) + x + 1] = data[y * (w + 1) + x + 1] + row
        }
      }
    }
    func count(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Int {
      let a = max(0, x0)
      let b = max(0, y0)
      let c = min(w, max(0, x1))
      let d = min(h, max(0, y1))
      guard c > a && d > b else { return 0 }
      return data[d * (w + 1) + c] + data[b * (w + 1) + a] - data[b * (w + 1) + c]
        - data[d * (w + 1) + a]
    }
  }
  static func dilate(_ w: Int, _ h: Int, _ mask: [Bool], radius: Int) throws -> [Bool] {
    let integral = Integral(w, h, mask)
    var result = mask
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        result[y * w + x] =
          integral.count(x - radius, y - radius, x + radius + 1, y + radius + 1) > 0
      }
    }
    return result
  }
  static func membrane(_ g: Grid) throws -> [Float] {
    var result = g.image
    for c in 0..<g.ch {
      let values = g.hole.indices.map { g.hole[$0] ? Float(0) : g.image[$0 * g.ch + c] }
      let plane = try HealingSolver.membrane(
        width: g.w, height: g.h, unknown: g.hole, values: values)
      for i in g.hole.indices { result[i * g.ch + c] = plane[i] }
    }
    return result
  }
  static func downsample(_ g: Grid) throws -> Grid {
    let w = (g.w + 1) / 2
    let h = (g.h + 1) / 2
    var image = [Float](repeating: 0, count: w * h * g.ch)
    var hole = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        var n: Float = 0
        let o = (y * w + x) * g.ch
        for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
          let sx = x * 2 + dx
          let sy = y * 2 + dy
          if sx >= g.w || sy >= g.h { continue }
          let i = sy * g.w + sx
          if g.hole[i] {
            hole[y * w + x] = true
          } else {
            for c in 0..<g.ch { image[o + c] += g.image[i * g.ch + c] }
            n += 1
          }
        }
        if n > 0 { for c in 0..<g.ch { image[o + c] /= n } }
      }
    }
    return Grid(w: w, h: h, ch: g.ch, image: image, hole: hole)
  }

  public static func bestOffset(
    width: Int, height: Int, channels: Int, image: [Float], hole: [Bool], ring: Int, maxRadius: Int
  ) throws -> (x: Int, y: Int)? {
    let g = Grid(w: width, h: height, ch: channels, image: image, hole: hole)
    try validate(g)
    guard (1...64).contains(ring), (1...4096).contains(maxRadius) else {
      throw CraftError.invalid("Invalid proximity search size.")
    }
    return try offset(g, ring: ring, maxRadius: maxRadius).map { ($0.x, $0.y) }
  }
  static func offset(_ g: Grid, ring: Int, maxRadius: Int) throws -> Point? {
    guard let b = bbox(g.w, g.h, g.hole) else { return nil }
    let hs = Integral(g.w, g.h, g.hole)
    let x0 = b.x - ring
    let y0 = b.y - ring
    let x1 = b.x + b.width + ring
    let y1 = b.y + b.height + ring
    var points: [Point] = []
    for y in max(0, y0)..<min(g.h, y1) {
      for x in max(0, x0)..<min(g.w, x1) where !g.hole[y * g.w + x] {
        if hs.count(x - ring, y - ring, x + ring + 1, y + ring + 1) > 0 {
          points.append(Point(x: x, y: y))
        }
      }
    }
    let stepPoints = max(1, points.count / 2000)
    points = stride(from: 0, to: points.count, by: stepPoints).map { points[$0] }
    var best: Point?
    var bestCost = Float.infinity
    func consider(_ dx: Int, _ dy: Int) {
      let a = x0 + dx
      let b = y0 + dy
      let c = x1 + dx
      let d = y1 + dy
      guard dx != 0 || dy != 0, a >= 0, b >= 0, c <= g.w, d <= g.h,
        hs.count(a, b, c, d) == 0
      else { return }
      var error: Float = 0
      for p in points {
        let i = (p.y * g.w + p.x) * g.ch
        let j = ((p.y + dy) * g.w + p.x + dx) * g.ch
        for c in 0..<g.ch {
          let delta = g.image[i + c] - g.image[j + c]
          error += delta * delta
        }
      }
      let cost =
        error / Float(max(1, points.count))
        * (1 + 1e-3 * sqrt(Float(dx * dx + dy * dy)) / Float(maxRadius))
      if best == nil || cost < bestCost {
        best = Point(x: dx, y: dy)
        bestCost = cost
      }
    }
    let step = max(1, maxRadius / 24)
    for dy in stride(from: -maxRadius, through: maxRadius, by: step) {
      try Task.checkCancellation()
      for dx in stride(from: -maxRadius, through: maxRadius, by: step) { consider(dx, dy) }
    }
    if step > 1, let b = best {
      for dy in (b.y - step)...(b.y + step) {
        try Task.checkCancellation()
        for dx in (b.x - step)...(b.x + step) { consider(dx, dy) }
      }
    }
    return best
  }

  public static func synthesize(
    width: Int, height: Int, channels: Int, image: [Float], hole: [Bool], block: Int,
    seed: UInt64 = 0x5eed
  ) throws -> [Float] {
    let g = Grid(w: width, h: height, ch: channels, image: image, hole: hole)
    try validate(g)
    guard (4...64).contains(block) else { throw CraftError.invalid("Invalid texture block size.") }
    return try texture(g, block: block, seed: seed)
  }
  static func texture(_ g: Grid, block b: Int, seed: UInt64) throws -> [Float] {
    guard let box = bbox(g.w, g.h, g.hole) else { return g.image }
    var output = g.image
    let overlap = max(1, b / 3)
    let hs = Integral(g.w, g.h, g.hole)
    var candidates: [Point] = []
    if overlap < g.h - b - overlap && overlap < g.w - b - overlap {
      for y in overlap..<(g.h - b - overlap) {
        try Task.checkCancellation()
        for x in overlap..<(g.w - b - overlap) {
          if hs.count(x - overlap, y - overlap, x + b + overlap, y + b + overlap) == 0 {
            candidates.append(Point(x: x, y: y))
          }
        }
      }
    }
    guard !candidates.isEmpty else { return try membrane(g) }
    var filled = g.hole.map { !$0 }
    var rng = RNG(seed)
    for by in stride(from: box.y, to: box.y + box.height, by: b) {
      for bx in stride(from: box.x, to: box.x + box.width, by: b) {
        try Task.checkCancellation()
        guard hs.count(bx, by, bx + b, by + b) > 0 else { continue }
        var best = candidates[0]
        var cost = Float.infinity
        for _ in 0..<48 {
          let c = candidates[Int(rng.next() % UInt64(candidates.count))]
          var error: Float = 0
          var n: Float = 0
          for y in (by - overlap)..<(by + b + overlap) {
            for x in (bx - overlap)..<(bx + b + overlap) {
              guard x >= 0, y >= 0, x < g.w, y < g.h, filled[y * g.w + x] else { continue }
              let a = (y * g.w + x) * g.ch
              let s = ((y - by + c.y) * g.w + x - bx + c.x) * g.ch
              for k in 0..<g.ch {
                let d = output[a + k] - g.image[s + k]
                error += d * d
              }
              n += 1
            }
          }
          let e: Float = n == 0 ? 0 : error / n
          if e < cost {
            best = c
            cost = e
          }
        }
        for y in (by - overlap)..<(by + b + overlap) {
          for x in (bx - overlap)..<(bx + b + overlap) {
            guard x >= 0, y >= 0, x < g.w, y < g.h else { continue }
            let i = y * g.w + x
            guard g.hole[i] else { continue }
            let a = i * g.ch
            let s = ((y - by + best.y) * g.w + x - bx + best.x) * g.ch
            let k: Float = filled[i] ? 0.5 : 1
            for c in 0..<g.ch { output[a + c] += (g.image[s + c] - output[a + c]) * k }
            filled[i] = true
          }
        }
      }
    }
    return output
  }
}
