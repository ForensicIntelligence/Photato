import Foundation

/// The Classic Gradient tool samples the drag directly. Fill layers use GradientField's
/// reference-frame geometry instead; substituting that field changes the pixel phase.
public struct GradientToolField: Sendable {
  private let style: GradientStyle
  private let x: Float
  private let y: Float
  private let length: Float
  private let ux: Float
  private let uy: Float
  public init(style: GradientStyle, start: PathPoint, end: PathPoint) throws {
    guard
      [start.x, start.y, end.x, end.y].allSatisfy({
        $0.isFinite && abs($0) <= 1_000_000
      })
    else { throw CraftError.invalid("Invalid gradient endpoints.") }
    self.style = style
    x = Float(start.x)
    y = Float(start.y)
    let dx = Float(end.x) - x
    let dy = Float(end.y) - y
    length = max(sqrt(dx * dx + dy * dy), 1e-6)
    ux = dx / length
    uy = dy / length
  }
  public func parameter(x: Float, y: Float) -> Float {
    guard x.isFinite, y.isFinite, abs(x) <= 1e9, abs(y) <= 1e9 else { return 0 }
    let px = x - self.x
    let py = y - self.y
    let along = px * ux + py * uy
    let across = -px * uy + py * ux
    let t: Float
    switch style {
    case .linear: t = along / length
    case .radial: t = sqrt(px * px + py * py) / length
    case .reflected: t = abs(along) / length
    case .diamond: t = (abs(along) + abs(across)) / length
    case .angle:
      let remainder = (atan2(across, along) / Float(2 * Double.pi))
        .truncatingRemainder(dividingBy: 1)
      t = remainder < 0 ? remainder + 1 : remainder
    }
    return unit(t)
  }
}

public struct GradientStroke: Sendable {
  public var gradient: GradientDefinition
  public var start: PathPoint
  public var end: PathPoint
  public var style: GradientStyle = .linear
  public var reverse = false
  public var dither = true
  public var transparency = true
  public var opacity: Float = 1
  public var mode = BlendMode.normal
  public var mask = false
  public init(gradient: GradientDefinition, start: PathPoint, end: PathPoint) {
    self.gradient = gradient
    self.start = start
    self.end = end
  }
}

public enum GradientPainter {
  @discardableResult public static func paint(
    _ stroke: GradientStroke, on layer: inout Layer, canvasWidth: Int, canvasHeight: Int,
    selection: IntRect? = nil, selectionMask: SelectionMask? = nil, preserveTransparency: Bool = false
  ) throws -> Bool {
    let preserve = !stroke.mask && (preserveTransparency || layer.protection.locksTransparency)
    _ = try Surface(width: canvasWidth, height: canvasHeight)
    try GradientFill(gradient: stroke.gradient).validate()
    let ramp = try GradientRamp(stroke.gradient)
    let field = try GradientToolField(style: stroke.style, start: stroke.start, end: stroke.end)
    guard stroke.opacity.isFinite, (0...1).contains(stroke.opacity),
      selectionMask == nil
        || (selectionMask?.width == canvasWidth && selectionMask?.height == canvasHeight)
    else { throw CraftError.invalid("Invalid Gradient tool settings.") }
    if stroke.mask {
      guard layer.mask != nil else { throw CraftError.invalid("This layer has no pixel mask.") }
    } else if case .raster = layer.content {
    } else {
      throw CraftError.unsupported("Rasterize this layer before using Classic Gradient.")
    }
    try Task.checkCancellation()
    let clipping = (selection ?? IntRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight))
      .clipped(toWidth: canvasWidth, height: canvasHeight)
    guard stroke.opacity > 0, clipping.width > 0, clipping.height > 0 else { return false }
    return try ClonePainter.paintTarget(
      mask: stroke.mask, bounds: clipping, on: &layer, clipping: clipping,
      preserveTransparency: preserve
    ) { pixels, transform, _ in
      let inverse = try transform.inverted()
      let local = try (inverse * .translation(Double(clipping.x), Double(clipping.y)))
        .bounds(width: clipping.width, height: clipping.height)
        .clipped(toWidth: pixels.width, height: pixels.height)
      let linear = pixels.depth == .f32 && !stroke.mask
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
          let coverage = stroke.opacity * (selectionMask?.coverage(x: dx, y: dy) ?? 1)
          guard coverage > 0 else { continue }
          let t = field.parameter(x: Float(dx) + 0.5, y: Float(dy) + 0.5)
          var source = ramp.sample(stroke.reverse ? 1 - t : t)
          if !stroke.transparency { source.a = 1 }
          if stroke.dither { source = GradientRamp.dither(source, x: dx, y: dy) }
          if stroke.mask {
            let gray = unit(0.2126 * source.r + 0.7152 * source.g + 0.0722 * source.b)
            source = Pixel(gray, gray, gray, source.a)
          }
          guard source.a > 0 else { continue }
          let old = pixels.pixel(x: x, y: y)
          if preserve && old.a <= 0 { continue }
          let raw = stroke.mask ? Pixel(unit(old.r), unit(old.r), unit(old.r)) : old
          let result: Pixel
          if preserve {
            let blended = ProtectedPixels.composite(stroke.mode,
              backdrop: linear ? SRGBTransfer.linear(raw) : raw,
              source: linear ? SRGBTransfer.linear(source) : source,
              opacity: coverage, x: dx, y: dy)
            result = linear ? SRGBTransfer.encoded(blended) : blended
          } else if stroke.mode == .normal && coverage == 1 && source.a == 1 {
            result = source
          } else {
            let blended = stroke.mode.composite(
              backdrop: linear ? SRGBTransfer.linear(raw) : raw,
              source: linear ? SRGBTransfer.linear(source) : source,
              opacity: coverage, x: dx, y: dy)
            result = linear ? SRGBTransfer.encoded(blended) : blended
          }
          guard result.isFinite else { throw CraftError.invalid("Invalid gradient sample.") }
          pixels.setPixel(
            x: x, y: y, stroke.mask ? Pixel(unit(result.r), unit(result.r), unit(result.r)) : result
          )
          if !pixels.pixel(x: x, y: y).hasSameBits(as: old) { changed = true }
        }
      }
      return changed
    }
  }
}
