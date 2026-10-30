import Foundation

/// Worker-confined cumulative coverage, shared by full and incremental Clone Stamp.
/// The existing64x64 tile and160MiB admission limit is unchanged.
final class RetouchCoverageAccumulator {
  let width: Int
  let height: Int
  let columns: Int
  let transform: Transform2D
  let inverse: Transform2D
  let brush: CloneBrush
  private var generator = RetouchDabGenerator()
  private var dabCount = 0
  private var tiles: [Int: [Float]] = [:]
  private var dirty: Set<Int> = []
  init(width: Int, height: Int, transform: Transform2D, brush: CloneBrush) throws {
    self.width = width; self.height = height; columns = (width + 63) / 64
    self.transform = transform; inverse = try transform.inverted(); self.brush = brush
  }
  func append(_ points: [StrokePoint]) throws {
    dirty.removeAll(keepingCapacity: true)
    var sequence = generator
    try sequence.append(points, brush: brush) { try self.dab($0) }
    generator = sequence
  }
  func snapshot(dirtyOnly: Bool = false) -> RetouchCoverage {
    let values = dirtyOnly ? Dictionary(uniqueKeysWithValues: dirty.map { ($0, tiles[$0]!) }) : tiles
    return RetouchCoverage(width: width, height: height, columns: columns, tiles: values)
  }
  private func dab(_ p: StrokePoint) throws {
      try Task.checkCancellation()
      dabCount += 1
      guard dabCount <= 200_000 else { throw CraftError.invalid("Clone Stamp stroke is too long.") }
      guard p.pressure > 0 else { return }
      let radius = max(0.25, brush.size * (brush.pressureSize ? Double(p.pressure) : 1) / 2)
      let center = inverse.point(p.x, p.y)
      let rx = (radius + 0.5) * hypot(inverse.a, inverse.c)
      let ry = (radius + 0.5) * hypot(inverse.b, inverse.d)
      let x0 = Int(max(0, min(Double(width), floor(center.x - rx))))
      let x1 = Int(max(-1, min(Double(width - 1), ceil(center.x + rx))))
      let y0 = Int(max(0, min(Double(height), floor(center.y - ry))))
      let y1 = Int(max(-1, min(Double(height - 1), ceil(center.y + ry))))
      guard x0 <= x1, y0 <= y1 else { return }
      let ceiling: Float = brush.pressureOpacity ? p.pressure : 1
      for y in y0...y1 {
        try Task.checkCancellation()
        for x in x0...x1 {
          let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
          let v =
            ClonePainter.coverage(
              distance: Float(hypot(q.x - p.x, q.y - p.y)), radius: Float(radius),
              hardness: brush.hardness) * brush.flow
          guard v > 0 else { continue }
          let key = (y / 64) * columns + x / 64
          let i = (y % 64) * 64 + x % 64
          if tiles[key] == nil {
            guard tiles.count < 10_240 else {
              throw CraftError.invalid("Clone Stamp coverage exceeds its memory limit.")
            }
            tiles[key] = [Float](repeating: 0, count: 4096)
          }
          let prior = tiles[key]?[i] ?? 0
          let updated = prior + v * max(0, ceiling - prior)
          if updated != prior { dirty.insert(key); tiles[key]?[i] = updated }
        }
      }
    }
}
