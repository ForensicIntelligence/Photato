import Accelerate
import Foundation

/// Preserve the legacy vDSP convolution's full row/column lengths. Accelerate
/// can choose a different accumulation order for shorter patch lines on Intel,
/// including at a final coverage-byte rounding boundary. A transposed scratch
/// plane allows both passes to stream row-major with at most64cached lines.
enum SkyMaskGaussian {
  static func apply(_ source: Surface, sigma: Float) throws -> Surface {
    try Task.checkCancellation()
    guard sigma.isFinite, (0...5).contains(sigma), source.depth == .u8,
      source.colorEncoding == .sRGB else { throw CraftError.invalid("Invalid sky Gaussian input.") }
    guard sigma >= 0.1, source.tileCount > 0 else { return source }
    let width = source.width, height = source.height, radius = Int(ceil(sigma * 3))
    var kernel = (-radius...radius).map { exp(-Float($0 * $0) / (2 * sigma * sigma)) }
    let total = kernel.reduce(0, +); kernel = kernel.map { $0 / total }
    func filtered(_ line: [Float]) throws -> [Float] {
      try Task.checkCancellation()
      let padded = Array(repeating: line[0], count: radius) + line + Array(repeating: line.last!, count: radius)
      var result = [Float](repeating: 0, count: line.count)
      vDSP_conv(padded, 1, kernel, 1, &result, 1, vDSP_Length(line.count), vDSP_Length(kernel.count))
      return result
    }
    let canvas = IntRect(x: 0, y: 0, width: width, height: height)
    let sparse = source.tileCount <= RasterGeometry.sparseGridSourceTileLimit
    let support = try sparse ? source.projectedGeometrySupport(.identity, bounds: canvas, halo: 0) : [canvas]
    let horizontalSupport = support.map { r in
      IntRect(x: r.x - radius, y: r.y, width: r.width + 2 * radius, height: r.height)
        .clipped(toWidth: width, height: height)
    }
    let background = source.defaultPixel.r
    let uniformRow = try filtered(Array(repeating: background, count: width))
    var rowCache: [Int: [Float]] = [:], cachedRow = -1
    func row(_ y: Int) throws -> [Float] {
      if let value = rowCache[y] { return value }
      let rectangles = support.filter { y >= $0.y && y < $0.y + $0.height }
      if rectangles.isEmpty { return uniformRow }
      var line = [Float](repeating: background, count: width)
      for r in rectangles { for x in r.x..<r.x + r.width { line[x] = source.pixel(x: x, y: y).r } }
      let value = try filtered(line); rowCache[y] = value; return value
    }
    // Green marks an explicitly calculated horizontal sample. Elsewhere a
    // column uses uniformRow[x], preserving even position-dependent Float bits
    // in Accelerate's otherwise-uniform horizontal result.
    let horizontalBuilder = try Surface.PagedBuilder(width: width, height: height, depth: .f32, fill: .black)
    for region in GeometryPatchRegions(width: width, height: height, rectangles: horizontalSupport) {
      try Task.checkCancellation()
      if cachedRow != region.y { rowCache.removeAll(keepingCapacity: true); cachedRow = region.y }
      var patch = try Surface(width: region.width, height: region.height, depth: .f32, fill: .black)
      for y in 0..<region.height {
        let values = try row(region.y + y)
        for x in 0..<region.width { patch.setPixel(x: x, y: y, Pixel(values[region.x + x], 1, 0)) }
      }
      try horizontalBuilder.append(patch, atX: region.x, atY: region.y)
    }
    let horizontal = try horizontalBuilder.finish()
    rowCache.removeAll(keepingCapacity: false)
    let horizontalBounds = horizontal.tileCount <= RasterGeometry.sparseGridSourceTileLimit
      ? try horizontal.projectedGeometrySupport(.identity, bounds: canvas, halo: 0) : [canvas]
    let transpose = Transform2D(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
    let transposedCanvas = IntRect(x: 0, y: 0, width: height, height: width)
    let transposedSupport = horizontal.tileCount <= RasterGeometry.sparseGridSourceTileLimit
      ? try horizontal.projectedGeometrySupport(transpose, bounds: transposedCanvas, halo: radius) : [transposedCanvas]
    var columnCache: [Int: [Float]] = [:], cachedColumn = -1
    func column(_ x: Int) throws -> [Float] {
      if let value = columnCache[x] { return value }
      var line = [Float](repeating: uniformRow[x], count: height)
      for r in horizontalBounds where x >= r.x && x < r.x + r.width {
        for y in r.y..<r.y + r.height {
          let value = horizontal.pixel(x: x, y: y)
          if value.g > 0 { line[y] = value.r }
        }
      }
      let value = try filtered(line); columnCache[x] = value; return value
    }
    let output = try Surface.PagedBuilder(width: height, height: width, depth: .u8,
      fill: Pixel(background, background, background))
    for region in GeometryPatchRegions(width: height, height: width, rectangles: transposedSupport) {
      try Task.checkCancellation()
      if cachedColumn != region.y { columnCache.removeAll(keepingCapacity: true); cachedColumn = region.y }
      var patch = try Surface(width: region.width, height: region.height, depth: .u8,
        fill: Pixel(background, background, background))
      for y in 0..<region.height {
        let values = try column(region.y + y)
        for x in 0..<region.width {
          let byte = UInt8(min(255, max(0, (values[region.x + x] * 255).rounded())))
          let v = Float(byte) / 255
          if v != background { patch.setPixel(x: x, y: y, Pixel(v, v, v)) }
        }
      }
      try output.append(patch, atX: region.x, atY: region.y)
    }
    return try RasterGeometry.render(output.finish(), transform: transpose, bounds: canvas, method: .nearest)
  }
}
