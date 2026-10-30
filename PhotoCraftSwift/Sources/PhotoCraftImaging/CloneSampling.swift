import Foundation
import PhotoCraftCore

extension Renderer {
  public static func cloneSample(
    in document: CraftDocument, layerID: UUID, sampling: CloneSampling,
    ignoreAdjustments: Bool = false, mask: Bool = false
  ) throws -> CloneSample {
    try Task.checkCancellation()
    try document.validate()
    guard let i = document.layers.firstIndex(where: { $0.id == layerID }) else {
      throw CraftError.invalid(
        "Clone source layer no longer exists. Option-click to set a new source.")
    }
    let layer = document.layers[i]
    let origin = RetouchSampleOrigin(document: document, layerID: layerID,
      sampling: sampling, ignoreAdjustments: ignoreAdjustments, mask: mask)
    if mask {
      guard let pixels = layer.mask else {
        throw CraftError.invalid("Clone source mask no longer exists.")
      }
      let outside = layer.effectiveMaskProperties.outside
      return CloneSample(
        surface: pixels, transform: layer.maskCoordinateTransform,
        outside: Pixel(outside, outside, outside), origin: origin)
    }
    if sampling == .current {
      if case .adjustment = layer.content {
        throw CraftError.invalid("Choose a source with pixels, or sample multiple layers.")
      }
      let surface = try layerSurface(layer, in: document)
      let transform: Transform2D
      if layer.isCanvasFill {
        transform = .identity
      } else if case .group = layer.content {
        transform = .identity
      } else {
        transform = layer.coordinateTransform
      }
      return CloneSample(surface: surface, transform: transform, origin: origin)
    }
    var probe = document
    let ancestors = Set(document.ancestors(of: layerID).map(\.id))
    for index in probe.layers.indices {
      if sampling == .currentAndBelow && index > i && !ancestors.contains(probe.layers[index].id) {
        probe.layers[index].visible = false
      }
      if ignoreAdjustments, case .adjustment = probe.layers[index].content {
        probe.layers[index].visible = false
      }
    }
    return CloneSample(surface: try composite(probe), origin: origin)
  }
}
