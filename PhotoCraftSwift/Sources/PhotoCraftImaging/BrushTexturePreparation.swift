import Foundation
import PhotoCraftCore

/// Shared sampled-brush texture conversion. Retains the existing ABR encoded-RGB
/// luminance-times-alpha calculation; this is not a Photoshop numeric oracle.
public enum BrushTexturePreparation {
  public static func bitmap(_ pattern: RasterPattern) throws -> BrushBitmap {
    let s = pattern.surface
    guard s.width <= 2500, s.height <= 2500 else {
      throw CraftError.invalid("Brush textures are limited to 2500 × 2500 pixels. The pattern was not resized.")
    }
    try Task.checkCancellation()
    try pattern.validate()
    var bytes = Data(count: s.width * s.height)
    for y in 0..<s.height {
      try Task.checkCancellation()
      for x in 0..<s.width {
        let p = s.pixel(x: x, y: y)
        bytes[y*s.width+x] = UInt8((unit((p.r*0.2126+p.g*0.7152+p.b*0.0722)*p.a)*255).rounded())
      }
    }
    return BrushBitmap(width: s.width, height: s.height, bytes: bytes)
  }
}
