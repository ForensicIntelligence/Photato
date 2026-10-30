import Foundation
import PhotoCraftCore

/// Rendering stays inside Imaging; only the validated core stroke owns final edits.
public final class IncrementalRetouchRenderer {
  private let stroke: DocumentRetouchStrokeSession
  public var sampleCount: Int { stroke.sampleCount }
  public func hasInputPrefix(_ points: [StrokePoint]) -> Bool { stroke.hasInputPrefix(points) }
  public init(document: CraftDocument, command: Command) throws {
    stroke = try DocumentRetouchStrokeSession(document: document, command: command)
  }
  public func snapshot(appending points: [StrokePoint], reusing previous: RenderSnapshot?) throws -> RenderSnapshot {
    try Renderer.renderValidated(stroke.append(points), reusing: previous)
  }
  public func prepareEdit(points: [StrokePoint]) throws -> PreparedEdit { try stroke.prepareEdit(points: points) }
}
