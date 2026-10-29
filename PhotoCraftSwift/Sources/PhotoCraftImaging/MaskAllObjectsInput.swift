import Foundation
import PhotoCraftCore

public protocol AllObjectsDetecting: Sendable {
  func masks(for image: Surface) async throws -> [DetectedObjectMask]
}

public enum MaskAllObjectsInput {
  public static func command(document: CraftDocument, layerID: UUID,
    detector: any AllObjectsDetecting = VisionForegroundDetector()) async throws -> Command {
    try ForegroundSelection.checkSize(document.width, document.height)
    try MaskAllObjectsEdit.checkTarget(document, layerID: layerID)
    var layer = document.layers.first { $0.id == layerID }!
    layer.visible = true; layer.style = nil
    let source = try Renderer.clippingCoverage(layer, in: document)
    let proxy = try ColorManagement.converted(source, from: document, to: CraftDocument(width: 1, height: 1))
    let masks = try await detector.masks(for: proxy)
    try Task.checkCancellation()
    return .maskAllObjects(.init(layerID: layerID, objects: masks))
  }
}
