import PhotoCraftCore

enum PagedFilterFixture {
  static let kinds:[RasterFilter.Kind]=[.gaussianBlur,.boxBlur,.motionBlur,.unsharpMask,.highPass,.addNoise,.mosaic,.average]
  static func filter(_ kind:RasterFilter.Kind)->RasterFilter {
    var f=RasterFilter(kind);f.radius=2.75
    if kind == .boxBlur {f.radius=3}
    f.distance=7;f.angle=29;f.amount=61;f.threshold=3;f.cellSize=7
    f.seed=729;f.monochromatic=false;f.distribution = .gaussian;return f
  }
  static func document(_ depth:PixelDepth,variant:Int)throws->CraftDocument {
    var d=try CraftDocument(width:131,height:69,depth:depth)
    var s=try Surface(width:d.width,height:d.height,depth:depth,colorEncoding:depth == .f32 ? .linearRGB:.sRGB)
    for y in 0..<s.height {for x in 0..<s.width {
      let p=Pixel(Float((x*13+y*3)%37)/36,Float((x*3+y*7)%31)/30,Float((x+y*11)%41)/40,Float((x+y)%5)/4)
      if depth == .f32 {s.setLinearPixel(x:x,y:y,p)}else{s.setPixel(x:x,y:y,p)}
    }}
    if depth == .f32 {s.setLinearPixel(x:64,y:64,Pixel(2,-0.25,-0.0,0.5))}
    d.layers[0].content = .raster(s)
    if variant==1 {
      d.layers[0].affine = .translation(1.25,-2.5);d.layers[0].protection = [.transparency]
      let bytes=(0..<d.width*d.height).map{UInt8(($0%7)*255/6)}
      d.selectionMask=try SelectionMask(width:d.width,height:d.height,bytes:bytes)
      d.selection=d.selectionMask?.bounds
    }
    return d
  }
  static func wideSurface(height:Int)throws->Surface {
    let width=6000,builder=try Surface.PagedBuilder(width:width,height:height,depth:.f32,colorEncoding:.linearRGB)
    for y in stride(from:0,to:height,by:64) {for x in stride(from:0,to:width,by:2048) {
      var patch=try Surface(width:min(2048,width-x),height:min(64,height-y),depth:.f32,colorEncoding:.linearRGB)
      for py in 0..<patch.height {for px in 0..<patch.width {
        patch.setLinearPixel(x:px,y:py,Pixel(Float((x+px)%257)/256,Float((y+py)%251)/250,
          Float((x+px+3*(y+py))%239)/238,Float((x+px+y+py)%5)/4))
      }}
      try builder.append(patch,atX:x,atY:y)
    }}
    return try builder.finish()
  }
}
