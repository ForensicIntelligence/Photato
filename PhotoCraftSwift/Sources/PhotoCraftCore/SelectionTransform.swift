import Foundation

public enum SelectionTransform {
  public static func projection(bounds:IntRect,corners:[PathPoint])throws->ProjectiveTransform {
    guard bounds.width>0,bounds.height>0,PerspectiveSettings.validQuad(corners) else {throw CraftError.invalid("Transform Selection requires a finite convex quadrilateral.")}
    let unit=try PerspectiveMap.homography(corners)
    return try ProjectiveTransform(unit.m).preceded(by:.scale(1/Double(bounds.width),1/Double(bounds.height)) * .translation(-Double(bounds.x),-Double(bounds.y)))
  }
  public static func command(in document:CraftDocument,projection:ProjectiveTransform,interpolation:Resampling = .bicubic)throws->Command {
    guard let mask=try document.coverageSelection() else {throw CraftError.invalid("Make a selection before Transform Selection.")}
    return .transformedSelection(try apply(mask,projection:projection,interpolation:interpolation))
  }
  public static func apply(_ mask:SelectionMask,projection:ProjectiveTransform,interpolation:Resampling = .bicubic)throws->SelectionMask {
    try Task.checkCancellation();try projection.validate();let w=mask.width,h=mask.height
    guard let support=mask.bounds else{return mask}
    if let affine=try projection.affineValue(),let inverse=try? affine.inverted(),RasterGridMap(affine,inverse:inverse,width:w,height:h,bounds:.init(x:0,y:0,width:w,height:h)) != nil {
      return try mask.transformed(by:affine,width:w,height:h)
    }
    let source=try mask.coverageSurface(),canvas=IntRect(x:0,y:0,width:w,height:h),matrix=projection.values,inverse=try projection.inverted().values
    func projected(_ rect:IntRect)throws->IntRect {
      let corners=[PathPoint(Double(rect.x),Double(rect.y)),.init(Double(rect.x+rect.width),Double(rect.y)),.init(Double(rect.x+rect.width),Double(rect.y+rect.height)),.init(Double(rect.x),Double(rect.y+rect.height))]
      let denominators=corners.map{matrix[6]*$0.x+matrix[7]*$0.y+matrix[8]},epsilon=max(1e-15,(denominators.map{abs($0)}.max() ?? 1)*1e-12)
      guard denominators.allSatisfy({$0>epsilon}) || denominators.allSatisfy({$0 < -epsilon}) else {throw CraftError.invalid("The selection transform crosses infinity.")}
      let output=try corners.map{try projection.point($0.x,$0.y)}
      let x0=max(0,min(w,Int(floor(output.map(\.x).min()!-2)))),y0=max(0,min(h,Int(floor(output.map(\.y).min()!-2))))
      let x1=max(0,min(w,Int(ceil(output.map(\.x).max()!+2)))),y1=max(0,min(h,Int(ceil(output.map(\.y).max()!+2))))
      return .init(x:x0,y:y0,width:max(0,x1-x0),height:max(0,y1-y0))
    }
    let halo=interpolation == .nearest ? 0:2
    let paddedSupport=IntRect(x:support.x-halo,y:support.y-halo,width:support.width+2*halo,height:support.height+2*halo)
    let full=try projected(paddedSupport)
    let regions: [IntRect]
    if source.defaultPixel.r==0,source.tileCount<=RasterGeometry.sparseGridSourceTileLimit {
      regions=try source.projectedGeometrySupport(.identity,bounds:canvas,halo:halo).map{r in
        let x=max(paddedSupport.x,r.x-halo),y=max(paddedSupport.y,r.y-halo),right=min(paddedSupport.x+paddedSupport.width,r.x+r.width+halo),bottom=min(paddedSupport.y+paddedSupport.height,r.y+r.height+halo)
        return try projected(.init(x:x,y:y,width:max(0,right-x),height:max(0,bottom-y)))
      }
    }else{regions=[full]}
    let builder=try Surface.PagedBuilder(width:w,height:h,depth:.u8,fill:.black)
    func value(_ x:Int,_ y:Int)->Double {guard x>=0,y>=0,x<w,y<h else{return 0};return Double(mask.byte(at:y*w+x))}
    func sampled(_ x:Double,_ y:Double)->Double {
      guard x.isFinite,y.isFinite,abs(x)<10_000_000,abs(y)<10_000_000 else{return 0}
      if interpolation == .nearest {return value(Int(floor(x)),Int(floor(y)))}
      let px=x-0.5,py=y-0.5,ix=Int(floor(px)),iy=Int(floor(py)),fx=px-Double(ix),fy=py-Double(iy)
      if interpolation == .bilinear {return (value(ix,iy)*(1-fx)+value(ix+1,iy)*fx)*(1-fy)+(value(ix,iy+1)*(1-fx)+value(ix+1,iy+1)*fx)*fy}
      func weight(_ t:Double)->Double {let t=abs(t);if t<=1{return 1.5*t*t*t-2.5*t*t+1};if t<2{return -0.5*t*t*t+2.5*t*t-4*t+2};return 0}
      var total=0.0;for dy in -1...2 {for dx in -1...2 {total+=value(ix+dx,iy+dy)*weight(Double(dx)-fx)*weight(Double(dy)-fy)}};return total
    }
    for region in GeometryPatchRegions(width:w,height:h,rectangles:regions) {
      var patch=try Surface(width:region.width,height:region.height,depth:.u8,fill:.black)
      for y in 0..<region.height {try Task.checkCancellation();for x in 0..<region.width {
        let px=Double(region.x+x)+0.5,py=Double(region.y+y)+0.5,den=inverse[6]*px+inverse[7]*py+inverse[8]
        guard den.isFinite,abs(den)>1e-15 else{continue}
        let sx=(inverse[0]*px+inverse[1]*py+inverse[2])/den,sy=(inverse[3]*px+inverse[4]*py+inverse[5])/den
        let byte=Int(min(255,max(0,sampled(sx,sy))).rounded())
        if byte>0 {let v=Float(byte)/255;patch.setPixel(x:x,y:y,Pixel(v,v,v))}
      }}
      try builder.append(patch,atX:region.x,atY:region.y)
    }
    return try SelectionMask(coverage:builder.finish())
  }
}
