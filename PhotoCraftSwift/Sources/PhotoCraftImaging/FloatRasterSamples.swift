import CoreGraphics
import Foundation
import PhotoCraftCore

/// Avoid a premultiply/unpremultiply round trip when the decoded image already
/// contains straight Float32 samples in the requested working colour space.
enum FloatRasterSamples {
  static func surface(_ image: CGImage, space: CGColorSpace) throws -> Surface? {
    guard image.bitsPerComponent == 32, image.bitmapInfo.contains(.floatComponents),
      let sourceSpace = image.colorSpace, sourceSpace.model == .rgb,
      space.model == .rgb, image.decode == nil,
      !image.isMask
    else { return nil }
    // ImageIO can return an extended-range space that is not CFEqual to the
    // same ICC profile reconstructed by ColorSync. Identical ICC bytes still
    // describe identical RGB coordinates; drawing would clip the HDR range.
    if sourceSpace != space {
      guard let sourceICC = sourceSpace.copyICCData() as Data?,
        let targetICC = space.copyICCData() as Data?, sourceICC == targetICC
      else { return nil }
    }
    let channels: Int
    switch (image.alphaInfo, image.bitsPerPixel) {
    case (.last, 128), (.noneSkipLast, 128): channels = 4
    case (.none, 96): channels = 3
    default: return nil
    }
    let order = image.bitmapInfo.intersection(.byteOrderMask)
    guard order == .byteOrder32Little || order == .byteOrder32Big else { return nil }
    var result = try Surface(
      width: image.width, height: image.height, depth: .f32, colorEncoding: .linearRGB)
    let rowBytes = image.width * channels * 4
    guard image.bytesPerRow >= rowBytes,
      image.bytesPerRow <= Int.max / image.height,
      let data = image.dataProvider?.data as Data?,
      data.count >= (image.height - 1) * image.bytesPerRow + rowBytes
    else { throw CraftError.invalid("Truncated floating-point image samples.") }
    try data.withUnsafeBytes { bytes in
      func sample(_ offset: Int) -> Float {
        let bits = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        return Float(bitPattern: order == .byteOrder32Little
          ? UInt32(littleEndian: bits) : UInt32(bigEndian: bits))
      }
      for y in 0..<image.height {
        try Task.checkCancellation()
        for x in 0..<image.width {
          let offset = y * image.bytesPerRow + x * channels * 4
          let p = Pixel(sample(offset), sample(offset + 4), sample(offset + 8),
            image.alphaInfo == .last ? sample(offset + 12) : 1)
          guard p.isFinite else {
            throw CraftError.invalid("Non-finite floating-point image samples.")
          }
          result.setLinearPixel(x: x, y: y, p)
        }
      }
    }
    return result
  }
}
