import Foundation

/// An immutable prepared result. New-document outputs leave the source document untouched.
public struct SelectionRefinementEdit: Sendable {
  public let layerID: UUID
  public let output: SelectionRefinementOutput
  public let mask: SelectionMask
  public let corrected: Surface?
  public init(layerID: UUID, output: SelectionRefinementOutput, mask: SelectionMask, corrected: Surface? = nil) {
    self.layerID = layerID; self.output = output; self.mask = mask; self.corrected = corrected
  }
  public func applied(to original: CraftDocument) throws -> CraftDocument {
    guard mask.width == original.width, mask.height == original.height,
      let index = original.layers.firstIndex(where: { $0.id == layerID }),
      case .raster(let pixels) = original.layers[index].content else { throw CraftError.invalid("Select and Mask requires a raster layer.") }
    try SelectionMatting.checkSize(mask.width,mask.height)
    var result = original
    if output == .selection { result.setCoverageSelection(mask); return result }
    guard output.createsDocument || !original.isLocked(layerID) else { throw CraftError.invalid("Unlock the layer before changing its mask or creating a cutout.") }
    if let corrected { guard corrected.width == pixels.width, corrected.height == pixels.height, corrected.depth == pixels.depth else { throw CraftError.invalid("Corrected pixels do not match the layer.") } }
    var layer = original.layers[index]
    if output != .layerMask {
      layer.id = UUID(); layer.name += " copy"; layer.visible = true; layer.locked = false; layer.protection = []
      if let corrected { layer.content = .raster(corrected); layer.smartObject = nil; layer.smartFilters = nil }
    }
    var coverage = try Surface(width:mask.width,height:mask.height,depth:original.depth,fill:Pixel(0,0,0))
    for y in 0..<mask.height { try Task.checkCancellation(); for x in 0..<mask.width {
      let a = Float(mask.byte(at:y*mask.width+x))/255
      if a > 0 { coverage.setPixel(x:x,y:y,Pixel(a,a,a)) }
    } }
    var properties = MaskProperties(); properties.outside = 0; properties.transform = try layer.coordinateTransform.inverted()
    layer.mask = coverage; layer.maskProperties = properties
    if output == .newLayer || output == .newDocument {
      // Bake coverage in source coordinates, keeping HDR/hidden RGB and affine geometry.
      var cutout = corrected ?? pixels
      for y in 0..<pixels.height { try Task.checkCancellation(); for x in 0..<pixels.width {
        let point = layer.coordinateTransform.point(Double(x)+0.5,Double(y)+0.5)
        let ix = Int(floor(point.x)), iy = Int(floor(point.y))
        let a: Float = ix >= 0 && iy >= 0 && ix < mask.width && iy < mask.height ? Float(mask.byte(at:iy*mask.width+ix))/255 : 0
        var p = pixels.depth == .f32 ? cutout.linearPixel(x:x,y:y) : cutout.pixel(x:x,y:y); p.a *= a
        if pixels.depth == .f32 { cutout.setLinearPixel(x:x,y:y,p) } else { cutout.setPixel(x:x,y:y,p) }
      } }
      layer.content = .raster(cutout); layer.mask = nil; layer.maskProperties = nil; layer.smartObject = nil; layer.smartFilters = nil
    }
    if output.createsDocument {
      result = try LayerDuplication.newDocument(from:original,selected:[layerID],documentName:original.name+" refined")
      layer.parentID = nil; layer.clipped = false; layer.visible = true
      result.layers = [layer]
    } else if output == .layerMask { result.layers[index] = layer }
    else {
      guard result.layers.count < 512 else { throw CraftError.invalid("Layer limit reached.") }
      result.layers[index].visible = false; result.layers.insert(layer,at:index+1)
    }
    result.activeLayerID = layer.id; result.setCoverageSelection(nil); try result.validate(); return result
  }
}
