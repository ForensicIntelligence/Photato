import Foundation
import PhotoCraftCore

public enum MaskViewMode: String, Sendable { case gray, overlay }
public enum MaskThumbnailKind: Sendable { case pixel, vector }

extension Renderer {
  /// The editable channel, independent of enablement, density, feather and layer opacity.
  /// Geometry, outside coverage and inversion still belong to the stored mask.
  private static func rawMaskSampler(_ layer: Layer) throws -> MaskSampler {
    var raw = layer
    var properties = layer.effectiveMaskProperties
    properties.enabled = true
    properties.density = 1
    properties.feather = 0
    raw.maskProperties = properties
    return try MaskSampler(layer: raw, feather: false)
  }

  public static func maskSelection(
    _ layer: Layer, kind: MaskThumbnailKind, width: Int, height: Int
  ) throws -> SelectionMask {
    _ = try Surface(width: width, height: height)
    if kind == .vector {
      guard let mask = layer.vectorMask else {
        throw CraftError.invalid("Layer has no vector mask.")
      }
      return try VectorRasterizer.coverage(
        mask.path, width: width, height: height, emptyRevealsAll: true)
    }
    let sampler = try rawMaskSampler(layer)
    var bytes = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        bytes[y * width + x] = UInt8(
          (sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) * 255).rounded())
      }
    }
    return try SelectionMask(width: width, height: height, bytes: bytes)
  }

  /// Canvas-only image. Overlay is composited by the view, never into the document surface.
  public static func maskPresentation(
    _ layer: Layer, mode: MaskViewMode, width: Int, height: Int
  ) throws -> Surface {
    let sampler = try rawMaskSampler(layer)
    var output = try Surface(width: width, height: height, depth: .f32)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let value = sampler.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5)
        output.setPixel(
          x: x, y: y,
          mode == .gray ? Pixel(value, value, value) : Pixel(1, 0, 0, 0.5 * (1 - value)))
      }
    }
    return output
  }

  /// Viewport-only projection of the raw editable mask. Exact at native pixel centers;
  /// reduced views sample their document-space centers, without materializing the canvas.
  public static func maskPresentation(
    _ layer: Layer, mode: MaskViewMode, request: RasterPreviewRequest
  ) throws -> Surface {
    try Task.checkCancellation()
    let sampler = try rawMaskSampler(layer)
    var output = try Surface(width: request.width, height: request.height, depth: .f32)
    let sx = Double(request.region.width) / Double(request.width)
    let sy = Double(request.region.height) / Double(request.height)
    for y in 0..<request.height {
      try Task.checkCancellation()
      for x in 0..<request.width {
        let value = sampler.coverage(
          x: Double(request.region.x) + (Double(x) + 0.5) * sx,
          y: Double(request.region.y) + (Double(y) + 0.5) * sy)
        output.setPixel(x: x, y: y,
          mode == .gray ? Pixel(value, value, value) : Pixel(1, 0, 0, 0.5 * (1 - value)))
      }
    }
    return output
  }
}
