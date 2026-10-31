import Foundation
import PhotoCraftCore

enum PagedSmartFilterFixture {
  static let kinds:[RasterFilter.Kind] = [.gaussianBlur,.boxBlur,.motionBlur,.unsharpMask,.highPass,.addNoise,.mosaic,.average]
  static func document(_ depth:PixelDepth,kind:RasterFilter.Kind,variant:Int)throws->CraftDocument {
    var source=try CraftDocument(width:131,height:69,depth:depth)
    var pixels=try Surface(width:131,height:69,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<69 {for x in 0..<131 {
      let a=Float((x*11+y*7)%17)/16
      let p=Pixel(Float((x*13+y*3)%101)/97,Float((x*5+y*19)%113)/109,depth == .f32 ? Float((x+y)%19)-3:Float((x+y)%19)/18,a)
      if depth == .f32 {pixels.setLinearPixel(x:x,y:y,p)}else{pixels.setPixel(x:x,y:y,p)}
    }}
    source.layers[0].content = .raster(pixels)
    var doc=try CraftDocument(width:137,height:75,depth:depth)
    var layer=Layer(name:"Owned filter source",content:.raster(pixels))
    layer.smartObject=try SmartObject(fileName:"Owned.photato",mediaType:"application/vnd.photato.document",data:NativeArchive.encodeChunked(source),width:131,height:69)
    layer.x = -1;layer.y=2;layer.affine = .translation(0.25,-0.125) * .scale(1.01,1.02)
    var filter=RasterFilter(kind);filter.radius=2.2;if kind == .boxBlur {filter.radius=2}
    filter.distance=5;filter.angle=27;filter.cellSize=7;filter.seed=0xfedcba98
    var stack=SmartFilterStack()
    if variant==1 {
      stack.filters=[SmartFilter(filter:RasterFilter(.highPass),opacity:0.4,blendMode:.multiply)]
      var mask=try Surface(width:133,height:73,depth:.u8,fill:.white)
      for y in 0..<73 {for x in 0..<133 {let v=Float((x*3+y*7)%256)/255;mask.setPixel(x:x,y:y,Pixel(v,v,v))}}
      stack.mask=mask;stack.maskProperties.transform = .translation(-0.25,1.125) * .scale(1.01,0.99)
      stack.maskProperties.density=0.73;stack.maskProperties.outside=0.25
    }
    stack.filters.append(SmartFilter(filter:filter,opacity:variant==0 ? 1:0.625,blendMode:variant==0 ? .normal:(kinds.firstIndex(of:kind)!.isMultiple(of:2) ? .screen:.dissolve)))
    layer.smartFilters=stack;doc.layers=[layer];doc.activeLayerID=layer.id;return doc
  }
  static func constantDocument(width:Int,height:Int,depth:PixelDepth = .u8)throws->CraftDocument {
    var d=try CraftDocument(width:width,height:height,depth:depth)
    d.layers[0].smartObject=try SmartObject(fileName:"Owned.photato",mediaType:"application/vnd.photato.document",data:NativeArchive.encodeChunked(d),width:width,height:height)
    return d
  }
}
