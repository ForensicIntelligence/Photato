import CoreGraphics
import Foundation
import PhotoCraftCore

extension RasterIO {
  /// Bounded conversion patches. ImageIO may retain its own decoded input/cache;
  /// Photato does not allocate a complete Float32 RGBA conversion raster.
  public static func pagedSurface(_ image: CGImage, depth: PixelDepth = .u8,
    space: CGColorSpace? = nil, colorEncoding: SurfaceColorEncoding = .sRGB,
    backing: RasterTileStore? = nil) throws -> Surface {
    let target = try space ?? colorSpace()
    let direct = depth == .f32 && colorEncoding == .linearRGB ? try FloatRasterSamples.Reader(image, space: target) : nil
    return try pagedRaster(width: image.width, height: image.height, depth: depth,
      colorEncoding: colorEncoding, backing: backing) { region in
      if let direct { return try direct.surface(region: region) }
      guard let crop = image.cropping(to: CGRect(x: region.x, y: region.y, width: region.width, height: region.height))
      else { throw CraftError.invalid("Could not decode an image patch.") }
      return try surface(crop, depth: depth, space: target, colorEncoding: colorEncoding)
    }
  }

  static func pagedRaster(width: Int, height: Int, depth: PixelDepth,
    colorEncoding: SurfaceColorEncoding, fill: Pixel = .clear, backing: RasterTileStore? = nil,
    patch: (IntRect) throws -> Surface) throws -> Surface {
    let builder = try Surface.PagedBuilder(width: width, height: height, depth: depth, fill: fill,
      colorEncoding: colorEncoding, backing: backing)
    for y in stride(from: 0, to: height, by: Surface.tileSide) {
      for x in stride(from: 0, to: width, by: 2048) {
        try Task.checkCancellation()
        let region = IntRect(x: x, y: y, width: min(2048, width - x), height: min(Surface.tileSide, height - y))
        try builder.append(patch(region), atX: x, atY: y)
      }
    }
    return try builder.finish()
  }
  static func pagedOrientation(_ source: Surface, orientation: Int) throws -> Surface {
    guard (1...8).contains(orientation) else { throw CraftError.invalid("Invalid EXIF orientation.") }
    if orientation == 1 { return source }
    let swapped = orientation >= 5
    let width = swapped ? source.height : source.width, height = swapped ? source.width : source.height
    let fill: Pixel = source.colorEncoding == .sRGB ? source.defaultPixel : .clear
    let builder=try Surface.PagedBuilder(width:width,height:height,depth:source.depth,fill:fill,colorEncoding:source.colorEncoding)
    for y in stride(from: 0, to: height, by: Surface.tileSide) {
      for x in stride(from: 0, to: width, by: 2048) {
        var patch = try Surface(width: min(2048,width-x),height: min(Surface.tileSide,height-y),depth:source.depth,
          fill:fill,colorEncoding:source.colorEncoding)
        for py in 0..<patch.height {
          try Task.checkCancellation()
          for px in 0..<patch.width {
            let dx=x+px,dy=y+py,sx:Int,sy:Int
            switch orientation {
            case 2:(sx,sy)=(source.width-1-dx,dy)
            case 3:(sx,sy)=(source.width-1-dx,source.height-1-dy)
            case 4:(sx,sy)=(dx,source.height-1-dy)
            case 5:(sx,sy)=(dy,dx)
            case 6:(sx,sy)=(dy,source.height-1-dx)
            case 7:(sx,sy)=(source.width-1-dy,source.height-1-dx)
            case 8:(sx,sy)=(source.width-1-dy,dx)
            default:(sx,sy)=(dx,dy)
            }
            if source.colorEncoding == .linearRGB { patch.setLinearPixel(x:px,y:py,source.linearPixel(x:sx,y:sy)) }
            else {
              let sample = source.pixel(x:sx,y:sy)
              if sample != fill { patch.setPixel(x:px,y:py,sample) }
            }
          }
        }
        try builder.append(patch,atX:x,atY:y)
      }
    }
    return try builder.finish()
  }
}
