import Foundation
import PhotoCraftCore

/// Internal early exit: the exact backdrop supplied to the adjustment evaluator.
struct AdjustmentInputReached: Error {
  let surface: Surface
}

extension Renderer {
  public static func adjustmentInput(_ id: UUID, in document: CraftDocument) throws -> Surface {
    guard let index = document.layers.firstIndex(where: { $0.id == id }),
      case .adjustment = document.layers[index].content
    else {
      throw CraftError.invalid("Select an adjustment layer to analyze its input.")
    }
    var probe = document
    // Editing a hidden adjustment should still expose its input. The stop occurs
    // before its own opacity/masks or ancestor group mixing is evaluated.
    let required = Set(document.ancestors(of: id).map(\.id)).union([id])
    for i in probe.layers.indices where required.contains(probe.layers[i].id) {
      probe.layers[i].visible = true
      if probe.layers[i].opacity == 0 { probe.layers[i].opacity = 1 }
    }
    do { _ = try composite(probe, inputTarget: id) } catch let captured as AdjustmentInputReached {
      return captured.surface
    }
    throw CraftError.unavailable("This adjustment has no visible input. Check its clipping base.")
  }
  public static func levelsHistogram(
    _ id: UUID, in document: CraftDocument, luminance: Bool = false
  ) throws -> RGBHistogram {
    let input = try adjustmentInput(id, in: document)
    return try RGBHistogram.analyze(input, depth: document.depth, luminance: luminance)
  }
}
