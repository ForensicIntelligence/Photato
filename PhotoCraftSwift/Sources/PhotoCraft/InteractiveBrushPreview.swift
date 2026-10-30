import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Serial worker ownership keeps mutable stroke coverage off the main thread.
actor InteractiveBrushPreview {
  private let original: CraftDocument
  private let layerID: UUID
  private let brush: Brush
  private var renderer: IncrementalBrushRenderer?
  private var acceptedPoints: [StrokePoint] = []
  private var committed = false
  init?(document: CraftDocument, command: Command) {
    guard case .stroke(let id, _, let brush) = command,
      BrushStrokeSession.supports(brush), document.animation == nil, document.variables == nil,
      document.videoTimeline == nil, document.modeDescriptor == nil, document.restrictedMode == nil,
      document.inkMode == nil, let layer = document.layers.first(where: { $0.id == id }),
      layer.smartObject == nil, case .raster = layer.content else { return nil }
    original = document; layerID = id; self.brush = brush
  }
  func snapshot(base: CraftDocument, points: [StrokePoint], previous: RenderSnapshot?) throws -> RenderSnapshot? {
    try Task.checkCancellation()
    guard !committed else { throw CancellationError() }
    // An additional draft must use normal command composition, never bypass it.
    guard base == original else { return nil }
    if points.count < acceptedPoints.count {
      guard points.elementsEqual(acceptedPoints.prefix(points.count)) else {
        throw CraftError.invalid("The brush preview source changed.")
      }
      throw CancellationError()
    }
    if renderer == nil { renderer = try IncrementalBrushRenderer(document: original, layerID: layerID, brush: brush) }
    guard renderer!.hasInputPrefix(points) else { throw CraftError.invalid("The brush preview source changed.") }
    do {
      let snapshot = try renderer!.append(Array(points.dropFirst(renderer!.sampleCount)), reusing: previous, includingReleaseTail: false)
      acceptedPoints = points
      return snapshot
    } catch is CancellationError { renderer = nil; throw CancellationError() }
  }
  func prepareCommit(base: CraftDocument, points: [StrokePoint]) throws -> PreparedEdit? {
    try Task.checkCancellation(); guard base == original else { return nil }
    guard !committed else { throw CraftError.invalid("The brush stroke has already finished.") }
    if renderer == nil { renderer = try IncrementalBrushRenderer(document: original, layerID: layerID, brush: brush) }
    let prepared = try renderer!.prepareEdit(points: points)
    acceptedPoints = points; committed = true
    return prepared
  }
}
