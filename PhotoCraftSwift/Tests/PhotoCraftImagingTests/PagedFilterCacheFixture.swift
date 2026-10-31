import Foundation
import PhotoCraftCore
@testable import PhotoCraftImaging

enum PagedFilterCacheFixture {
  static func large()throws->CraftDocument {
    var d=try CraftDocument(width:6000,height:1500)
    try SmartObjectIO.convert(in:d,selected:[d.layers[0].id]).apply(to:&d)
    d.layers[0].id=UUID(uuidString:"00000000-0000-4000-8000-000000000295")!;d.activeLayerID=d.layers[0].id
    try Command.applyFilter(d.layers[0].id,RasterFilter(.highPass)).apply(to:&d)
    return d
  }
  static func document(_ depth:PixelDepth,variant:Int)throws->CraftDocument {
    var d=try CraftDocument(width:137,height:75,depth:depth)
    var source=try CraftDocument(width:131,height:69,depth:depth)
    var pixels=try Surface(width:131,height:69,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<69 {for x in 0..<131 {
      let p=Pixel(Float((x*13+y*3)%101)/97,Float((x*5+y*19)%113)/109,
        depth == .f32 ? Float((x+y)%19)-3:Float((x+y)%19)/18,Float((x*11+y*7)%17)/16)
      if depth == .f32 {pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}
    }}
    source.layers[0].content = .raster(pixels)
    let(object,cache)=try SmartObjectIO.embedded(document:source,in:d)
    var layer=Layer(name:"Owned cache input",content:.raster(cache));layer.id=UUID(uuidString:"00000000-0000-4000-8000-000000000295")!
    layer.smartObject=object;layer.x = -1;layer.y=2;layer.affine = .translation(0.25,-0.125) * .scale(1.01,1.02)
    var stack=SmartFilterStack();stack.filters=[SmartFilter(filter:RasterFilter(.highPass))]
    if variant==1 {
      var mask=try Surface(width:133,height:73,depth:.u8,fill:.white)
      for y in 0..<73 {for x in 0..<133 {let v=Float((x*3+y*7)%256)/255;mask.setPixel(x:x,y:y,Pixel(v,v,v))}}
      stack.mask=mask;stack.maskProperties.transform = .translation(-0.25,1.125) * .scale(1.01,0.99)
      stack.maskProperties.enabled=false;stack.maskProperties.outside=0
    }
    layer.smartFilters=stack;d.layers=[layer];d.activeLayerID=layer.id;return d
  }
}
