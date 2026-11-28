import Foundation

extension CameraRawEngine {
  private typealias DetailPlane = CameraRawScalarPlane

  private static func prepareDetailPlanes(_ source: Surface, settings: CameraRawSettings) throws
    -> (luma: DetailPlane, cb: DetailPlane, cr: DetailPlane) {
    let w = source.width, h = source.height
    let scratch = try writePagedRGB(source) { append in
      try preparePagedRGB(source, settings: settings) { _, pixels in
        try append(pixels.map { pixel in
          let luma = M.luma(pixel)
          return SIMD4(luma, pixel.z - luma, pixel.x - luma, 0)
        })
      }
    }
    return try scratch.data.withUnsafeBytes { bytes in
      let samples = bytes.bindMemory(to: SIMD4<Float>.self)
      return (try DetailPlane(width: w, height: h, values: { samples[$0].x }),
        try DetailPlane(width: w, height: h, values: { samples[$0].y }),
        try DetailPlane(width: w, height: h, values: { samples[$0].z }))
    }
  }

  static func developPagedDetail(_ source: Surface, settings s: CameraRawSettings) throws -> Surface {
    let w = source.width, h = source.height, side = Surface.tileSide
    let detail = DetailSettings(s)
    var (luma, cb, cr) = try prepareDetailPlanes(source, settings: s)
    if s.noiseLuminance > 0 {
      luma = try luma.mixing(luma.guidedSelf(radius: detail.luminanceRadius, epsilon: detail.luminanceEpsilon),
        keeping: detail.luminanceKeep)
    }
    if s.noiseColor > 0 {
      cb = try cb.mixing(cb.gaussian(sigma: detail.colorSigma), keeping: detail.colorKeep)
      cr = try cr.mixing(cr.gaussian(sigma: detail.colorSigma), keeping: detail.colorKeep)
    }
    if s.sharpenAmount > 0 {
      let blur = try luma.gaussian(sigma: detail.sharpenSigma)
      let mask = s.sharpenMasking > 0 ? try luma.gaussian(sigma: detail.maskSigma) : luma
      luma = try luma.withSamples { y in
        try blur.withSamples { smooth in
          try mask.withSamples { mask in
            try DetailPlane(width: w, height: h, values: { i in
              detail.sharpen(y[i], blurred: smooth[i], index: i, width: w, height: h, mask: mask)
            })
          }
        }
      }
    }

    let paged = try Surface.PagedBuilder(width: w, height: h, depth: source.depth,
      fill: source.defaultPixel, colorEncoding: source.colorEncoding)
    return try luma.withSamples { y in
      try cb.withSamples { cb in
        try cr.withSamples { cr in
          for top in stride(from: 0, to: h, by: side) {
            try Task.checkCancellation()
            let rows = min(side, h - top)
            let band = try source.cropped(to: IntRect(x: 0, y: top, width: w, height: rows))
            var pixels = (top * w..<(top + rows) * w).map { detailRGB(luma: y[$0], cb: cb[$0], cr: cr[$0]) }
            let developed = try finishBand(&pixels, source: band, settings: s, canvasHeight: h, top: top)
            try paged.append(developed, atX: 0, atY: top)
          }
          return try paged.finish()
        }
      }
    }
  }
}
