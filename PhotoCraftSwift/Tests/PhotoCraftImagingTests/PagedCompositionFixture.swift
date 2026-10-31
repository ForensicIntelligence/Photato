import Foundation
import PhotoCraftCore

/// Owned inputs captured through the qualified Source13 renderer before its rebuild.
enum PagedCompositionFixture {
  static func document(depth: PixelDepth, variant: Int) throws -> CraftDocument {
    var d=try CraftDocument(width:129,height:67,depth:depth)
    let encoding:SurfaceColorEncoding=depth == .f32 ? .linearRGB:.sRGB
    var pixels=try Surface(width:d.width,height:d.height,depth:depth,
      fill:Pixel(0.25,0.5,0.75,variant%2 == 0 ? 1:0.5),colorEncoding:encoding)
    for y in 0..<d.height {for x in 0..<d.width where (x+y)%7 == 0 {
      let p=Pixel(Float((x*3+y)%29)/28,Float((x+y*5)%31)/30,Float((x*7+y)%23)/22,Float((x+y)%5)/4)
      if depth == .f32 {pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}
    }}
    if depth == .f32 {pixels.setLinearPixel(x:128,y:66,Pixel(2,-0.25,-0.0,0))}
    var base=Layer(name:"Owned base",content:.raster(pixels));base.opacity=variant%3 == 0 ? 1:128/255
    var top=Layer(name:"Owned top",content:.raster(try Surface(width:129,height:67,depth:depth,
      fill:Pixel(0.8,0.2,0.4,0.5),colorEncoding:encoding)))
    top.opacity=177/255
    let group=Layer(name:"Owned group",content:.group(GroupContent(passThrough:variant%2 == 0)))
    top.parentID=group.id
    var clip=Layer(name:"Owned clip",content:.fill(Pixel(0.1,0.8,0.3,0.3)))
    clip.parentID=group.id;clip.clipped=true;clip.blendMode = variant%2 == 0 ? .screen:.normal
    top.blendClippedAsGroup=variant%3 != 0
    if variant==2 || variant==3 {top.blendMode = .multiply}
    if variant==4 || variant==5 {
      var mask=try Surface(width:129,height:67,depth:.f32,fill:Pixel(0.75,0,0,0))
      mask.setPixel(x:64,y:64,Pixel(0.125,0,0,0));top.mask=mask
      var properties=MaskProperties();properties.density=0.625;properties.inverted=variant==5
      top.maskProperties=properties
    }
    if variant==5 {top.affine = .translation(3,2) * .rotation(7)}
    if variant==6 {top.blendMode = .dissolve}
    var adjustment=Layer(name:"Owned adjustment",content:.adjustment(variant==7 ? .gradientMap(.init(dither:true)):.invert))
    adjustment.opacity=0.2
    d.layers=[base,top,clip,group,adjustment];d.activeLayerID=base.id
    try d.validate();return d
  }
}
