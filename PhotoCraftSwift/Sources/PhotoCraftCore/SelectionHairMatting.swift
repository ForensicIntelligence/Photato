import Foundation
import simd

/// Builds an editable coverage estimate for strands near an existing selection.
public enum SelectionHairMatting {
  private static let band = 31
  private static let reach = 65
  private static let candidateCount = 5
  private static let connectedCoverage: UInt8 = 40

  private struct Offset {
    let x: Int
    let y: Int
    let distance: Float
  }

  private struct Sample {
    let color: SIMD3<Float>
    let distance: Float
  }

  private static let offsets: [Offset] = {
    // Fixed directions keep the sample positions and tie order reproducible.
    let directions = [(1000, 0), (966, 259), (866, 500), (707, 707), (500, 866), (259, 966),
                      (0, 1000), (-259, 966), (-500, 866), (-707, 707), (-866, 500), (-966, 259),
                      (-1000, 0), (-966, -259), (-866, -500), (-707, -707), (-500, -866), (-259, -966),
                      (0, -1000), (259, -966), (500, -866), (707, -707), (866, -500), (966, -259)]
    var seen = Set<SIMD2<Int>>()
    for radius in [1, 2, 3, 5, 8, 13, 19, 27, 37, 50, reach] {
      for (x, y) in directions {
        let dx = Int((Double(x * radius) / 1000).rounded(.toNearestOrEven))
        let dy = Int((Double(y * radius) / 1000).rounded(.toNearestOrEven))
        seen.insert(.init(dx, dy))
      }
    }
    return seen.sorted {
      let a = $0.x * $0.x + $0.y * $0.y, b = $1.x * $1.x + $1.y * $1.y
      return a == b ? ($0.y, $0.x) < ($1.y, $1.x) : a < b
    }.map { .init(x: $0.x, y: $0.y, distance: hypot(Float($0.x), Float($0.y))) }
  }()

