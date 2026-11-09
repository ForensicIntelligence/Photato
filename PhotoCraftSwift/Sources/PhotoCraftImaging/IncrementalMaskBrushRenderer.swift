import Foundation
import PhotoCraftCore

/// Owns one validated mask operation. Only the Core session may produce the
/// changing document; clients cannot inject pixels into the validated renderer.
public final class IncrementalMaskBrushRenderer {
  private let stroke: DocumentMaskStrokeSession
  private let lightPreview: LightEditingPreview?
  public var sampleCount: Int { stroke.sampleCount }
  public func hasInputPrefix(_ points: [StrokePoint]) -> Bool { stroke.hasInputPrefix(points) }
  public init(document: CraftDocument, command: Command, pausingLightWhileEditing: Bool = false) throws {
    stroke = try DocumentMaskStrokeSession(document: document, command: command)
    lightPreview = pausingLightWhileEditing ? .init(document: document, editingLayers: [stroke.layerID]) : nil
  }
  public func append(_ points: [StrokePoint], reusing previous: RenderSnapshot?, includingReleaseTail: Bool = true) throws -> RenderSnapshot {
    let document = try stroke.append(points, includingReleaseTail: includingReleaseTail)
    return try Renderer.renderValidated(lightPreview?.project(document) ?? document, reusing: previous)
  }
  public func prepareEdit(points: [StrokePoint]) throws -> PreparedEdit { try stroke.prepareEdit(points: points) }
}
