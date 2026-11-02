import Foundation

/// Exact inverse homogeneous placement for an undeformed source. Warp + projective
/// placement uses WarpRaster's tessellation; the original source remains untouched.
public enum ProjectiveRaster {
  public static func renderPaged(_ source:Surface,placement:ProjectiveTransform,bounds:IntRect,method:Resampling)throws->Surface {
    try Task.checkCancellation();try source.validated();try placement.validate()
    if let affine=try placement.affineValue(){return try RasterGeometry.render(source,transform:affine,bounds:bounds,method:method,clampEdges:true)}
    _ = try placement.bounds(width:source.width,height:source.height)
    let inverse=try placement.inverted().values,linear=source.colorEncoding == .linearRGB
    let builder=try Surface.PagedBuilder(width:bounds.width,height:bounds.height,depth:source.depth,fill:.clear,colorEncoding:source.colorEncoding)
    let sourceBox=IntRect(x:0,y:0,width:source.width,height:source.height),supports:[IntRect]
    if source.defaultPixel.hasSameBits(as:.clear),source.tileCount<=RasterGeometry.sparseGridSourceTileLimit {
      supports=try source.projectedGeometrySupport(.identity,bounds:sourceBox,halo:method == .nearest ? 0:2).map{try SelectedPixelTransform.projectedBounds($0,using:placement,clipping:bounds)}
    }else{supports=[bounds]}
    let local=supports.map{IntRect(x:$0.x-bounds.x,y:$0.y-bounds.y,width:$0.width,height:$0.height)}
    for region in GeometryPatchRegions(width:bounds.width,height:bounds.height,rectangles:local) {
      var patch=try Surface(width:region.width,height:region.height,depth:source.depth,colorEncoding:source.colorEncoding)
      for y in 0..<region.height{try Task.checkCancellation();for x in 0..<region.width {
        let px=Double(bounds.x+region.x+x)+0.5,py=Double(bounds.y+region.y+y)+0.5,w=inverse[6]*px+inverse[7]*py+inverse[8]
        guard w.isFinite,abs(w)>1e-15 else{continue}
        let sx=(inverse[0]*px+inverse[1]*py+inverse[2])/w,sy=(inverse[3]*px+inverse[4]*py+inverse[5])/w
        guard sx>=0,sy>=0,sx<Double(source.width),sy<Double(source.height) else{continue}
        if method == .nearest{patch.copyStoredSample(from:source,x:Int(floor(sx)),y:Int(floor(sy)),toX:x,toY:y);continue}
        let p=WarpRaster.sample(source,.init(sx,sy),method:method,clampEdges:true,encoding:source.colorEncoding)
        if linear{patch.setLinearPixel(x:x,y:y,p)}else{patch.setPixel(x:x,y:y,p)}
      }}
      try builder.append(patch,atX:region.x,atY:region.y)
    }
    return try builder.finish()
  }

  public static func mapping(_ projection:ProjectiveTransform,width:Int,height:Int,transform:Transform2D)throws->WarpRaster.Mapping {
    let full=try projection.followed(by:transform),bounds=try full.bounds(width:width,height:height)
    guard width<=WarpRaster.maximumPixels/height,bounds.width<=WarpRaster.maximumPixels/bounds.height else{throw CraftError.unsupported("Projective preparation currently supports8,388,608 source/output pixels.")}
    let inverse=try full.inverted(),a=inverse.values
    var uv=[PathPoint](repeating:.init(.nan,.nan),count:bounds.width*bounds.height)
    for y in 0..<bounds.height {
      try Task.checkCancellation()
      for x in 0..<bounds.width {
        let px=Double(bounds.x+x)+0.5,py=Double(bounds.y+y)+0.5,w=a[6]*px+a[7]*py+a[8]
        guard w.isFinite,w != 0 else{continue}
        let sx=(a[0]*px+a[1]*py+a[2])/w,sy=(a[3]*px+a[4]*py+a[5])/w
        if sx.isFinite,sy.isFinite,sx>=0,sy>=0,sx<Double(width),sy<Double(height){uv[y*bounds.width+x] = .init(sx,sy)}
      }
    }
    return .init(bounds:bounds,uv:uv)
  }
}

