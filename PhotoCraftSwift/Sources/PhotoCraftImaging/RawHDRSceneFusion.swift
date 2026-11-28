import Foundation
import PhotoCraftCore

/// Combines developed scene-linear exposure samples without fitting a display response curve.
enum RawHDRSceneFusion {
  struct Result: Sendable {
    let pixels: Surface
    let exposureEV: [Double]
    let offsets: [SIMD2<Int>]
    let ghostMask: CameraRawScalarPlane?
  }

  struct Bracket: Sendable {
    let pixels: Surface
    let exposure: Double
  }

  // A shoulder below the decoder's unit output limits the influence of clipped color components.
  private static let sensorShoulder: Float = 0.7

  static func merge(_ inputs: [Bracket], options: RawHDRMergeSettings,
    referenceExposure: Double? = nil, preferPaged: Bool = false) throws -> Result {
    guard RawHDRMerge.sourceCount.contains(inputs.count), let first = inputs.first else {
      throw CraftError.invalid("Select two to sixteen RAW exposures to merge.")
    }
    let width = first.pixels.width, height = first.pixels.height
    guard width <= RawHDRMerge.maximumPixels / height, width * height <= RawHDRMerge.maximumTotalPixels / inputs.count,
      inputs.allSatisfy({ $0.pixels.width == width && $0.pixels.height == height &&
        $0.pixels.depth == .f32 && $0.pixels.colorEncoding == .linearRGB &&
        $0.exposure.isFinite && $0.exposure > 0 })
    else { throw CraftError.invalid("The RAW exposure samples must have matching linear RGB dimensions and valid exposures.") }
    let order = inputs.indices.sorted { inputs[$0].exposure < inputs[$1].exposure }
    let reference = order[order.count / 2]
    let shortest = inputs[order[0]].exposure
    let relative = inputs.map { $0.exposure / shortest }
    guard relative.allSatisfy({ (1...1_099_511_627_776).contains($0) }) else {
      throw CraftError.invalid("The RAW bracket exceeds the supported 40-stop exposure span.")
    }
    let exposureEV = relative.map(log2)
    let normalization = relative.map { Float(relative[reference] / $0) }
    let globalGain = (referenceExposure ?? inputs[reference].exposure) / inputs[reference].exposure
    let maximumRatio: Double = 1_099_511_627_776
    guard globalGain.isFinite, (1 / maximumRatio...maximumRatio).contains(globalGain) else {
      throw CraftError.invalid("The panorama brackets exceed the supported 40-stop exposure span.")
    }
    let sceneGain = Float(globalGain)
    let offsets = options.align ? try align(inputs, reference: reference, normalization: normalization)
      : Array(repeating: .zero, count: inputs.count)
    let trackMotion = options.deghost != .off
    let movementRatio = Float(exp(options.deghost.threshold))
    let paged = preferPaged || width * height > Surface.maximumDensePixels
    func fusedSample(x: Int, y: Int) throws -> (pixel: Pixel, motion: Bool) {
      var sums = SIMD3<Float>.zero
      var weights = SIMD3<Float>.zero
      var fallback: SIMD3<Float>?
      var darkest = Float.infinity
      var brightest: Float = 0
      for index in order {
        guard let raw = sample(inputs[index].pixels, x: x, y: y, offset: offsets[index]) else { continue }
        let color = SIMD3<Float>(max(0, raw.r), max(0, raw.g), max(0, raw.b))
        let normalized = color * normalization[index]
        if fallback == nil { fallback = normalized }
        for channel in 0..<3 {
          let weight = max(0, min(color[channel], sensorShoulder - color[channel]))
          sums[channel] += normalized[channel] * weight
          weights[channel] += weight
        }
        if trackMotion, max(color.x, color.y, color.z) < sensorShoulder {
          let observed = luminance(color)
          if observed >= 0.015 {
            let linear = observed * normalization[index]
            darkest = min(darkest, linear)
            brightest = max(brightest, linear)
          }
        }
      }
      guard let fallback else { throw CraftError.unsupported("The aligned RAW brackets leave an uncovered part of the image.") }
      for channel in 0..<3 {
        sums[channel] = weights[channel] > 0 ? sums[channel] / weights[channel] : fallback[channel]
      }
      let motion = trackMotion && darkest.isFinite && brightest > darkest * movementRatio
      return (Pixel(sums.x * sceneGain, sums.y * sceneGain, sums.z * sceneGain, 1), motion)
    }

    guard trackMotion else {
      let fused = try Surface.linearBands(width: width, height: height, paged: paged) { top, rows in
        try Surface.linearPatch(width: width, height: rows) { x, y in try fusedSample(x: x, y: top + y).pixel }
      }
      return Result(pixels: fused, exposureEV: exposureEV, offsets: offsets, ghostMask: nil)
    }

    let maskBytes = width * height * MemoryLayout<Float>.stride
    var firstPass: Surface?
    var hasMotion = false
    let storage = try FileBackedSource.writing(maximumBytes: maskBytes) { url in
      let writer = try AtomicFileWriter(to: url, maximumBytes: maskBytes)
      defer { writer.discard() }
      firstPass = try Surface.linearBands(width: width, height: height, paged: true) { top, rows in
        var band = [Float](repeating: 0, count: width * rows)
        let patch = try Surface.linearPatch(width: width, height: rows) { x, y in
          let fused = try fusedSample(x: x, y: top + y)
          if fused.motion {
            band[y * width + x] = 1
            hasMotion = true
          }
          return fused.pixel
        }
        try writer.append(band.withUnsafeBytes { Data($0) })
        return patch
      }
      try writer.commit()
    }
    guard let firstPass else { throw CraftError.invalid("The HDR exposure blend was incomplete.") }
    let mask = try CameraRawScalarPlane(width: width, height: height, storage: storage)
    guard hasMotion else {
      return Result(pixels: firstPass, exposureEV: exposureEV, offsets: offsets, ghostMask: mask)
    }

    let smooth = try mask.gaussian(sigma: max(2, Float(max(width, height)) / 200))
    let anchor = inputs[reference].pixels
    let ghost = try smooth.withSamples { values in
      try CameraRawScalarPlane(width: width, height: height) { index in
        let strength = min(1, values[index] * 3)
        if strength > 0, sample(anchor, x: index % width, y: index / width, offset: .zero) == nil { return 0 }
        return strength
      }
    }
    let fused = try ghost.withSamples { values in
      try Surface.linearBands(width: width, height: height, paged: paged) { top, rows in
        try Surface.linearPatch(width: width, height: rows) { x, y in
          let row = top + y
          let amount = values[row * width + x]
          let existing = firstPass.linearPixel(x: x, y: row)
          guard amount > 0, let source = sample(anchor, x: x, y: row, offset: .zero) else { return existing }
          let referenceColor = SIMD3<Float>(max(0, source.r), max(0, source.g), max(0, source.b))
          let blended = existing.rgb * (1 - amount) + referenceColor * (amount * sceneGain)
          return Pixel(blended.x, blended.y, blended.z, 1)
        }
      }
    }
    return Result(pixels: fused, exposureEV: exposureEV, offsets: offsets, ghostMask: ghost)
  }

