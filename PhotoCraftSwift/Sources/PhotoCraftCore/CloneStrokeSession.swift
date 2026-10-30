import Foundation

/// Incremental Clone Stamp on a fixed pixel grid. Initial points are painted by
/// init; append accepts only new samples. Returned surfaces remain immutable.
/// The owning worker must discard the session after cancellation or an error.
public final class CloneStrokeSession {
  public private(set) var surface: Surface
  private let original: Surface
  private let stroke: CloneStroke
  private let transform: Transform2D
  private let sourceMapping: Transform2D
  private let selection: IntRect?
  private let selectionMask: SelectionMask?
  private let preserveTransparency: Bool
  private let coverage: RetouchCoverageAccumulator
  private var count = 0
  private var failed = false
  public init(surface: Surface, stroke: CloneStroke, transform: Transform2D,
    selection: IntRect? = nil, selectionMask: SelectionMask? = nil,
    preserveTransparency: Bool = false) throws {
    try surface.validated(); try transform.validated()
    sourceMapping = try ClonePainter.prepare(stroke)
    self.surface = surface; original = surface; self.transform = transform
    self.selection = selection; self.selectionMask = selectionMask
    self.preserveTransparency = preserveTransparency
    var metadata = stroke; metadata.points = []; self.stroke = metadata
    coverage = try RetouchCoverageAccumulator(width: surface.width, height: surface.height,
      transform: transform, brush: stroke.brush)
    _ = try append(stroke.points)
  }
  public func append(_ points: [StrokePoint]) throws -> Surface {
    guard !failed else { throw CraftError.invalid("The cancelled or failed retouching stroke must be restarted.") }
    do {
      try Task.checkCancellation()
      guard count + points.count <= 100_000 else { throw CraftError.invalid("Invalid Clone Stamp stroke size.") }
      for point in points {
        guard point.x.isFinite, point.y.isFinite, abs(point.x) <= 1_000_000, abs(point.y) <= 1_000_000,
          point.pressure.isFinite, (0...1).contains(point.pressure)
        else { throw CraftError.invalid("Invalid Clone Stamp sample.") }
      }
      try coverage.append(points)
      var result = surface
      try ClonePainter.applyCoverage(stroke, on: &result, transform: transform,
        sourceMapping: sourceMapping, selection: selection, selectionMask: selectionMask,
        coverage: coverage.snapshot(dirtyOnly: true), preserveTransparency: preserveTransparency,
        backdrop: original)
      try Task.checkCancellation()
      count += points.count; surface = result; return result
    } catch { failed = true; throw error }
  }
}
