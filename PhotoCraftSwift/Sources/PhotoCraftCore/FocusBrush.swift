import Foundation

public enum FocusTool: String, CaseIterable, Codable, Sendable {
  case blur = "Blur"
  case sharpen = "Sharpen"
  case smudge = "Smudge"
}
public struct FocusOptions: Codable, Equatable, Sendable {
  public var strength: Float = 0.5
  public var protectDetail = true
  public var sampleAllLayers = false
  public var fingerPainting = false
  public init() {}
}
public struct FocusStroke: Sendable {
  public var tool: FocusTool
  public var options: FocusOptions
  public var brush: CloneBrush
  public var points: [StrokePoint]
  public var mask: Bool
  public var foreground: Pixel
  /// Immutable visible composite when Sample All Layers is enabled. Nil otherwise.
  public var sample: CloneSample?
  public init(
    tool: FocusTool, options: FocusOptions = .init(), brush: CloneBrush,
    points: [StrokePoint], mask: Bool = false, foreground: Pixel = .black,
    sample: CloneSample? = nil
  ) {
    self.tool = tool
    self.options = options
    self.brush = brush
    self.points = points
    self.mask = mask
    self.foreground = foreground
    self.sample = sample
  }
}

public enum FocusPainter {
  @discardableResult public static func paint(
    _ focus: FocusStroke, on layer: inout Layer,
    canvasWidth: Int, canvasHeight: Int, selection: IntRect? = nil,
    selectionMask: SelectionMask? = nil, preserveTransparency: Bool = false
  ) throws -> Bool {
    let preserve = !focus.mask && (preserveTransparency || layer.protection.locksTransparency)
    try Task.checkCancellation()
    let prepared = try prepare(focus, on: layer)
    let original = prepared.original
    let source = prepared.source
    let stroke = prepared.stroke
    let mapping = prepared.mapping
    _ = try Surface(width: canvasWidth, height: canvasHeight)
    guard focus.brush.opacity > 0, focus.brush.flow > 0, focus.options.strength > 0 else {
      return false
    }
    // Neighborhood effects and pickup operate before selection clipping, as in the source.
    let canvas = IntRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
    guard let bounds = ClonePainter.footprint(stroke, clipping: canvas) else { return false }
    let sigma = min(4, max(1, Float(focus.brush.size) * 0.03))
    let halo =
      focus.tool == .smudge ? Int(ceil(focus.brush.size / 2)) + 2 : Int(ceil(sigma * 3)) + 1
    let region = IntRect(
      x: bounds.x - halo, y: bounds.y - halo, width: bounds.width + 2 * halo,
      height: bounds.height + 2 * halo)
    guard region.width <= 36_864, region.height <= 36_864,
      region.width <= FocusKernels.maxPixels / region.height
    else {
      throw CraftError.invalid("Retouching region exceeds its 40-megapixel working limit.")
    }
    let workspace = try FocusWorkBuffer(
      focus: focus, source: source, mapping: mapping,
      depth: original.depth, region: region)
    try workspace.append(focus.points)
    guard workspace.touched else { return false }
    return try ClonePainter.paintTarget(
      stroke, on: &layer, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
      selection: selection, preserveTransparency: preserve
    ) { pixels, transform, clipping in
      let coverage = try ClonePainter.strokeCoverage(stroke, surface: pixels, transform: transform)
      return try applyCoverage(
        focus, on: &pixels, transform: transform, clipping: clipping,
        selectionMask: selectionMask, preserve: preserve, coverage: coverage, workspace: workspace)
    }
  }

  static func applyCoverage(
    _ focus: FocusStroke, on pixels: inout Surface,
    transform: Transform2D, clipping: IntRect, selectionMask: SelectionMask?, preserve: Bool,
    coverage: RetouchCoverage, workspace: FocusWorkBuffer, backdrop: Surface? = nil,
    dirty: IntRect? = nil
  ) throws -> Bool {
    let original = backdrop ?? pixels
    var result = pixels
    var changed = false
    for (key, values) in coverage.tiles {
      try Task.checkCancellation()
      for i in values.indices where values[i] > 0 {
        let x = key % coverage.columns * 64 + i % 64
        let y = key / coverage.columns * 64 + i / 64
        guard x < pixels.width, y < pixels.height else { continue }
        let q = transform.point(Double(x) + 0.5, Double(y) + 0.5)
        let dx = Int(floor(q.x))
        let dy = Int(floor(q.y))
        guard clipping.contains(dx, dy), dirty == nil || dirty!.contains(dx, dy) else { continue }
        let k = focus.brush.opacity * (selectionMask?.coverage(x: dx, y: dy) ?? 1)
        if k <= 0 { continue }
        let raw = original.pixel(x: x, y: y)
        if preserve && raw.a <= 0 { continue }
        let before = focus.mask ? Pixel(unit(raw.r), unit(raw.r), unit(raw.r)) : raw
        let after = workspace.sample(q.x, q.y)
        if !focus.mask && before.a == 0 && after.a == 0 {
          if !raw.hasSameBits(as: result.pixel(x: x, y: y)) {
            result.setPixel(x: x, y: y, raw)
            changed = true
          }
          continue
        }
        let p =
          (preserve
          ? ProtectedPixels.fill(before, color: after, coverage: k)
          : FocusKernels.mix(before, after, k)).quantized(pixels.depth)
        guard p.isFinite else {
          throw CraftError.invalid("Retouching produced a non-finite sample.")
        }
        if !p.hasSameBits(as: result.pixel(x: x, y: y)) {
          result.setPixel(x: x, y: y, p)
          changed = true
        }
      }
    }
    try Task.checkCancellation()
    if changed { pixels = result }
    return changed
  }

  static func prepare(_ focus: FocusStroke, on layer: Layer) throws -> (
    original: Surface, transform: Transform2D, source: CloneSample, stroke: CloneStroke,
    mapping: Transform2D
  ) {
    let original: Surface
    let targetTransform: Transform2D
    let outside: Pixel
    if focus.mask {
      guard let mask = layer.mask else { throw CraftError.invalid("This layer has no pixel mask.") }
      original = mask
      targetTransform = layer.maskCoordinateTransform
      let value = layer.effectiveMaskProperties.outside
      outside = Pixel(value, value, value)
    } else {
      guard case .raster(let pixels) = layer.content else {
        throw CraftError.unsupported("Rasterize this layer before retouching.")
      }
      original = pixels
      targetTransform = layer.coordinateTransform
      outside = .clear
    }
    let useAll = focus.options.sampleAllLayers && !focus.mask
    if useAll && focus.sample == nil {
      throw CraftError.invalid("Sample All Layers needs an immutable image sample.")
    }
    let source =
      useAll
      ? focus.sample! : CloneSample(surface: original, transform: targetTransform, outside: outside)
    let stroke = CloneStroke(
      source: source, mapping: .init(source: .init(0, 0), anchor: .init(0, 0)),
      brush: focus.brush, points: focus.points, mask: focus.mask)
    let mapping = try ClonePainter.prepare(stroke)
    guard focus.options.strength.isFinite, (0...1).contains(focus.options.strength),
      focus.foreground.isFinite, (0...1).contains(focus.foreground.a), focus.brush.mode == .normal
    else { throw CraftError.invalid("Invalid focus tool settings.") }
    return (original, targetTransform, source, stroke, mapping)
  }
}
