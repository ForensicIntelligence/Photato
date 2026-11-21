import Foundation

struct WireRidgeMap: Sendable {
  let width: Int
  let height: Int
  /// Zero leaves the source untouched. The other values identify a normal in 22.5° steps.
  let normals: [UInt8]
  let trackCount: Int

  static func unitNormal(_ code: UInt8) -> SIMD2<Double> {
    let angle = Double(code - 1) * .pi / 8
    return SIMD2(cos(angle), sin(angle))
  }

  func expanded() throws -> Self {
    var expanded = normals
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let i = y * width + x
        guard normals[i] == 0 else { continue }
        if x > 0 { expanded[i] = normals[i - 1] }
        if expanded[i] == 0 && x + 1 < width { expanded[i] = normals[i + 1] }
        if expanded[i] == 0 && y > 0 { expanded[i] = normals[i - width] }
        if expanded[i] == 0 && y + 1 < height { expanded[i] = normals[i + width] }
      }
    }
    return .init(width: width, height: height, normals: expanded, trackCount: trackCount)
  }
}

enum WireRidgeDetection {
  static let analysisSide = 1536
  private static let padding = 13

  static func detect(luma: [Float], width: Int, height: Int, reduced: Bool = false) throws -> WireRidgeMap {
    precondition((1...analysisSide).contains(width) && (1...analysisSide).contains(height))
    precondition(luma.count == width * height)
    let stride = width + 2 * padding
    let paddedHeight = height + 2 * padding
    var image = [Float](repeating: 0, count: stride * paddedHeight)
    for y in 0..<paddedHeight {
      try Task.checkCancellation()
      let row = min(height - 1, max(0, y - padding)) * width
      for x in 0..<stride { image[y * stride + x] = luma[row + min(width - 1, max(0, x - padding))] }
    }
    let narrow = try detectNormals(image: image, width: width, height: height, stride: stride,
      radii: [2, 3, 4, 6], threshold: 6.5)
    let detected = try tracks(width: width, height: height, normals: narrow, frameCrossing: false).expanded()
    guard reduced else { return detected }
    // Wide detections only supplement a continuous run across the frame. Keeping that
    // vote separate avoids joining ordinary narrow wires to a nearby roof or branch.
    let wide = try detectNormals(image: image, width: width, height: height, stride: stride,
      radii: [4, 6, 8, 10, 12], threshold: 7.5)
    let combined = try tracks(width: width, height: height, normals: wide, frameCrossing: true, retaining: detected)
    // At reduced resolution edge cells may contain a mixture of sky and wire pixels.
    return try combined.expanded()
  }

  private static func detectNormals(image: [Float], width: Int, height: Int, stride: Int,
    radii: [Double], threshold: Float) throws -> [UInt8] {
    var score = [Float](repeating: threshold, count: width * height)
    var normals = [UInt8](repeating: 0, count: score.count)
    var ridge = [Float](repeating: 0, count: image.count)
    for code in UInt8(1)...8 {
      let n = WireRidgeMap.unitNormal(code)
      let forward = SampleOffset(x: -n.y * 4, y: n.x * 4, stride: stride)
      let back = SampleOffset(x: n.y * 4, y: -n.x * 4, stride: stride)
      for radius in radii {
        let plus = SampleOffset(x: n.x * radius, y: n.y * radius, stride: stride)
        let minus = SampleOffset(x: -n.x * radius, y: -n.y * radius, stride: stride)
        try image.withUnsafeBufferPointer { source in
          try ridge.withUnsafeMutableBufferPointer { responses in
            try scan(source: source, responses: responses, width: width, height: height,
              stride: stride, plus: plus, minus: minus, threshold: threshold)
          }
        }
        let cost = 1 + Float(radius - radii[0]) * 0.09
        try ridge.withUnsafeBufferPointer { responses in
          try score.withUnsafeMutableBufferPointer { scores in
            try normals.withUnsafeMutableBufferPointer { directions in
              for y in 0..<height {
                try Task.checkCancellation()
                let row = (y + padding) * stride + padding
                for x in 0..<width {
                  let center = row + x, out = y * width + x
                  let peak = responses[center]
                  guard abs(peak) > scores[out] else { continue }
                  let polarity: Float = peak > 0 ? 1 : -1
                  let supported = min(abs(peak), polarity * forward.sample(responses, at: center),
                    polarity * back.sample(responses, at: center)) / cost
                  if supported > scores[out] { scores[out] = supported; directions[out] = code }
                }
              }
            }
          }
        }
      }
    }
    return normals
  }

  // Every sample offset is fixed for a direction and scale. Padding replicates edge pixels,
  // so interior and frame-edge wires use the same kernel without wrapping into another row.
  private struct SampleOffset {
    let offset: Int, stride: Int
    let fx: Float, fy: Float

    init(x: Double, y: Double, stride: Int) {
      let ix = Int(floor(x)), iy = Int(floor(y))
      self.offset = iy * stride + ix; self.stride = stride
      self.fx = Float(x - Double(ix)); self.fy = Float(y - Double(iy))
    }

