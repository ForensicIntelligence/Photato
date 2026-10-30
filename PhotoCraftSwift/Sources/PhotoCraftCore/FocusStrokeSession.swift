import Foundation

/// Worker-confined fixed-grid Focus stroke. Unsupported boundary/storage cases
/// return to the complete command; a failed session cannot publish partial work.
public final class FocusStrokeSession {
  public private(set) var surface: Surface
  private let original: Surface
  private let transform: Transform2D
  private let canvas: IntRect
  private let clipping: IntRect
  private let selectionMask: SelectionMask?
  private let focus: FocusStroke
  private let source: CloneSample
  private let mapping: Transform2D
  private let preserve: Bool
  private let coverage: RetouchCoverageAccumulator
  private var work: FocusWorkBuffer?
  private var points: [StrokePoint] = []
  private var failed = false

  public init(
    layer: Layer, stroke: FocusStroke, canvasWidth: Int, canvasHeight: Int,
    selection: IntRect? = nil, selectionMask: SelectionMask? = nil,
    preserveTransparency: Bool = false
  ) throws {
    let prepared = try FocusPainter.prepare(stroke, on: layer)
    try prepared.original.validated()
    _ = try Surface(width: canvasWidth, height: canvasHeight)
    original = prepared.original
    surface = original
    transform = prepared.transform
    source = prepared.source
    mapping = prepared.mapping
    canvas = .init(x: 0, y: 0, width: canvasWidth, height: canvasHeight)
    clipping = (selection ?? canvas).clipped(toWidth: canvasWidth, height: canvasHeight)
    self.selectionMask = selectionMask
    preserve = !stroke.mask && (preserveTransparency || layer.protection.locksTransparency)
    let bounds = try transform.inverted().bounds(width: canvasWidth, height: canvasHeight)
    guard
      preserve
        || (bounds.x >= 0 && bounds.y >= 0 && bounds.x + bounds.width <= original.width
          && bounds.y + bounds.height <= original.height)
    else {
      throw CraftError.unsupported("This focus target needs storage expansion.")
    }
    coverage = try RetouchCoverageAccumulator(
      width: original.width, height: original.height,
      transform: transform, brush: stroke.brush)
    var metadata = stroke
    metadata.points = []
    focus = metadata
    _ = try append(stroke.points)
  }

  public func append(_ added: [StrokePoint]) throws -> Surface {
    guard !failed else {
      throw CraftError.invalid("The failed or cancelled focus stroke must be restarted.")
    }
    do {
      try Task.checkCancellation()
      if added.isEmpty { return surface }
      guard points.count + added.count <= 100_000 else {
        throw CraftError.invalid("Focus stroke is too long.")
      }
      for p in added {
        guard p.x.isFinite, p.y.isFinite, abs(p.x) <= 1_000_000, abs(p.y) <= 1_000_000,
          p.pressure.isFinite, (0...1).contains(p.pressure)
        else {
          throw CraftError.invalid("Invalid focus sample.")
        }
        // Keeping the complete brush/pickup neighborhood inside the canvas
        // makes growing the buffer independent of clamped prefix boundaries.
        let margin = focus.brush.size / 2 + 2
        guard p.x >= margin, p.y >= margin, p.x <= Double(canvas.width) - margin,
          p.y <= Double(canvas.height) - margin
        else {
          throw CraftError.unsupported("Boundary focus strokes use complete preparation.")
        }
      }
      points += added
      guard focus.brush.opacity > 0, focus.brush.flow > 0, focus.options.strength > 0 else {
        return surface
      }
      let clone = CloneStroke(
        source: source, mapping: .init(source: .init(0, 0), anchor: .init(0, 0)),
        brush: focus.brush, points: points, mask: focus.mask)
      guard let bounds = ClonePainter.footprint(clone, clipping: canvas) else { return surface }
      let sigma = min(4, max(1, Float(focus.brush.size) * 0.03))
      let halo =
        focus.tool == .smudge ? Int(ceil(focus.brush.size / 2)) + 2 : Int(ceil(sigma * 3)) + 1
      let region = IntRect(
        x: bounds.x - halo, y: bounds.y - halo,
        width: bounds.width + 2 * halo, height: bounds.height + 2 * halo)
      if let work {
        try work.grow(to: region)
        try work.append(added)
        try coverage.append(added)
      } else {
        work = try FocusWorkBuffer(
          focus: focus, source: source, mapping: mapping, depth: original.depth, region: region)
        try work!.append(points)
        try coverage.append(points)
      }
      guard let work, work.touched, let dirty = work.dirty else { return surface }
      var result = surface
      _ = try FocusPainter.applyCoverage(
        focus, on: &result, transform: transform, clipping: clipping,
        selectionMask: selectionMask, preserve: preserve, coverage: coverage.snapshot(),
        workspace: work, backdrop: original, dirty: dirty)
      try Task.checkCancellation()
      surface = result
      return surface
    } catch {
      failed = true
      throw error
    }
  }
}