  private static func luminance(_ rgb: SIMD3<Float>) -> Float {
    0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
  }

  private static func sample(_ pixels: Surface, x: Int, y: Int, offset: SIMD2<Int>) -> Pixel? {
    let sx = x - offset.x, sy = y - offset.y
    guard sx >= 0, sy >= 0, sx < pixels.width, sy < pixels.height else { return nil }
    let pixel = pixels.linearPixel(x: sx, y: sy)
    return pixel.a > 0.99 ? pixel : nil
  }

  private static func align(_ inputs: [Bracket], reference: Int, normalization: [Float]) throws -> [SIMD2<Int>] {
    let anchor = inputs[reference].pixels
    let step = max(1, (max(anchor.width, anchor.height) + 1_199) / 1_200)
    let width = (anchor.width + step - 1) / step
    let height = (anchor.height + step - 1) / step
    func brightness(_ surface: Surface, multiplier: Float) throws -> [Float] {
      var proxy = [Float]()
      proxy.reserveCapacity(width * height)
      for y in 0..<height {
        try Task.checkCancellation()
        for x in 0..<width {
          let pixel = surface.linearPixel(x: min(x * step + step / 2, surface.width - 1),
            y: min(y * step + step / 2, surface.height - 1))
          proxy.append(min(1, max(0, luminance(pixel.rgb) * multiplier)))
        }
      }
      return proxy
    }
    let anchorProxy = try brightness(anchor, multiplier: 1)
    return try inputs.indices.map { index in
      guard index != reference else { return .zero }
      let moving = inputs[index].pixels
      let proxy = try brightness(moving, multiplier: normalization[index])
      let coarse = try HDRMergeMath.offset(width: width, height: height, reference: anchorProxy, image: proxy)
      let candidate = SIMD2(coarse.x * step, coarse.y * step)
      guard candidate != .zero else { return .zero }
      return try acceptedOffset(candidate, anchor: anchor, moving: moving, normalization: normalization[index], step: step)
    }
  }

  private static func acceptedOffset(_ candidate: SIMD2<Int>, anchor: Surface, moving: Surface,
    normalization: Float, step: Int) throws -> SIMD2<Int> {
    let sampling = max(1, Int(sqrt(Double(anchor.width * anchor.height) / 8_192)))
    func error(_ offset: SIMD2<Int>) throws -> Double {
      var error = 0.0
      var hits = 0
      for y in stride(from: 0, to: anchor.height, by: sampling) {
        try Task.checkCancellation()
        for x in stride(from: 0, to: anchor.width, by: sampling) {
          guard let raw = sample(moving, x: x, y: y, offset: offset),
            let base = sample(anchor, x: x, y: y, offset: .zero) else { continue }
          let a = luminance(base.rgb), b = luminance(raw.rgb)
          guard (0.015...sensorShoulder).contains(a), (0.015...sensorShoulder).contains(b) else { continue }
          let aligned = b * normalization
          error += Double(abs(a - aligned) / max(0.1, a, aligned))
          hits += 1
        }
      }
      let expected = ((anchor.width + sampling - 1) / sampling) * ((anchor.height + sampling - 1) / sampling)
      guard hits >= max(12, expected / 20) else { return .infinity }
      return error / Double(hits)
    }
    let baseline = try error(.zero)
    var best = candidate
    var bestError = try error(best)
    if step > 1 {
      let half = max(1, step / 2)
      for dy in [-half, 0, half] {
        for dx in [-half, 0, half] where dx != 0 || dy != 0 {
          let refined = SIMD2(candidate.x + dx, candidate.y + dy)
          let score = try error(refined)
          if score < bestError { best = refined; bestError = score }
        }
      }
    }
    // Require a real improvement over the fixed camera position. Periodic motifs can
    // otherwise move the coarse estimator by a whole repeat even on a tripod.
    return bestError.isFinite && bestError + 0.003 < baseline * 0.95 ? best : .zero
  }
}
