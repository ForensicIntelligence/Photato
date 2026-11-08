import Foundation
import PhotoCraftCore

struct ColorProfileRasterResult {
  let pixels: Surface
  let native: NativeModeRaster?
}

/// The original row transform is also the bounded patch kernel. Sparse defaults
/// and ordered stored tile streams avoid allocating or scanning the logical canvas.
struct ColorProfileRasterConversion {
  let request: ColorProfileRequest
  let depth: PixelDepth
  let sourceProfile: Data
  let sourceMode: DocumentColorMode
  let destination: DocumentColorMode
  let nativeOutput: Bool
  let transform: ProofTransform

  func apply(_ pixels: Surface, native: NativeModeRaster?) throws -> ColorProfileRasterResult {
    if pixels.width > NativeModeRaster.maximumPixels / pixels.height {
      return try paged(pixels, native: native)
    }
    return try dense(pixels, native: native)
  }

  func dense(_ pixels: Surface, native: NativeModeRaster?) throws -> ColorProfileRasterResult {
    try Task.checkCancellation()
    var output = try NativeModeRaster(width: pixels.width, height: pixels.height, mode: destination,
      depth: depth, profile: request.profile, intent: request.intent)
    for y in 0..<pixels.height {
      try Task.checkCancellation()
      var row: [Float] = []; row.reserveCapacity(pixels.width * sourceMode.componentCount)
      for x in 0..<pixels.width {
        if let native {
          var values = Array(native.components(index: y * pixels.width + x).prefix(sourceMode.componentCount))
          if sourceMode == .lab { values[1] *= 255 / 256; values[2] *= 255 / 256 }
          row += values
        } else {
          let p = depth == .f32 ? pixels.linearPixel(x: x, y: y) : pixels.pixel(x: x, y: y)
          row += [p.r, p.g, p.b]
        }
      }
      let converted = sourceProfile == request.profile && sourceMode == destination ? row : try transform.apply(row)
      for x in 0..<pixels.width {
        let at = y * pixels.width + x
        for c in 0..<destination.componentCount {
          let value = converted[x * destination.componentCount + c] * (destination == .lab && c > 0 ? 256 / 255 : 1)
          try output.set(value, component: c, index: at)
        }
        let alpha = native?.value(component: sourceMode.componentCount, index: at) ?? pixels.pixel(x: x, y: y).a
        try output.set(alpha, component: destination.componentCount, index: at)
      }
    }
    if nativeOutput { return .init(pixels: try output.surface(), native: output) }
    else {
      var surface = try Surface(width: pixels.width, height: pixels.height, depth: depth,
        colorEncoding: depth == .f32 ? .linearRGB : .sRGB)
      for y in 0..<surface.height { try Task.checkCancellation(); for x in 0..<surface.width {
        let values = output.components(index: y * surface.width + x), p = Pixel(values[0], values[1], values[2], values[3])
        if depth == .f32 { surface.setLinearPixel(x: x, y: y, p) } else { surface.setPixel(x: x, y: y, p) }
      } }
      return .init(pixels: surface, native: nil)
    }
  }

  func paged(_ pixels: Surface, native: NativeModeRaster?) throws -> ColorProfileRasterResult {
    try Task.checkCancellation()
    var sources = [pixels]
    if let native {
      for c in 0..<native.mode.componentCount { sources.append(try native.channel(c)) }
      sources.append(try native.opacityChannel())
    }
    // Reinterpret a raw Float default without an encode/decode round trip.
    let raw = try pixels.interpretingSamples(as: .sRGB).defaultPixel
    let constantPixels = try uniform(raw, width: 1, height: 1, encoding: pixels.colorEncoding)
    var constantNative: NativeModeRaster?
    if let native {
      var value = try NativeModeRaster(width: 1, height: 1, mode: native.mode,
        depth: depth, profile: native.profile, intent: native.intent)
      for c in 0...native.mode.componentCount {
        try value.set(sources[c + 1].defaultPixel.r, component: c, index: 0)
      }
      constantNative = value
    }
    let constant = try dense(constantPixels, native: constantNative)
    let fill = constant.pixels.colorEncoding == .linearRGB
      ? constant.pixels.linearPixel(x: 0, y: 0) : constant.pixels.pixel(x: 0, y: 0)
    let output = try Surface.PagedBuilder(template: uniform(fill, width: pixels.width,
      height: pixels.height, encoding: constant.pixels.colorEncoding))
    var components: [Surface.PagedBuilder] = []
    if let native = constant.native {
      for c in 0...destination.componentCount {
        let v = native.value(component: c, index: 0)
        components.append(try Surface.PagedBuilder(width: pixels.width, height: pixels.height,
          depth: depth, fill: Pixel(v, v, v), colorEncoding: .sRGB))
      }
    }
    let columns = (pixels.width + Surface.tileSide - 1) / Surface.tileSide
    var iterators = sources.map { $0.storedTileKeys.makeIterator() }
    var heads = iterators.indices.map { iterators[$0].next() }
    func nextKey() -> Int? {
      guard let first = heads.compactMap({ $0 }).min() else { return nil }
      for i in heads.indices where heads[i] == first { heads[i] = iterators[i].next() }
      return first
    }
    var next = nextKey()
    while let first = next {
      try Task.checkCancellation()
      let row = first / columns
      var end = first + 1
      next = nextKey()
      while let key = next, key == end, key / columns == row, end - first < 32 {
        end += 1; next = nextKey()
      }
      let x = first % columns * Surface.tileSide, y = row * Surface.tileSide
      let bounds = IntRect(x: x, y: y, width: min(pixels.width - x, (end - first) * Surface.tileSide),
        height: min(Surface.tileSide, pixels.height - y))
      let patch = try dense(pixels.cropped(to: bounds), native: native?.cropped(to: bounds))
      try output.append(patch.pixels, atX: x, atY: y)
      if let native = patch.native {
        for c in 0..<destination.componentCount {
          try components[c].append(native.channel(c), atX: x, atY: y)
        }
        try components[destination.componentCount].append(native.opacityChannel(), atX: x, atY: y)
      }
    }
    var resultNative: NativeModeRaster?
    if nativeOutput {
      var value = try NativeModeRaster(width: pixels.width, height: pixels.height, mode: destination,
        depth: depth, profile: request.profile, intent: request.intent)
      for c in 0..<destination.componentCount {
        value = try value.replacingChannel(c, with: components[c].finish())
      }
      value = try value.replacingOpacity(with: components[destination.componentCount].finish())
      resultNative = value
    }
    try Task.checkCancellation()
    return .init(pixels: try output.finish(), native: resultNative)
  }

  private func uniform(_ raw: Pixel, width: Int, height: Int,
    encoding: SurfaceColorEncoding) throws -> Surface {
    try Surface(width: width, height: height, depth: depth, fill: raw)
      .interpretingSamples(as: encoding)
  }
}
