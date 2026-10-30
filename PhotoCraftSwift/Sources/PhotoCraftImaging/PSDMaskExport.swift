import Foundation
import PhotoCraftCore

enum PSDMaskExport {
  /// PSD raster masks have integer document-space rectangles. Project only the
  /// export copy into that representation; never overwrite the native source mask.
  static func prepared(_ layer: Layer) throws -> Layer {
    guard let mask = layer.mask else {return layer}
    let transform = layer.maskCoordinateTransform
    if transform.a == 1,transform.b == 0,transform.c == 0,transform.d == 1,
      transform.tx == transform.tx.rounded(),transform.ty == transform.ty.rounded() {return layer}
    var properties = layer.effectiveMaskProperties
    guard properties.feather == 0 else {throw CraftError.unsupported("Transformed feathered masks require native Photato saving until PSD feather-space interchange is qualified.")}
    // Bilinear mask coverage extends half a source pixel past the stored bounds.
    // A full source-pixel border also bounds rotations and fractional translations.
    let bounds = try (transform * .translation(-1,-1)).bounds(width:mask.width+2,height:mask.height+2)
    let inverse = try transform.inverted()
    var result = try Surface(width:bounds.width,height:bounds.height,depth:mask.depth,
      fill:Pixel(properties.outside,properties.outside,properties.outside))
    for y in 0..<bounds.height {
      try Task.checkCancellation()
      for x in 0..<bounds.width {
        let point = inverse.point(Double(bounds.x+x)+0.5,Double(bounds.y+y)+0.5)
        let value = MaskSampler.sample(mask,x:point.x,y:point.y,outside:properties.outside)
        result.setPixel(x:x,y:y,Pixel(value,value,value))
      }
    }
    var output = layer;output.mask = result
    properties.transform = try layer.coordinateTransform.inverted() * .translation(Double(bounds.x),Double(bounds.y))
    output.maskProperties = properties;return output
  }
}
