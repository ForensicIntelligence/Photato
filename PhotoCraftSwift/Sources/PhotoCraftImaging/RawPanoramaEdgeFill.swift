import Foundation
import PhotoCraftCore

/// Solve a patch field over the whole panorama, then vote with the original
/// full-resolution donor pixels. The dense solver never needs the full raster.
enum RawPanoramaEdgeFill {
  private static let analysisBudget = 131_072
  private static let minimumCoverage: Float = 0.999
  private static let missing = SIMD2<Int32>(repeating: -1)

  static func fill(_ source: Surface) throws -> Surface {
    let width = source.width, height = source.height
    var step = max(1, Int(ceil(sqrt(Double(width * height) / Double(analysisBudget)))))
    while ((width + step - 1) / step) * ((height + step - 1) / step) > analysisBudget {
      step += 1
    }
    let cellSide = step
    let columns = (width + step - 1) / step
    let rows = (height + step - 1) / step
    let count = columns * rows
    var sums = [SIMD3<Double>](repeating: .zero, count: count)
    var knownCount = [Int](repeating: 0, count: count)
    var witnesses = [SIMD2<Int32>](repeating: missing, count: count)
    var needsFill = false
    for y in 0..<height {
      try Task.checkCancellation()
      let line = source.linearRow(y)
      let row = y / step * columns
      for (x, pixel) in line.enumerated() {
        if pixel.a < 1 { needsFill = true }
        guard pixel.a >= minimumCoverage else { continue }
        let index = row + x / step
        if knownCount[index] == 0 { witnesses[index] = SIMD2(Int32(x), Int32(y)) }
        knownCount[index] += 1
        sums[index] += SIMD3<Double>(Double(pixel.r), Double(pixel.g), Double(pixel.b))
      }
    }
    guard needsFill else { return source }
    guard knownCount.contains(where: { $0 > 0 }) else {
      throw CraftError.invalid("Fill Edges needs opaque source pixels.")
    }
    var hole = [Bool]()
    var image = [Float]()
    hole.reserveCapacity(count)
    image.reserveCapacity(count * 3)
    for i in 0..<count {
      let x = i % columns, y = i / columns
      let size = min(step, width - x * step) * min(step, height - y * step)
      hole.append(knownCount[i] < size)
      let average = sums[i] / Double(max(1, knownCount[i]))
      image.append(Float(average.x))
      image.append(Float(average.y))
      image.append(Float(average.z))
    }
    let donors = try Inpainting.patchDonors(width: columns, height: rows, image: image, hole: hole)
    let nearest = try nearestKnown(witnesses, columns: columns)

    return try Surface.linearBands(width: width, height: height, paged: true) { top, bandRows in
      let lines = (top..<(top + bandRows)).map(source.linearRow)
      return try Surface.linearPatch(width: width, height: bandRows) { x, localY in
        let pixel = lines[localY][x]
        guard pixel.a < 1 else { return pixel }
        let y = top + localY
        guard pixel.a < minimumCoverage else { return Pixel(pixel.r, pixel.g, pixel.b, 1) }
        let fallback = nearest[y / cellSide * columns + x / cellSide]
        let replacement = donors.flatMap {
          sample(source, donors: $0, x: x, y: y, step: cellSide, columns: columns, rows: rows)
        } ?? source.linearPixel(x: Int(fallback.x), y: Int(fallback.y)).rgb
        let color = pixel.rgb * pixel.a + replacement * (1 - pixel.a)
        return Pixel(max(0, color.x), max(0, color.y), max(0, color.z), 1)
      }
    }
  }

  private static func sample(_ source: Surface, donors: [SIMD2<Int32>], x: Int, y: Int,
    step: Int, columns: Int, rows: Int) -> SIMD3<Float>? {
    let gridX = (Double(x) + 0.5) / Double(step) - 0.5
    let gridY = (Double(y) + 0.5) / Double(step) - 0.5
    let baseX = Int(floor(gridX)), baseY = Int(floor(gridY))
    var weights = 0.0
    var votes = SIMD3<Double>.zero
    for cy in baseY...baseY + 1 where (0..<rows).contains(cy) {
      for cx in baseX...baseX + 1 where (0..<columns).contains(cx) {
        let donor = donors[cy * columns + cx]
        guard donor.x >= 0 else { continue }
        let sx = x + (Int(donor.x) - cx) * step, sy = y + (Int(donor.y) - cy) * step
        guard (0..<source.width).contains(sx), (0..<source.height).contains(sy) else { continue }
        let pixel = source.linearPixel(x: sx, y: sy)
        guard pixel.a >= minimumCoverage else { continue }
        let weight = (1 - abs(gridX - Double(cx))) * (1 - abs(gridY - Double(cy)))
        weights += weight
        votes += SIMD3<Double>(Double(pixel.r), Double(pixel.g), Double(pixel.b)) * weight
      }
    }
    guard weights > 0 else { return nil }
    return SIMD3(Float(votes.x / weights), Float(votes.y / weights), Float(votes.z / weights))
  }

  /// Seed thin coverage and other cells without a complete patch with the
  /// closest available fine sample. Covered pixels themselves are never replaced.
  private static func nearestKnown(_ points: [SIMD2<Int32>], columns: Int) throws -> [SIMD2<Int32>] {
    var nearest = points
    var queue = points.indices.filter { points[$0] != missing }
    var next = 0
    while next < queue.count {
      if next % 1024 == 0 { try Task.checkCancellation() }
      let i = queue[next], x = i % columns
      next += 1
      func visit(_ neighbor: Int) {
        guard nearest.indices.contains(neighbor), nearest[neighbor] == missing else { return }
        nearest[neighbor] = nearest[i]
        queue.append(neighbor)
      }
      if x > 0 { visit(i - 1) }
      if x + 1 < columns { visit(i + 1) }
      visit(i - columns)
      visit(i + columns)
    }
    return nearest
  }
}
