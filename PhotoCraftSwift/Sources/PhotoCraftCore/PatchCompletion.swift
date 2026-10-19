import Foundation

extension Inpainting {
  public struct Parameters: Sendable {
    public var patchRadius = 3
    public var emIterations = 8
    public var minimumIterations = 2
    public var patchMatchIterations = 2
    public var refineExtent = 96
    public var seed: UInt64 = 1
    public init() {}
    func validate() throws {
      guard (1...16).contains(patchRadius), (1...32).contains(emIterations),
        (1...emIterations).contains(minimumIterations), (1...8).contains(patchMatchIterations),
        (1...32768).contains(refineExtent)
      else { throw CraftError.invalid("Invalid content-aware completion parameters.") }
    }
  }
  public static func complete(
    width: Int, height: Int, channels: Int, image: [Float], hole: [Bool],
    parameters p: Parameters = Parameters()
  ) throws -> [Float]? {
    let g = Grid(w: width, h: height, ch: channels, image: image, hole: hole)
    try validate(g)
    try p.validate()
    return try completion(g, p)
  }
  static func completion(_ g: Grid, _ p: Parameters = Parameters()) throws -> [Float]? {
    guard let box = bbox(g.w, g.h, g.hole) else { return g.image }
    let r = p.patchRadius
    let size = 2 * r + 1
    var levels = [g]
    var extent = max(box.width, box.height)
    var extents = [max(box.width, box.height)]
    while let last = levels.last {
      try Task.checkCancellation()
      if extent <= 2 * size || last.w / 2 < 3 * size || last.h / 2 < 3 * size { break }
      levels.append(try downsample(last))
      extent = (extent + 1) / 2
      extents.append(extent)
    }
    var field: [Point] = []
    var previous: Grid?
    for li in levels.indices.reversed() {
      try Task.checkCancellation()
      var level = levels[li]
      if let previous {
        for y in 0..<level.h {
          try Task.checkCancellation()
          for x in 0..<level.w where level.hole[y * level.w + x] {
            let sx = min(x / 2, previous.w - 1)
            let sy = min(y / 2, previous.h - 1)
            let d = (y * level.w + x) * level.ch
            let s = (sy * previous.w + sx) * level.ch
            for c in 0..<level.ch { level.image[d + c] = previous.image[s + c] }
          }
        }
      } else {
        level.image = try membrane(level)
      }
      var solver = try PatchSolver(level, radius: r)
      if solver.validPoints.isEmpty {
        if li == 0 { return nil }
        previous = level
        field = []
        continue
      }
      var rng = RNG(p.seed ^ (UInt64(li) << 20))
      let old = field
      let pw = previous?.w ?? 0
      field = [Point](repeating: Point(x: 0, y: 0), count: level.w * level.h)
      for y in 0..<level.h {
        try Task.checkCancellation()
        for x in 0..<level.w where solver.targets[y * level.w + x] {
          var candidate: Point?
          if !old.isEmpty && pw > 0 {
            let i = (y / 2) * pw + x / 2
            if i < old.count {
              let point = Point(x: old[i].x * 2 + x % 2, y: old[i].y * 2 + y % 2)
              if solver.isValid(point) { candidate = point }
            }
          }
          field[y * level.w + x] =
            candidate ?? solver.validPoints[Int(rng.next() % UInt64(solver.validPoints.count))]
        }
      }
      let refine = li + 1 < levels.count && extents[li] > p.refineExtent
      let em =
        li + 1 == levels.count
        ? p.emIterations
        : refine ? 1 : max(p.minimumIterations, p.emIterations >> (levels.count - 1 - li))
      let pm = refine ? 1 : p.patchMatchIterations
      let search = max(level.w, level.h)
      var cost = [Float](repeating: .infinity, count: field.count)
      for iteration in 0..<em {
        for i in field.indices {
          if i % (level.w * 32) == 0 { try Task.checkCancellation() }
          if solver.targets[i] {
            cost[i] = solver.distance(
              Point(x: i % level.w, y: i / level.w), field[i], cutoff: .infinity)
          }
        }
        let radius =
          refine ? 2 : li + 1 == levels.count || iteration == 0 ? search : min(4 * size, search)
        for pass in 0..<pm {
          try solver.patchMatch(
            &field, &cost, pass: pass + iteration * pm,
            seed: p.seed &+ UInt64(li * 1000 + iteration), searchRadius: radius)
        }
        try solver.vote(field, cost)
      }
      previous = solver.grid
    }
    try Task.checkCancellation()
    return previous?.image
  }

