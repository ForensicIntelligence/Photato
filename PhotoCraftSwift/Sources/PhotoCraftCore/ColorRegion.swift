import Foundation

public struct ColorMatchOptions: Equatable, Sendable {
  public var tolerance = 32
  public var contiguous = true
  public var antiAlias = true
  public init() {}
  public func validate() throws {
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
    _ = try Surface(width: width, height: height)
    try options.validate()
    guard seed.x.isFinite, seed.y.isFinite,
      abs(seed.x) <= 1_000_000, abs(seed.y) <= 1_000_000,
      source.outside.isFinite, (0...1).contains(source.outside.a)
    else { throw CraftError.invalid("Invalid color sample.") }
    try source.surface.validated()
    let inverse = try source.transform.inverted()
    let nearest =
      inverse.a == 1 && inverse.d == 1 && inverse.b == 0 && inverse.c == 0
      && inverse.tx.rounded() == inverse.tx && inverse.ty.rounded() == inverse.ty
    let sx = Int(floor(seed.x))
    let sy = Int(floor(seed.y))
    guard sx >= 0, sy >= 0, sx < width, sy < height else {
      return try SelectionMask(
        width: width, height: height,
        bytes: [UInt8](repeating: 0, count: width * height))
    }
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: width * height)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let p = inverse.point(Double(x) + 0.5, Double(y) + 0.5)
        let value = ClonePainter.sample(
          source.surface, x: p.x, y: p.y,
          nearest: nearest, linear: source.surface.depth == .f32 && !mask,
          outside: source.outside, grayscale: mask)
        func q(_ f: Float) -> UInt8 { UInt8((unit(f) * 255).rounded()) }
        pixels[y * width + x] = SIMD4(q(value.r), q(value.g), q(value.b), q(value.a))
      }
    }
    return try selection(
      pixels: pixels, width: width, height: height,
      seedX: sx, seedY: sy, options: options)
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
    let target = pixels[seedY * width + seedX]
    let tolerance = options.tolerance
    func similar(_ index: Int) -> Bool {
      let p = pixels[index]
      return abs(Int(p.x) - Int(target.x)) <= tolerance
        && abs(Int(p.y) - Int(target.y)) <= tolerance
        && abs(Int(p.z) - Int(target.z)) <= tolerance
        && abs(Int(p.w) - Int(target.w)) <= tolerance
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
        if marks[index] != 0 { continue }
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
            let avg = Float(sum) / (9 * 255)
            let f: Float = value > 127 ? 0.5 + 0.5 * avg : 0.5 * avg
            output[y * width + x] = UInt8((f * 255).rounded())
          }
        }
      }
      marks = output
    }
    try Task.checkCancellation()
    return try SelectionMask(width: width, height: height, bytes: marks)
  }
}
