import Foundation

/// The existing eight basic native filters with Float64 intermediates and the
/// same reduction order, layer-edge clamps and final stored-pixel operations.
enum PagedRasterFilters {
  typealias Sample=SIMD4<Double>
  static let maximumPlaneBytes=4_398_046_511_104
  static let kinds:[RasterFilter.Kind]=[.gaussianBlur,.boxBlur,.motionBlur,.unsharpMask,.highPass,.addNoise,.mosaic,.average]
  static func apply(_ filter:RasterFilter,to layerID:UUID,in document:inout CraftDocument,
    maximumScratchPlaneBytes:Int=maximumPlaneBytes)throws {
    try filter.validate();try Task.checkCancellation()
    guard kinds.contains(filter.kind),let index=document.layers.firstIndex(where:{$0.id==layerID}),
      !document.isLocked(layerID),!document.isImageLocked(layerID),case .raster(let source)=document.layers[index].content
    else {throw CraftError.unsupported("This filter target requires its existing bounded engine.")}
    let linear=document.depth == .f32,w=source.width,h=source.height
    func pixel(_ x:Int,_ y:Int)->Pixel {linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)}
    func sample(_ p:Pixel)throws->Sample {
      guard p.isFinite,max(abs(p.r),abs(p.g),abs(p.b))<=1e12 else {throw CraftError.invalid("Filter input exceeds the supported numeric range.")}
      let a=Double(p.a);return Sample(Double(p.r)*a,Double(p.g)*a,Double(p.b)*a,a)
    }
    let input:FilterSamplePlane
    if source.tileCount==0 {input=FilterSamplePlane(width:w,height:h,constant:try sample(pixel(0,0)))}
    else {
      let writer=try FilterSamplePlane.Writer(width:w,height:h,maximumBytes:maximumScratchPlaneBytes)
      for y in 0..<h {
        try Task.checkCancellation();var row=[Sample]();row.reserveCapacity(w)
        for x in 0..<w {row.append(try sample(pixel(x,y)))}
        try writer.row(row,y:y)
      }
      input=try writer.finish()
    }
    var output=input
    switch filter.kind {
    case .gaussianBlur,.highPass,.unsharpMask:
      let ideal=sqrt(4*filter.radius*filter.radius+1)
      var lower=Int(floor(ideal));if lower%2==0 {lower-=1};lower=max(1,lower)
      let upper=lower+2
      let count=Int(((12*filter.radius*filter.radius-Double(3*lower*lower+12*lower+9))/Double(-4*lower-4)).rounded())
      for pass in 0..<3 {
        let radius=((pass<count ? lower:upper)-1)/2
        output=try box(output,radius:radius,horizontal:true,budget:maximumScratchPlaneBytes)
        output=try box(output,radius:radius,horizontal:false,budget:maximumScratchPlaneBytes)
      }
    case .boxBlur:
      output=try box(output,radius:Int(filter.radius),horizontal:true,budget:maximumScratchPlaneBytes)
      output=try box(output,radius:Int(filter.radius),horizontal:false,budget:maximumScratchPlaneBytes)
    case .motionBlur:output=try motion(input,filter:filter,budget:maximumScratchPlaneBytes)
    case .mosaic:output=try mosaic(input,cell:Int(filter.cellSize),budget:maximumScratchPlaneBytes)
    case .average:
      if let value=input.constant,document.selection==nil,document.selectionMask==nil,exactIntegerSum(value,count:w*h) {
        output=FilterSamplePlane(width:w,height:h,constant:normalizedSumZero(value))
      }else{
        var sum=Sample.zero,total=0.0;let matrix=document.layers[index].coordinateTransform
        for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
          let q=matrix.point(Double(x)+0.5,Double(y)+0.5)
          let c=Double(document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y))))
          sum+=input.sample(x,y)*c;total+=c
        }}
        if total>0 {output=FilterSamplePlane(width:w,height:h,constant:sum/total)}
      }
    case .addNoise:break
    default:throw CraftError.unsupported("Filter is not part of the paged basic family.")
    }
    let layer=document.layers[index],protect=document.isTransparencyLocked(layerID)
    func edited(_ before:Pixel,_ sample:Sample,x:Int,y:Int)throws->Pixel? {
      var after=sample.w>1e-15 ? Pixel(Float(sample.x/sample.w),Float(sample.y/sample.w),Float(sample.z/sample.w),Float(sample.w)):.clear
      switch filter.kind {
      case .unsharpMask,.highPass:
        let difference=before.rgb-after.rgb,threshold=Float(filter.threshold/255);var rgb=before.rgb
        for channel in 0..<3 {
          if filter.kind == .highPass {rgb[channel]=0.5+difference[channel]}
          else if abs(difference[channel])>=threshold {rgb[channel]+=Float(filter.amount/100)*difference[channel]}
        }
        after=Pixel(rgb.x,rgb.y,rgb.z,before.a)
      case .addNoise:
        let calls=(filter.monochromatic ? 1:3)*(filter.distribution == .uniform ? 1:2)
        var random=RasterFilterEngine.NoiseRandom(state:UInt64(filter.seed) &+ (UInt64(y*w+x) &* UInt64(calls) &* 0x9E3779B97F4A7C15))
        let amount=filter.amount/100,first=random.noise(filter.distribution)*amount
        let g=filter.monochromatic ? first:random.noise(filter.distribution)*amount
        let b=filter.monochromatic ? first:random.noise(filter.distribution)*amount
        after=Pixel(before.r+Float(first),before.g+Float(g),before.b+Float(b),before.a)
      default:break
      }
      if protect {if before.a==0 {return nil};after.a=before.a}
      let q=layer.coordinateTransform.point(Double(x)+0.5,Double(y)+0.5)
      let coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)))
      if coverage<=0 {return nil}
      let result=before.mixing(after,coverage:coverage)
      guard result.isFinite else {throw CraftError.invalid("Nonfinite filter result.")};return result
    }
    if source.tileCount==0,let constant=output.constant,filter.kind != .addNoise,
      document.selection==nil,document.selectionMask==nil {
      var one=try source.cropped(to:.init(x:0,y:0,width:1,height:1))
      if let value=try edited(pixel(0,0),constant,x:0,y:0) {
        if linear {one.setLinearPixel(x:0,y:0,value)}else{one.setPixel(x:0,y:0,value)}
      }
      let raw=one.colorEncoding == .linearRGB ? one.linearPixel(x:0,y:0):one.pixel(x:0,y:0)
      let result=try source.reframedImplicitValue(width:w,height:h,sample:raw,linear:one.colorEncoding == .linearRGB)
      try Task.checkCancellation();document.layers[index].content = .raster(result);return
    }
    let builder=try Surface.PagedBuilder(width:w,height:h,depth:source.depth,colorEncoding:source.colorEncoding)
    for y in stride(from:0,to:h,by:64) {for x in stride(from:0,to:w,by:2048) {
      try Task.checkCancellation()
      var patch=try source.cropped(to:.init(x:x,y:y,width:min(2048,w-x),height:min(64,h-y)))
      for py in 0..<patch.height {try Task.checkCancellation();for px in 0..<patch.width {
        if let value=try edited(pixel(x+px,y+py),output.sample(x+px,y+py),x:x+px,y:y+py) {
          if linear {patch.setLinearPixel(x:px,y:py,value)}else{patch.setPixel(x:px,y:py,value)}
        }
      }}
      try builder.append(patch,atX:x,atY:y)
    }}
    let result=try builder.finish();try Task.checkCancellation();document.layers[index].content = .raster(result)
  }
  private static func exactIntegerSum(_ value:Sample,count:Int)->Bool {
    (0..<4).allSatisfy{value[$0].isFinite && value[$0].rounded()==value[$0] && abs(value[$0])<=9_007_199_254_740_992/Double(count)}
  }
  private static func normalizedSumZero(_ value:Sample)->Sample {
    // Legacy reductions start at positive zero, including a constant -0 input.
    Sample(value.x==0 ? 0:value.x,value.y==0 ? 0:value.y,value.z==0 ? 0:value.z,value.w==0 ? 0:value.w)
  }
  private static func box(_ source:FilterSamplePlane,radius:Int,horizontal:Bool,budget:Int)throws->FilterSamplePlane {
    if radius==0 {return source}
    let w=source.width,h=source.height,scale=1/Double(radius*2+1)
    if let value=source.constant {
      var sum=Sample.zero;for _ in -radius...radius {sum+=value}
      return FilterSamplePlane(width:w,height:h,constant:sum*scale)
    }
    let writer=try FilterSamplePlane.Writer(width:w,height:h,maximumBytes:budget)
    if horizontal {
      for y in 0..<h {
        try Task.checkCancellation();var sum=Sample.zero
        for k in -radius...radius {sum+=source.sample(min(w-1,max(0,k)),y)}
        var row=[Sample]();row.reserveCapacity(w)
        for x in 0..<w {
          row.append(sum*scale)
          sum+=source.sample(min(w-1,max(0,x+radius+1)),y)-source.sample(min(w-1,max(0,x-radius)),y)
        }
        try writer.row(row,y:y)
      }
    }else{
      for x in stride(from:0,to:w,by:64) {
        let n=min(64,w-x);var sums=[Sample](repeating:.zero,count:n)
        for i in 0..<n {for k in -radius...radius {sums[i]+=source.sample(x+i,min(h-1,max(0,k)))}}
        for y in 0..<h {
          try Task.checkCancellation();var values=[Sample]();values.reserveCapacity(n)
          for i in 0..<n {
            values.append(sums[i]*scale)
            sums[i]+=source.sample(x+i,min(h-1,max(0,y+radius+1)))-source.sample(x+i,min(h-1,max(0,y-radius)))
          }
          try writer.row(values,x:x,y:y)
        }
      }
    }
    return try writer.finish()
  }
  private static func motion(_ source:FilterSamplePlane,filter:RasterFilter,budget:Int)throws->FilterSamplePlane {
    if filter.distance==1 {return source}
    // Bilinear interpolation of exact zero/one samples remains zero/one;
    // summing at most257 such samples and dividing by that count is exact.
    // Preserve the existing loop for other constants, whose rounding may differ.
    if let value=source.constant,(0..<4).allSatisfy({value[$0]==0 || value[$0]==1}) {
      return FilterSamplePlane(width:source.width,height:source.height,constant:normalizedSumZero(value))
    }
    let w=source.width,h=source.height,radians=filter.angle * .pi/180,dx=cos(radians),dy = -sin(radians)
    let count=min(257,Int(filter.distance)+1),writer=try FilterSamplePlane.Writer(width:w,height:h,maximumBytes:budget)
    for y in 0..<h {
      try Task.checkCancellation();var row=[Sample]();row.reserveCapacity(w)
      for x in 0..<w {
        var sum=Sample.zero
        for i in 0..<count {
          let offset=(Double(i)/Double(count-1)-0.5)*(filter.distance-1)
          let px=min(Double(w-1),max(0,Double(x)+offset*dx)),py=min(Double(h-1),max(0,Double(y)+offset*dy))
          let x0=Int(px),y0=Int(py),x1=min(w-1,x0+1),y1=min(h-1,y0+1),fx=px-Double(x0),fy=py-Double(y0)
          let top=source.sample(x0,y0)*(1-fx)+source.sample(x1,y0)*fx
          let bottom=source.sample(x0,y1)*(1-fx)+source.sample(x1,y1)*fx
          sum+=top*(1-fy)+bottom*fy
        }
        row.append(sum/Double(count))
      }
      try writer.row(row,y:y)
    }
    return try writer.finish()
  }
  private static func mosaic(_ source:FilterSamplePlane,cell:Int,budget:Int)throws->FilterSamplePlane {
    let w=source.width,h=source.height
    if let value=source.constant,exactIntegerSum(value,count:cell*cell) {
      return FilterSamplePlane(width:w,height:h,constant:normalizedSumZero(value))
    }
    let writer=try FilterSamplePlane.Writer(width:w,height:h,maximumBytes:budget)
    for y0 in stride(from:0,to:h,by:cell) {
      let y1=min(h,y0+cell);var cells=[Sample]();cells.reserveCapacity((w+cell-1)/cell)
      for x0 in stride(from:0,to:w,by:cell) {
        try Task.checkCancellation();let x1=min(w,x0+cell);var sum=Sample.zero
        for y in y0..<y1 {for x in x0..<x1 {sum+=source.sample(x,y)}}
        cells.append(sum/Double((x1-x0)*(y1-y0)))
      }
      let row=(0..<w).map{cells[$0/cell]}
      for y in y0..<y1 {try writer.row(row,y:y)}
    }
    return try writer.finish()
  }
}
