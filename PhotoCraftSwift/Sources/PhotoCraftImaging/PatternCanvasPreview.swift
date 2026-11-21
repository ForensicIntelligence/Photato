import Foundation
import PhotoCraftCore

/// A periodic composite with bounded deviations from the repeating source.
/// This is a display representation. Full-resolution exports use the normal renderer.
public struct PatternCanvasPreview: Sendable {
  public static let maximumPeriodPixels = 262_144
  private static let maximumChangedTiles = 2048

  private let document: CraftDocument
  private let repeatTile: Surface
  private let changedTiles: Set<Int>

  public init?(_ document: CraftDocument) throws {
    guard (1...Surface.maxDimension).contains(document.width),
      (1...Surface.maxDimension).contains(document.height),
      document.width * document.height > Surface.maximumDensePixels,
      document.colorMode == .rgb, document.inkMode == nil, document.restrictedMode == nil,
      !document.isChannelOnly, document.videoTimeline == nil,
      document.layers.contains(where: { layer in
        layer.visible && layer.style?.effects.contains { $0.kind == .patternOverlay && $0.enabled } == true
      }) else { return nil }
    try document.validate()
    let side = Surface.tileSide, columns = (document.width + side - 1) / side
    let canvas = IntRect(x: 0, y: 0, width: document.width, height: document.height)
    var implicit = document
    var changed = Set<Int>()
    var periodWidth = 1, periodHeight = 1
    var hasRepeatingBase = false

    func add(_ rect: IntRect) throws -> Bool {
      let bounds = rect.clipped(toWidth: canvas.width, height: canvas.height)
      guard bounds.width > 0, bounds.height > 0 else { return true }
      for row in (bounds.y / side)...((bounds.y + bounds.height - 1) / side) {
        try Task.checkCancellation()
        for column in (bounds.x / side)...((bounds.x + bounds.width - 1) / side) {
          changed.insert(row * columns + column)
          if changed.count > Self.maximumChangedTiles { return false }
        }
      }
      return true
    }

    func addStored(_ source: Surface, x: Int, y: Int) throws -> Bool {
      let sourceColumns = (source.width + side - 1) / side
      for key in source.storedTileKeys {
        let left = key % sourceColumns * side, top = key / sourceColumns * side
        let rect = IntRect(x: x + left, y: y + top,
          width: min(side, source.width - left), height: min(side, source.height - top))
        if try !add(rect) { return false }
      }
      return true
    }

    for (index, layer) in document.layers.enumerated() {
      try Task.checkCancellation()
      guard layer.parentID == nil, !layer.isGroup, !layer.isClipped else { return nil }
      if !layer.visible { continue }
      guard layer.affine == nil, layer.warp == nil, layer.smartObject == nil,
        layer.smartFilters == nil, layer.sourceProjection == nil, layer.nativeMode == nil,
        layer.vectorMask?.enabled != true, layer.blendMode != .dissolve else { return nil }
      let coversCanvas: Bool
      let implicitAlpha: Float
      switch layer.content {
      case .fill(let pixel):
        coversCanvas = true
        implicitAlpha = pixel.a
      case .raster(let source):
        coversCanvas = layer.x == 0 && layer.y == 0
          && source.width == canvas.width && source.height == canvas.height
        implicitAlpha = coversCanvas ? source.defaultPixel.a : 0
        if !coversCanvas && source.defaultPixel.a > 0 {
          if try !add(IntRect(x: layer.x, y: layer.y, width: source.width, height: source.height)) { return nil }
        } else if try !addStored(source, x: layer.x, y: layer.y) { return nil }
        if !coversCanvas || source.tileCount > 0 {
          implicit.layers[index].content = .raster(try source.implicitSampleSurface(
            fill: coversCanvas ? nil : Pixel.clear))
        }
      default:
        return nil
      }
      if let mask = layer.mask, layer.effectiveMaskProperties.enabled {
        guard layer.effectiveMaskProperties.feather == 0, layer.maskCoordinateTransform == .identity,
          mask.width == canvas.width, mask.height == canvas.height else { return nil }
        if try !addStored(mask, x: 0, y: 0) { return nil }
        implicit.layers[index].mask = try mask.implicitSampleSurface()
      }
      guard let style = layer.style else { continue }
      guard style.supportsRegionalPatternOverlay else { return nil }
      if !style.enabled || implicitAlpha == 0 || layer.opacity == 0 { continue }
      for effect in style.effects where effect.enabled && effect.opacity > 0 {
        guard effect.blendMode != .dissolve, let fill = effect.pattern,
          let period = try PatternFillSampler.exactAxisPeriod(fill, style: style, layer: layer, in: document),
          let width = Self.commonPeriod(periodWidth, period.width),
          let height = Self.commonPeriod(periodHeight, period.height),
          width <= Self.maximumPeriodPixels / height else { return nil }
        periodWidth = width
        periodHeight = height
        hasRepeatingBase = true
      }
    }
    guard hasRepeatingBase else { return nil }
    let region = IntRect(x: 0, y: 0, width: min(periodWidth, document.width),
      height: min(periodHeight, document.height))
    self.document = document
    repeatTile = try Renderer.compositePrepared(implicit, region: region).cropped(to: region)
    changedTiles = changed
  }

