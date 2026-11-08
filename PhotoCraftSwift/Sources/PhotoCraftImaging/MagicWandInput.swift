import Foundation
import PhotoCraftCore

/// Captured tool options are shared by desktop and API preparation.
public struct MagicWandRequest: Sendable {
  public var layerID: UUID
  public var point: PathPoint
  public var options: ColorMatchOptions
  public var mode: SelectionMode
  public var sampleAllLayers: Bool
  public var mask: Bool

  public init(layerID: UUID, point: PathPoint, options: ColorMatchOptions,
    mode: SelectionMode, sampleAllLayers: Bool, mask: Bool) {
    self.layerID = layerID; self.point = point; self.options = options
    self.mode = mode; self.sampleAllLayers = sampleAllLayers; self.mask = mask
  }
  public func command(in document: CraftDocument) throws -> Command {
    try options.validate(); try Task.checkCancellation()
    guard document.colorMode == .rgb else {
      throw CraftError.unsupported("Magic Wand currently requires an RGB document.")
    }
    guard point.x.isFinite, point.y.isFinite, point.x >= 0, point.y >= 0,
      point.x < Double(document.width), point.y < Double(document.height) else {
      throw CraftError.invalid("Sample inside the document.")
    }
    let source = try Renderer.cloneSample(in: document, layerID: layerID,
      sampling: sampleAllLayers && !mask ? .all : .current, mask: mask)
    return .magicWand(source, point, options, mode, mask)
  }
}
