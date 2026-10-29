import CoreGraphics
import CoreText
import Foundation
import PhotoCraftCore

public enum Renderer {
  public static func layerSurface(_ layer: Layer, in document: CraftDocument) throws -> Surface {
    switch layer.content {
    case .raster(let s): return s
    case .gradientFill(let fill): return try gradientSurface(fill, layer: layer, in: document)
    case .patternFill(let fill): return try patternSurface(fill, in: document)
    case .fill(let p):
      // Photoshop evaluates RGB/16 solid fills on its 0...32768 working grid,
      // then expands to the full-range 16-bit channel representation used here.
      // Descriptor color remains continuous and editable.
      let color: Pixel
      if document.depth == .u16 {
        func channel(_ value: Float) -> Float { (unit(value) * 32768).rounded() / 32768 }
        color = Pixel(channel(p.r), channel(p.g), channel(p.b), p.a)
      } else {
        color = p
      }
      return try Surface(
        width: document.width, height: document.height, depth: document.depth, fill: color)
    case .shape(let shape):
      if let definition=shape.definition { return try ShapeRenderer.surface(definition,layer:layer,document:document) }
      var s = try Surface(width: shape.width, height: shape.height, depth: document.depth)
      if shape.kind == .rectangle {
        return try Surface(
          width: shape.width, height: shape.height, depth: document.depth, fill: shape.color)
      }
      for y in 0..<shape.height {
        for x in 0..<shape.width {
          let nx = (Double(x) + 0.5) / Double(shape.width) * 2 - 1
          let ny = (Double(y) + 0.5) / Double(shape.height) * 2 - 1
          let coverage = unit(
            Float((1 - sqrt(nx * nx + ny * ny)) * Double(min(shape.width, shape.height)) / 2 + 0.5))
          var p = shape.color
          p.a *= coverage
          s.setPixel(x: x, y: y, p)
        }
      }
      return s
    case .text(let text): return try text.typography == nil ? renderText(text, document: document) : NativeTextLayout.render(text, document: document)
    case .group:
      return try compositeStack(
        document.children(of: layer.id), in: document, over: emptyCanvas(document))
    case .adjustment:
      throw CraftError.unsupported("An adjustment layer needs the layers below it to render.")
    }
  }
  private static func renderText(_ text: TextContent, document: CraftDocument) throws -> Surface {
    let font = CTFontCreateWithName(text.fontName as CFString, text.size, nil)
    let p = document.depth == .f32 ? SRGBTransfer.linear(text.color) : text.color
    let color =
      CGColor(
        colorSpace: try ColorManagement.space(for: document),
        components: [CGFloat(p.r), CGFloat(p.g), CGFloat(p.b), CGFloat(p.a)])
      ?? CGColor(gray: 0, alpha: 1)
    let attrs =
      [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color] as [CFString: Any]
    let string = NSAttributedString(
      string: text.text,
      attributes: Dictionary(
        uniqueKeysWithValues: attrs.map { (NSAttributedString.Key($0 as String), $1) }))
    let setter = CTFramesetterCreateWithAttributedString(string)
    let layoutWidth = text.layoutWidth ?? document.width
    let layoutHeight = text.layoutHeight ?? document.height
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
      setter, CFRange(location: 0, length: 0), nil,
      CGSize(width: layoutWidth, height: layoutHeight), nil)
    let width = max(1, min(layoutWidth, Int(ceil(size.width)) + 4))
    let height = max(1, min(layoutHeight, Int(ceil(size.height)) + 8))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: try ColorManagement.space(for: document),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw CraftError.invalid("Could not render type.") }
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
    CTFrameDraw(
      CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
    guard let image = context.makeImage() else {
      throw CraftError.invalid("Could not render type.")
    }
    return try RasterIO.surface(
      image, depth: document.depth, space: ColorManagement.space(for: document),
      colorEncoding: document.depth == .f32 ? .linearRGB : .sRGB)
  }
  static func compositePixel(
    _ blend: BlendMode, backdrop: Pixel, source: Pixel,
    opacity: Float, depth: PixelDepth, x: Int, y: Int
  ) -> Pixel {
    if depth == .f32 {
      return SRGBTransfer.encoded(
        blend.composite(
          backdrop: SRGBTransfer.linear(backdrop),
          source: SRGBTransfer.linear(source), opacity: opacity, x: x, y: y))
    }
    return blend.composite(backdrop: backdrop, source: source, opacity: opacity, x: x, y: y)
  }
  /// Linear storage avoids an encoded Float32 round trip between layers.
  static func compositeLinearPixel(
    _ blend: BlendMode, backdrop: Pixel, source: Pixel,
    opacity: Float, x: Int, y: Int
  ) -> Pixel {
    let alpha = unit(source.a * opacity)
    if alpha == 0 { return backdrop }
    if blend == .normal && (alpha == 1 || backdrop.a == 0) {
      return Pixel(source.r, source.g, source.b, alpha)
    }
    return blend.composite(backdrop: backdrop, source: source, opacity: opacity, x: x, y: y)
  }
  public static func composite(_ d: CraftDocument) throws -> Surface {
    try composite(d, inputTarget: nil)
  }
  public static func composite(_ d: CraftDocument, videoTime: Double) throws -> Surface {
    try d.validate()
    return try compositeValidated(d, videoTime: videoTime)
  }
  /// The returned surface retains document coordinates and is transparent outside the region.
  public static func composite(_ d: CraftDocument, region: IntRect) throws -> Surface {
    try d.validate()
    return try compositeValidated(d, region: region)
  }
  static func composite(_ d: CraftDocument, inputTarget: UUID?) throws -> Surface {
    try d.validate()
    return try compositeValidated(d, inputTarget: inputTarget)
  }
  static func compositeValidated(
    _ d: CraftDocument, region: IntRect? = nil, inputTarget: UUID? = nil, videoTime: Double? = nil
  ) throws -> Surface {
    try Task.checkCancellation()
    if inputTarget == nil, let ink = d.inkMode { return try ink.surface(region: region) }
    var (d,videoTransitions) = try VideoTransitionRenderContext.prepare(d, at:videoTime)
    for i in d.layers.indices where d.layers[i].smartFilters != nil || d.layers[i].warp != nil {
      d.layers[i] = try SmartFilterEngine.renderedLayer(d.layers[i], in: d)
    }
    let region = (region ?? IntRect(x: 0, y: 0, width: d.width, height: d.height))
      .clipped(toWidth: d.width, height: d.height)
    let output = try emptyCanvas(d)
    guard region.width > 0, region.height > 0 else { return output }
    if inputTarget == nil, videoTransitions == nil,
      let linear = try RGB32NormalRenderer.composite(d, over: output, region: region)
    {
      return linear
    }
    if videoTransitions != nil || d.layers.contains(where: { $0.isGroup || $0.isClipped }) {
      // Recursive CPU composition retains parent backdrops, which are not bounded by the
      // document's storage budget. Count whole touched tiles,
      // including both boundary tiles for a region that straddles a tile edge.
      let nesting = d.layers.map { d.ancestors(of: $0.id).count }.max() ?? 0
      let buffers = max(5, nesting * 2 + 5) + (videoTransitions == nil ? 0:6)
      let side = Surface.tileSide
      let canvasBytes =
        ((region.x + region.width - 1) / side - region.x / side + 1)
        * ((region.y + region.height - 1) / side - region.y / side + 1) * side * side * 16
      guard canvasBytes * buffers <= 1_610_612_736 else {
        throw CraftError.unsupported(
          "This grouped document exceeds the current CPU compositing memory budget.")
      }
      if inputTarget == nil, videoTransitions == nil,
        let linear = try RGB32HierarchyRenderer.composite(d, region: region)
      {
        return linear
      }
      return try compositeStack(
        d.children(of: nil), in: d, over: output,
        cache: GroupRenderCache(inputTarget: inputTarget, region: region, video:videoTransitions))
    }
    return try compositeFlat(
      d.layers, in: d, over: output, inputTarget: inputTarget, region: region)
  }
  static func emptyCanvas(_ d: CraftDocument) throws -> Surface {
    try Surface(
      width: d.width, height: d.height, depth: .f32,
      colorEncoding: d.depth == .f32 ? .linearRGB : .sRGB)
  }
  static func compositeFlat(
    _ layers: [Layer], in d: CraftDocument, over backdrop: Surface,
    inputTarget: UUID? = nil, region: IntRect? = nil
  ) throws
    -> Surface
  {
    let region = (region ?? IntRect(x: 0, y: 0, width: d.width, height: d.height))
      .clipped(toWidth: d.width, height: d.height)
    var output = backdrop
    for layer in layers where layer.visible && layer.opacity > 0 {
      try Task.checkCancellation()
      if layer.id == inputTarget { throw AdjustmentInputReached(surface: output) }
      if layer.style != nil {
        output = try LayerStyleRenderer.composite(layer, in: d, over: output, region: region)
        continue
      }
      let mask = try LayerMaskSampler.make(layer: layer, document: d, pixelRegion: region)
      if case .adjustment(let adjustment) = layer.content {
        let evaluate = try adjustment.spatialEvaluator(depth: d.depth)
        for y in region.y..<region.y + region.height {
          try Task.checkCancellation()
          for x in region.x..<region.x + region.width {
            let b = output.pixel(x: x, y: y)
            let p = evaluate(b, x, y)
            let m = mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
            let amount = unit(layer.opacity * m)
            if amount == 0 { continue }
            if adjustment.usesDocumentToneSpace, layer.blendMode == .normal {
              let mixed = LevelsTransfer.mix(b, with: p, coverage: amount, depth: d.depth)
              guard mixed.isFinite else {
                throw CraftError.invalid("Adjustment result exceeds the floating-point range.")
              }
              output.setPixel(x: x, y: y, mixed)
              continue
            }
            if adjustment.usesDocumentToneSpace, d.depth == .f32 {
              let before = SRGBTransfer.linear(b)
              let after = SRGBTransfer.linear(p)
              let rgb =
                before.rgb + (layer.blendMode.rgb(before.rgb, after.rgb) - before.rgb) * amount
              let mixed = SRGBTransfer.encoded(Pixel(rgb.x, rgb.y, rgb.z, b.a))
              guard mixed.isFinite else {
                throw CraftError.invalid("Adjustment result exceeds the floating-point range.")
              }
              output.setPixel(x: x, y: y, mixed)
              continue
            }
            let c = b.rgb + (layer.blendMode.rgb(b.rgb, p.rgb) - b.rgb) * amount
            output.setPixel(x: x, y: y, Pixel(c.x, c.y, c.z, b.a))
          }
        }
        continue
      }
      if case .gradientFill(let fill) = layer.content {
        let sampler = try GradientFillSampler(fill, layer: layer, document: d)
        for y in region.y..<region.y + region.height {
          try Task.checkCancellation()
          for x in region.x..<region.x + region.width {
            var pixel = sampler.sample(x: x, y: y)
            pixel.a *= mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
            guard pixel.a > 0 else { continue }
            output.setPixel(
              x: x, y: y,
              compositePixel(
                layer.blendMode, backdrop: output.pixel(x: x, y: y), source: pixel,
                opacity: layer.opacity, depth: d.depth, x: x, y: y))
          }
        }
        continue
      }
      if case .patternFill(let fill) = layer.content {
        let sampler = try PatternFillSampler(fill, in: d)
        for y in region.y..<region.y + region.height {
          try Task.checkCancellation()
          for x in region.x..<region.x + region.width {
            var pixel = sampler.sample(x: Double(x) + 0.5, y: Double(y) + 0.5)
            pixel.a *= mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
            guard pixel.a > 0 else { continue }
            output.setPixel(
              x: x, y: y,
              compositePixel(
                layer.blendMode, backdrop: output.pixel(x: x, y: y), source: pixel,
                opacity: layer.opacity, depth: d.depth, x: x, y: y))
          }
        }
        continue
      }
      let surface = try layerSurface(layer, in: d)
      // Fill layers cover the full canvas, independent of crop offsets.
      let isFill: Bool = {
        if case .fill = layer.content { return true }
        return false
      }()
      if layer.affine != nil {
        let inverse = try layer.coordinateTransform.inverted()
        let bounds =
          isFill
          ? IntRect(x: 0, y: 0, width: d.width, height: d.height)
          : try layer.coordinateTransform.bounds(width: surface.width, height: surface.height)
        let x0 = max(region.x, bounds.x)
        let y0 = max(region.y, bounds.y)
        let x1 = min(region.x + region.width, bounds.x + bounds.width)
        let y1 = min(region.y + region.height, bounds.y + bounds.height)
        if x0 >= x1 || y0 >= y1 { continue }
        for y in y0..<y1 {
          try Task.checkCancellation()
          for x in x0..<x1 {
            let local = inverse.point(Double(x) + 0.5, Double(y) + 0.5)
            var p =
              isFill
              ? surface.pixel(x: x, y: y)
              : RasterGeometry.sample(surface, x: local.x, y: local.y, method: .bilinear)
            p.a *= mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
            guard p.a > 0 else { continue }
            output.setPixel(
              x: x, y: y,
              compositePixel(
                layer.blendMode,
                backdrop: output.pixel(x: x, y: y), source: p, opacity: layer.opacity,
                depth: d.depth, x: x, y: y))
          }
        }
        continue
      }
      let ox = isFill ? 0 : layer.x
      let oy = isFill ? 0 : layer.y
      let x0 = max(region.x, ox)
      let y0 = max(region.y, oy)
      let x1 = min(region.x + region.width, ox + surface.width)
      let y1 = min(region.y + region.height, oy + surface.height)
      if x0 >= x1 || y0 >= y1 { continue }
      for y in y0..<y1 {
        if y % 64 == 0 { try Task.checkCancellation() }
        for x in x0..<x1 {
          var p =
            d.depth == .f32
            ? surface.linearPixel(x: x - ox, y: y - oy)
            : surface.pixel(x: x - ox, y: y - oy)
          p.a *= mask?.coverage(x: Double(x) + 0.5, y: Double(y) + 0.5) ?? 1
          guard p.a > 0 else { continue }
          if d.depth == .f32 {
            output.setLinearPixel(
              x: x, y: y,
              compositeLinearPixel(
                layer.blendMode, backdrop: output.linearPixel(x: x, y: y),
                source: p, opacity: layer.opacity, x: x, y: y))
            continue
          }
          output.setPixel(
            x: x, y: y,
            compositePixel(
              layer.blendMode,
              backdrop: output.pixel(x: x, y: y), source: p, opacity: layer.opacity, depth: d.depth,
              x: x, y: y))
        }
      }
    }
    return output
  }
  public static func gaussianBlur(_ surface: Surface, radius: Double) throws -> Surface {
    guard radius.isFinite, (0...100).contains(radius) else {
      throw CraftError.invalid("Blur radius must be 0–100 pixels.")
    }
    if radius == 0 { return surface }
    let extent = max(1, Int(ceil(radius * 3)))
    var kernel = (-extent...extent).map { exp(-Double($0 * $0) / (2 * radius * radius)) }
    let total = kernel.reduce(0, +)
    kernel = kernel.map { $0 / total }
    let w = surface.width
    let h = surface.height
    var intermediate = [SIMD4<Float>](repeating: .zero, count: w * h)
    func premul(_ p: Pixel) -> SIMD4<Float> { SIMD4(p.r * p.a, p.g * p.a, p.b * p.a, p.a) }
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        var sum = SIMD4<Float>.zero
        for k in -extent...extent {
          sum +=
            premul(surface.pixel(x: min(w - 1, max(0, x + k)), y: y)) * Float(kernel[k + extent])
        }
        intermediate[y * w + x] = sum
      }
    }
    var output = try Surface(width: w, height: h, depth: surface.depth)
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        var sum = SIMD4<Float>.zero
        for k in -extent...extent {
          sum += intermediate[min(h - 1, max(0, y + k)) * w + x] * Float(kernel[k + extent])
        }
        let a = unit(sum.w)
        let f = a > 0 ? 1 / a : 0
        output.setPixel(x: x, y: y, Pixel(sum.x * f, sum.y * f, sum.z * f, a))
      }
    }
    return output
  }
  public static func resize(_ surface: Surface, width: Int, height: Int) throws -> Surface {
    var output = try Surface(width: width, height: height, depth: surface.depth)
    func premul(_ p: Pixel) -> SIMD4<Float> { SIMD4(p.r * p.a, p.g * p.a, p.b * p.a, p.a) }
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let sx = max(
          0,
          min(
            Double(surface.width - 1),
            (Double(x) + 0.5) * Double(surface.width) / Double(width) - 0.5))
        let sy = max(
          0,
          min(
            Double(surface.height - 1),
            (Double(y) + 0.5) * Double(surface.height) / Double(height) - 0.5))
        let ix = Int(sx)
        let iy = Int(sy)
        let fx = Float(sx - Double(ix))
        let fy = Float(sy - Double(iy))
        let a = premul(surface.pixel(x: ix, y: iy))
        let b = premul(surface.pixel(x: min(surface.width - 1, ix + 1), y: iy))
        let c = premul(surface.pixel(x: ix, y: min(surface.height - 1, iy + 1)))
        let d = premul(
          surface.pixel(x: min(surface.width - 1, ix + 1), y: min(surface.height - 1, iy + 1)))
        let p = (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
        let f = p.w > 0 ? 1 / p.w : 0
        output.setPixel(x: x, y: y, Pixel(p.x * f, p.y * f, p.z * f, p.w))
      }
    }
    return output
  }
}