  public static func refine(_ mask: SelectionMask, guide: Surface) throws -> SelectionMask {
    try SelectionMatting.checkSize(mask.width, mask.height)
    guard mask.width == guide.width, mask.height == guide.height else {
      throw CraftError.invalid("Hair refinement canvas sizes differ.")
    }
    guard let selected = mask.bounds else {
      throw CraftError.invalid("Select a subject before refining hair.")
    }
    let margin = band + reach
    let left = max(0, selected.x - margin), top = max(0, selected.y - margin)
    let right = min(mask.width, selected.x + selected.width + margin)
    let bottom = min(mask.height, selected.y + selected.height + margin)
    let width = right - left, height = bottom - top

    var output = try mask.bytes
    var selection: [UInt8] = []
    selection.reserveCapacity(width * height)
    for y in top..<bottom {
      let start = y * mask.width + left
      selection.append(contentsOf: output[start..<(start + width)])
    }
    let seeds: [Float] = selection.map { $0 >= 128 ? 1 : 0 }
    guard seeds.contains(1), seeds.contains(0) else { return mask }
    let exterior = try MattingFilters.extreme(seeds, width, height, band, maximum: true)
    guard exterior.contains(0) else { return mask }
    let interior = try MattingFilters.extreme(seeds, width, height, 2, maximum: false)

    var samples: [SIMD4<Float>] = []
    samples.reserveCapacity(width * height)
    for y in top..<bottom {
      try Task.checkCancellation()
      for x in left..<right {
        let p = guide.pixel(x: x, y: y)
        samples.append(.init(p.r, p.g, p.b, p.isFinite ? p.a : 0))
      }
    }

    var estimated = selection
    var foreground: [Sample] = [], background: [Sample] = []
    foreground.reserveCapacity(candidateCount)
    background.reserveCapacity(candidateCount)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let index = y * width + x
        guard interior[index] == 0, exterior[index] > 0, samples[index].w >= 0.99 else { continue }
        let pixel = SIMD3(samples[index].x, samples[index].y, samples[index].z)
        foreground.removeAll(keepingCapacity: true)
        background.removeAll(keepingCapacity: true)
        var backingError = Float.infinity
        var nearbyError = Float.infinity
        for offset in offsets {
          let sx = x + offset.x, sy = y + offset.y
          guard (0..<width).contains(sx), (0..<height).contains(sy) else { continue }
          let neighbor = sy * width + sx
          guard samples[neighbor].w >= 0.99 else { continue }
          let color = SIMD3(samples[neighbor].x, samples[neighbor].y, samples[neighbor].z)
          if exterior[neighbor] == 0 {
            let error = simd_length_squared(pixel - color)
            backingError = min(backingError, error)
            if background.count < candidateCount {
              background.append(.init(color: color, distance: offset.distance))
              nearbyError = min(nearbyError, error)
            }
          } else if interior[neighbor] > 0, foreground.count < candidateCount {
            foreground.append(.init(color: color, distance: offset.distance))
          }
        }
        if let alpha = coverage(pixel, prior: Float(selection[index]) / 255, foreground: foreground,
                                background: background, nearbyError: nearbyError, backingError: backingError) {
          estimated[index] = UInt8((alpha * 255).rounded())
        }
      }
    }
    try removeDetachedCoverage(&estimated, selection: selection, width: width, height: height)
    for y in 0..<height {
      let start = (top + y) * mask.width + left
      let source = y * width
      output.replaceSubrange(start..<(start + width), with: estimated[source..<(source + width)])
    }
    return try SelectionMask(width: mask.width, height: mask.height, bytes: output)
  }

  private static func coverage(_ pixel: SIMD3<Float>, prior: Float, foreground: [Sample],
                               background: [Sample], nearbyError: Float, backingError: Float) -> Float? {
    let foregroundPenalty = 0.045 * exp(-nearbyError / 0.014) * (1 - prior)
    var bestCost = Float.infinity, estimate: Float?
    for inner in foreground {
      for outer in background {
        let difference = inner.color - outer.color, observed = pixel - outer.color
        let contrast = simd_length_squared(difference)
        guard contrast >= 0.000001 else { continue }
        let value = min(1, max(0, simd_dot(difference, observed) / contrast))
        let residual = simd_length_squared(observed - difference * value)
        let travel = inner.distance * value + outer.distance * (1 - value)
        let cost = residual + 0.00007 * travel + 0.0002 / max(0.03, contrast) + foregroundPenalty * value * value
        if cost < bestCost {
          bestCost = cost
          estimate = value
        }
      }
    }
    guard let estimate else { return nil }
    let unreliable = exp(-nearbyError / 0.008) * (1 - prior)
    let suppressed = max(0, estimate - unreliable * min(estimate, 0.15) * 0.85)
    return suppressed * (1 - exp(-backingError / 0.0006) * (1 - prior))
  }

  private static func removeDetachedCoverage(_ estimate: inout [UInt8], selection: [UInt8],
                                             width: Int, height: Int) throws {
    var connected = selection.map { $0 >= 128 }
    var pending: [Int] = []
    for index in estimate.indices where !connected[index] && estimate[index] >= connectedCoverage {
      if index.isMultiple(of: 4096) { try Task.checkCancellation() }
      if touchesSelection(index, connected: connected, width: width, height: height) {
        connected[index] = true
        pending.append(index)
      }
    }
    while let index = pending.popLast() {
      if index.isMultiple(of: 256) { try Task.checkCancellation() }
      let x = index % width, y = index / width
      for row in max(0, y - 1)...min(height - 1, y + 1) {
        for col in max(0, x - 1)...min(width - 1, x + 1) {
          let next = row * width + col
          if !connected[next], estimate[next] >= connectedCoverage {
            connected[next] = true
            pending.append(next)
          }
        }
      }
    }
    // Retain a soft fringe around the connected strands.
    for index in estimate.indices where estimate[index] > selection[index] && !connected[index] {
      if !touchesSelection(index, connected: connected, width: width, height: height) {
        estimate[index] = selection[index]
      }
    }
  }

  private static func touchesSelection(_ index: Int, connected: [Bool], width: Int, height: Int) -> Bool {
    let x = index % width, y = index / width
    for row in max(0, y - 1)...min(height - 1, y + 1) {
      for col in max(0, x - 1)...min(width - 1, x + 1) where connected[row * width + col] { return true }
    }
    return false
  }
}
