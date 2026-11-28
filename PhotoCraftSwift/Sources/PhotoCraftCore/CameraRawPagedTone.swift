import Foundation

extension CameraRawEngine {
  private typealias Plane = CameraRawScalarPlane

  static func usesLocalLight(_ s: CameraRawSettings) -> Bool { s.highlights != 0 || s.shadows != 0 }
  static func usesLocalTone(_ s: CameraRawSettings) -> Bool {
    usesLocalLight(s) || s.clarity != 0 || s.texture != 0
  }
  static func usesBaseTone(_ s: CameraRawSettings) -> Bool {
    usesLocalTone(s) || s.contrast != 0 || s.whites != 0 || s.blacks != 0
  }

  static func localLightRadius(_ longSide: Float) -> Int { max(2, Int(longSide * 0.015)) }
  static func localClarityRadius(_ longSide: Float) -> Int { max(3, Int(longSide * 0.02)) }
  static func localTextureSigma(_ longSide: Float, _ s: CameraRawSettings) -> Float {
    max(longSide * 0.002, 1.5 * s.pixelScale)
  }

  static func tonedPixel(_ pixel: RGB, luma: Float, clipped: Float, base: Float,
    clarity: Float, texture: Float, settings s: CameraRawSettings) -> RGB {
    let highlights = M.smooth(0.45, 0.95, base), shadows = 1 - M.smooth(0.05, 0.5, base)
    var value = clipped * pow(2, s.highlights / 100 * 1.2 * highlights + s.shadows / 100 * 1.4 * shadows)
    let middle = 2 * unit(value) - 1
    value += s.clarity / 100 * 0.8 * (clipped - clarity) * (1 - middle * middle)
    value += s.texture / 100 * 0.9 * min(0.1, max(-0.1, clipped - texture))
    value += s.whites / 100 * 0.25 * M.smooth(0.4, 1, value)
    value += s.blacks / 100 * 0.15 * (1 - M.smooth(0, 0.45, value))
    value -= s.contrast / 100 * 0.6 * sin(2 * Float.pi * unit(value)) / (2 * Float.pi)
    value = max(0, value) + (luma - clipped)
    return luma > 1e-5 ? pixel * (value / luma) : pixel + RGB(repeating: value - luma)
  }

  static func writePagedRGB(_ source: Surface, writing write: (([SIMD4<Float>]) throws -> Void) throws -> Void)
    throws -> FileBackedSource {
    let bytes = source.width * source.height * MemoryLayout<SIMD4<Float>>.stride
    return try FileBackedSource.writing(maximumBytes: bytes) { url in
      let writer = try AtomicFileWriter(to: url, maximumBytes: bytes)
      try write { try writer.append($0.withUnsafeBytes { Data($0) }) }
      try writer.commit()
    }
  }

  static func preparePagedRGB(_ source: Surface, settings s: CameraRawSettings,
    consume: (Int, [RGB]) throws -> Void) throws {
    let w = source.width, h = source.height, side = Surface.tileSide
    guard usesLocalTone(s) else {
      for top in stride(from: 0, to: h, by: side) {
        let band = try source.cropped(to: IntRect(x: 0, y: top, width: w, height: min(side, h - top)))
        try consume(top, prepareRGB(band, settings: s))
      }
      return
    }

    let exposed = try writePagedRGB(source) { append in
      for top in stride(from: 0, to: h, by: side) {
        try Task.checkCancellation()
        let band = try source.cropped(to: IntRect(x: 0, y: top, width: w, height: min(side, h - top)))
        try append(exposedRGB(band, settings: s).map { pixel in
          SIMD4(pixel.x, pixel.y, pixel.z, max(M.luma(pixel), 0))
        })
      }
    }

    let longSide = Float(max(w, h))
    try exposed.data.withUnsafeBytes { raw in
      let pixels = raw.bindMemory(to: SIMD4<Float>.self)
      let clipped = try Plane(width: w, height: h, values: { min(pixels[$0].w, 1) })
      let base = usesLocalLight(s) ? try clipped.guidedSelf(radius: localLightRadius(longSide), epsilon: 0.02) : clipped
      let clarity = s.clarity != 0 ? try clipped.guidedSelf(radius: localClarityRadius(longSide), epsilon: 0.005) : clipped
      let texture = s.texture != 0 ? try clipped.gaussian(sigma: localTextureSigma(longSide, s)) : clipped
      try base.withSamples { base in
        try clarity.withSamples { clarity in
          try texture.withSamples { texture in
            for top in stride(from: 0, to: h, by: side) {
              try Task.checkCancellation()
              let rows = min(side, h - top)
              var band = (top * w..<(top + rows) * w).map { i in
                let p = pixels[i]
                return tonedPixel(RGB(p.x, p.y, p.z), luma: p.w, clipped: min(p.w, 1), base: base[i],
                  clarity: clarity[i], texture: texture[i], settings: s)
              }
              try color(&band, s, w)
              try consume(top, band)
            }
          }
        }
      }
    }
  }

  static func developPagedTone(_ source: Surface, settings s: CameraRawSettings) throws -> Surface {
    let w = source.width, h = source.height
    let paged = try Surface.PagedBuilder(width: w, height: h, depth: source.depth,
      fill: source.defaultPixel, colorEncoding: source.colorEncoding)
    try preparePagedRGB(source, settings: s) { top, toned in
      let sourceBand = try source.cropped(to: IntRect(x: 0, y: top, width: w, height: toned.count / w))
      var pixels = toned
      let developed = try finishBand(&pixels, source: sourceBand, settings: s, canvasHeight: h, top: top)
      try paged.append(developed, atX: 0, atY: top)
    }
    return try paged.finish()
  }
}
