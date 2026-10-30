import Foundation
import PhotoCraftCore

/// Source-compatible renderer backed by the validated retained document stroke.
public final class IncrementalToningRenderer {
  private let renderer: IncrementalRetouchRenderer
  public static func supports(document: CraftDocument, layerID: UUID, stroke: ToningStroke) -> Bool {
    DocumentRetouchStrokeSession.supports(document: document, command: .toning(layerID, stroke))
  }
  public init(document: CraftDocument, layerID: UUID, initial: ToningStroke) throws {
    renderer = try IncrementalRetouchRenderer(document: document, command: .toning(layerID, initial))
  }
  public func snapshot(appending points: [StrokePoint], reusing previous: RenderSnapshot?) throws -> RenderSnapshot {
    try renderer.snapshot(appending: points, reusing: previous)
  }
}
