import Foundation

/// Owns a validated ordinary raster stroke from first preview through commitment.
/// No caller-supplied replacement pixels or unchecked prepared edit are accepted.
public final class DocumentBrushStrokeSession {
  private let original: CraftDocument
  private let index: Int
  private let layerID: UUID
  private let brush: Brush
  private let stroke: BrushStrokeSession
  private var points: [StrokePoint] = []
  private var finished = false
  public var sampleCount: Int { points.count }
  public init(document: CraftDocument, layerID: UUID, brush: Brush) throws {
    guard document.animation == nil, document.videoTimeline == nil, document.variables == nil,
      document.modeDescriptor == nil, document.restrictedMode == nil, document.inkMode == nil,
      let index = document.layers.firstIndex(where: { $0.id == layerID }),
      document.layers[index].smartObject == nil, case .raster(let surface) = document.layers[index].content
    else { throw CraftError.unsupported("This target uses the complete stroke renderer.") }
    var checked = document; try Command.stroke(layerID, [], brush).apply(to: &checked)
    guard checked == document else { throw CraftError.unsupported("This stroke requires document reconciliation.") }
    original = document; self.index = index; self.layerID = layerID; self.brush = brush
    stroke = try BrushStrokeSession(surface: surface, brush: brush,
      selection: document.selection, selectionMask: document.selectionMask,
      transform: document.layers[index].coordinateTransform,
      preserveTransparency: document.isTransparencyLocked(layerID))
  }
  public func hasInputPrefix(_ samples: [StrokePoint]) -> Bool {
    samples.count >= points.count && points.elementsEqual(samples.prefix(points.count))
  }
  public func append(_ samples: [StrokePoint], includingReleaseTail: Bool = true) throws -> CraftDocument {
    guard !finished else { throw CraftError.invalid("The stroke has already finished.") }
    var result = original
    result.layers[index].content = .raster(try stroke.append(samples, includingReleaseTail: includingReleaseTail))
    points.append(contentsOf: samples)
    return result
  }
  public func prepareEdit(points samples: [StrokePoint]) throws -> PreparedEdit {
    guard hasInputPrefix(samples) else { throw CraftError.invalid("The stroke input changed during painting.") }
    let result = try append(Array(samples.dropFirst(points.count)))
    try result.validate(); try Task.checkCancellation(); finished = true
    return PreparedEdit(retainedStrokeOriginal: original, result: result, command: .stroke(layerID, points, brush))
  }
}
