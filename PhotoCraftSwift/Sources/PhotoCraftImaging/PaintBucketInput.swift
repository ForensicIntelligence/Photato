import Foundation
import PhotoCraftCore

/// Captures the click, tool settings and resources before either entry point
/// starts its background document transaction.
public struct PaintBucketRequest: Sendable {
  public let layerID: UUID
  public let point: PathPoint
  public let color: Pixel
  public let options: BucketOptions
  public let mask: Bool
  public let pattern: RasterPattern?
  public let placement: PatternPlacement

  public init(layerID: UUID, point: PathPoint, color: Pixel, options: BucketOptions,
    mask: Bool, pattern: RasterPattern?, placement: PatternPlacement) {
    self.layerID = layerID; self.point = point; self.color = color; self.options = options
    self.mask = mask; self.pattern = pattern; self.placement = placement
  }

  public func command(in document: CraftDocument) throws -> Command {
    try options.validate()
    try Task.checkCancellation()
    guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
      point.x < Double(document.width), point.y < Double(document.height)
    else { throw CraftError.invalid("Sample inside the document.") }
    try document.validateBucketTarget(layerID: layerID, mask: mask, clearsAlpha: options.clearsAlpha)
    let sample = try Renderer.cloneSample(in: document, layerID: layerID,
      sampling: options.sampling(mask: mask), mask: mask)
    return .paintBucket(layerID, BucketFill(source: sample, seed: point, color: color,
      options: options, mask: mask, pattern: pattern, placement: placement))
  }
}
