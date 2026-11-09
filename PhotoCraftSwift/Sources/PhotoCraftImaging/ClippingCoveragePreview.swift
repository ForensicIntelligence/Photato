import Foundation
import PhotoCraftCore

extension Renderer {
  /// The selected root raster's masked content at a bounded reference size.
  /// Source samples, masks and document geometry remain unchanged. Paged
  /// composition retains existing mask/transform/kernel resource validation.
  public static func clippingCoveragePreview(
    _ layer: Layer, in document: CraftDocument, request: RasterPreviewRequest
  ) throws -> Surface {
    try Task.checkCancellation(); try document.validate()
    guard document.layers.contains(where: { $0.id == layer.id }),
      layer.parentID == nil, !layer.isClipped, case .raster = layer.content else {
      throw CraftError.unsupported("A bounded clipping preview requires a root pixel layer.")
    }
    var content = layer
    content.style = nil; content.opacity = 1; content.blendMode = .normal
    var isolated = document
    isolated.layers = [content]; isolated.activeLayerID = content.id
    // The original document is validated above. Unrelated comp/channel records
    // are not rewritten merely to sample the explicitly selected layer.
    let rendered = try compositeValidated(isolated, preferPaged: true)
    try Task.checkCancellation()
    return try request.reducing(rendered)
  }
}
