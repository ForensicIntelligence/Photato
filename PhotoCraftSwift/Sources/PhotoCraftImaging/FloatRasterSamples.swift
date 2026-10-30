import CoreGraphics
import Foundation
import PhotoCraftCore

/// Avoid a premultiply/unpremultiply round trip for straight Float32 samples.
/// One reader retains one provider buffer while bounded regions are decoded.
enum FloatRasterSamples {
  static func surface(_ image: CGImage, space: CGColorSpace, region: IntRect? = nil) throws -> Surface? {
    try Reader(image, space: space)?.surface(region: region)
  }
  struct Reader {
    let data: Data
    let width: Int
    let height: Int
    let rowBytes: Int
    let channels: Int
    let hasAlpha: Bool
    let littleEndian: Bool
    init?(_ image: CGImage, space: CGColorSpace) throws {
      guard image.bitsPerComponent == 32, image.bitmapInfo.contains(.floatComponents),
        let source = image.colorSpace, source.model == .rgb, space.model == .rgb,
        image.decode == nil, !image.isMask else { return nil }
      if source != space {
        guard let a = source.copyICCData() as Data?, let b = space.copyICCData() as Data?, a == b else { return nil }
      }
      switch (image.alphaInfo,image.bitsPerPixel) {
      case (.last,128),(.noneSkipLast,128):channels=4
      case (.none,96):channels=3
      default:return nil
      }
      let order=image.bitmapInfo.intersection(.byteOrderMask)
      guard order == .byteOrder32Little || order == .byteOrder32Big else { return nil }
      width=image.width;height=image.height;rowBytes=image.bytesPerRow;hasAlpha=image.alphaInfo == .last;littleEndian=order == .byteOrder32Little
      guard width > 0,height > 0,rowBytes >= width * channels * 4,rowBytes <= Int.max/height else { throw CraftError.invalid("Invalid floating-point image layout.") }
      guard rowBytes * height <= 1_073_741_824 else { throw CraftError.unsupported("This Float32 ImageIO provider exceeds its1GiB source-buffer budget; streamed HDR input is not yet available.") }
      guard let bytes=image.dataProvider?.data as Data?, bytes.count >= (height-1)*rowBytes+width*channels*4 else { throw CraftError.invalid("Truncated floating-point image samples.") }
      data=bytes
    }
    func surface(region requested:IntRect?=nil)throws->Surface {
      let r=requested ?? IntRect(x:0,y:0,width:width,height:height)
      guard r.width>0,r.height>0,r == r.clipped(toWidth:width,height:height) else { throw CraftError.invalid("Invalid floating-point import region.") }
      var result=try Surface(width:r.width,height:r.height,depth:.f32,colorEncoding:.linearRGB)
      try data.withUnsafeBytes { bytes in
        func sample(_ offset:Int)->Float {
          let bits=bytes.loadUnaligned(fromByteOffset:offset,as:UInt32.self)
          return Float(bitPattern:littleEndian ? UInt32(littleEndian:bits):UInt32(bigEndian:bits))
        }
        for y in r.y..<r.y+r.height {
          try Task.checkCancellation()
          for x in r.x..<r.x+r.width {
            let at=y*rowBytes+x*channels*4
            let p=Pixel(sample(at),sample(at+4),sample(at+8),hasAlpha ? sample(at+12):1)
            guard p.isFinite else { throw CraftError.invalid("Non-finite floating-point image samples.") }
            result.setLinearPixel(x:x-r.x,y:y-r.y,p)
          }
        }
      }
      return result
    }
  }
}
