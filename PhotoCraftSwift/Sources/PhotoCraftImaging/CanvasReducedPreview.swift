import CoreGraphics
import Foundation
import PhotoCraftCore

/// Area-filtered SDR presentation at display-pixel resolution. The filter's phase
/// is fixed to document coordinates, so regional and complete updates agree exactly.
/// This changes only the minified canvas presentation, never working/export pixels.
public struct CanvasReducedPreview: Sendable {
  public let image: CGImage
  let bytes: Data
  let sourceWidth: Int
  let sourceHeight: Int

  static func make(image source: CGImage, bytes: Data?, scale: Double,
    damage: RenderSnapshot.Update, previous: Self?) throws -> Self? {
    guard scale.isFinite, scale > 0, scale < 1, let bytes,
      source.bitsPerComponent == 8, source.bitsPerPixel == 32,
      source.bytesPerRow == source.width * 4, bytes.count == source.bytesPerRow * source.height
    else { return nil }
    let width = max(1, Int(ceil(Double(source.width) * scale)))
    let height = max(1, Int(ceil(Double(source.height) * scale)))
    guard width < source.width || height < source.height else { return nil }
    let prior = previous.flatMap { $0.sourceWidth == source.width && $0.sourceHeight == source.height
      && $0.image.width == width && $0.image.height == height ? $0 : nil }
    if case .unchanged = damage, let prior { return prior }
    let sx = Double(source.width) / Double(width), sy = Double(source.height) / Double(height)
    var bounds = IntRect(x: 0, y: 0, width: width, height: height)
    if let _ = prior, case .region(let r) = damage {
      // One conservative pixel protects floating-point boundaries of the area filter.
      let left = max(0, Int(floor(Double(r.x) / sx)) - 1)
      let top = max(0, Int(floor(Double(r.y) / sy)) - 1)
      let right = min(width, Int(ceil(Double(r.x + r.width) / sx)) + 1)
      let bottom = min(height, Int(ceil(Double(r.y + r.height) / sy)) + 1)
      bounds = IntRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
    }
    var output = prior?.bytes ?? Data(count: width * height * 4)
    let stepX = source.width / width, stepY = source.height / height
    let integral = source.width % width == 0 && source.height % height == 0
      && stepX <= 65_535 / stepY
    try output.withUnsafeMutableBytes { (target: UnsafeMutableRawBufferPointer) in
      try bytes.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
        if integral {
          try renderIntegral(input, sourceWidth: source.width, target: target, width: width,
            bounds: bounds, stepX: stepX, stepY: stepY)
          return
        }
        for y in bounds.y..<bounds.y + bounds.height {
          try Task.checkCancellation()
          let top = Double(y) * sy, bottom = Double(y + 1) * sy
          for x in bounds.x..<bounds.x + bounds.width {
            let left = Double(x) * sx, right = Double(x + 1) * sx
            var a = 0.0, red = 0.0, green = 0.0, blue = 0.0
            for iy in Int(floor(top))..<min(source.height, Int(ceil(bottom))) {
              let wy = min(bottom, Double(iy + 1)) - max(top, Double(iy))
              for ix in Int(floor(left))..<min(source.width, Int(ceil(right))) {
                let weight = wy * (min(right, Double(ix + 1)) - max(left, Double(ix)))
                let offset = (iy * source.width + ix) * 4
                let alpha = Double(input[offset + 3]) * weight
                a += alpha; red += Double(input[offset]) * alpha
                green += Double(input[offset + 1]) * alpha; blue += Double(input[offset + 2]) * alpha
              }
            }
            let offset = (y * width + x) * 4
            target[offset] = a > 0 ? byte(red / a) : 0
            target[offset + 1] = a > 0 ? byte(green / a) : 0
            target[offset + 2] = a > 0 ? byte(blue / a) : 0
            target[offset + 3] = byte(a / (sx * sy))
          }
        }
      }
    }
    try Task.checkCancellation()
    guard let provider = CGDataProvider(data: output as CFData),
      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: try RasterIO.colorSpace(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
        decode: nil, shouldInterpolate: true, intent: .relativeColorimetric)
    else { throw CraftError.invalid("Could not create the reduced canvas preview.") }
    return Self(image: image, bytes: output, sourceWidth: source.width, sourceHeight: source.height)
  }

  /// Whole-pixel boxes have unit weights. All sums in the generic Double loop
  /// are exact integers here, and at most 65,535 samples fit in the UInt32 lanes.
  private static func renderIntegral(_ input: UnsafeRawBufferPointer, sourceWidth: Int,
    target: UnsafeMutableRawBufferPointer, width: Int, bounds: IntRect,
    stepX: Int, stepY: Int) throws {
    let area = Double(stepX * stepY), rowStride = sourceWidth * 4
    for y in bounds.y..<bounds.y + bounds.height {
      try Task.checkCancellation()
      let firstRow = y * stepY * rowStride
      for x in bounds.x..<bounds.x + bounds.width {
        let first = firstRow + x * stepX * 4
        var sum = SIMD4<UInt32>.zero
        for row in 0..<stepY {
          let offset = first + row * rowStride
          for column in 0..<stepX {
            let packed = input.loadUnaligned(fromByteOffset: offset + column * 4, as: SIMD4<UInt8>.self)
            let a = UInt32(packed.w)
            let rgb = SIMD4(UInt32(packed.x), UInt32(packed.y), UInt32(packed.z), 1)
            sum &+= rgb &* SIMD4(repeating: a)
          }
        }
        let offset = (y * width + x) * 4
        let alpha = Double(sum.w)
        target[offset] = alpha > 0 ? byte(Double(sum.x) / alpha) : 0
        target[offset + 1] = alpha > 0 ? byte(Double(sum.y) / alpha) : 0
        target[offset + 2] = alpha > 0 ? byte(Double(sum.z) / alpha) : 0
        target[offset + 3] = byte(alpha / area)
      }
    }
  }

  @inline(__always)
  private static func byte(_ value: Double) -> UInt8 {
    UInt8(min(255, max(0, value.rounded())))
  }
}
