import CoreGraphics
import Foundation
import PhotoCraftCore

public struct RemovePeopleDetection: Sendable {
  public let count: Int
  public let protectedCount: Int
  public let coverage: SelectionMask?
  public let overlay: CGImage?
}

public enum RemovePeoplePreparation {
  public static func detect(_ document: CraftDocument, layerID: UUID, settings: RemoveToolSettings,
    detector: any PeopleDetecting = VisionPeopleDetector(),
    foregroundDetector: any ForegroundDetecting = VisionForegroundDetector()) async throws -> RemovePeopleDetection {
    try settings.validate(); try document.validate(); try Task.checkCancellation()
    guard document.colorMode == .rgb, document.width <= RemovePreparation.maximumCanvasPixels / document.height,
      let layer = document.layers.first(where: { $0.id == layerID }), case .raster = layer.content,
      layer.smartObject == nil, layer.sourceProjection == nil,
      !document.ancestors(of: layerID).contains(where: { $0.protection.fullyLocks }),
      settings.createNewLayer || !document.isImageLocked(layerID) else {
      throw CraftError.unsupported("People distraction removal requires an available RGB raster target within the current Remove canvas limits.")
    }
    // Share exactly one normalized source grid between person and foreground models.
    // Body-part inference is not needed for this workflow.
    let input = try PeopleAnalysis.input(document, layerID: layerID, allLayers: settings.sampleAllLayers)
    let masks = try await detector.people(in: input)
    try Task.checkCancellation()
    let scene = try PeopleScene(source: .init(document, layerID: layerID, sampleAllLayers: settings.sampleAllLayers), input: input, masks: masks)
    guard !scene.people.isEmpty else { return .init(count: 0, protectedCount: 0, coverage: nil, overlay: nil) }
    let foreground: SelectionMask?
    if let optional = foregroundDetector as? any OptionalForegroundDetecting {
      foreground = try await optional.maskIfPresent(for: input)
    } else { foreground = try await foregroundDetector.mask(for: input) }
    try Task.checkCancellation()
    let candidates = try distractionIDs(scene, foreground: foreground)
    let protected = scene.people.count - candidates.count
    guard !candidates.isEmpty else { return .init(count: 0, protectedCount: protected, coverage: nil, overlay: nil) }
    let mask = try scene.coverage(instanceIDs: candidates, hardEdge: true)
    let preview = try RasterPreviewRequest.overview(width: document.width, height: document.height)
    let overlay = try SelectionToolPreparation.overlay(mask, color: Pixel(1, 0.12, 0.55), request: preview)
    try Task.checkCancellation()
    return .init(count: candidates.count, protectedCount: protected, coverage: mask, overlay: overlay)
  }
  /// Protect whole foreground people. The weighted-majority policy is our explicit
  /// classifier, not a claim about Adobe's proprietary subject-ranking model.
  static func distractionIDs(_ scene: PeopleScene, foreground: SelectionMask?) throws -> [Int] {
    guard let foreground else { return scene.people.map(\.instanceID) }
    guard foreground.width == scene.analysisWidth, foreground.height == scene.analysisHeight else {
      throw CraftError.invalid("Foreground/person analysis grids differ.")
    }
    return try scene.people.compactMap { person in
      guard let bounds = person.mask.bounds else { return nil }
      var total = 0, protected = 0
      for y in bounds.y..<(bounds.y + bounds.height) {
        try Task.checkCancellation()
        for x in bounds.x..<(bounds.x + bounds.width) {
          let index = y * scene.analysisWidth + x, weight = Int(person.mask.byte(at: index))
          total += weight; protected += min(weight, Int(foreground.byte(at: index)))
        }
      }
      return total > 0 && protected * 2 >= total ? nil : person.instanceID
    }
  }

}
