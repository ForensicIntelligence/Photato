import Foundation

extension ModeComponentEdit {
  /// The dense path remains the pre393 arithmetic reference. Large planes use
  /// bounded projections, immutable native output and the same paint/filter engines.
  func applyPaged(to document: inout CraftDocument) throws {
    let index = document.layers.firstIndex { $0.id == layerID }!
    let before = document, layer = document.layers[index]
    let source = try Self.raster(layer, in: before), transform = layer.coordinateTransform
    try transform.validated(); try Task.checkCancellation()
    switch operation {
    case .fill(let value, let opacity):
      guard value.isFinite, opacity.isFinite, (0...1).contains(value), (0...1).contains(opacity)
      else { throw CraftError.invalid("Invalid channel fill.") }
    case .stroke(let points, let brush): try BrushPainter.validate(brush, points: points)
    case .filter(let filter):
      guard Self.filters.contains(filter.kind) else { throw CraftError.unsupported("This filter has not been implemented for individual color components.") }
      try filter.validate()
    case .invert: break
    }
    let coverage: Surface?
    switch operation {
    case .fill, .invert:
      coverage = try Self.pagedCoverage(before, transform: transform, width: source.width, height: source.height)
    default: coverage = nil
    }
    var result = source
    for component in components.sorted() {
      try Task.checkCancellation()
      var plane = try source.channel(component)
      if source.mode == .cmyk {
        plane = try plane.mappedStoredSamples { p in let v = 1-p.r; return Pixel(v,v,v) }.quantizedStoredDepth(source.depth)
      }
      switch operation {
      case .fill(let value, let opacity):
        plane = try plane.combiningStoredSamples(with: coverage!) { p, mask in
          if source.depth == .u8 {
            return RGBComponentFill(components: .all, value: value, opacity: opacity).applying(to: p, coverage: mask.r)
          }
          let k = mask.r*opacity, v = p.r*(1-k)+value*k
          return Pixel(v,v,v)
        }
      case .invert:
        plane = try plane.combiningStoredSamples(with: coverage!) { p, mask in
          let v = p.r*(1-mask.r)+(1-p.r)*mask.r
          return Pixel(v,v,v)
        }
      case .stroke(let points, var brush):
        let ink = brush.erase ? brush.backgroundColor ?? .white : brush.color
        let value = unit(ink.r*0.2126+ink.g*0.7152+ink.b*0.0722)
        brush.color = Pixel(value,value,value,ink.a); brush.erase = false
        try Painter.stroke(surface: &plane, points: points, brush: brush,
          selection: before.selection, selectionMask: before.selectionMask,
          offsetX: layer.x, offsetY: layer.y, transform: transform, grayscaleMask: true)
      case .filter(let filter):
        var proxy = try CraftDocument(width: before.width, height: before.height, depth: source.depth)
        if source.depth == .f32 { plane = try plane.interpretingSamples(as: .linearRGB) }
        var target = Layer(name: "Channel", content: .raster(plane))
        target.x = layer.x; target.y = layer.y; target.affine = layer.affine
        proxy.layers = [target]; proxy.activeLayerID = target.id
        proxy.selection = before.selection; proxy.selectionMask = before.selectionMask
        try RasterFilterEngine.apply(filter, to: target.id, in: &proxy)
        guard case .raster(let pixels) = proxy.layers[0].content else { throw CraftError.invalid("Invalid channel filter result.") }
        plane = pixels
      }
      if plane.colorEncoding == .linearRGB { plane = try plane.interpretingSamples(as: .sRGB) }
      if source.mode == .cmyk { plane = try plane.mappedStoredSamples { p in let v = 1-p.r; return Pixel(v,v,v) } }
      plane = try plane.quantizedStoredDepth(source.depth)
      result = try result.replacingChannel(component, with: plane)
    }
    var candidate = before
    if before.hasNativeModeStorage {
      candidate.layers[index].nativeMode = result
      candidate.layers[index].content = .raster(try result.surface())
    } else {
      guard case .raster(let pixels) = layer.content else { throw CraftError.invalid("Missing component target.") }
      let encodedFloat = source.depth == .f32 && pixels.colorEncoding == .sRGB
      var edited = try pixels.mappedStoredSamples(encoding: .sRGB) { encodedFloat ? SRGBTransfer.linear($0):$0 }
      for c in components.sorted() {
        edited = try edited.combiningStoredSamples(with: result.channel(c)) { p, q in
          var out = p
          if c == 0 { out.r = q.r } else if c == 1 { out.g = q.r } else { out.b = q.r }
          return out
        }
      }
      edited = try edited.mappedStoredSamples(encoding: pixels.colorEncoding) { encodedFloat ? SRGBTransfer.encoded($0):$0 }.quantizedStoredDepth(pixels.depth)
      candidate.layers[index].content = .raster(edited)
    }
    try candidate.validate(); try Task.checkCancellation(); document = candidate
  }

