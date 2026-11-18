import Foundation

/// Owns a validated ordinary raster stroke from first preview through commitment.
/// No caller-supplied replacement pixels or unchecked prepared edit are accepted.
public final class DocumentBrushStrokeSession {
  private let original: CraftDocument
  private let index: Int
  private let layerID: UUID
  private let brush: Brush
  private var stroke: BrushStrokeSession?
  private var points: [StrokePoint] = []
  private var finished = false
  private var failed = false
  public var sampleCount: Int { points.count }

  package static func supports(_ brush: Brush) -> Bool {
    BrushStrokeSession.supports(brush, allowingWideRaster: true)
  }
  public init(document: CraftDocument, layerID: UUID, brush: Brush) throws {
    guard document.animation == nil, document.videoTimeline == nil, document.variables == nil,
      document.modeDescriptor == nil, document.restrictedMode == nil, document.inkMode == nil,
      let index = document.layers.firstIndex(where: { $0.id == layerID }),
      document.layers[index].smartObject == nil, case .raster(let surface) = document.layers[index].content
    else { throw CraftError.unsupported("This target uses the complete stroke renderer.") }
    var checked = document; try Command.stroke(layerID, [], brush).apply(to: &checked)
    guard checked == document else { throw CraftError.unsupported("This stroke requires document reconciliation.") }
    original = document; self.index = index; self.layerID = layerID; self.brush = brush
    stroke = try BrushStrokeSession(surface: surface, brush:document.layers[index].backgroundBrush(brush),
      selection: document.selection, selectionMask: document.selectionMask,
      transform: document.layers[index].coordinateTransform,
      preserveTransparency: document.isTransparencyLocked(layerID), allowingWideRaster: true)
  }
  public func hasInputPrefix(_ samples: [StrokePoint]) -> Bool {
    samples.count >= points.count && points.elementsEqual(samples.prefix(points.count))
  }
  public func append(_ samples: [StrokePoint], includingReleaseTail: Bool = true) throws -> CraftDocument {
    guard !finished, !failed else { throw CraftError.invalid("The finished, cancelled or failed stroke must be restarted.") }
    do { return try update(samples, includingReleaseTail: includingReleaseTail) }
    catch { failed = true; throw error }
  }

  private func update(_ samples: [StrokePoint], includingReleaseTail: Bool) throws -> CraftDocument {
    try Task.checkCancellation()
    guard samples.count <= 100_000 - points.count else { throw CraftError.invalid("Invalid brush input count.") }
    var result = original
    if let stroke {
      do {
        result.layers[index].content = .raster(try stroke.append(samples, includingReleaseTail: includingReleaseTail))
        points.append(contentsOf: samples)
        return result
      } catch BrushRetentionError.coverageBudget {
        // Drop retained coverage before the complete banded renderer allocates
        // its working tiles. Future batches use the original samples as input.
        self.stroke = nil
      }
    }
    var settings = brush
    if !includingReleaseTail { settings.settings?.smoothing.catchUpOnEnd = false }
    let all = points + samples
    try Command.stroke(layerID, all, settings).apply(to: &result)
    points = all
    return result
  }
  public func prepareEdit(points samples: [StrokePoint]) throws -> PreparedEdit {
    guard hasInputPrefix(samples) else { throw CraftError.invalid("The stroke input changed during painting.") }
    let result = try append(Array(samples.dropFirst(points.count)))
    try result.validate(); try Task.checkCancellation(); finished = true
    return PreparedEdit(retainedStrokeOriginal: original, result: result, command: .stroke(layerID, points, brush))
  }
}
