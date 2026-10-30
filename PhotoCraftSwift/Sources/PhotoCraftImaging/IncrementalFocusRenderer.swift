import Foundation
import PhotoCraftCore

/// Source-compatible renderer backed by the validated retained document stroke.
public final class IncrementalFocusRenderer {
  private let renderer: IncrementalRetouchRenderer
  public static func supports(document: CraftDocument, layerID: UUID, stroke: FocusStroke) -> Bool {
    DocumentRetouchStrokeSession.supports(document: document, command: .focus(layerID, stroke))
  }
  public init(document: CraftDocument, layerID: UUID, initial: FocusStroke) throws {
    renderer = try IncrementalRetouchRenderer(document: document, command: .focus(layerID, initial))
  }
  public func snapshot(appending points: [StrokePoint], reusing previous: RenderSnapshot?) throws -> RenderSnapshot {
    try renderer.snapshot(appending: points, reusing: previous)
  }
}
