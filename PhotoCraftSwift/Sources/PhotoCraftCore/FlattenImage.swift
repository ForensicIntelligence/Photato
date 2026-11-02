import Foundation

/// Immutable compositor output; native/API/Actions commit the same source-bound edit.
public struct FlattenImageEdit: Sendable {
  public let source: CraftDocument
  public let result: CraftDocument
  public init(source: CraftDocument, result: CraftDocument) { self.source = source; self.result = result }
  public func applied(to document: CraftDocument) throws -> CraftDocument {
    try Task.checkCancellation()
    guard source == document, result.id == document.id else { throw CraftError.invalid("The document changed before Flatten Image could commit.") }
    try result.validate(); return result
  }
  public static func hiddenLayerIDs(in document: CraftDocument) -> [UUID] {
    let hierarchy = LayerHierarchyIndex(document)
    return document.layers.filter { !$0.visible || hierarchy.ancestors(of: $0.id).contains { !$0.visible } }.map(\.id)
  }
  public static func unavailableReason(_ document: CraftDocument) -> String? {
    if document.layers.isEmpty { return "Open an image with layers first." }
    if document.animation != nil || document.videoTimeline != nil { return "Flattening every frame and retained Timeline source needs temporal composition. Create a still copy first." }
    if document.inkMode != nil || document.restrictedMode != nil { return "Indexed, Bitmap and ink-mode flattening require their palette/plate composition workflow." }
    if document.layers.count == 1, document.layers[0].isBackground { return "The image already has a single Background layer." }
    if document.modeDescriptor != nil {
      guard document.layers.count == 1, let layer = document.layers.first,
        layer.nativeMode != nil, case .raster = layer.content,
        layer.visible, layer.opacity == 1, layer.blendMode == .normal,
        layer.x == 0, layer.y == 0, layer.affine == nil, layer.parentID == nil,
        layer.mask == nil, layer.vectorMask == nil, layer.style == nil,
        layer.smartObject == nil, layer.smartFilters == nil, layer.warp == nil,
        layer.sourceProjection == nil else { return "Layered native component flattening needs numerical channel composition; RGB conversion would lose source components." }
    }
    return nil
  }
}
