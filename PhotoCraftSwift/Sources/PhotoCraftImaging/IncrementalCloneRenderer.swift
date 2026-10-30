import Foundation
import PhotoCraftCore

/// Source-compatible renderer backed by the validated retained document stroke.
public final class IncrementalCloneRenderer {
  private let renderer: IncrementalRetouchRenderer
  public static func supports(document: CraftDocument, layerID: UUID, stroke: CloneStroke) -> Bool {
    DocumentRetouchStrokeSession.supports(document: document, command: .cloneStamp(layerID, stroke))
  }
  public init(document: CraftDocument, layerID: UUID, initial: CloneStroke) throws {
    renderer = try IncrementalRetouchRenderer(document: document, command: .cloneStamp(layerID, initial))
  }
  public func snapshot(appending points: [StrokePoint], reusing previous: RenderSnapshot?) throws -> RenderSnapshot {
    try renderer.snapshot(appending: points, reusing: previous)
  }
}
