import Foundation

/// One quantized document-space sample, shared with the ordinary dense path.
struct ColorRegionProjection {
  let source: CloneSample
  let canvas: IntRect
  private let inverse: Transform2D
  private let nearest: Bool
  private let mask: Bool
  private let linear: Bool

  init(source: CloneSample, width: Int, height: Int, mask: Bool) throws {
    self.source = source
    self.canvas = IntRect(x: 0, y: 0, width: width, height: height)
    self.mask = mask
    linear = source.surface.depth == .f32 && !mask
    let mapping = try source.transform.inverted()
    inverse = mapping
    nearest = mapping.a == 1 && mapping.d == 1 && mapping.b == 0 && mapping.c == 0
      && mapping.tx.rounded() == mapping.tx && mapping.ty.rounded() == mapping.ty
  }

  func sample(_ x: Int, _ y: Int) -> SIMD4<UInt8> {
    let p = inverse.point(Double(x) + 0.5, Double(y) + 0.5)
    return bytes(ClonePainter.sample(source.surface, x: p.x, y: p.y,
      nearest: nearest, linear: linear, outside: source.outside, grayscale: mask))
  }

  private func bytes(_ pixel: Pixel) -> SIMD4<UInt8> {
    func q(_ value: Float) -> UInt8 { UInt8((unit(value) * 255).rounded()) }
    return SIMD4(q(pixel.r), q(pixel.g), q(pixel.b), q(pixel.a))
  }

  private func constantSample(_ pixel: Pixel) -> SIMD4<UInt8> {
    let encoded = bytes(pixel)
    return mask ? SIMD4(encoded.x, encoded.x, encoded.x, 255) : encoded
  }

  /// Integral translations have an exact interior rectangle and constant
  /// exterior. Other transforms retain the general sampling path.
  private var interior: IntRect? {
    guard nearest else { return nil }
    let first = inverse.point(0.5, 0.5)
    let last = inverse.point(Double(canvas.width) - 0.5, Double(canvas.height) - 0.5)
    guard [first.x, first.y, last.x, last.y].allSatisfy({ $0.isFinite && abs($0) < 10_000_000 })
    else { return nil }
    let localX = Int(floor(first.x)), localY = Int(floor(first.y))
    return IntRect(x: -localX, y: -localY, width: source.surface.width, height: source.surface.height)
      .clipped(toWidth: canvas.width, height: canvas.height)
  }

  var hasUniformSample: Bool {
    guard source.surface.tileCount == 0, let interior else { return false }
    return interior == canvas || interior.width == 0 || interior.height == 0
      || constantSample(source.surface.defaultPixel) == constantSample(source.outside)
  }

  /// Restrict noncontiguous scans to stored source tiles when their implicit
  /// match agrees with the exterior, including the antialias halo.
  func noncontiguousSupport(
    antiAlias: Bool, matches: (SIMD4<UInt8>) -> Bool
  ) throws -> (implicit: Bool, regions: [IntRect]) {
    guard let interior else { return (false, [canvas]) }
    let inside = matches(constantSample(source.surface.defaultPixel))
    let outside = matches(constantSample(source.outside))
    let halo = antiAlias ? 1 : 0
    if interior.width == 0 || interior.height == 0 { return (outside, []) }
    if (inside == outside || interior == canvas),
      source.surface.tileCount <= RasterGeometry.sparseGridSourceTileLimit {
      let support = try source.surface.projectedGeometrySupport(source.transform, bounds: canvas, halo: halo)
      return (inside, support)
    }
    if !outside { return (false, [expanded(interior, halo: halo)]) }
    return (inside && outside, [canvas])
  }

  func expanded(_ region: IntRect, halo: Int) -> IntRect {
    IntRect(x: region.x - halo, y: region.y - halo,
      width: region.width + 2 * halo, height: region.height + 2 * halo)
      .clipped(toWidth: canvas.width, height: canvas.height)
  }
}

