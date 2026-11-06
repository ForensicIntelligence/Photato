import Foundation
import PhotoCraftCore

/// Rendering stays inside Imaging; only the validated core stroke owns final edits.
public final class IncrementalRetouchRenderer {
  private let lightPreview: LightEditingPreview?
  private let stroke: DocumentRetouchStrokeSession
  public var sampleCount: Int { stroke.sampleCount }
  public func hasInputPrefix(_ points: [StrokePoint]) -> Bool { stroke.hasInputPrefix(points) }
  public init(document: CraftDocument, command: Command, pausingLightWhileEditing: Bool = false) throws {
    let targets: Set<UUID>
    switch command {
    case .cloneStamp(let id, _), .toning(let id, _), .focus(let id, _): targets = [id]
    default: targets = []
    }
    lightPreview = pausingLightWhileEditing ? .init(document: document, editingLayers: targets) : nil
    stroke = try DocumentRetouchStrokeSession(document: document, command: command)
  }
  public func snapshot(appending points: [StrokePoint], reusing previous: RenderSnapshot?) throws -> RenderSnapshot {
    let document = try stroke.append(points)
    return try Renderer.renderValidated(lightPreview?.project(document) ?? document, reusing: previous)
  }
  public func prepareEdit(points: [StrokePoint]) throws -> PreparedEdit { try stroke.prepareEdit(points: points) }
}
