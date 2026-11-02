import Foundation

public struct SelectedPixelTransformRequest:Codable,Equatable,Sendable {
  public var layerID:UUID
  public var matrix:ProjectiveTransform
  public var interpolation:Resampling
  public var backgroundColor:Pixel?
  public var copy:Bool?
  public init(layerID:UUID,matrix:ProjectiveTransform,interpolation:Resampling = .bicubic,backgroundColor:Pixel? = nil,copy:Bool? = nil){self.layerID=layerID;self.matrix=matrix;self.interpolation=interpolation;self.backgroundColor=backgroundColor;self.copy=copy}
}
public enum SelectedPixelTransform {
  /// Virtual interpolation support may exceed a physical raster's side by a few pixels.
  /// Validate the projected storage extent, not the virtual source rectangle.
  static func projectedBounds(_ rect:IntRect,using matrix:ProjectiveTransform,clipping:IntRect? = nil)throws->IntRect {
    try matrix.validate();guard rect.width>0,rect.height>0 else{throw CraftError.invalid("Invalid selection support.")}
    let x=Double(rect.x),y=Double(rect.y),right=x+Double(rect.width),bottom=y+Double(rect.height)
    let corners:[PathPoint]=[.init(x,y),.init(right,y),.init(right,bottom),.init(x,bottom)],m=matrix.values
    let ws=corners.map{m[6]*$0.x+m[7]*$0.y+m[8]},epsilon=max(Double.leastNormalMagnitude,(ws.map{abs($0)}.max() ?? 1)*1e-12)
    guard ws.allSatisfy({$0>epsilon}) || ws.allSatisfy({$0 < -epsilon}) else{throw CraftError.invalid("The selection support crosses infinity.")}
    let output=try corners.map{try matrix.point($0.x,$0.y)},left=floor(output.map(\.x).min()!+1e-9),top=floor(output.map(\.y).min()!+1e-9),r=ceil(output.map(\.x).max()!-1e-9),b=ceil(output.map(\.y).max()!-1e-9)
    let outputLeft=clipping.map{max(left,Double($0.x))} ?? left,outputTop=clipping.map{max(top,Double($0.y))} ?? top,outputRight=clipping.map{min(r,Double($0.x+$0.width))} ?? r,outputBottom=clipping.map{min(b,Double($0.y+$0.height))} ?? b
    if clipping != nil,(outputRight<=outputLeft || outputBottom<=outputTop){return .init(x:0,y:0,width:0,height:0)}
    guard outputRight>outputLeft,outputBottom>outputTop,outputRight-outputLeft<=Double(Surface.maxDimension),outputBottom-outputTop<=Double(Surface.maxDimension),(outputRight-outputLeft)*(outputBottom-outputTop)<=Double(Surface.maxPixels) else{throw CraftError.invalid("Transformed pixel storage exceeds the supported extent.")}
    return .init(x:Int(outputLeft),y:Int(outputTop),width:Int(outputRight-outputLeft),height:Int(outputBottom-outputTop))
  }
  public static func available(_ document:CraftDocument,layerID:UUID)->Bool {
    guard document.colorMode == .rgb,document.animation==nil,document.videoTimeline==nil,document.selection != nil,
      !document.isImageLocked(layerID),
      let layer=document.layers.first(where:{$0.id==layerID}),layer.isBackground || (!document.isPositionLocked(layerID) && !document.isTransparencyLocked(layerID)),case .raster=layer.content,layer.smartObject==nil,
      layer.sourceProjection==nil,layer.warp==nil,layer.smartFilters==nil else{return false}
    return true
  }
  public static func apply(_ request:SelectedPixelTransformRequest,to document:inout CraftDocument)throws {
    try Task.checkCancellation();try request.matrix.validate()
    guard available(document,layerID:request.layerID),let index=document.layers.firstIndex(where:{$0.id==request.layerID}),
      case .raster(let original)=document.layers[index].content,let mask=try document.coverageSelection(),let sourceBounds=mask.bounds
    else{throw CraftError.unsupported("Choose an editable RGB pixel or Background layer and a nonempty selection. Mask/component/Smart Object/animation transforms need separate workflows.")}
    let background=document.layers[index].isBackground
    guard background || request.backgroundColor==nil else{throw CraftError.invalid("backgroundColor applies only to Background pixels.")}
    let backgroundColor=request.backgroundColor ?? .white
    if background{try BackgroundLayer.validate(backgroundColor)}
    if try request.matrix.affineValue() == .identity{return}
    let moved=try SelectionTransform.apply(mask,projection:request.matrix,interpolation:request.interpolation)
    let canvas=IntRect(x:0,y:0,width:document.width,height:document.height)
    let halo=request.interpolation == .nearest ? 0:2
    let padded=IntRect(x:sourceBounds.x-halo,y:sourceBounds.y-halo,width:sourceBounds.width+2*halo,height:sourceBounds.height+2*halo)
    let destinationBounds=try projectedBounds(padded,using:request.matrix,clipping:background ? canvas:nil)
    let supportBounds=[sourceBounds,destinationBounds]
    let left=supportBounds.map(\.x).min()!,top=supportBounds.map(\.y).min()!,right=supportBounds.map{$0.x+$0.width}.max()!,bottom=supportBounds.map{$0.y+$0.height}.max()!
    let union=IntRect(x:left,y:top,width:right-left,height:bottom-top)
    let sourceTransform=document.layers[index].coordinateTransform,inverse=try sourceTransform.inverted(),linear=original.colorEncoding == .linearRGB
    let localMap=try request.matrix.inverted().followed(by:inverse),method=request.interpolation
    let hole=linear ? SRGBTransfer.linear(backgroundColor):backgroundColor
    func coverage(_ x:Double,_ y:Double)->Float {guard x.isFinite,y.isFinite,x>=0,y>=0,x<Double(mask.width),y<Double(mask.height) else{return 0};return Float(mask.byte(at:Int(y)*mask.width+Int(x)))/255}
    func read(_ x:Int,_ y:Int)->Pixel {linear ? original.linearPixel(x:x,y:y):original.pixel(x:x,y:y)}
    func lifted(_ x:Int,_ y:Int)->SIMD4<Float> {
      let p=read(x,y),q=sourceTransform.point(Double(x)+0.5,Double(y)+0.5),a=p.a*coverage(q.x,q.y)
      return SIMD4(p.r*a,p.g*a,p.b*a,a)
    }
    func sample(_ x:Double,_ y:Double)->SIMD4<Float> {
      guard x.isFinite,y.isFinite,abs(x)<10_000_000,abs(y)<10_000_000 else{return .zero}
      if method == .nearest{return lifted(Int(floor(x)),Int(floor(y)))}
      let px=x-0.5,py=y-0.5,ix=Int(floor(px)),iy=Int(floor(py)),fx=Float(px-Double(ix)),fy=Float(py-Double(iy))
      if method == .bilinear{return (lifted(ix,iy)*(1-fx)+lifted(ix+1,iy)*fx)*(1-fy)+(lifted(ix,iy+1)*(1-fx)+lifted(ix+1,iy+1)*fx)*fy}
      func weight(_ n:Float)->Float {let v=abs(n);if v<=1{return 1.5*v*v*v-2.5*v*v+1};if v<2{return -0.5*v*v*v+2.5*v*v-4*v+2};return 0}
      var sum=SIMD4<Float>.zero;for dy in -1...2 {for dx in -1...2 {sum+=lifted(ix+dx,iy+dy)*weight(Float(dx)-fx)*weight(Float(dy)-fy)}};return sum
    }
    // Keep original bits outside changed support, including hidden RGB and HDR values.
    var layer=document.layers[index]
    let coverageSurface=try mask.coverageSurface()
    let candidates=coverageSurface.defaultPixel.r==0 && coverageSurface.tileCount<=RasterGeometry.sparseGridSourceTileLimit
      ? try coverageSurface.projectedGeometrySupport(.identity,bounds:canvas,halo:2):[padded]
    let sourceSupports=candidates.compactMap{r->IntRect? in
      let x=max(r.x,padded.x),y=max(r.y,padded.y),right=min(r.x+r.width,padded.x+padded.width),bottom=min(r.y+r.height,padded.y+padded.height)
      return right>x && bottom>y ? IntRect(x:x,y:y,width:right-x,height:bottom-y):nil
    }
    var supports=sourceSupports
    for rect in sourceSupports where rect.width>0 && rect.height>0 {
      let destination=try projectedBounds(rect,using:request.matrix,clipping:background ? canvas:nil)
      if destination.width>0,destination.height>0{supports.append(destination)}
    }
    try ClonePainter.paintTarget(mask:false,bounds:background ? union.clipped(toWidth:document.width,height:document.height):union,on:&layer,clipping:canvas) { target,transform,_ in
      let toLocal=try transform.inverted(),mapping=try localMap.preceded(by:transform),m=mapping.values
      let grid:Bool
      if let a=try mapping.affineValue() {grid=[a.a,a.b,a.c,a.d].allSatisfy{[-1.0,0,1].contains($0)} && abs(a.a)+abs(a.c)==1 && abs(a.b)+abs(a.d)==1 && abs(a.a)+abs(a.b)==1 && a.tx==a.tx.rounded() && a.ty==a.ty.rounded()}else{grid=false}
      let regions=try supports.map{try (toLocal * .translation(Double($0.x),Double($0.y))).bounds(width:$0.width,height:$0.height).clipped(toWidth:target.width,height:target.height)}
      for region in GeometryPatchRegions(width:target.width,height:target.height,rectangles:regions) {
        for y in region.y..<(region.y+region.height) {try Task.checkCancellation();for x in region.x..<(region.x+region.width) {
          let p=transform.point(Double(x)+0.5,Double(y)+0.5)
          let k=request.copy == true ? 0:coverage(p.x,p.y),old=linear ? target.linearPixel(x:x,y:y):target.pixel(x:x,y:y)
          let px=Double(x)+0.5,py=Double(y)+0.5,den=m[6]*px+m[7]*py+m[8]
          var fill=SIMD4<Float>.zero,sx=Double.nan,sy=Double.nan
          if den.isFinite,abs(den)>1e-15 {sx=(m[0]*px+m[1]*py+m[2])/den;sy=(m[3]*px+m[4]*py+m[5])/den;fill=sample(sx,sy)}
          let rawAlpha=fill.w
          if rawAlpha<=1e-8{fill = .zero}else{let alpha=unit(rawAlpha);fill *= alpha/rawAlpha;fill.w=alpha}
          if k==0 && fill.w==0{continue}
          let base=old.a*(1-k),alpha=fill.w+base*(1-fill.w)
          if grid,sx.isFinite,sy.isFinite,abs(sx)<10_000_000,abs(sy)<10_000_000 {
            let ix=Int(floor(sx)),iy=Int(floor(sy)),q=sourceTransform.point(Double(ix)+0.5,Double(iy)+0.5)
            if ix>=0,iy>=0,ix<original.width,iy<original.height,coverage(q.x,q.y)==1,(base==0 || fill.w==1) {
              target.copyStoredSample(from:original,x:ix,y:iy,toX:x,toY:y);continue
            }
          }
          let output:Pixel
          if background {
            let remainder=Pixel(old.r*(1-k)+hole.r*k,old.g*(1-k)+hole.g*k,old.b*(1-k)+hole.b*k,1)
            output=Pixel(fill.x+remainder.r*(1-fill.w),fill.y+remainder.g*(1-fill.w),fill.z+remainder.b*(1-fill.w),1)
          }else{output=alpha>1e-8 ? Pixel((fill.x+old.r*base*(1-fill.w))/alpha,(fill.y+old.g*base*(1-fill.w))/alpha,(fill.z+old.b*base*(1-fill.w))/alpha,alpha):.clear}
          if linear {target.setLinearPixel(x:x,y:y,output)}else{target.setPixel(x:x,y:y,output)}
        }}
      };return true
    }
    try Task.checkCancellation();document.layers[index]=layer;document.setCoverageSelection(moved)
  }
}
