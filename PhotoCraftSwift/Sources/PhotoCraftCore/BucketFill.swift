import Foundation

public struct BucketOptions: Equatable, Sendable {
  public var match = ColorMatchOptions()
  public var opacity: Float = 1
  public var mode = BlendMode.normal
  public var sampleAllLayers = false
  public init() {}
}

public struct BucketFill: Sendable {
  public var source: CloneSample
  public var seed: PathPoint
  public var color: Pixel
  public var options: BucketOptions
  public var mask: Bool
  public var pattern: RasterPattern?
  public var placement = PatternPlacement()
  public init(
    source: CloneSample, seed: PathPoint, color: Pixel,
    options: BucketOptions = BucketOptions(), mask: Bool = false,
    pattern: RasterPattern? = nil, placement: PatternPlacement = PatternPlacement()
  ) {
    self.source = source
    self.seed = seed
    self.color = color
    self.options = options
    self.mask = mask
    self.pattern = pattern
    self.placement = placement
  }
}

public enum BucketPainter {
  @discardableResult public static func paint(
    _ fill: BucketFill, on layer: inout Layer, canvasWidth: Int, canvasHeight: Int,
    selection: IntRect? = nil, selectionMask: SelectionMask? = nil, preserveTransparency: Bool = false
  ) throws -> Bool {
    let preserve = !fill.mask && (preserveTransparency || layer.protection.locksTransparency)
    _ = try Surface(width: canvasWidth, height: canvasHeight)
    try fill.options.match.validate()
    let pattern = try fill.pattern.map { try PatternSampler($0, placement: fill.placement) }
    guard fill.color.isFinite, (0...1).contains(fill.color.a),
      fill.options.opacity.isFinite, (0...1).contains(fill.options.opacity),
      selectionMask == nil
        || (selectionMask?.width == canvasWidth && selectionMask?.height == canvasHeight)
    else { throw CraftError.invalid("Invalid Paint Bucket settings.") }
    if fill.mask {
      guard layer.mask != nil else { throw CraftError.invalid("This layer has no pixel mask.") }
    } else if case .raster = layer.content {
    } else {
      throw CraftError.unsupported("Rasterize this layer before using Paint Bucket.")
    }
    try Task.checkCancellation()
    guard fill.options.opacity > 0, pattern != nil || fill.color.a > 0 else { return false }
    let region = try ColorRegion.selection(
      source: fill.source,
      width: canvasWidth, height: canvasHeight, seed: fill.seed,
      options: fill.options.match, mask: fill.mask)
    guard let regionBounds = region.bounds else { return false }
    let clipping = (selection ?? IntRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
      .clipped(toWidth: canvasWidth, height: canvasHeight)
    let x0 = max(regionBounds.x, clipping.x)
    let y0 = max(regionBounds.y, clipping.y)
    let x1 = min(regionBounds.x + regionBounds.width, clipping.x + clipping.width)
    let y1 = min(regionBounds.y + regionBounds.height, clipping.y + clipping.height)
    guard x1 > x0, y1 > y0 else { return false }
    let bounds = IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    return try ClonePainter.paintTarget(
      mask: fill.mask, bounds: bounds, on: &layer,
      clipping: clipping, preserveTransparency: preserve
    ) { pixels, transform, _ in
      let inverse = try transform.inverted()
      let local = try (inverse * .translation(Double(bounds.x), Double(bounds.y)))
        .bounds(width: bounds.width, height: bounds.height)
        .clipped(toWidth: pixels.width, height: pixels.height)
      let linear = pixels.depth == .f32 && !fill.mask
      func sourceColor(_ color: Pixel) -> Pixel {
        guard fill.mask else { return color }
        let gray = unit(0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b)
        return Pixel(gray, gray, gray, color.a)
      }
      let foreground = sourceColor(fill.color)
      let preparedForeground = linear ? SRGBTransfer.linear(foreground) : foreground
      var changed = false
      for y in local.y..<local.y + local.height {
        try Task.checkCancellation()
        for x in local.x..<local.x + local.width {
          let p = transform.point(Double(x) + 0.5, Double(y) + 0.5)
          let dx = Int(floor(p.x))
          let dy = Int(floor(p.y))
          guard dx >= clipping.x, dy >= clipping.y,
            dx < clipping.x + clipping.width, dy < clipping.y + clipping.height
          else { continue }
          let coverage =
            region.coverage(x: dx, y: dy) * fill.options.opacity
            * (selectionMask?.coverage(x: dx, y: dy) ?? 1)
          guard coverage > 0 else { continue }
          let rawSource: Pixel
          let source: Pixel
          if let pattern {
            rawSource = sourceColor(pattern.sample(x: Double(dx) + 0.5, y: Double(dy) + 0.5))
            source = linear ? SRGBTransfer.linear(rawSource) : rawSource
          } else {
            rawSource = foreground
            source = preparedForeground
          }
          guard rawSource.a > 0 else { continue }
          let old = pixels.pixel(x: x, y: y)
          if preserve && old.a <= 0 { continue }
          let raw = fill.mask ? Pixel(unit(old.r), unit(old.r), unit(old.r)) : old
          let backdrop = linear ? SRGBTransfer.linear(raw) : raw
          let result: Pixel
          if preserve {
            let blended = ProtectedPixels.composite(fill.options.mode, backdrop: backdrop,
              source: source, opacity: coverage, x: dx, y: dy)
            result = linear ? SRGBTransfer.encoded(blended) : blended
          } else if fill.options.mode == .normal && coverage == 1 && rawSource.a == 1 {
            result = rawSource
          } else {
            let blended = fill.options.mode.composite(
              backdrop: backdrop, source: source,
              opacity: coverage, x: dx, y: dy)
            result = linear ? SRGBTransfer.encoded(blended) : blended
          }
          guard result.isFinite else {
            throw CraftError.invalid("Paint Bucket produced an invalid sample.")
          }
          pixels.setPixel(
            x: x, y: y, fill.mask ? Pixel(unit(result.r), unit(result.r), unit(result.r)) : result)
          if !pixels.pixel(x: x, y: y).hasSameBits(as: old) { changed = true }
        }
      }
      return changed
    }
  }
}