  private static func commonPeriod(_ a: Int, _ b: Int) -> Int? {
    var x = a, y = b
    while y != 0 { (x, y) = (y, x % y) }
    let (value, overflow) = (a / x).multipliedReportingOverflow(by: b)
    return overflow ? nil : value
  }

  public var documentWidth: Int { document.width }
  public var documentHeight: Int { document.height }

  /// Read a full-resolution merged pixel even when the visible image is reduced.
  public func pixel(x: Int, y: Int) throws -> Pixel {
    guard x >= 0, y >= 0, x < document.width, y < document.height else { return .clear }
    let side = Surface.tileSide
    let key = y / side * ((document.width + side - 1) / side) + x / side
    if changedTiles.contains(key) {
      return try Renderer.compositePrepared(document, region: .init(x: x, y: y, width: 1, height: 1))
        .pixel(x: x, y: y)
    }
    return repeatTile.pixel(x: x % repeatTile.width, y: y % repeatTile.height)
  }

  public func imageSamples(_ request: RasterPreviewRequest, channels: RGBChannelView = .init(),
    proof: ProofSettings? = nil) throws -> Surface {
    let region = request.region
    guard region == region.clipped(toWidth: document.width, height: document.height) else {
      throw CraftError.invalid("The preview region is outside the document.")
    }
    let integerView = request.width == region.width && request.height == region.height
    let projection = try RasterPreviewProjection(document, channels: channels, proof: proof)
    let plane = try projection.apply(repeatTile)
    let linear = plane.colorEncoding == .linearRGB
    func stored(_ surface: Surface, x: Int, y: Int) -> Pixel {
      linear ? surface.linearPixel(x: x, y: y) : surface.pixel(x: x, y: y)
    }
    func base(_ x: Int, _ y: Int) -> Pixel {
      stored(plane, x: x % plane.width, y: y % plane.height)
    }
    let area = IntRect(x: 0, y: 0, width: request.width, height: request.height)
    var output = try Surface(width: area.width, height: area.height, depth: .f32,
      colorEncoding: plane.colorEncoding)
    let sx = Double(region.width) / Double(area.width), sy = Double(region.height) / Double(area.height)
    let pixelArea = sx * sy
    let integral = try integerView ? nil : PatternIntegral(plane)
    let xs = integral.map { $0.horizontalFootprints(start: region.x, count: area.width, scale: sx) }
    let ys = integral.map { $0.verticalFootprints(start: region.y, count: area.height, scale: sy) }

    // Most requests have no changed tiles in view. Only changed output bins
    // need a correction table, and the unit-scale path copies exact values.
    let side = Surface.tileSide, columns = (document.width + side - 1) / side
    var deltas = [Int: SIMD4<Double>]()
    var replacements = [Int: Pixel]()
    for key in changedTiles.sorted() {
      try Task.checkCancellation()
      let tileX = key % columns * side, tileY = key / columns * side
      let x0 = max(region.x, tileX), y0 = max(region.y, tileY)
      let x1 = min(region.x + region.width, tileX + side), y1 = min(region.y + region.height, tileY + side)
      guard x0 < x1, y0 < y1 else { continue }
      let patch = try projection.apply(Renderer.compositePrepared(document,
        region: .init(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
        .cropped(to: .init(x: x0, y: y0, width: x1 - x0, height: y1 - y0)))
      for y in y0..<y1 {
        let t = Double(y - region.y) / sy, b = Double(y + 1 - region.y) / sy
        for x in x0..<x1 {
          let p = stored(patch, x: x - x0, y: y - y0)
          let old = base(x, y)
          if p.hasSameBits(as: old) { continue }
          if integerView {
            replacements[(y - region.y) * area.width + x - region.x] = p
            continue
          }
          let delta = PatternIntegral.premultiplied(p) - PatternIntegral.premultiplied(old)
          if delta == .zero { continue }
          let l = Double(x - region.x) / sx, r = Double(x + 1 - region.x) / sx
          for oy in max(0, Int(floor(t)))..<min(area.height, Int(ceil(b))) {
            let dy = (min(b, Double(oy + 1)) - max(t, Double(oy))) * sy
            for ox in max(0, Int(floor(l)))..<min(area.width, Int(ceil(r))) {
              let dx = (min(r, Double(ox + 1)) - max(l, Double(ox))) * sx
              deltas[oy * area.width + ox, default: .zero] += delta * (dx * dy)
            }
          }
        }
      }
    }

    for y in 0..<area.height {
      try Task.checkCancellation()
      for x in 0..<area.width {
        let index = y * area.width + x
        let p: Pixel
        if let integral, let xs, let ys {
          let sum = integral.sum(xs[x], ys[y]) + (deltas[index] ?? .zero)
          p = sum.w > 0 ? Pixel(Float(sum.x / sum.w), Float(sum.y / sum.w),
            Float(sum.z / sum.w), Float(min(1, max(0, sum.w / pixelArea)))) : .clear
        } else {
          p = replacements[index] ?? base(x + region.x, y + region.y)
        }
        if linear { output.setLinearPixel(x: x, y: y, p) } else { output.setPixel(x: x, y: y, p) }
      }
    }
    return output
  }
}

/// Summed areas of one periodic cell. Fractional prefixes integrate the nearest
/// stored pixel's area, with whole periods added before the edge corrections.
private struct PatternIntegral {
  struct Edge {
    let cycles: Double
    let index: Int
    let fraction: Double
  }
  struct Footprint {
    let start: Edge
    let end: Edge
  }
  private let width: Int, height: Int, stride: Int
  private let prefix: [SIMD4<Double>]

  init(_ samples: Surface) throws {
    width = samples.width
    height = samples.height
    stride = width + 1
    var prefix = [SIMD4<Double>](repeating: .zero, count: stride * (height + 1))
    for y in 0..<height {
      try Task.checkCancellation()
      var row = SIMD4<Double>.zero
      for x in 0..<width {
        let p = samples.colorEncoding == .linearRGB
          ? samples.linearPixel(x: x, y: y) : samples.pixel(x: x, y: y)
        row += Self.premultiplied(p)
        prefix[(y + 1) * stride + x + 1] = row + prefix[y * stride + x + 1]
      }
    }
    self.prefix = prefix
  }

  static func premultiplied(_ p: Pixel) -> SIMD4<Double> {
    let a = Double(p.a)
    return SIMD4(Double(p.r) * a, Double(p.g) * a, Double(p.b) * a, a)
  }

  private static func edges(start: Int, count: Int, scale: Double, period: Int) -> [Footprint] {
    func edge(_ index: Int) -> Edge {
      let location = Double(start) + Double(index) * scale
      let cycles = floor(location / Double(period))
      let remainder = min(Double(period), max(0, location - cycles * Double(period)))
      let whole = min(period - 1, Int(floor(remainder)))
      return Edge(cycles: cycles, index: whole, fraction: remainder - Double(whole))
    }
    return (0..<count).map { Footprint(start: edge($0), end: edge($0 + 1)) }
  }

  func horizontalFootprints(start: Int, count: Int, scale: Double) -> [Footprint] {
    Self.edges(start: start, count: count, scale: scale, period: width)
  }

  func verticalFootprints(start: Int, count: Int, scale: Double) -> [Footprint] {
    Self.edges(start: start, count: count, scale: scale, period: height)
  }

  private func rectanglePrefix(_ x: Edge, _ y: Edge) -> SIMD4<Double> {
    let i = y.index * stride + x.index
    let a = prefix[i], b = prefix[i + 1], c = prefix[i + stride], d = prefix[i + stride + 1]
    let top = a + (b - a) * x.fraction, bottom = c + (d - c) * x.fraction
    return top + (bottom - top) * y.fraction
  }

  func sum(_ x: Footprint, _ y: Footprint) -> SIMD4<Double> {
    let dx = x.end.cycles - x.start.cycles, dy = y.end.cycles - y.start.cycles
    let allX = Edge(cycles: 0, index: width - 1, fraction: 1)
    let allY = Edge(cycles: 0, index: height - 1, fraction: 1)
    let endRows = rectanglePrefix(x.end, allY) - rectanglePrefix(x.start, allY)
    let endColumns = rectanglePrefix(allX, y.end) - rectanglePrefix(allX, y.start)
    let lower = rectanglePrefix(x.end, y.end) - rectanglePrefix(x.start, y.end)
    let upper = rectanglePrefix(x.end, y.start) - rectanglePrefix(x.start, y.start)
    return prefix.last! * (dx * dy) + endRows * dy + endColumns * dx + lower - upper
  }
}
