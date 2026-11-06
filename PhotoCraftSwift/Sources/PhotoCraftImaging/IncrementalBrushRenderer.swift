import Foundation
import PhotoCraftCore

/// A validated, fixed document plus one bounded pixel edit. No arbitrary document
/// mutation or unchecked renderer API is exposed outside the imaging module.
public final class IncrementalBrushRenderer {
  private let lightPreview: LightEditingPreview?
  private let stroke: DocumentBrushStrokeSession
  public var sampleCount: Int { stroke.sampleCount }
  public func hasInputPrefix(_ points: [StrokePoint]) -> Bool { stroke.hasInputPrefix(points) }
  public init(document: CraftDocument, layerID: UUID, brush: Brush, pausingLightWhileEditing: Bool = false) throws {
    lightPreview = pausingLightWhileEditing ? .init(document: document, editingLayers: [layerID]) : nil
    stroke = try DocumentBrushStrokeSession(document: document, layerID: layerID, brush: brush)
  }
  public func append(_ points: [StrokePoint], reusing previous: RenderSnapshot?, includingReleaseTail: Bool = true) throws -> RenderSnapshot {
    let document = try stroke.append(points, includingReleaseTail: includingReleaseTail)
    return try Renderer.renderValidated(lightPreview?.project(document) ?? document, reusing: previous)
  }
  public func prepareEdit(points: [StrokePoint]) throws -> PreparedEdit { try stroke.prepareEdit(points: points) }
}
