import Foundation

/// Existing Equalize CDF and quantization, evaluated over paged/implicit samples.
/// This expands capacity; independent Photoshop bin/output qualification stays open.
enum PagedEqualize {
  static func storedUpdate(_ value: Pixel, before: Pixel, depth: PixelDepth,
    encoding: SurfaceColorEncoding) -> Pixel {
    let q = value.quantized(depth)
    guard encoding == .linearRGB else { return q }
    let prior = SRGBTransfer.encoded(before)
    func changed(_ next: Float, _ old: Float, _ raw: Float) -> Float {
      next.bitPattern == old.bitPattern ? raw : PixelDepth.f32.quantize(SRGBTransfer.linear(next))
    }
    return Pixel(changed(q.r, prior.r, before.r), changed(q.g, prior.g, before.g),
      changed(q.b, prior.b, before.b), value.a.bitPattern == prior.a.bitPattern ? before.a : q.a)
  }
  static func render(_ source: Surface, mask: Surface?) throws -> Surface {
    let histogram = try source.equalizeHistogram(mask: mask)
    let total = histogram.reduce(0, +), first = histogram.first(where: { $0 > 0 }) ?? 0
    guard total > first else { return source }
    var acc = 0.0, lut = [Float](repeating: 0, count: 256)
    for i in 0..<256 {
      acc += histogram[i]; lut[i] = Float(min(1, max(0, (acc - first) / (total - first))))
    }
    let encoding = source.colorEncoding, depth = source.depth
    return try source.mappedStoredSamples { raw in
      let p = encoding == .linearRGB ? SRGBTransfer.encoded(raw) : raw
      guard p.a > 0 else { return raw }
      func mapped(_ x: Float) -> Float { lut[Int((min(1, max(0, x)) * 255).rounded())] }
      let q = Pixel(mapped(p.r), mapped(p.g), mapped(p.b), p.a)
      if q.hasSameBits(as: p) { return raw }
      return storedUpdate(q, before: raw, depth: depth, encoding: encoding)
    }.quantizedStoredDepth(depth)
  }
  static func apply(_ request: ClassicToneRequest, to document: inout CraftDocument) throws {
    let i = try ClassicToneEngine.validateTarget(request, in: document)
    guard case .raster(let source) = document.layers[i].content else { return }
    let layer = document.layers[i]
    // Equalize accepts ordinary pixels, not a Smart Filter render. Preserve the
    // existing canvas/placed-pixel union without imposing a filter-family limit.
    let placed = try layer.sourceProjection.map { try $0.followed(by: layer.coordinateTransform).bounds(width: source.width, height: source.height) }
      ?? layer.coordinateTransform.bounds(width: source.width, height: source.height)
    let x = min(0, placed.x), y = min(0, placed.y)
    let extent = IntRect(x: x, y: y, width: max(document.width, placed.x+placed.width)-x,
      height: max(document.height, placed.y+placed.height)-y)
    _ = try Surface(width: extent.width, height: extent.height)
    let ignore = request.settings.equalizeEntireImage
    let canvas = IntRect(x: 0, y: 0, width: document.width, height: document.height)
    let area = (ignore ? canvas : document.selection ?? canvas).clipped(toWidth: canvas.width, height: canvas.height)
    guard area.width > 0, area.height > 0 else { return }
    let mapped = layer.affine == nil
      ? try source.expanded(to: .init(x: extent.x-layer.x, y: extent.y-layer.y, width: extent.width, height: extent.height), fill: .clear)
      : try RasterGeometry.render(source, transform: layer.coordinateTransform, bounds: extent, method: .bicubic, clampEdges: false)
    let selected = try document.coverageSelection()?.coverageSurface()
    let statistics = try selected?.expanded(to: extent, fill: .black)
    let output = try render(mapped, mask: statistics)
    if output == mapped { return }
    let coverage = try (ignore ? nil : selected) ?? Surface(width: canvas.width, height: canvas.height, depth: .u8, fill: .white)
    let protect = document.isTransparencyLocked(layer.id)
    var edited = layer
    _ = try ClonePainter.paintTarget(mask: false, bounds: area, on: &edited, clipping: area, preserveTransparency: protect) { pixels, transform, _ in
      let inverse = try transform.inverted(), bounds = IntRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
      let after = try RasterGeometry.render(output, transform: inverse * .translation(Double(extent.x), Double(extent.y)),
        bounds: bounds, method: .nearest, clampEdges: false)
      let mask = try RasterGeometry.render(coverage, transform: inverse, bounds: bounds, method: .nearest, clampEdges: false)
      // A temporary encoded RGB/coverage tuple avoids a third full raster plane or array.
      let encoded = try after.mappedStoredSamples(encoding: .sRGB) {
        after.colorEncoding == .linearRGB ? SRGBTransfer.encoded($0) : $0
      }
      let packed = try encoded.combiningStoredSamples(with: mask) { p, m in Pixel(p.r, p.g, p.b, m.r) }
      let depth = pixels.depth, encoding = pixels.colorEncoding
      let raw = try pixels.interpretingSamples(as: .sRGB)
      let result = try raw.combiningStoredSamples(with: packed) { before, tuple in
        guard tuple.a > 0 else { return before }
        let p = encoding == .linearRGB ? SRGBTransfer.encoded(before) : before
        guard !protect || p.a > 0 else { return before }
        let after = Pixel(tuple.r, tuple.g, tuple.b, p.a)
        let value = tuple.a >= 1 ? after : p.mixing(after, coverage: tuple.a)
        if value.hasSameBits(as: p) { return before }
        return storedUpdate(value, before: before, depth: depth, encoding: encoding)
      }.interpretingSamples(as: encoding).quantizedStoredDepth(depth)
      if result == pixels { return false }
      pixels = result; return true
    }
    try Task.checkCancellation()
    document.layers[i] = edited
  }
}
