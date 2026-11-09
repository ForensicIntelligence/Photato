import PhotoCraftCore

/// Opaque artboard backgrounds seed the same measured Normal arithmetic as an
/// opaque raster base. Other layer contexts retain the general compositor.
enum ArtboardRasterRenderer {
  static func composite(_ layers:[Layer],in document:CraftDocument,over backdrop:Surface,
    region:IntRect,facts:CompositionFacts?) throws -> Surface? {
    guard document.depth == .u16 || document.depth == .f32,
      layers.allSatisfy({layer in
        guard case .raster=layer.content else{return false}
        return layer.affine==nil && layer.blendMode == .normal && !layer.isClipped && layer.style==nil
      }) else{return nil}
    var output=backdrop
    for layer in layers where layer.visible && layer.opacity>0 {
      try Task.checkCancellation()
      guard case .raster(let source)=layer.content else{continue}
      let mask=try facts.map{try $0.mask(layer,region:region)}
        ?? LayerMaskSampler.make(layer:layer,document:document,pixelRegion:region)
      let left=max(region.x,layer.x),top=max(region.y,layer.y)
      let right=min(region.x+region.width,layer.x+source.width)
      let bottom=min(region.y+region.height,layer.y+source.height)
      guard left<right,top<bottom else{continue}
      for y in top..<bottom {
        try Task.checkCancellation()
        for x in left..<right {
          var pixel=document.depth == .f32
            ? source.linearPixel(x:x-layer.x,y:y-layer.y):source.pixel(x:x-layer.x,y:y-layer.y)
          pixel.a *= mask?.coverage(x:Double(x)+0.5,y:Double(y)+0.5) ?? 1
          if document.depth == .f32 {
            pixel.a=unit(pixel.a*layer.opacity)
            output.setLinearPixel(x:x,y:y,try RGB32NormalRenderer.blend(output.linearPixel(x:x,y:y),pixel,opaque:true))
          } else {
            output.setPixel(x:x,y:y,NormalLayerComposite.composite(
              backdrop:output.pixel(x:x,y:y),source:pixel,opacity:layer.opacity,depth:.u16))
          }
        }
      }
    }
    return output
  }
}
