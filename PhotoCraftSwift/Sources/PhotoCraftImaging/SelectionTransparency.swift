import Foundation
import PhotoCraftCore

enum SelectionTransparency {
  typealias RGB = SIMD3<Double>

  struct Plane {
    let origin: RGB
    let xSlope: RGB
    let ySlope: RGB
    let width: Double
    let height: Double

    func sample(x: Int, y: Int) -> RGB {
      origin + xSlope * (Double(x) / width) + ySlope * (Double(y) / height)
    }
  }

  enum Background {
    case fitted(Plane)
    case reference(Surface, linear: Bool)

    func sample(x: Int, y: Int) -> RGB? {
      switch self {
      case .fitted(let plane): return plane.sample(x: x, y: y)
      case .reference(let image, let linear):
        let pixel = Self.pixel(image, x: x, y: y, linear: linear)
        return pixel.a >= 0.999 ? RGB(pixel.rgb) : nil
      }
    }

    static func pixel(_ surface: Surface, x: Int, y: Int, linear: Bool) -> Pixel {
      linear ? surface.linearPixel(x: x, y: y) : surface.pixel(x: x, y: y)
    }
  }

  struct Sample {
    let x: Int
    let y: Int
    let color: RGB
  }

  static func recover(_ mask: SelectionMask, guide: Surface, plate: Surface?, linear: Bool,
    protected: [UInt8]) throws -> (SelectionMask, Background?) {
    guard let bounds = mask.bounds else { return (mask, nil) }
    let margin = max(24, min(192, min(bounds.width, bounds.height) / 2))
    let region = IntRect(x: bounds.x - margin, y: bounds.y - margin, width: bounds.width + 2 * margin,
      height: bounds.height + 2 * margin).clipped(toWidth: mask.width, height: mask.height)
    let step = max(1, Int(ceil(sqrt(Double(region.width * region.height) / 40_000))))
    var exterior: [Sample] = [], interior: [Sample] = []
    for y in stride(from: region.y, to: region.y + region.height, by: step) {
      try Task.checkCancellation()
      for x in stride(from: region.x, to: region.x + region.width, by: step) {
        let p = Background.pixel(guide, x: x, y: y, linear: linear)
        guard p.a >= 0.999 else { continue }
        let weight = mask.byte(at: y * mask.width + x)
        let sample = Sample(x: x, y: y, color: RGB(p.rgb))
        if weight == 0 { exterior.append(sample) }
        if weight >= 128 { interior.append(sample) }
      }
    }
    // Pixels with stored alpha already carry their own transparency.
    guard !interior.isEmpty else { return (mask, nil) }
    let background: Background
    if let plate { background = .reference(plate, linear: linear) }
    else { background = .fitted(try fit(exterior, width: mask.width, height: mask.height)) }

    var squaredError = 0.0
    for sample in exterior {
      guard let backing = background.sample(x: sample.x, y: sample.y) else {
        throw CraftError.invalid("The background layer must cover the image behind the selection.")
      }
      squaredError += lengthSquared(sample.color - backing)
    }
    if sqrt(squaredError / Double(max(1, exterior.count))) > 0.04 {
      throw CraftError.invalid(plate == nil
        ? "Choose an aligned background layer for this textured or uneven background."
        : "The background layer differs from the exposed background. Align it and match its exposure.")
    }

    let measured = try interior.map { sample -> (color: RGB, distance: Double) in
      guard let backing = background.sample(x: sample.x, y: sample.y) else {
        throw CraftError.invalid("The background layer must cover the image behind the selection.")
      }
      return (sample.color, lengthSquared(sample.color - backing))
    }.sorted { $0.distance > $1.distance }
    guard let strongest = measured.first, strongest.distance >= 0.0004 else {
      throw CraftError.invalid("The subject and background colors are too similar to recover transparency.")
    }
    let highlights = measured.prefix(max(1, (measured.count + 49) / 50))
    let foreground = RGB((0..<3).map { channel in highlights.map { $0.color[channel] }.sorted()[highlights.count / 2] })
    var bytes = try mask.bytes
    for y in bounds.y..<(bounds.y + bounds.height) {
      try Task.checkCancellation()
      for x in bounds.x..<(bounds.x + bounds.width) {
        let i = y * mask.width + x
        let original = bytes[i]
        guard original > 0, protected[i] < 255 else { continue }
        let observed = Background.pixel(guide, x: x, y: y, linear: linear)
        guard observed.a >= 0.999 else { continue }
        guard let backing = background.sample(x: x, y: y) else {
          throw CraftError.invalid("The background layer must cover the image behind the selection.")
        }
        let difference = RGB(observed.rgb) - backing
        let axis = foreground - backing
        let projected = dot(difference, axis) / max(0.000_001, lengthSquared(axis))
        let floor = linear ? 0 : minimumCoverage(difference: difference, background: backing)
        let recovered = UInt8((max(0, min(1, max(projected, floor))) * 255).rounded(.up))
        let coverage = min(original, recovered), keep = Int(protected[i])
        bytes[i] = UInt8((Int(coverage) * (255 - keep) + Int(original) * keep + 127) / 255)
      }
    }
    if let plate {
      try PlateTransparency.refine(&bytes, inside: mask, bounds: bounds, guide: guide, plate: plate,
        linear: linear, protected: protected)
    }
    return (try SelectionMask(width: mask.width, height: mask.height, bytes: bytes), background)
  }

