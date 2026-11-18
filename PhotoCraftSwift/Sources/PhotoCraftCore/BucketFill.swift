import Foundation

public struct BucketOptions: Codable, Equatable, Sendable {
  public var match = ColorMatchOptions()
  public var opacity: Float = 1
  public var mode = BlendMode.normal
  public var clearsAlpha = false
  public var sampleAllLayers = false
  public init() {}

  public func sampling(mask: Bool) -> CloneSampling {
    sampleAllLayers && !mask ? .all : .current
  }

  public func validate() throws {
    try match.validate()
    guard opacity.isFinite, (0...1).contains(opacity) else {
      throw CraftError.invalid("Paint Bucket opacity must be between 0 and 1.")
    }
  }
}

extension CraftDocument {
  public func validateBucketTarget(layerID: UUID, mask: Bool, clearsAlpha: Bool) throws {
    guard let layer = layers.first(where: { $0.id == layerID }) else {
      throw CraftError.invalid("Choose a Paint Bucket target.")
    }
    if clearsAlpha {
      guard !mask, layer.smartObject == nil, case .raster = layer.content else {
        throw CraftError.unsupported("Paint Bucket Clear requires an ordinary pixel layer.")
      }
      try validateBrushPaintModeTarget(layerID: layerID)
    } else if mask {
      guard layer.mask != nil, !isLocked(layerID) else {
        throw CraftError.invalid("Choose an unlocked pixel mask.")
      }
    } else {
      guard case .raster = layer.content else {
        throw CraftError.unsupported("Rasterize this layer before using Paint Bucket.")
      }
      guard !isImageLocked(layerID) else {
        throw CraftError.invalid("Unlock this layer and its parent groups before editing it.")
      }
    }
  }
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

/// The source image is sampled from the playback document at this step.
public struct RecordedPaintBucket: Codable, Sendable {
  public let target: ActionLayerTarget
  public let point: PathPoint
  public let color: Pixel
  public let options: BucketOptions
  public let mask: Bool
  public let pattern: RasterPattern?
  public let placement: PatternPlacement

  init?(recording fill: BucketFill, layerID: UUID, in document: CraftDocument) {
    guard let origin = fill.source.origin, origin.documentID == document.id,
      origin.layerID == layerID, origin.sampling == fill.options.sampling(mask: fill.mask),
      origin.mask == fill.mask, !origin.ignoreAdjustments, !origin.convertToTarget
    else { return nil }
    target = ActionLayerTarget(layerID, in: document)
    point = fill.seed
    color = fill.color
    options = fill.options
    mask = fill.mask
    pattern = fill.pattern
    placement = fill.placement
  }

