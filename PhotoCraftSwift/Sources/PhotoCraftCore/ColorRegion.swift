import Foundation

public struct ColorMatchOptions: Equatable, Sendable {
  public var sampleSize = 1
  public var tolerance = 32
  public var contiguous = true
  public var antiAlias = true
  public init() {}
  public func validate() throws {
    guard ColorSampleSettings.sizes.contains(sampleSize) else {
      throw CraftError.invalid("Choose Point Sample or a supported average size.")
    }
    guard (0...255).contains(tolerance) else {
      throw CraftError.invalid("Tolerance must be between 0 and 255.")
    }
  }
}

/// PhotoCraft's RGBA8 color comparison and span flood. Matching is deliberately
/// quantized to eight bits even when the edited document has higher precision.
public enum ColorRegion {
  public static func selection(
    source: CloneSample, width: Int, height: Int, seed: PathPoint,
    options: ColorMatchOptions, mask: Bool = false
  ) throws -> SelectionMask {
    try selection(source: source, width: width, height: height, seed: seed,
      options: options, mask: mask, densePixelLimit: Surface.maximumDensePixels)
  }

  static func selection(
    source: CloneSample, width: Int, height: Int, seed: PathPoint,
    options: ColorMatchOptions, mask: Bool = false, densePixelLimit: Int
  ) throws -> SelectionMask {
    _ = try Surface(width: width, height: height)
    try options.validate()
    try Task.checkCancellation()
    guard seed.x.isFinite, seed.y.isFinite,
      abs(seed.x) <= 1_000_000, abs(seed.y) <= 1_000_000,
      source.outside.isFinite, (0...1).contains(source.outside.a)
    else { throw CraftError.invalid("Invalid color sample.") }
    try source.surface.validated()
    let projection = try ColorRegionProjection(source: source, width: width, height: height, mask: mask)
    let sx = Int(floor(seed.x))
    let sy = Int(floor(seed.y))
    guard projection.canvas.contains(sx, sy) else {
      return try constantCoverage(width: width, height: height, selected: false)
    }
    if options.tolerance == 255 || projection.hasUniformSample {
      return try constantCoverage(width: width, height: height, selected: true)
    }
    if width > densePixelLimit / height {
      return try pagedSelection(projection: projection, seedX: sx, seedY: sy, options: options)
    }
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: width * height)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        pixels[y * width + x] = projection.sample(x, y)
      }
    }
    return try selection(
      pixels: pixels, width: width, height: height,
      seedX: sx, seedY: sy, options: options)
  }

  static func constantCoverage(width: Int, height: Int, selected: Bool) throws -> SelectionMask {
    let surface = try Surface(width: width, height: height, fill: selected ? .white : .black)
    return try SelectionMask(paged: PagedSelectionCoverage(quantized: surface))
  }

  static func matchTarget(width: Int, height: Int, seedX: Int, seedY: Int, size: Int,
    sample: (Int, Int) -> SIMD4<UInt8>
  ) throws -> SIMD4<UInt8> {
    if size == 1 { return sample(seedX, seedY) }
    let area = try ColorAveraging.region(x: Double(seedX), y: Double(seedY),
      width: width, height: height, size: size)
    var sum = SIMD4<Int>(repeating: 0)
    for y in area.y..<(area.y + area.height) {
      try Task.checkCancellation()
      for x in area.x..<(area.x + area.width) {
        let p = sample(x, y)
        sum.x += Int(p.x); sum.y += Int(p.y); sum.z += Int(p.z); sum.w += Int(p.w)
      }
    }
    let count = area.width * area.height
    return SIMD4(UInt8((sum.x + count / 2) / count), UInt8((sum.y + count / 2) / count),
      UInt8((sum.z + count / 2) / count), UInt8((sum.w + count / 2) / count))
  }

  static func matches(_ pixel: SIMD4<UInt8>, _ target: SIMD4<UInt8>, tolerance: Int) -> Bool {
    abs(Int(pixel.x) - Int(target.x)) <= tolerance
      && abs(Int(pixel.y) - Int(target.y)) <= tolerance
      && abs(Int(pixel.z) - Int(target.z)) <= tolerance
      && abs(Int(pixel.w) - Int(target.w)) <= tolerance
  }

  static func edgeCoverage(selected: Bool, count: Int) -> UInt8 {
    let average = Float(count * 255) / (9 * 255)
    let coverage: Float = selected ? 0.5 + 0.5 * average : 0.5 * average
    return UInt8((coverage * 255).rounded())
  }

  public static func selection(
    pixels: [SIMD4<UInt8>], width: Int, height: Int, seedX: Int, seedY: Int,
    options: ColorMatchOptions
  ) throws -> SelectionMask {
    _ = try Surface(width: width, height: height)
    try options.validate()
    try Task.checkCancellation()
    guard pixels.count == width * height else {
      throw CraftError.invalid("Invalid color sample dimensions.")
    }
    var marks = [UInt8](repeating: 0, count: pixels.count)
    guard seedX >= 0, seedY >= 0, seedX < width, seedY < height else {
      return try SelectionMask(width: width, height: height, bytes: marks)
    }
    let target = try matchTarget(width: width, height: height, seedX: seedX, seedY: seedY,
      size: options.sampleSize) { x, y in pixels[y * width + x] }
    func similar(_ index: Int) -> Bool {
      matches(pixels[index], target, tolerance: options.tolerance)
    }
    var bx0 = width
    var by0 = height
    var bx1 = -1
    var by1 = -1
    if options.contiguous {
      // One span seed, rather than a queued entry for every pixel. Connectivity
      // is four-way, including at diagonal corners and across transparent pixels.
      var stack = [seedY * width + seedX]
      while let index = stack.popLast() {
        try Task.checkCancellation()
        if marks[index] != 0 || !similar(index) { continue }
        let y = index / width
        let x = index % width
        let row = y * width
        var left = x
        var right = x
        while left > 0 && marks[row + left - 1] == 0 && similar(row + left - 1) { left -= 1 }
        while right + 1 < width && marks[row + right + 1] == 0 && similar(row + right + 1) {
          right += 1
        }
        for nx in left...right { marks[row + nx] = 255 }
        bx0 = min(bx0, left)
        bx1 = max(bx1, right)
        by0 = min(by0, y)
        by1 = max(by1, y)
        for ny in [y - 1, y + 1] where ny >= 0 && ny < height {
          var inRun = false
          for nx in left...right {
            let i = ny * width + nx
            let ok = marks[i] == 0 && similar(i)
            if ok && !inRun { stack.append(i) }
            inRun = ok
          }
        }
      }
    } else {
      for y in 0..<height {
        try Task.checkCancellation()
        for x in 0..<width where similar(y * width + x) {
          marks[y * width + x] = 255
          bx0 = min(bx0, x)
          bx1 = max(bx1, x)
          by0 = min(by0, y)
          by1 = max(by1, y)
        }
      }
    }
    if options.antiAlias && bx1 >= bx0 {
      var output = marks
      for y in max(0, by0 - 1)..<min(height, by1 + 2) {
        try Task.checkCancellation()
        for x in max(0, bx0 - 1)..<min(width, bx1 + 2) {
          let value = marks[y * width + x]
          var sum = 0
          var edge = false
          for dy in -1...1 {
            for dx in -1...1 {
              let nx = x + dx
              let ny = y + dy
              let n =
                nx < 0 || ny < 0 || nx >= width || ny >= height
                ? value : marks[ny * width + nx]
              sum += Int(n)
              edge = edge || n != value
            }
          }
          if edge {
            output[y * width + x] = edgeCoverage(selected: value > 127, count: sum / 255)
          }
        }
      }
      marks = output
    }
    try Task.checkCancellation()
    return try SelectionMask(width: width, height: height, bytes: marks)
  }
}
