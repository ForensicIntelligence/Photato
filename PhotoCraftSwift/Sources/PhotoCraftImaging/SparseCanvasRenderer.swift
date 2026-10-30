import Foundation
import PhotoCraftCore

/// Exact coordinate-independent raster stacks. Logical extent does not determine
/// the working set: missing source and composite tiles retain an implicit value.
enum SparseCanvasRenderer {
  static func composite(_ d: CraftDocument) throws -> Surface? {
    guard d.inkMode == nil, d.restrictedMode == nil, d.videoTimeline == nil,
      d.layers.allSatisfy({ !$0.isGroup && $0.parentID == nil && !$0.isClipped }) else { return nil }
    let layers = d.layers.filter { $0.visible && $0.opacity > 0 }
    guard layers.allSatisfy({ layer in
      guard layer.coordinateTransform == .identity, layer.mask == nil, layer.vectorMask == nil,
        layer.style == nil, layer.smartObject == nil, layer.smartFilters == nil,
        layer.warp == nil, layer.blendMode != .dissolve else { return false }
      switch layer.content {
      case .raster(let s): return s.width == d.width && s.height == d.height
      case .fill: return true
      default: return false
      }
    }) else { return nil }
    if layers.count == 1, let layer = layers.first, layer.opacity == 1, layer.blendMode == .normal,
      case .raster(let source) = layer.content,
      source.colorEncoding == (d.depth == .f32 ? .linearRGB : .sRGB) {
      let share = try source.allStoredSamplesSatisfy { $0.a == 1 }
      if share { return try source.floatingStorageView() }
    }
    let linearNormal = d.depth == .f32 && layers.allSatisfy {
      if case .raster = $0.content { return $0.blendMode == .normal }; return false
    }
    let opaque: Bool
    if linearNormal, let first = layers.first, first.opacity == 1, case .raster(let s) = first.content {
      opaque = try s.allStoredSamplesSatisfy { $0.a == 1 }
    } else { opaque = false }
    var output = try Renderer.emptyCanvas(d)
    for (index, layer) in layers.enumerated() {
      try Task.checkCancellation()
      var source = try Renderer.layerSurface(layer, in: d)
      let encoding: SurfaceColorEncoding = d.depth == .f32 ? .linearRGB : .sRGB
      if source.colorEncoding != encoding {
        source = try source.mappedStoredSamples(encoding: encoding) {
          encoding == .linearRGB ? SRGBTransfer.linear($0) : SRGBTransfer.encoded($0)
        }
      }
      if linearNormal {
        let opacity = RGB32NormalRenderer.expandedOpacity(layer.opacity, opaque: opaque)
        output = try output.combiningStoredSamples(with: source) { backdrop, source in
          var pixel = source; pixel.a = unit(pixel.a * opacity)
          if index == 0 { return pixel }
          return try RGB32NormalRenderer.blend(backdrop, pixel, opaque: opaque)
        }
      } else {
        output = try output.combiningStoredSamples(with: source) { backdrop, pixel in
          guard pixel.a > 0 else { return backdrop }
          return d.depth == .f32
            ? Renderer.compositeLinearPixel(layer.blendMode, backdrop: backdrop, source: pixel, opacity: layer.opacity, x: 0, y: 0)
            : Renderer.compositePixel(layer.blendMode, backdrop: backdrop, source: pixel, opacity: layer.opacity, depth: d.depth, x: 0, y: 0)
        }
      }
    }
    return output
  }
}
