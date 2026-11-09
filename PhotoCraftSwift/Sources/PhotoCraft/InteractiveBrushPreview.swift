import Foundation
import PhotoCraftCore
import PhotoCraftImaging

/// Serial worker ownership keeps mutable stroke coverage off the main thread.
actor InteractiveBrushPreview {
  private enum Worker {
    case raster(IncrementalBrushRenderer)
    case mask(IncrementalMaskBrushRenderer, previewTail: Bool)
    var sampleCount: Int {
      switch self { case .raster(let value): return value.sampleCount; case .mask(let value, _): return value.sampleCount }
    }
    func hasInputPrefix(_ points: [StrokePoint]) -> Bool {
      switch self { case .raster(let value): return value.hasInputPrefix(points); case .mask(let value, _): return value.hasInputPrefix(points) }
    }
    func append(_ points: [StrokePoint], previous: RenderSnapshot?) throws -> RenderSnapshot {
      switch self {
      case .raster(let value): return try value.append(points, reusing: previous, includingReleaseTail: false)
      case .mask(let value, let tail): return try value.append(points, reusing: previous, includingReleaseTail: tail)
      }
    }
    func prepareEdit(points: [StrokePoint]) throws -> PreparedEdit {
      switch self { case .raster(let value): return try value.prepareEdit(points: points); case .mask(let value, _): return try value.prepareEdit(points: points) }
    }
  }
  private let original: CraftDocument
  private let command: Command
  private var renderer: Worker?
  private var completePreparation = false
  private var acceptedPoints: [StrokePoint] = []
  private var committed = false
  init?(document: CraftDocument, command: Command) {
    if case .stroke(let id, _, let brush) = command {
      guard BrushStrokeSession.supports(brush), document.animation == nil, document.variables == nil,
        document.videoTimeline == nil, document.modeDescriptor == nil, document.restrictedMode == nil,
        document.inkMode == nil, let layer = document.layers.first(where: { $0.id == id }),
        layer.smartObject == nil, case .raster = layer.content else { return nil }
    } else if !DocumentMaskStrokeSession.supports(document: document, command: command) { return nil }
    original = document; self.command = command
  }
  private func worker() throws -> Worker? {
    guard !completePreparation else { return nil }
    if let renderer { return renderer }
    let next: Worker
    if case .stroke(let id, _, let brush) = command {
      next = .raster(try IncrementalBrushRenderer(document: original, layerID: id, brush: brush, pausingLightWhileEditing: true))
    } else {
      let adjustment: Bool
      if case .adjustmentBrush = command { adjustment = true } else { adjustment = false }
      do {
        next = .mask(try IncrementalMaskBrushRenderer(document: original, command: command,
          pausingLightWhileEditing: !adjustment), previewTail: adjustment)
      } catch CraftError.unsupported {
        // Reconciliation can require complete preparation even after cheap admission.
        completePreparation = true; return nil
      }
    }
    renderer = next; return next
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
    do {
      guard let renderer = try worker() else { return nil }
      guard renderer.hasInputPrefix(points) else { throw CraftError.invalid("The brush preview source changed.") }
      let snapshot = try renderer.append(Array(points.dropFirst(renderer.sampleCount)), previous: previous)
      acceptedPoints = points
      return snapshot
    } catch is CancellationError { renderer = nil; throw CancellationError() }
  }
  func prepareCommit(base: CraftDocument, points: [StrokePoint]) throws -> PreparedEdit? {
    try Task.checkCancellation(); guard base == original else { return nil }
    guard !committed else { throw CraftError.invalid("The brush stroke has already finished.") }
    guard let renderer = try worker() else { return nil }
    let prepared = try renderer.prepareEdit(points: points)
    acceptedPoints = points; committed = true
    return prepared
  }
}