  struct PatchSolver {
    var grid: Grid
    let r: Int
    var valid: [Bool], validPoints: [Point], targets: [Bool]
    init(_ grid: Grid, radius: Int) throws {
      self.grid = grid
      r = radius
      let hs = Integral(grid.w, grid.h, grid.hole)
      valid = [Bool](repeating: false, count: grid.w * grid.h)
      targets = valid
      validPoints = []
      for y in 0..<grid.h {
        try Task.checkCancellation()
        for x in 0..<grid.w {
          let count = hs.count(x - r, y - r, x + r + 1, y + r + 1)
          let inside = x >= r && y >= r && x + r < grid.w && y + r < grid.h
          let i = y * grid.w + x
          if inside && count == 0 {
            valid[i] = true
            validPoints.append(Point(x: x, y: y))
          }
          targets[i] = count > 0
        }
      }
    }
    func isValid(_ point: Point) -> Bool {
      point.x >= 0 && point.y >= 0 && point.x < grid.w && point.y < grid.h
        && valid[point.y * grid.w + point.x]
    }
    func distance(_ t: Point, _ s: Point, cutoff: Float) -> Float {
      let full = Float((2 * r + 1) * (2 * r + 1)) * Float(grid.ch)
      var sum: Float = 0
      var n = 0
      for dy in -r...r {
        let ty = t.y + dy
        if ty < 0 || ty >= grid.h { continue }
        let sy = s.y + dy
        for dx in -r...r {
          let tx = t.x + dx
          if tx < 0 || tx >= grid.w { continue }
          let ti = (ty * grid.w + tx) * grid.ch
          let si = (sy * grid.w + s.x + dx) * grid.ch
          for c in 0..<grid.ch {
            let d = grid.image[ti + c] - grid.image[si + c]
            sum += d * d
          }
          n += grid.ch
        }
        if sum > cutoff * full { return .infinity }
      }
      return n == 0 ? .infinity : sum / Float(n)
    }
    // Fixed 16-row bands preserve the original parallel implementation's propagation boundaries.
    func patchMatch(
      _ field: inout [Point], _ costs: inout [Float], pass: Int, seed: UInt64, searchRadius: Int
    ) throws {
      let reverse = pass % 2 == 1
      let step = reverse ? -1 : 1
      let w = grid.w
      for y0 in stride(from: 0, to: grid.h, by: 16) {
        try Task.checkCancellation()
        let band = y0 / 16
        let rows = min(16, grid.h - y0)
        var rng = RNG(seed ^ (UInt64(band) &* 0x2545_F491_4F6C_DD1D) ^ (UInt64(pass) << 40))
        for ry in 0..<rows {
          let ly = reverse ? rows - 1 - ry : ry
          let y = y0 + ly
          for rx in 0..<w {
            let x = reverse ? w - 1 - rx : rx
            let i = y * w + x
            if !targets[i] { continue }
            let t = Point(x: x, y: y)
            var best = field[i]
            var cost = costs[i]
            func consider(_ candidate: Point) {
              if isValid(candidate) && candidate != best {
                let d = distance(t, candidate, cutoff: cost)
                if d < cost {
                  best = candidate
                  cost = d
                }
              }
            }
            let nx = x - step
            if nx >= 0 && nx < w {
              let c = field[y * w + nx]
              consider(Point(x: c.x + step, y: c.y))
            }
            let nly = ly - step
            if nly >= 0 && nly < rows {
              let c = field[(y0 + nly) * w + x]
              consider(Point(x: c.x, y: c.y + step))
            }
            var radius = searchRadius
            while radius >= 1 {
              let candidate = Point(
                x: best.x + rng.range(-radius, radius), y: best.y + rng.range(-radius, radius))
              consider(candidate)
              radius /= 2
            }
            field[i] = best
            costs[i] = cost
          }
        }
      }
    }
    mutating func vote(_ field: [Point], _ cost: [Float]) throws {
      let costs = cost.indices.compactMap { targets[$0] && cost[$0].isFinite ? cost[$0] : nil }
        .sorted()
      let sigma: Float =
        costs.isEmpty ? 1 : max(1e-6, costs[min(costs.count - 1, costs.count * 3 / 4)])
      var output = grid.image
      for y in 0..<grid.h {
        try Task.checkCancellation()
        for x in 0..<grid.w where grid.hole[y * grid.w + x] {
          var acc = [Float](repeating: 0, count: grid.ch)
          var sum: Float = 0
          for dy in -r...r {
            let ty = y + dy
            if ty < 0 || ty >= grid.h { continue }
            for dx in -r...r {
              let tx = x + dx
              if tx < 0 || tx >= grid.w { continue }
              let ti = ty * grid.w + tx
              if !targets[ti] || !cost[ti].isFinite { continue }
              let s = field[ti]
              let sx = s.x - dx
              let sy = s.y - dy
              let weight = max(1e-8, exp(-cost[ti] / (2 * sigma)))
              let si = (sy * grid.w + sx) * grid.ch
              for c in 0..<grid.ch { acc[c] += grid.image[si + c] * weight }
              sum += weight
            }
          }
          if sum > 0 {
            for c in 0..<grid.ch { output[(y * grid.w + x) * grid.ch + c] = acc[c] / sum }
          }
        }
      }
      grid.image = output
    }
  }
}
