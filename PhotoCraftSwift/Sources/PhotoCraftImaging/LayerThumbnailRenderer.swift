import Foundation
import PhotoCraftCore

public enum ThumbnailFraming: String, Codable, CaseIterable, Sendable {
  case layerBounds
  case entireDocument
}

public enum LayerThumbnailComponent: String, Sendable {
  case content, pixelMask, vectorMask
}

extension Renderer {
  /// A content preview, independent of visibility, opacity, masks and the backdrop.
  /// Sample into the small output directly rather than allocating a transformed canvas.
  public static func layerThumbnail(
    _ layer: Layer, in document: CraftDocument, framing: ThumbnailFraming, maximumSize: Int,
    component: LayerThumbnailComponent = .content
  ) throws -> Surface? {
    guard (1...512).contains(maximumSize) else {
      throw CraftError.invalid("Invalid layer thumbnail size.")
    }
    try Task.checkCancellation()
    if component != .content {
      return try maskThumbnail(
        layer, in: document, framing: framing, maximumSize: maximumSize, component: component)
    }
    if layer.isGroup { return nil }
    if case .adjustment = layer.content { return nil }
    let source = try layerSurface(layer, in: document)
    let transform = layer.isCanvasFill ? Transform2D.identity : layer.coordinateTransform
    let inverse = try transform.inverted()
    let layout = try thumbnailLayout(
      layer, in: document, framing: framing, maximumSize: maximumSize, content: source)
    let frame = layout.frame
    let width = layout.width
    let height = layout.height
    var result = try Surface(width: width, height: height, depth: source.depth)
    var sampler = ThumbnailCoverage(
      mapping: inverse * .translation(Double(frame.x), Double(frame.y))
        * .scale(Double(frame.width) / Double(width), Double(frame.height) / Double(height)))
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        result.setPixel(x: x, y: y, try sampler.sample(source, x: x, y: y))
      }
    }
    return result
  }
}

struct LayerThumbnailLayout {
  let frame: IntRect
  let width: Int
  let height: Int
  var documentToPreview: Transform2D {
    .scale(Double(width) / Double(frame.width), Double(height) / Double(frame.height))
      * .translation(-Double(frame.x), -Double(frame.y))
  }
}

extension Renderer {
  static func thumbnailLayout(
    _ layer: Layer, in document: CraftDocument, framing: ThumbnailFraming, maximumSize: Int,
    content: Surface? = nil
  ) throws -> LayerThumbnailLayout {
    var frame = IntRect(x: 0, y: 0, width: document.width, height: document.height)
    if framing == .layerBounds, !layer.isGroup {
      if case .adjustment = layer.content {
      } else {
        let source = try content ?? layerSurface(layer, in: document)
        if let occupied = try source.contentBounds() {
          let transform = layer.isCanvasFill ? Transform2D.identity : layer.coordinateTransform
          frame = try (transform * .translation(Double(occupied.x), Double(occupied.y)))
            .bounds(width: occupied.width, height: occupied.height)
        }
      }
    }
    let scale = min(
      Double(maximumSize) / Double(frame.width), Double(maximumSize) / Double(frame.height))
    return LayerThumbnailLayout(
      frame: frame,
      width: max(1, Int((Double(frame.width) * scale).rounded(.down))),
      height: max(1, Int((Double(frame.height) * scale).rounded(.down))))
  }
}
