import Foundation
import PhotoCraftCore
import PhotoCraftImaging

extension AutomationService {
  /// View-only resources share the native raw-mask projection and preview admission.
  func maskPreview(_ document: CraftNSDocument, shareID: UUID, layerID: UUID,
    mode: MaskViewMode
  ) async throws -> AutomationResponse {
    try Self.checkLimits(document.store.document)
    guard !previewBusy else { throw AutomationFailure(status: 429, message: "A preview is already rendering. Retry shortly.") }
    let snapshot = document.store.document
    guard let layer = snapshot.layers.first(where: { $0.id == layerID }), layer.mask != nil else {
      throw AutomationFailure(status: 404, message: "Pixel mask not found.")
    }
    previewBusy = true; defer { previewBusy = false }
    let expectedRevision = revision(document.store), expectedGeneration = generation
    let worker = Task.detached(priority: .utility) {
      let pixels: Surface
      if snapshot.width * snapshot.height > Surface.maximumDensePixels {
        pixels = try Renderer.maskPresentation(layer, mode: mode,
          request: .overview(width: snapshot.width, height: snapshot.height))
      } else {
        pixels = try Renderer.maskPresentation(layer, mode: mode, width: snapshot.width, height: snapshot.height)
      }
      return try Self.png(RasterIO.displayImage(pixels))
    }
    let bytes = try await withTaskCancellationHandler(operation: { try await worker.value },
      onCancel: { worker.cancel() })
    prune()
    guard !Task.isCancelled, generation == expectedGeneration,
      revision(document.store) == expectedRevision, shares.contains(where: { $0.id == shareID })
    else { throw AutomationFailure(status: 409, message: "Document changed or sharing ended during rendering.") }
    return .init(status: 200, contentType: "image/png", body: bytes)
  }
}