    func sample(_ values: UnsafeBufferPointer<Float>, at center: Int) -> Float {
      let i = center + offset
      let top = values[i] * (1 - fx) + values[i + 1] * fx
      let bottom = values[i + stride] * (1 - fx) + values[i + stride + 1] * fx
      return top * (1 - fy) + bottom * fy
    }
  }

  private static func scan(source: UnsafeBufferPointer<Float>, responses: UnsafeMutableBufferPointer<Float>,
    width: Int, height: Int, stride: Int, plus: SampleOffset, minus: SampleOffset, threshold: Float) throws {
    for y in 0..<height {
      try Task.checkCancellation()
      let row = (y + padding) * stride + padding
      for x in 0..<width {
        let i = row + x, center = source[i]
        let a = plus.sample(source, at: i) - center
        let b = minus.sample(source, at: i) - center
        // A one-sided step such as a roofline has no same-sign response on both shoulders.
        let magnitude = min(abs(a), abs(b))
        if a.isFinite, b.isFinite, magnitude > threshold, (a > 0) == (b > 0) {
          let balance = min(1, 1.65 * magnitude / max(abs(a), abs(b)))
          responses[i] = (a > 0 ? 1 : -1) * magnitude * balance
        } else { responses[i] = 0 }
      }
    }
    for y in padding..<(padding + height) {
      let row = y * stride, left = responses[row + padding], right = responses[row + padding + width - 1]
      for i in 0..<padding {
        responses[row + i] = left; responses[row + padding + width + i] = right
      }
    }
    for y in 0..<padding {
      for x in 0..<stride {
        responses[y * stride + x] = responses[padding * stride + x]
        responses[(padding + height + y) * stride + x] = responses[(padding + height - 1) * stride + x]
      }
    }
  }

  private static func tracks(width: Int, height: Int, normals: [UInt8], frameCrossing: Bool,
    retaining existing: WireRidgeMap? = nil) throws -> WireRidgeMap {
    var unseen = normals
    var accepted = existing?.normals ?? [UInt8](repeating: 0, count: normals.count)
    var queue: [Int] = []
    var trackCount = existing?.trackCount ?? 0
    for start in normals.indices where unseen[start] != 0 {
      try Task.checkCancellation()
      queue.removeAll(keepingCapacity: true)
      queue.append(start); unseen[start] = 0
      var read = 0
      var shape = TrackShape(x: start % width, y: start / width)
      while read < queue.count {
        if read.isMultiple(of: 4096) { try Task.checkCancellation() }
        let i = queue[read], x = i % width, y = i / width
        read += 1; shape.include(x: x, y: y)
        for ny in max(0, y - 1)...min(height - 1, y + 1) {
          for nx in max(0, x - 1)...min(width - 1, x + 1) {
            let next = ny * width + nx
            if unseen[next] != 0 { unseen[next] = 0; queue.append(next) }
          }
        }
      }
      guard shape.isWire(inWidth: width, height: height, count: queue.count, frameCrossing: frameCrossing) else { continue }
      if !queue.contains(where: { accepted[$0] != 0 }) { trackCount += 1 }
      for index in queue where accepted[index] == 0 { accepted[index] = normals[index] }
    }
    return .init(width: width, height: height, normals: accepted, trackCount: trackCount)
  }

  private struct TrackShape {
    private var minX: Int, maxX: Int, minY: Int, maxY: Int
    private var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0

    init(x: Int, y: Int) { minX = x; maxX = x; minY = y; maxY = y }

    mutating func include(x: Int, y: Int) {
      minX = min(minX, x); maxX = max(maxX, x)
      minY = min(minY, y); maxY = max(maxY, y)
      let dx = Double(x), dy = Double(y)
      sx += dx; sy += dy; sxx += dx * dx; syy += dy * dy; sxy += dx * dy
    }

    func isWire(inWidth width: Int, height: Int, count: Int, frameCrossing: Bool) -> Bool {
      let span = max(maxX - minX + 1, maxY - minY + 1)
      let canvas = max(width, height)
      let atBorder = minX <= 2 || minY <= 2 || maxX >= width - 3 || maxY >= height - 3
      // Cable runs may exit the photo. Interior candidates need more evidence to
      // exclude window trim, twig tips, letters, and other short ridges.
      let minimum: Int
      if frameCrossing {
        guard (minX <= 2 && maxX >= width - 3) || (minY <= 2 && maxY >= height - 3) else { return false }
        minimum = max(20, canvas / 2)
      } else { minimum = atBorder ? max(12, canvas / 18) : max(20, canvas / 5) }
      guard span >= minimum, count >= minimum, count <= span * (frameCrossing ? 13 : 7) else { return false }
      let divisor = Double(count)
      let xx = sxx - sx * sx / divisor, yy = syy - sy * sy / divisor, xy = sxy - sx * sy / divisor
      let spread = hypot(xx - yy, 2 * xy)
      let elongation = frameCrossing ? 0.035 : 0.13
      return xx + yy - spread <= elongation * (xx + yy + spread)
    }
  }
}
