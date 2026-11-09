import CoreGraphics
import Foundation
import PhotoCraftCore

/// Sky preparation keeps working samples on their original grid. Only display
/// images are reduced; color conversion and statistics stream allocated pages.
enum SkyRasterPreparation {
  static func converted(_ surface: Surface, from source: CraftDocument, to target: CraftDocument) throws -> Surface {
    if surface.width <= Surface.maximumDensePixels / surface.height {
      return try ColorManagement.converted(surface, from: source, to: target)
    }
    try Task.checkCancellation()
    if try ColorManagement.space(for: source) == ColorManagement.space(for: target),
      (source.depth == .f32) == (target.depth == .f32) {
      return try surface.converted(to: target.depth)
    }
    // Reinterpretation exposes the raw linear default without an sRGB roundtrip.
    let raw = try surface.interpretingSamples(as: .sRGB).defaultPixel
    let constant = try Surface(width: 1, height: 1, depth: surface.depth, fill: raw)
      .interpretingSamples(as: surface.colorEncoding)
    let converted = try ColorManagement.converted(constant, from: source, to: target)
    // The converter may materialize its only sample in a tile over an empty
    // default. Read that actual converted sample, including hidden RGB/alpha.
    let fill = try converted.interpretingSamples(as: .sRGB).pixel(x: 0, y: 0)
    let template = try Surface(width: surface.width, height: surface.height, depth: target.depth, fill: fill)
      .interpretingSamples(as: converted.colorEncoding)
    let builder = try Surface.PagedBuilder(template: template)
    let columns = (surface.width + 63) / 64
    for key in surface.storedTileKeys {
      try Task.checkCancellation()
      let x = key % columns * 64, y = key / columns * 64
      let region = IntRect(x: x, y: y, width: min(64, surface.width - x), height: min(64, surface.height - y))
      let patch = try ColorManagement.converted(surface.cropped(to: region), from: source, to: target)
      try builder.append(patch, atX: x, atY: y)
    }
    return try builder.finish()
  }

  static func placed(_ layer: Layer, in document: CraftDocument) throws -> Surface {
    if document.width <= SkyReplacement.denseMaximumPixels / document.height {
      return try Renderer.clippingCoverage(layer, in: document)
    }
    var isolated = document, source = layer
    source.parentID = nil; source.opacity = 1; source.blendMode = .normal; source.clipped = false
    isolated.layers = [source]; isolated.activeLayerID = source.id
    // Like clippingCoverage, read this content independently of the document's
    // timeline and ancestor stack. The caller already validated the source.
    isolated.videoTimeline = nil
    return try Renderer.compositeValidated(isolated, preferPaged: true)
  }

  static func mask(_ coverage: SelectionMask, inverted: Bool) throws -> Surface {
    let source = try coverage.coverageSurface()
    if !inverted { return source }
    return try source.mappedStoredSamples { p in let v = 1 - p.r; return Pixel(v, v, v) }.quantizedStoredDepth(.u8)
  }

  struct Statistics {
    var original = SIMD3<Double>.zero
    var replacement = SIMD3<Double>.zero
    var weight = 0.0
  }
  /// Same even-coordinate sample lattice and alpha/mask weights as the dense
  /// implementation. Missing samples contribute analytically, without a scan
  /// through billions of uniform pixels. Accumulation order is page based.
  static func statistics(original: Surface, replacement: Surface, mask: SelectionMask) throws -> Statistics {
    guard original.width == replacement.width, original.height == replacement.height,
      mask.width == original.width, mask.height == original.height else { throw CraftError.invalid("Sky statistic grids differ.") }
    let coverage = try mask.coverageSurface(), sources = [original, replacement, coverage]
    var iterators = sources.map { $0.storedTileKeys.makeIterator() }
    var heads = iterators.indices.map { iterators[$0].next() }
    let columns = (original.width + 63) / 64
    var output = Statistics(), visited = 0
    func add(_ old: Pixel, _ new: Pixel, _ a: Float, count: Int) {
      let weight = Double(a) * Double(new.a) * Double(count)
      output.original += SIMD3(Double(old.r), Double(old.g), Double(old.b)) * weight
      output.replacement += SIMD3(Double(new.r), Double(new.g), Double(new.b)) * weight
      output.weight += weight
    }
    while let key = heads.compactMap({ $0 }).min() {
      try Task.checkCancellation()
      for i in heads.indices where heads[i] == key { heads[i] = iterators[i].next() }
      let left = key % columns * 64, top = key / columns * 64
      for y in stride(from: top, to: min(original.height, top + 64), by: 2) {
        try Task.checkCancellation()
        for x in stride(from: left, to: min(original.width, left + 64), by: 2) {
          add(original.pixel(x: x, y: y), replacement.pixel(x: x, y: y), coverage.pixel(x: x, y: y).r, count: 1)
          visited += 1
        }
      }
    }
    let implicit = ((original.width + 1) / 2) * ((original.height + 1) / 2) - visited
    if implicit > 0 { add(original.defaultPixel, replacement.defaultPixel, coverage.defaultPixel.r, count: implicit) }
    try Task.checkCancellation()
    return output
  }

  static func display(_ surface: Surface, in document: CraftDocument, request: RasterPreviewRequest? = nil) throws -> CGImage {
    if let request { return try ColorManagement.displayImage(request.reducing(surface), in: document) }
    // Preserve the original full-detail preview on canvases admitted by the old sky workspace.
    if surface.width <= SkyReplacement.denseMaximumPixels / surface.height {
      return try ColorManagement.displayImage(surface, in: document)
    }
    let overview = try RasterPreviewRequest.overview(width: surface.width, height: surface.height)
    return try ColorManagement.displayImage(overview.reducing(surface), in: document)
  }
}
