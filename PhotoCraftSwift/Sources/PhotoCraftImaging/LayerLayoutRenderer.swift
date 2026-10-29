import Foundation
import PhotoCraftCore

extension Renderer {
  public static func layoutBounds(
    _ layer: Layer, in document: CraftDocument, stored: Bool
  ) throws -> IntRect? {
    try Task.checkCancellation()
    if let bounds = layer.frameBounds { return bounds }
    if let bounds = layer.artboardBounds { return bounds }
    if layer.isGroup {
      return try LayerLayout.union(
        document.children(of: layer.id).compactMap {
          try layoutBounds($0, in: document, stored: stored)
        })
    }
    if case .adjustment = layer.content { return nil }
    guard !layer.isCanvasFill else {
      throw CraftError.unsupported("Alignment of canvas fill layers is not available yet.")
    }
    let layer = try SmartFilterEngine.renderedLayer(layer, in: document)
    let surface = try layerSurface(layer, in: document)
    guard let content = try surface.contentBounds() else { return nil }
    let bounds =
      stored ? IntRect(x: 0, y: 0, width: surface.width, height: surface.height) : content
    let matrix = layer.coordinateTransform * .translation(Double(bounds.x), Double(bounds.y))
    return try matrix.bounds(width: bounds.width, height: bounds.height)
  }

  public static func layoutCommand(
    in document: CraftDocument, selected: Set<UUID>, operation: LayerLayoutOperation,
    target: LayerLayoutTarget = .selection
  ) throws -> Command {
    try document.validate()
    let roots = try LayerLayout.roots(selected, in: document)
    let reference: IntRect?
    switch operation {
    case .align:
      reference =
        target == .canvas
        ? IntRect(x: 0, y: 0, width: document.width, height: document.height) : document.selection
    case .distribute: reference = nil
    }
    let items = try roots.compactMap { layer -> LayerLayoutItem? in
      guard let bounds = try layoutBounds(layer, in: document, stored: reference != nil) else {
        return nil
      }
      return LayerLayoutItem(id: layer.id, bounds: bounds)
    }
    let moves = try LayerLayout.plan(items, operation: operation, target: reference)
    return .layoutLayers(moves, operation)
  }
}
