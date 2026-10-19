import Foundation
import PhotoCraftCore

extension Renderer {
  /// Editable mask coverage stays visible when disabled. Density/feather and layer opacity
  /// are not baked into this raw editing preview; the row shows enablement separately.
  static func maskThumbnail(
    _ layer: Layer, in document: CraftDocument, framing: ThumbnailFraming, maximumSize: Int,
    component: LayerThumbnailComponent
  ) throws -> Surface? {
    let layout = try thumbnailLayout(
      layer, in: document, framing: framing, maximumSize: maximumSize)
    switch component {
    case .content: return nil
    case .pixelMask:
      guard let source = layer.mask else { return nil }
      let properties = layer.effectiveMaskProperties
      try properties.validate()
      let mapping =
        try layer.maskCoordinateTransform.inverted() * layout.documentToPreview.inverted()
      var sampler = ThumbnailCoverage(
        mapping: mapping,
        channels: .mask(outside: properties.outside, inverted: properties.inverted))
      var output = try Surface(width: layout.width, height: layout.height, depth: source.depth)
      for y in 0..<layout.height {
        try Task.checkCancellation()
        for x in 0..<layout.width {
          output.setPixel(x: x, y: y, try sampler.sample(source, x: x, y: y))
        }
      }
      return output
    case .vectorMask:
      guard let mask = layer.vectorMask else { return nil }
      try mask.validate()
      let coverage = try VectorRasterizer.coverage(
        mask.path.transformed(layout.documentToPreview), width: layout.width, height: layout.height,
        emptyRevealsAll: true)
      var output = try Surface(width: layout.width, height: layout.height, depth: .u8)
      for y in 0..<layout.height {
        try Task.checkCancellation()
        for x in 0..<layout.width {
          // Source UI convention: revealed vector regions white, excluded regions gray.
          let value = (128 + 127 * coverage.coverage(x: x, y: y)) / 255
          output.setPixel(x: x, y: y, Pixel(value, value, value))
        }
      }
      return output
    }
  }
}
