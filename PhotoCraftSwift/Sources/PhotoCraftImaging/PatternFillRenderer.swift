import Foundation
import PhotoCraftCore

struct PatternFillSampler {
  private enum Sampling {
    case continuous(PatternSampler)
    case legacy(LegacyPatternGrid)
  }
  private let sampling: Sampling
  private let inverse: Transform2D
  init(_ fill: PatternFill, in document: CraftDocument, legacyShapeGrid: Bool = false,
       origin: PathPoint = PathPoint(0, 0)) throws {
    guard let pattern = document.pattern(fill.patternID) else {
      throw CraftError.invalid("Missing embedded pattern.")
    }
    if legacyShapeGrid, let grid = try LegacyPatternGrid(pattern, placement: fill.placement) {
      sampling = .legacy(grid)
    } else {
      sampling = .continuous(try PatternSampler(pattern, placement: fill.placement))
    }
    inverse = try (Transform2D.translation(origin.x, origin.y) * (fill.geometry ?? .identity)).inverted()
  }

  static func overlay(_ fill: PatternFill, style: LayerStyle, layer: Layer, in document: CraftDocument) throws -> Self {
    let origin = fill.linked ? style.patternReference(in: layer) : PathPoint(0, 0)
    let aligned = fill.geometry == nil && origin.x.rounded() == origin.x && origin.y.rounded() == origin.y
    return try Self(fill, in: document, legacyShapeGrid: aligned && document.colorMode == .rgb && document.depth == .u8,
                    origin: origin)
  }

  static func overlayOpacity(_ effect: LayerEffect, in document: CraftDocument) -> Float {
    guard effect.kind == .patternOverlay, effect.advanced == nil, effect.blendMode == .normal,
          document.colorMode == .rgb, document.depth == .u8 else { return effect.opacity }
    return PixelDepth.u8.quantize(effect.opacity)
  }

  /// The continuous sampler uses a power-of-two scale so multiplication by
  /// its reciprocal preserves every coordinate bit. A quarter turn can also
  /// repeat if the continuous sampler selects identical Float32 weights in
  /// every period. The axis-aligned legacy byte sampler has its own grid.
  static func exactAxisPeriod(_ fill: PatternFill, style: LayerStyle, layer: Layer,
    in document: CraftDocument) throws -> (width: Int, height: Int)? {
    guard fill.geometry == nil,
      let tile = document.pattern(fill.patternID)?.surface else { return nil }
    let scale = Double(fill.placement.scale) / 100
    guard let numerator = Int(exactly: scale * 256), numerator > 0 else { return nil }
    let origin = fill.linked ? style.patternReference(in: layer) : PathPoint(0, 0)
    let phase = [origin.x, origin.y, Double(fill.placement.phaseX), Double(fill.placement.phaseY)]
    guard phase.allSatisfy({ abs($0) <= 1_000_000 && ($0 * 256).rounded() == $0 * 256 }) else { return nil }
    let angle = fill.placement.angle
    if numerator.nonzeroBitCount != 1 {
      guard angle == 0, document.colorMode == .rgb, document.depth == .u8,
        origin.x.rounded() == origin.x, origin.y.rounded() == origin.y,
        try LegacyPatternGrid.admits(tile, scale: scale) else { return nil }
    }
    func period(_ length: Int) -> Int {
      let scaled = length * numerator
      return scaled >> min(8, scaled.trailingZeroBitCount)
    }
    if angle == 0 { return (period(tile.width), period(tile.height)) }
    guard let swapsAxes = exactQuarterTurn(fill.placement, origin: origin,
      width: document.width, height: document.height) else { return nil }
    return swapsAxes ? (period(tile.height), period(tile.width)) : (period(tile.width), period(tile.height))
  }