  /// Coverage uses the exact existing forward mapping and byte/255 division.
  /// Sparse support only bounds work; it never substitutes interpolation math.
  static func pagedCoverage(_ document: CraftDocument, transform: Transform2D,
    width: Int, height: Int) throws -> Surface {
    if document.selectionMask == nil && document.selection == nil {
      return try Surface(width: width, height: height, depth: .f32, fill: .white)
    }
    let local = IntRect(x: 0, y: 0, width: width, height: height), inverse = try transform.inverted()
    let corners = [transform.point(0,0),transform.point(Double(width),0),transform.point(0,Double(height)),transform.point(Double(width),Double(height))]
    let left = corners.map(\.x).min()!, top = corners.map(\.y).min()!, right = corners.map(\.x).max()!, bottom = corners.map(\.y).max()!
    let defaultCoverage: Float, supports: [IntRect]
    if let mask = document.selectionMask {
      let surface = try mask.coverageSurface()
      if transform == .identity, width == mask.width, height == mask.height {
        return try surface.mappedStoredSamples { p in let v = Float((unit(p.r)*255).rounded())/255; return Pixel(v,v,v) }
      }
      let inside = left >= 0 && top >= 0 && right <= Double(mask.width) && bottom <= Double(mask.height)
      let implicit = Float((unit(surface.defaultPixel.r)*255).rounded())/255
      defaultCoverage = inside ? implicit:0
      supports = (implicit == 0 || inside) && surface.tileCount <= RasterGeometry.sparseGridSourceTileLimit
        ? try surface.projectedGeometrySupport(inverse, bounds: local, halo: 1):[local]
    } else if let selection = document.selection {
      if left >= Double(selection.x) && top >= Double(selection.y) && right <= Double(selection.x+selection.width) && bottom <= Double(selection.y+selection.height) {
        return try Surface(width: width, height: height, depth: .f32, fill: .white)
      }
      defaultCoverage = 0
      // Translation by the selection origin is required before inverse placement.
      let points = [inverse.point(Double(selection.x),Double(selection.y)),inverse.point(Double(selection.x+selection.width),Double(selection.y)),inverse.point(Double(selection.x),Double(selection.y+selection.height)),inverse.point(Double(selection.x+selection.width),Double(selection.y+selection.height))]
      let x = Int(max(0,min(Double(width),floor(points.map(\.x).min()!)-1)))
      let y = Int(max(0,min(Double(height),floor(points.map(\.y).min()!)-1)))
      let right = Int(max(0,min(Double(width),ceil(points.map(\.x).max()!)+1)))
      let bottom = Int(max(0,min(Double(height),ceil(points.map(\.y).max()!)+1)))
      supports = [IntRect(x:x,y:y,width:max(0,right-x),height:max(0,bottom-y))]
    } else { throw CraftError.invalid("Missing component selection coverage.") }
    let builder = try Surface.PagedBuilder(width: width, height: height, depth: .f32, fill: Pixel(defaultCoverage,defaultCoverage,defaultCoverage))
    for region in GeometryPatchRegions(width: width, height: height, rectangles: supports) {
      var patch = try Surface(width: region.width, height: region.height, depth: .f32, fill: Pixel(defaultCoverage,defaultCoverage,defaultCoverage))
      for y in 0..<region.height {
        try Task.checkCancellation()
        for x in 0..<region.width {
          let q = transform.point(Double(region.x+x)+0.5,Double(region.y+y)+0.5)
          let value = document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)))
          if value != defaultCoverage { patch.setPixel(x:x,y:y,Pixel(value,value,value)) }
        }
      }
      try builder.append(patch,atX:region.x,atY:region.y)
    }
    return try builder.finish()
  }
}
