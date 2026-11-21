import Foundation
import PhotoCraftCore

/// Detect compact dust-like contrast on locally smooth backgrounds. Object and
/// foliage segmentation are separate, so a strong one-sided edge is not dust.
enum DistractionDustDetection {
  private static let rings = [2, 3, 4, 6]

  static func detect(_ image: Surface, protected: [IntRect]) throws -> RemoveDistractionMark? {
    let width = image.width, height = image.height
    let margin = 8
    guard width > 2 * margin, height > 2 * margin else { return nil }
    let rgba = try image.rgbaData(depth: .u8)
    var luma = [Float](repeating: .nan, count: width * height)
    rgba.withUnsafeBytes { raw in
      let bytes = raw.bindMemory(to: UInt8.self)
      for i in luma.indices where bytes[i * 4 + 3] >= 224 {
        luma[i] = Float(bytes[i * 4]) * 0.299 + Float(bytes[i * 4 + 1]) * 0.587 + Float(bytes[i * 4 + 2]) * 0.114
      }
    }
    var coverage = Array(repeating: UInt8(0), count: luma.count)
    var accepted: [(x: Int, y: Int, radius: Int)] = []
    for y in margin..<(height - margin) {
      try Task.checkCancellation()
      for x in margin..<(width - margin) {
        let i = y * width + x, center = luma[i]
        guard center.isFinite, coverage[i] == 0,
          abs(luma[i - 2] - center) >= 30 || abs(luma[i + 2] - center) >= 30 else { continue }
        if protected.contains(where: { $0.contains(x, y) }) { continue }
        guard let spot = spotAround(i, center: center, width: width, luma: luma) else { continue }
        if accepted.contains(where: { abs($0.x - x) <= $0.radius + spot.radius && abs($0.y - y) <= $0.radius + spot.radius }) { continue }
        let radius = spot.radius - 1
        for py in (y - radius)...(y + radius) {
          for px in (x - radius)...(x + radius) {
            guard (px - x) * (px - x) + (py - y) * (py - y) <= radius * radius,
              !protected.contains(where: { $0.contains(px, py) }) else { continue }
            let k = py * width + px
            if luma[k].isFinite, (luma[k] - spot.background) * spot.sign >= 13 { coverage[k] = 255 }
          }
        }
        accepted.append((x, y, radius))
        if accepted.count == 128 { break }
      }
      if accepted.count == 128 { break }
    }
    guard !accepted.isEmpty else { return nil }
    let mask = try SelectionMask(width: width, height: height, bytes: coverage)
    return .init(category: .spotsAndDust, mask: mask, count: accepted.count)
  }

  private static func spotAround(_ i: Int, center: Float, width: Int, luma: [Float])
    -> (radius: Int, background: Float, sign: Float)? {
    for r in rings {
      guard let inner = surround(i, radius: r, width: width, luma: luma), inner.range <= 11 else { continue }
      let background = inner.average, contrast = center - background
      // Require a second smooth surround. A tiny gap inside a textured branch
      // or gravel patch can otherwise look like an isolated spot at one scale.
      guard abs(contrast) >= 39,
        let outer = surround(i, radius: r + 2, width: width, luma: luma), outer.range <= 16,
        abs(outer.average - background) <= 8 else { continue }
      return (r, background, contrast > 0 ? 1 : -1)
    }
    return nil
  }

  private static func surround(_ i: Int, radius: Int, width: Int, luma: [Float])
    -> (average: Float, range: Float)? {
    let diag = Int((Double(radius) * 0.707).rounded())
    let offsets = [radius, -radius, radius * width, -radius * width, diag * width + diag, diag * width - diag,
      -diag * width + diag, -diag * width - diag]
    var low = Float.infinity, high = -Float.infinity, sum: Float = 0
    for offset in offsets {
      let sample = luma[i + offset]
      guard sample.isFinite else { return nil }
      low = min(low, sample); high = max(high, sample); sum += sample
    }
    return (sum / 8, high - low)
  }
}