  private static func exactQuarterTurn(_ placement: PatternPlacement, origin: PathPoint,
    width: Int, height: Int) -> Bool? {
    let angle = placement.angle
    guard let degrees = Int(exactly: angle), degrees.isMultiple(of: 90) else { return nil }
    let turn = (degrees / 90 % 4 + 4) % 4
    let swapsAxes = !turn.isMultiple(of: 2)
    let sign = turn < 2 ? 1.0 : -1.0
    let (cosine, sine) = PatternSampler.rotationCoefficients(angle)
    let primary = swapsAxes ? sine : cosine
    let secondary = swapsAxes ? cosine : sine
    guard primary == sign else { return nil }
    if secondary == 0 { return swapsAxes }

    let x = 0.5 - origin.x - Double(placement.phaseX)
    let y = 0.5 - origin.y - Double(placement.phaseY)
    let lastX = x + Double(width - 1), lastY = y + Double(height - 1)
    let xExtent = max(abs(x), abs(lastX)), yExtent = max(abs(y), abs(lastY))
    let reciprocal = 1 / Double(placement.scale / 100)
    let cycle = max(1, Int(1 / reciprocal))

    // The ideal coordinate is exact with the dyadic scale and phase admitted
    // above. Bound the unwanted cross-axis term and leave room for Double
    // rounding in the sum, half-pixel subtraction and fractional extraction.
    func stableWeights(start: Double, direction: Double, extent: Double, crossExtent: Double) -> Bool {
      let cross = crossExtent * abs(secondary)
      let maxCoordinate = (extent + cross + 1) * reciprocal + 1
      let error = cross * reciprocal + 8 * maxCoordinate.ulp
      return (0..<cycle).allSatisfy { offset in
        let coordinate = (start + Double(offset)) * direction * reciprocal - 0.5
        let fraction = coordinate - floor(coordinate)
        let weight = Float(fraction)
        let lower = (Double(weight.nextDown) + Double(weight)) * 0.5
        let upper = (Double(weight.nextUp) + Double(weight)) * 0.5
        return fraction - error > max(0, lower) && fraction + error < min(1, upper)
      }
    }
    let u = swapsAxes ? stableWeights(start: y, direction: -sign, extent: yExtent, crossExtent: xExtent)
      : stableWeights(start: x, direction: sign, extent: xExtent, crossExtent: yExtent)
    let v = swapsAxes ? stableWeights(start: x, direction: sign, extent: xExtent, crossExtent: yExtent)
      : stableWeights(start: y, direction: sign, extent: yExtent, crossExtent: xExtent)
    return u && v ? swapsAxes : nil
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

  static func reduction(for scale: Double) -> Int {
    var scale = scale
    var reduction = 1
    while scale <= 0.5 {
      reduction *= 2
      scale *= 2
    }
    return reduction
  }

  static func admits(_ tile: Surface, scale: Double) throws -> Bool {
    let factor = reduction(for: scale)
    guard scale != 1, tile.depth == .u8, tile.width % factor == 0, tile.height % factor == 0 else { return false }
    return try tile.isOpaque()
  }

  init?(_ pattern: RasterPattern, placement: PatternPlacement) throws {
    try placement.validate()
    guard placement.angle == 0, placement.scale != 100, pattern.surface.depth == .u8 else { return nil }
    let scale = Double(placement.scale) / 100
    try pattern.validate()
    guard try Self.admits(pattern.surface, scale: scale) else { return nil }
    let reduction = Self.reduction(for: scale)
    var tile = pattern.surface
    for _ in 0..<reduction.trailingZeroBitCount {
      var half = try Surface(width: tile.width / 2, height: tile.height / 2, fill: tile.defaultPixel)
      let side = Surface.tileSide
      let columns = (tile.width + side - 1) / side
      // Even-sized input tiles map to disjoint 2 × 2 reduction footprints.
      // Missing tiles reduce to the existing implicit color.
      for key in tile.storedTileKeys {
        try Task.checkCancellation()
        let left = key % columns * side
        let top = key / columns * side
        for y in (top / 2)..<(min(top + side, tile.height) / 2) {
          for x in (left / 2)..<(min(left + side, tile.width) / 2) {
            half.setPixel(x: x, y: y, Self.average(
              tile.pixel(x: 2 * x, y: 2 * y), tile.pixel(x: 2 * x + 1, y: 2 * y),
              tile.pixel(x: 2 * x, y: 2 * y + 1), tile.pixel(x: 2 * x + 1, y: 2 * y + 1)))
          }
        }
      }
      tile = half
    }
    self.tile = tile
    self.scale = scale * Double(reduction)
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
