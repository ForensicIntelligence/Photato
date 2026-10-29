import Foundation

/// Native port of photocraft/crates/algo/src/histogram.rs. Bins describe the
/// supplied sample domain. Visible pixels count once, including fractional alpha.
public struct RGBHistogram: Equatable, Sendable {
  public private(set) var channels = Array(
    repeating: Array(repeating: UInt64(0), count: 256), count: 3)
  public private(set) var samples: UInt64 = 0
  public private(set) var transparent: UInt64 = 0
  public private(set) var invalid: UInt64 = 0
  public private(set) var underflow: [UInt64] = [0, 0, 0]
  public private(set) var overflow: [UInt64] = [0, 0, 0]
  public private(set) var shadows: [UInt64] = [0, 0, 0]
  public private(set) var highlights: [UInt64] = [0, 0, 0]
  public init() {}
  public mutating func add(_ pixel: Pixel) {
    guard pixel.a.isFinite else {
      invalid += 1
      return
    }
    guard pixel.a > 0 else {
      transparent += 1
      return
    }
    guard pixel.isFinite else {
      invalid += 1
      return
    }
    samples += 1
    for c in 0..<3 {
      let value = pixel.rgb[c]
      if value <= 0 { shadows[c] += 1 }
      if value >= 1 { highlights[c] += 1 }
      if value < 0 { underflow[c] += 1 }
      if value > 1 { overflow[c] += 1 }
      channels[c][Int(unit(value) * 255 + 0.5)] += 1
    }
  }
  public func bins(_ channel: LevelsAdjustment.Channel) -> [UInt64] {
    switch channel {
    case .red: channels[0]
    case .green: channels[1]
    case .blue: channels[2]
    case .rgb: (0..<256).map { channels[0][$0] + channels[1][$0] + channels[2][$0] }
    }
  }
  public static func analyze(
    _ surface: Surface, depth: PixelDepth,
    luminance: Bool = false,
    include: (Int, Int) -> Bool = { _, _ in true }
  ) throws -> Self {
    var result = Self()
    for y in 0..<surface.height {
      try Task.checkCancellation()
      for x in 0..<surface.width where include(x, y) {
        let p = surface.pixel(x: x, y: y)
        let sample = depth == .f32 ? SRGBTransfer.linear(p) : p
        if luminance {
          var gray = TonalStepsTransfer.luminance(sample)
          if depth == .u8 { gray = (gray * 255).rounded(.toNearestOrEven) / 255 }
          result.add(Pixel(gray, gray, gray, sample.a))
        } else {
          result.add(sample)
        }
      }
    }
    return result
  }
  public static func pixelLayer(_ id: UUID, in document: CraftDocument, luminance: Bool = false)
    throws -> Self
  {
    try document.validate()
    guard let layer = document.layers.first(where: { $0.id == id }),
      case .raster(let surface) = layer.content
    else {
      throw CraftError.invalid("Select a pixel layer to analyze its tones.")
    }
    let matrix = layer.coordinateTransform
    return try analyze(surface, depth: document.depth, luminance: luminance) { x, y in
      let p = matrix.point(Double(x) + 0.5, Double(y) + 0.5)
      let dx = Int(floor(p.x))
      let dy = Int(floor(p.y))
      return dx >= 0 && dy >= 0 && dx < document.width && dy < document.height
        && document.selectionCoverage(x: dx, y: dy) > 0
    }
  }
}

public enum AutoCorrection: String, CaseIterable, Sendable, Codable {
  case tone = "Auto Tone"
  case contrast = "Auto Contrast"
  case color = "Auto Color"
  /// Port of edit_cmds.rs auto_adjust, clip_points and median. Auto Color's
  /// median neutralization is the source approximation, not Photoshop's algorithm.
  public func levels(
    from histogram: RGBHistogram, shadowClip: Double = 0.1,
    highlightClip: Double = 0.1
  ) throws -> LevelsAdjustment {
    guard shadowClip.isFinite, highlightClip.isFinite,
      (0...9.99).contains(shadowClip), (0...9.99).contains(highlightClip)
    else {
      throw CraftError.invalid("Clipping percentages must be between 0 and 9.99.")
    }
    guard histogram.samples > 0 else { return .init() }
    func points(_ h: [UInt64]) -> LevelsChannel {
      let total = h.reduce(0, +)
      if total == 0 { return .init() }
      let lowLimit = UInt64(Double(total) * shadowClip / 100)
      let highLimit = UInt64(Double(total) * highlightClip / 100)
      var acc: UInt64 = 0
      var lo = 0
      var hi = 255
      while lo < 254 && acc + h[lo] <= lowLimit {
        acc += h[lo]
        lo += 1
      }
      acc = 0
      while hi > lo + 1 && acc + h[hi] <= highLimit {
        acc += h[hi]
        hi -= 1
      }
      // ALV's legal endpoint range is 0...253 / 2...255.
      return .init(inputBlack: min(253, lo), inputWhite: max(2, hi))
    }
    if self == .contrast {
      let channel = points(histogram.bins(.rgb))
      return .init(red: channel, green: channel, blue: channel)
    }
    var channels = histogram.channels.map(points)
    if self == .color {
      let medians: [Float] = histogram.channels.map { h in
        let total = h.reduce(0, +)
        var count: UInt64 = 0
        for i in 0..<256 {
          count += h[i]
          if count * 2 >= total { return Float(i) / 255 }
        }
        return 0.5
      }
      let target = medians.reduce(0, +) / 3
      for i in 0..<3 {
        let low = Float(channels[i].inputBlack) / 255
        let range = max(1e-3, Float(channels[i].inputWhite) / 255 - low)
        let value = min(0.98, max(0.02, (medians[i] - low) / range))
        let desired = min(0.98, max(0.02, (target - low) / range))
        channels[i].gamma = min(9.99, max(0.1, log(value) / log(desired)))
      }
    }
    return .init(red: channels[0], green: channels[1], blue: channels[2])
  }
}