  private static func fit(_ samples: [Sample], width: Int, height: Int) throws -> Plane {
    guard samples.count >= 16 else {
      throw CraftError.invalid("Leave some unselected background around the subject or choose a background layer.")
    }
    let w = Double(width), h = Double(height), count = Double(samples.count)
    var sumX = 0.0, sumY = 0.0, xx = 0.0, yy = 0.0, xy = 0.0
    var sum = RGB.zero, xc = RGB.zero, yc = RGB.zero
    for sample in samples {
      let x = Double(sample.x) / w, y = Double(sample.y) / h
      sumX += x; sumY += y
      xx += x * x; yy += y * y; xy += x * y
      sum += sample.color; xc += sample.color * x; yc += sample.color * y
    }
    let meanX = sumX / count, meanY = sumY / count, mean = sum / count
    xx -= sumX * meanX; yy -= sumY * meanY; xy -= sumX * meanY
    xc -= sum * meanX; yc -= sum * meanY
    let determinant = xx * yy - xy * xy
    guard determinant > 1e-9 else {
      throw CraftError.invalid("Include exposed background around more than one side of the subject.")
    }
    let xSlope = (xc * yy - yc * xy) / determinant
    let ySlope = (yc * xx - xc * xy) / determinant
    return Plane(origin: mean - xSlope * meanX - ySlope * meanY, xSlope: xSlope, ySlope: ySlope, width: w, height: h)
  }

  private static func dot(_ a: RGB, _ b: RGB) -> Double {
    let v = a * b
    return v.x + v.y + v.z
  }

  private static func lengthSquared(_ v: RGB) -> Double { dot(v, v) }

  static func minimumCoverage(difference: RGB, background: RGB) -> Double {
    var result = 0.0
    for channel in 0..<3 {
      let delta = difference[channel], backing = background[channel]
      let headroom = delta < 0 ? backing : 1 - backing
      result = max(result, abs(delta) / max(0.000_1, headroom))
    }
    return result
  }

  static func corrected(_ source: Surface, on layer: Layer, mask: SelectionMask,
    background: Background, linear: Bool, amount: Double) throws -> Surface {
    var result = source
    let strength = Float(amount / 100)
    for y in 0..<source.height {
      try Task.checkCancellation()
      for x in 0..<source.width {
        let point = layer.coordinateTransform.point(Double(x) + 0.5, Double(y) + 0.5)
        let px = Int(floor(point.x)), py = Int(floor(point.y))
        guard px >= 0, px < mask.width, py >= 0, py < mask.height else { continue }
        let a = Float(mask.byte(at: py * mask.width + px)) / 255
        let sample = Background.pixel(source, x: x, y: y, linear: linear)
        guard a > 0, a < 1, sample.a >= 0.999, let backing = background.sample(x: px, y: py) else { continue }
        let value = SIMD3<Float>(backing)
        let corrected = sample.rgb + (sample.rgb - value) * ((1 - a) / a) * strength
        let output = Pixel(corrected.x, corrected.y, corrected.z, sample.a)
        if linear { result.setLinearPixel(x: x, y: y, output) }
        else { result.setPixel(x: x, y: y, output) }
      }
    }
    return result
  }
}