  public func validate() throws {
    try options.validate()
    guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
      point.x < Double(Surface.maxDimension), point.y < Double(Surface.maxDimension),
      color.isFinite, (0...1).contains(color.a), !mask || !options.clearsAlpha
    else { throw CraftError.invalid("Invalid recorded Paint Bucket settings.") }
    if case .named(_, let occurrence) = target, !(0..<LayerLimits.maximumLayers).contains(occurrence) {
      throw CraftError.invalid("Invalid recorded Paint Bucket layer.")
    }
    if let pattern {
      try pattern.validate()
      try placement.validate()
    }
  }
}

public enum BucketPainter {
  @discardableResult public static func paint(
    _ fill: BucketFill, on layer: inout Layer, canvasWidth: Int, canvasHeight: Int,
    selection: IntRect? = nil, selectionMask: SelectionMask? = nil, preserveTransparency: Bool = false
  ) throws -> Bool {
    let preserve = !fill.mask && (preserveTransparency || layer.protection.locksTransparency)
    _ = try Surface(width: canvasWidth, height: canvasHeight)
    try fill.options.validate()
    let clear = fill.options.clearsAlpha
    guard fill.color.isFinite, (0...1).contains(fill.color.a),
      selectionMask == nil
        || (selectionMask?.width == canvasWidth && selectionMask?.height == canvasHeight)
    else { throw CraftError.invalid("Invalid Paint Bucket settings.") }
    if clear {
      guard !fill.mask, !preserve, !layer.isBackground, !layer.protection.locksImage,
        layer.smartObject == nil, case .raster(let pixels) = layer.content, pixels.depth != .f32
      else { throw CraftError.unsupported("Clear requires an unlocked 8- or 16-bit pixel layer with transparency.") }
    } else if fill.mask {
      guard layer.mask != nil else { throw CraftError.invalid("This layer has no pixel mask.") }
    } else if case .raster = layer.content {
    } else {
      throw CraftError.unsupported("Rasterize this layer before using Paint Bucket.")
    }
    try Task.checkCancellation()
    let pattern = try fill.pattern.map { try PatternSampler($0, placement: fill.placement) }
    guard fill.options.opacity > 0, clear || pattern != nil || fill.color.a > 0 else { return false }
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
    // A full solid fill with coordinate-independent blending can update the
    // implicit sample and allocated tiles, even with partial opacity.
    if region.isPaged, !fill.mask, pattern == nil, clear || fill.options.mode != .dissolve,
      selectionMask == nil, bounds.width == canvasWidth, bounds.height == canvasHeight,
      layer.coordinateTransform == .identity, case .raster(let original) = layer.content,
      original.width == canvasWidth, original.height == canvasHeight, try region.isFullCoverage {
      let result: Surface
      if !clear && !preserve && fill.options.mode == .normal && fill.options.opacity == 1 && fill.color.a == 1 {
        result = try original.reframedImplicitValue(
          width: canvasWidth, height: canvasHeight, sample: fill.color, linear: false)
      } else {
        let encoding = original.colorEncoding
        let linear = original.depth == .f32
        let source = linear ? SRGBTransfer.linear(fill.color) : fill.color
        result = try original.mappedStoredSamples { stored in
          let old = encoding == .linearRGB ? SRGBTransfer.encoded(stored) : stored
          guard let next = try composite(old, rawInk: fill.color, ink: source, cover: fill.options.opacity,
            mode: fill.options.mode, clearWeight: clear ? 1 : nil,
            mask: false, preserve: preserve, linear: linear, x: 0, y: 0)
          else { return stored }
          return encoding == .linearRGB ? SRGBTransfer.linear(next) : next
        }.quantizedStoredDepth(original.depth)
      }
      try Task.checkCancellation()
      guard result != original else { return false }
      layer.content = .raster(result)
      return true
    }
    return try ClonePainter.paintTarget(
      mask: fill.mask, bounds: bounds, on: &layer,
      clipping: clipping, preserveTransparency: preserve || clear
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
      let areas: AnySequence<IntRect>
      if region.isPaged {
        let coverage = try region.coverageSurface()
        if coverage.defaultPixel.r == 0, coverage.tileCount <= RasterGeometry.sparseGridSourceTileLimit {
          let layerBounds = IntRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
          let support = try coverage.projectedGeometrySupport(inverse, bounds: layerBounds, halo: 0)
          areas = AnySequence(GeometryPatchRegions(width: pixels.width, height: pixels.height, rectangles: support))
        } else {
          areas = AnySequence([local])
        }
      } else {
        areas = AnySequence([local])
      }
      var changed = false
      for area in areas {
        let left = max(area.x, local.x), top = max(area.y, local.y)
        let right = min(area.x + area.width, local.x + local.width)
        let bottom = min(area.y + area.height, local.y + local.height)
        guard right > left, bottom > top else { continue }
        for y in top..<bottom {
          try Task.checkCancellation()
          for x in left..<right {
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
            guard clear || rawSource.a > 0 else { continue }
            let old = pixels.pixel(x: x, y: y)
            guard let result = try composite(old, rawInk: rawSource, ink: source,
              cover: coverage, mode: fill.options.mode, clearWeight: clear ? (pattern == nil ? 1 : rawSource.a) : nil,
              mask: fill.mask, preserve: preserve, linear: linear, x: dx, y: dy) else { continue }
            pixels.setPixel(x: x, y: y, result)
            if !pixels.pixel(x: x, y: y).hasSameBits(as: old) { changed = true }
          }
        }
      }
      return changed
    }
  }

  private static func composite(_ old: Pixel, rawInk: Pixel, ink: Pixel, cover: Float,
    mode: BlendMode, clearWeight: Float?, mask: Bool, preserve: Bool, linear: Bool, x: Int, y: Int
  ) throws -> Pixel? {
    if let clearWeight {
      return BrushPaintMode.clear.composite(backdrop: old, ink: .clear,
        weight: cover, opacity: clearWeight, mask: 1)
    }
    if preserve && old.a <= 0 { return nil }
    let raw = mask ? Pixel(unit(old.r), unit(old.r), unit(old.r)) : old
    let backdrop = linear ? SRGBTransfer.linear(raw) : raw
    let result: Pixel
    if preserve {
      let blended = ProtectedPixels.composite(mode, backdrop: backdrop,
        source: ink, opacity: cover, x: x, y: y)
      result = linear ? SRGBTransfer.encoded(blended) : blended
    } else if mode == .normal && cover == 1 && rawInk.a == 1 {
      result = rawInk
    } else {
      let blended = mode.composite(backdrop: backdrop, source: ink, opacity: cover, x: x, y: y)
      result = linear ? SRGBTransfer.encoded(blended) : blended
    }
    guard result.isFinite else { throw CraftError.invalid("Paint Bucket produced an invalid sample.") }
    return mask ? Pixel(unit(result.r), unit(result.r), unit(result.r)) : result
  }
}
