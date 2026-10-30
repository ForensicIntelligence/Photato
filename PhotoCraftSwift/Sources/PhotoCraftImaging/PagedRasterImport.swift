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
    var result = try Surface(width: image.width, height: image.height, depth: depth, colorEncoding: colorEncoding)
    let store = try backing ?? RasterTileStore()
    let direct = depth == .f32 && colorEncoding == .linearRGB ? try FloatRasterSamples.Reader(image, space: target) : nil
    for y in stride(from: 0, to: image.height, by: Surface.tileSide) {
      for x in stride(from: 0, to: image.width, by: 2048) {
        try Task.checkCancellation()
        let region = IntRect(x: x, y: y, width: min(2048, image.width - x), height: min(Surface.tileSide, image.height - y))
        let patch: Surface
        if let direct { patch = try direct.surface(region: region) }
        else {
          guard let crop = image.cropping(to: CGRect(x: x, y: y, width: region.width, height: region.height)) else { throw CraftError.invalid("Could not decode an image patch.") }
          patch = try surface(crop, depth: depth, space: target, colorEncoding: colorEncoding)
        }
        try result.importPatch(patch, atX: x, atY: y, backing: store)
      }
    }
    try result.validated(); return result
  }
  static func pagedOrientation(_ source: Surface, orientation: Int) throws -> Surface {
    let swapped = orientation >= 5
    let width = swapped ? source.height : source.width, height = swapped ? source.width : source.height
    var output = try Surface(width: width, height: height, depth: source.depth, colorEncoding: source.colorEncoding)
    let store = try RasterTileStore()
    for y in stride(from: 0, to: height, by: Surface.tileSide) {
      for x in stride(from: 0, to: width, by: 2048) {
        var patch = try Surface(width: min(2048,width-x),height: min(Surface.tileSide,height-y),depth:source.depth,colorEncoding:source.colorEncoding)
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
            else { patch.setPixel(x:px,y:py,source.pixel(x:sx,y:sy)) }
          }
        }
        try output.importPatch(patch,atX:x,atY:y,backing:store)
      }
    }
    return output
  }
}
