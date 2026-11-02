import Foundation

/// Numeric scalar projection shared by channel and pixel-mask transforms; no color transfer.
enum ScalarPlaneProjection {
  static func render(_ source:Surface,placement:ProjectiveTransform,bounds:IntRect,exterior:Float,interpolation:Resampling)throws->Surface{
    try Task.checkCancellation();try placement.validate();try source.validated()
    guard source.colorEncoding == .sRGB,exterior.isFinite,(0...1).contains(exterior) else{throw CraftError.invalid("Invalid numeric scalar source/exterior.")}
    _ = try SelectedPixelTransform.projectedBounds(.init(x:0,y:0,width:source.width,height:source.height),using:placement,clipping:bounds)
    let inverse=try placement.inverted().values
    var grid:RasterGridMap?
    if let affine=try placement.affineValue(){grid=RasterGridMap(affine,inverse:try affine.inverted(),width:source.width,height:source.height,bounds:bounds)}
    let outside=Pixel(exterior,exterior,exterior),method=interpolation
    // Work patches and sparse support are bounded independently of the document's pixel count.
    let builder=try Surface.PagedBuilder(width:bounds.width,height:bounds.height,depth:source.depth,fill:outside)
    let halo=method == .nearest ? 0:2,sourceRect=IntRect(x:0,y:0,width:source.width,height:source.height)
    let supports:[IntRect]
    if source.defaultPixel.r == exterior,source.tileCount<=RasterGeometry.sparseGridSourceTileLimit {
      supports=try source.projectedGeometrySupport(.identity,bounds:sourceRect,halo:halo).map{try SelectedPixelTransform.projectedBounds($0,using:placement,clipping:bounds)}
    }else{supports=[bounds]}
    let local=supports.map{IntRect(x:$0.x-bounds.x,y:$0.y-bounds.y,width:$0.width,height:$0.height)}
    func value(_ x:Int,_ y:Int)->Float {guard x>=0,y>=0,x<source.width,y<source.height else{return exterior};return unit(source.pixel(x:x,y:y).r)}
    func sample(_ x:Double,_ y:Double)->Float {
      guard x.isFinite,y.isFinite,abs(x)<10_000_000,abs(y)<10_000_000 else{return exterior}
      if method == .nearest{return value(Int(floor(x)),Int(floor(y)))}
      let px=x-0.5,py=y-0.5,ix=Int(floor(px)),iy=Int(floor(py)),fx=Float(px-Double(ix)),fy=Float(py-Double(iy))
      if method == .bilinear{return unit((value(ix,iy)*(1-fx)+value(ix+1,iy)*fx)*(1-fy)+(value(ix,iy+1)*(1-fx)+value(ix+1,iy+1)*fx)*fy)}
      func weight(_ n:Float)->Float{let v=abs(n);if v<=1{return 1.5*v*v*v-2.5*v*v+1};if v<2{return -0.5*v*v*v+2.5*v*v-4*v+2};return 0}
      var total:Float=0;for dy in -1...2{for dx in -1...2{total+=value(ix+dx,iy+dy)*weight(Float(dx)-fx)*weight(Float(dy)-fy)}};return unit(total)
    }
    for region in GeometryPatchRegions(width:bounds.width,height:bounds.height,rectangles:local) {
      var patch=try Surface(width:region.width,height:region.height,depth:source.depth,fill:outside)
      for y in 0..<region.height{try Task.checkCancellation();for x in 0..<region.width {
        if let grid{let(sx,sy)=grid.source(region.x+x,region.y+y);patch.copyStoredSample(from:source,x:sx,y:sy,toX:x,toY:y);continue}
        let px=Double(bounds.x+region.x+x)+0.5,py=Double(bounds.y+region.y+y)+0.5,den=inverse[6]*px+inverse[7]*py+inverse[8]
        guard den.isFinite,abs(den)>1e-15 else{continue}
        let sx=(inverse[0]*px+inverse[1]*py+inverse[2])/den,sy=(inverse[3]*px+inverse[4]*py+inverse[5])/den,v=sample(sx,sy)
        if v != exterior{patch.setPixel(x:x,y:y,Pixel(v,v,v))}
      }}
      try builder.append(patch,atX:region.x,atY:region.y)
    }
    return try builder.finish()
  }
}
