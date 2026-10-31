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
      let t=layer.coordinateTransform
      guard t.a==1,t.b==0,t.c==0,t.d==1,t.tx==t.tx.rounded(),t.ty==t.ty.rounded(),layer.vectorMask == nil,
        layer.style == nil, layer.smartObject == nil, layer.smartFilters == nil,
        layer.warp == nil, layer.blendMode != .dissolve else { return false }
      if let mask=layer.mask,layer.effectiveMaskProperties.enabled {
        guard mask.width==d.width,mask.height==d.height,
          layer.maskCoordinateTransform == .identity,layer.effectiveMaskProperties.feather==0 else {return false}
      }
      switch layer.content {
      case .raster: return true
      case .fill: return true
      default: return false
      }
    }) else { return nil }
    let sources=try layers.map {layer -> Surface in
      var source=try Renderer.layerSurface(layer,in:d)
      if !layer.isCanvasFill && (layer.coordinateTransform != .identity || source.width != d.width || source.height != d.height) {
        source=try RasterGeometry.render(source,transform:layer.coordinateTransform,
          bounds:IntRect(x:0,y:0,width:d.width,height:d.height),method:.nearest)
      }
      let properties=layer.effectiveMaskProperties
      guard let mask=layer.mask,properties.enabled else {return source}
      let encodedMask = mask.colorEncoding == .linearRGB
        ? try mask.mappedStoredSamples(encoding:.sRGB) { SRGBTransfer.encoded($0) } : mask
      let numeric=try encodedMask.floatingStorageView().interpretingSamples(as:source.colorEncoding)
      return try source.combiningStoredSamples(with:numeric) {pixel,mask in
        var coverage=unit(mask.r)
        if properties.inverted {coverage=1-coverage}
        if properties.density != 1 {coverage=1-properties.density*(1-coverage)}
        var pixel=pixel;pixel.a *= coverage;return pixel
      }
    }
    if layers.count == 1, let layer = layers.first, layer.opacity == 1, layer.blendMode == .normal,
      case .raster = layer.content,
      let source=sources.first,source.colorEncoding == (d.depth == .f32 ? .linearRGB : .sRGB) {
      let share = try source.allStoredSamplesSatisfy { $0.a == 1 }
      if share { return try source.floatingStorageView() }
    }
    let linearNormal = d.depth == .f32 && layers.allSatisfy {
      if case .raster = $0.content { return $0.blendMode == .normal }; return false
    }
    let opaque: Bool
    if linearNormal, let first = layers.first, first.opacity == 1, let s=sources.first {
      opaque = try s.allStoredSamplesSatisfy { $0.a == 1 }
    } else { opaque = false }
    var output = try Renderer.emptyCanvas(d)
    for (index, layer) in layers.enumerated() {
      try Task.checkCancellation()
      var source = sources[index]
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
