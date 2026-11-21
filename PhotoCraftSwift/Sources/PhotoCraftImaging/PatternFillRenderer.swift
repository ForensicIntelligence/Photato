import Foundation
import PhotoCraftCore

struct PatternFillSampler {
  private enum Sampling {
    case continuous(PatternSampler)
    case legacy(LegacyPatternGrid)
  }
  private let sampling: Sampling
  private let inverse: Transform2D
  init(_ fill: PatternFill, in document: CraftDocument, legacyShapeGrid: Bool = false) throws {
    guard let pattern = document.pattern(fill.patternID) else {
      throw CraftError.invalid("Missing embedded pattern.")
    }
    if legacyShapeGrid, let grid = try LegacyPatternGrid(pattern, placement: fill.placement) {
      sampling = .legacy(grid)
    } else {
      sampling = .continuous(try PatternSampler(pattern, placement: fill.placement))
    }
    inverse = try (fill.geometry ?? .identity).inverted()
  }
  func sample(x: Double, y: Double) -> Pixel {
    let p = inverse.point(x, y)
    switch sampling {
    case .continuous(let sampler): return sampler.sample(x: p.x, y: p.y)
    case .legacy(let grid): return grid.sample(x: Int(floor(p.x)), y: Int(floor(p.y)))
    }
  }
}

/// A pixel-aligned, opaque RGB8 Photoshop shape pattern. Minification rounds
/// each half-size tile before the next pass. Enlargement interpolates from
/// source texel corners instead of centering the enlarged samples.
private struct LegacyPatternGrid {
  let tile: Surface
  let scale: Double
  let phaseX: Double
  let phaseY: Double

  init?(_ pattern: RasterPattern, placement: PatternPlacement) throws {
    try placement.validate()
    guard placement.angle == 0, placement.scale != 100, pattern.surface.depth == .u8 else { return nil }
    var scale = Double(placement.scale) / 100
    var reduction = 1
    while scale <= 0.5 {
      reduction *= 2
      scale *= 2
    }
    guard pattern.surface.width % reduction == 0,
          pattern.surface.height % reduction == 0 else { return nil }
    try pattern.validate()
    guard try pattern.surface.isOpaque() else { return nil }
    var tile = pattern.surface
    for _ in 0..<reduction.trailingZeroBitCount {
      var half = try Surface(width: tile.width / 2, height: tile.height / 2, fill: tile.defaultPixel)
      for y in 0..<half.height {
        try Task.checkCancellation()
        for x in 0..<half.width {
          half.setPixel(x: x, y: y, Self.average(
            tile.pixel(x: 2 * x, y: 2 * y), tile.pixel(x: 2 * x + 1, y: 2 * y),
            tile.pixel(x: 2 * x, y: 2 * y + 1), tile.pixel(x: 2 * x + 1, y: 2 * y + 1)))
        }
      }
      tile = half
    }
    self.tile = tile
    self.scale = scale
    phaseX = Double(placement.phaseX)
    phaseY = Double(placement.phaseY)
  }

  private static func wrapped(_ index: Int, period: Int) -> Int {
    let remainder = index % period
    return remainder < 0 ? remainder + period : remainder
  }

  private static func bytes(_ pixel: Pixel) -> SIMD3<Int32> {
    SIMD3<Int32>((pixel.rgb * 255).rounded(.toNearestOrAwayFromZero))
  }

  private static func pixel(_ bytes: SIMD3<Int32>) -> Pixel {
    let result = SIMD3<Float>(bytes) / 255
    return Pixel(result.x, result.y, result.z)
  }

  private static func average(_ a: Pixel, _ b: Pixel, _ c: Pixel, _ d: Pixel) -> Pixel {
    let sum = bytes(a) &+ bytes(b) &+ bytes(c) &+ bytes(d)
    return pixel((sum &+ 2) &>> 2)
  }

  func sample(x: Int, y: Int) -> Pixel {
    // Truncate the source position to 8 fractional bits before interpolation.
    // Shifting the signed position yields the preceding texel on either side of phase.
    let u = Int(floor((Double(x) - phaseX) / scale * 256))
    let v = Int(floor((Double(y) - phaseY) / scale * 256))
    let left = Self.wrapped(u >> 8, period: tile.width)
    let top = Self.wrapped(v >> 8, period: tile.height)
    let fx = Int32(u & 255)
    let fy = Int32(v & 255)
    let first = tile.pixel(x: left, y: top)
    if fx == 0 && fy == 0 { return first }
    let right = (left + 1) % tile.width
    let bottom = (top + 1) % tile.height
    let upper = (Self.bytes(first) &* (256 - fx)) &+ (Self.bytes(tile.pixel(x: right, y: top)) &* fx)
    let lower = (Self.bytes(tile.pixel(x: left, y: bottom)) &* (256 - fx))
      &+ (Self.bytes(tile.pixel(x: right, y: bottom)) &* fx)
    let sum = (upper &* (256 - fy)) &+ (lower &* fy)
    return Self.pixel((sum &+ 32768) &>> 16)
  }
}

extension Renderer {
  /// One stored content pixel, for layer picking without allocating a canvas.
  public static func patternPixel(_ fill: PatternFill, in document: CraftDocument, x: Int, y: Int)
    throws -> Pixel
  {
    guard x >= 0, y >= 0, x < document.width, y < document.height else { return .clear }
    return try PatternFillSampler(fill, in: document).sample(x: Double(x) + 0.5, y: Double(y) + 0.5)
      .quantized(.f32)
  }
  static func patternSurface(_ fill: PatternFill, in document: CraftDocument) throws -> Surface {
    let sampler = try PatternFillSampler(fill, in: document)
    var surface = try Surface(width: document.width, height: document.height, depth: .f32)
    for y in 0..<document.height {
      try Task.checkCancellation()
      for x in 0..<document.width {
        surface.setPixel(x: x, y: y, sampler.sample(x: Double(x) + 0.5, y: Double(y) + 0.5))
      }
    }
    return surface
  }
}