extension ColorRegion {
  static func pagedSelection(projection: ColorRegionProjection, seedX: Int, seedY: Int,
    options: ColorMatchOptions
  ) throws -> SelectionMask {
    let width = projection.canvas.width, height = projection.canvas.height
    let target = try matchTarget(width: width, height: height, seedX: seedX, seedY: seedY,
      size: options.sampleSize, sample: projection.sample)
    func matchesSample(_ pixel: SIMD4<UInt8>) -> Bool {
      matches(pixel, target, tolerance: options.tolerance)
    }
    func selected(_ x: Int, _ y: Int) -> Bool { matchesSample(projection.sample(x, y)) }
    if options.contiguous {
      guard selected(seedX, seedY) else {
        return try constantCoverage(width: width, height: height, selected: false)
      }
      let marks = try ColorRegionMarks()
      let box = try flood(width: width, height: height, seed: seedY * width + seedX, marks: marks, matches: selected)
      let support = projection.expanded(box, halo: options.antiAlias ? 1 : 0)
      return try coverage(width: width, height: height, regions: [support], implicit: false,
        antiAlias: options.antiAlias) { x, y in try marks.contains(y * width + x) }
    }
    let support = try projection.noncontiguousSupport(antiAlias: options.antiAlias, matches: matchesSample)
    return try coverage(width: width, height: height, regions: support.regions, implicit: support.implicit,
      antiAlias: options.antiAlias, selected: selected)
  }

  private static func flood(width: Int, height: Int, seed: Int, marks: ColorRegionMarks,
    matches: (Int, Int) -> Bool
  ) throws -> IntRect {
    let work = try ColorRegionWorklist(seed: seed)
    var x0 = width, y0 = height, x1 = 0, y1 = 0
    while let index = try work.pop() {
      try Task.checkCancellation()
      guard try !marks.contains(index) else { continue }
      let x = index % width, y = index / width, row = y * width
      var left = x, right = x
      while try left > 0 && !marks.contains(row + left - 1) && matches(left - 1, y) { left -= 1 }
      while try right + 1 < width && !marks.contains(row + right + 1) && matches(right + 1, y) { right += 1 }
      try marks.insert((row + left)...(row + right))
      x0 = min(x0, left); x1 = max(x1, right + 1)
      y0 = min(y0, y); y1 = max(y1, y + 1)
      for ny in [y - 1, y + 1] where ny >= 0 && ny < height {
        var inRun = false
        for nx in left...right {
          let next = ny * width + nx
          let eligible = try !marks.contains(next) && matches(nx, ny)
          if eligible && !inRun { try work.push(next) }
          inRun = eligible
        }
      }
    }
    return IntRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
  }

  private static func coverage(width: Int, height: Int, regions: [IntRect], implicit: Bool,
    antiAlias: Bool, selected: (Int, Int) throws -> Bool
  ) throws -> SelectionMask {
    guard !regions.isEmpty else { return try constantCoverage(width: width, height: height, selected: implicit) }
    let background: Pixel = implicit ? .white : .black
    let builder = try Surface.PagedBuilder(width: width, height: height, fill: background)
    let canvas = IntRect(x: 0, y: 0, width: width, height: height)
    let halo = antiAlias ? 1 : 0
    for patch in GeometryPatchRegions(width: width, height: height, rectangles: regions) {
      let stride = patch.width + 2 * halo
      var bits = [Bool](repeating: false, count: stride * (patch.height + 2 * halo))
      for y in -halo..<(patch.height + halo) {
        try Task.checkCancellation()
        for x in -halo..<(patch.width + halo) where canvas.contains(patch.x + x, patch.y + y) {
          bits[(y + halo) * stride + x + halo] = try selected(patch.x + x, patch.y + y)
        }
      }
      var surface = try Surface(width: patch.width, height: patch.height, fill: background)
      for y in 0..<patch.height {
        try Task.checkCancellation()
        for x in 0..<patch.width {
          let center = (y + halo) * stride + x + halo
          let value = bits[center]
          var byte: UInt8 = value ? 255 : 0
          if antiAlias {
            var total = 0
            for dy in -1...1 {
              for dx in -1...1 {
                let neighbor = canvas.contains(patch.x + x + dx, patch.y + y + dy)
                  ? bits[center + dy * stride + dx] : value
                if neighbor { total += 1 }
              }
            }
            byte = edgeCoverage(selected: value, count: total)
          }
          if byte != (implicit ? 255 : 0) {
            let sample = Float(byte) / 255
            surface.setPixel(x: x, y: y, Pixel(sample, sample, sample))
          }
        }
      }
      try builder.append(surface, atX: patch.x, atY: patch.y)
    }
    return try SelectionMask(paged: PagedSelectionCoverage(quantized: builder.finish()))
  }
}
