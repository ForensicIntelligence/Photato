import Foundation

/// Internal GRAY8 selection plane. Sparse samples/index pages share the raster
/// store; callers never need a whole-canvas coverage array to sample or edit it.
struct PagedSelectionCoverage: Equatable, Sendable {
  let surface: Surface
  var width: Int { surface.width }
  var height: Int { surface.height }
  var allocatedBytes: Int { surface.allocatedBytes }
  var mappedBytes: Int { surface.mappedBytes }
  var bounds: IntRect? { get throws { try surface.scalarCoverageBounds() } }
  init(surface: Surface) throws { try Task.checkCancellation(); self.surface = try surface.quantizedCoverageStorage() }
  private init(quantized surface: Surface) { self.surface = surface }
  init(width: Int, height: Int, bytes: [UInt8]) throws {
    _ = try Surface(width:width,height:height)
    guard bytes.count == width*height else {throw CraftError.invalid("Invalid selection coverage.")}
    self = try Self.assemble(width:width,height:height,regions:[IntRect(x:0,y:0,width:width,height:height)]) {x,y in bytes[y*width+x]}
  }
  func byte(x:Int,y:Int)->UInt8 {
    guard x>=0,y>=0,x<width,y<height else {return 0}
    return UInt8((unit(surface.pixel(x:x,y:y).r)*255).rounded())
  }
  func denseBytes(maximumPixels:Int = Surface.maximumDensePixels)throws->[UInt8] {
    guard maximumPixels>=0,width<=maximumPixels/height else {throw CraftError.unsupported("This operation requires bounded dense selection coverage.")}
    var result=[UInt8](repeating:0,count:width*height)
    for y in 0..<height {try Task.checkCancellation();for x in 0..<width {result[y*width+x]=byte(x:x,y:y)}}
    return result
  }
  private static func assemble(width:Int,height:Int,regions:[IntRect],sample:(Int,Int)throws->UInt8)throws->Self {
    let builder=try Surface.PagedBuilder(width:width,height:height,depth:.u8,fill:.black)
    for region in GeometryPatchRegions(width:width,height:height,rectangles:regions) {
      var patch=try Surface(width:region.width,height:region.height,depth:.u8,fill:.black)
      for y in 0..<region.height {try Task.checkCancellation();for x in 0..<region.width {
        let b=try sample(x+region.x,y+region.y)
        if b>0 {let v=Float(b)/255;patch.setPixel(x:x,y:y,Pixel(v,v,v))}
      }}
      try builder.append(patch,atX:region.x,atY:region.y)
    }
    return Self(quantized:try builder.finish())
  }
  static func make(_ shape:SelectionShape,width:Int,height:Int,antiAlias:Bool=true)throws->Self {
    _ = try Surface(width:width,height:height);try Task.checkCancellation()
    let sub=antiAlias ? 4:1
    switch shape {
    case .rectangle(let r),.ellipse(let r):
      guard r.width>0,r.height>0,r.width<=Surface.maxDimension,r.height<=Surface.maxDimension,
        abs(Double(r.x))<=1_000_000,abs(Double(r.y))<=1_000_000 else {throw CraftError.invalid("Invalid selection rectangle.")}
      let box=r.clipped(toWidth:width,height:height)
      if case .rectangle = shape {return Self(quantized:try Surface.rectangularCoverage(width:width,height:height,rectangle:box))}
      return try assemble(width:width,height:height,regions:[box]) {x,y in
        var count=0
        for sy in 0..<sub {for sx in 0..<sub {
          let dx=(Double(x-r.x)+(Double(sx)+0.5)/Double(sub))/Double(r.width)*2-1
          let dy=(Double(y-r.y)+(Double(sy)+0.5)/Double(sub))/Double(r.height)*2-1
          if dx*dx+dy*dy<=1 {count+=1}
        }}
        return UInt8((Double(count)/Double(sub*sub)*255).rounded())
      }
    case .polygon(let points):
      guard points.count<=100_000,points.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1_000_000 && abs($0.y)<=1_000_000}) else {throw CraftError.invalid("Invalid lasso path.")}
      guard points.count>=3 else {return Self(quantized:try Surface(width:width,height:height,depth:.u8,fill:.black))}
      let left=max(0,min(width,Int(floor(points.map(\.x).min()!)))),right=max(0,min(width,Int(ceil(points.map(\.x).max()!))))
      let top=max(0,min(height,Int(floor(points.map(\.y).min()!)))),bottom=max(0,min(height,Int(ceil(points.map(\.y).max()!))))
      let builder=try Surface.PagedBuilder(width:width,height:height,depth:.u8,fill:.black)
      for region in GeometryPatchRegions(width:width,height:height,rectangles:[IntRect(x:left,y:top,width:max(0,right-left),height:max(0,bottom-top))]) {
        var patch=try Surface(width:region.width,height:region.height,depth:.u8,fill:.black)
        for localY in 0..<region.height {
          try Task.checkCancellation();let py=region.y+localY
          var row=[Double](repeating:0,count:region.width)
          for sample in 0..<sub {
            let y=Double(py)+(Double(sample)+0.5)/Double(sub);var crossings=[Double]()
            for i in points.indices {
              let a=points[i],b=points[(i+1)%points.count]
              if (a.y<=y && b.y>y)||(b.y<=y && a.y>y) {crossings.append(a.x+(y-a.y)/(b.y-a.y)*(b.x-a.x))}
            }
            crossings.sort()
            for i in stride(from:0,to:crossings.count-crossings.count%2,by:2) {
              let lo=max(0,crossings[i]),hi=min(Double(width),crossings[i+1]);guard hi>lo else {continue}
              let x0=max(region.x,Int(floor(lo))),x1=min(region.x+region.width,Int(ceil(hi)))
              guard x1>x0 else {continue}
              for x in x0..<x1 {
                let coverage=antiAlias ? min(Double(x+1),hi)-max(Double(x),lo):(Double(x)+0.5>=lo && Double(x)+0.5<hi ? 1.0:0.0)
                row[x-region.x]+=max(0,coverage)/Double(sub)
              }
            }
          }
          for x in row.indices {let b=UInt8((min(1,row[x])*255).rounded());if b>0 {let v=Float(b)/255;patch.setPixel(x:x,y:localY,Pixel(v,v,v))}}
        }
        try builder.append(patch,atX:region.x,atY:region.y)
      }
      return Self(quantized:try builder.finish())
    }
  }
  func combined(with old:Self?,mode:SelectionMode)throws->Self {
    try Task.checkCancellation()
    guard old == nil || (old?.width==width && old?.height==height) else {throw CraftError.invalid("Selection canvas sizes differ.")}
    if mode == .replace {try Task.checkCancellation();return self}
    let previous=try old?.surface ?? Surface(width:width,height:height,depth:.u8,fill:.black)
    let mapped=try surface.combiningStoredSamples(with:previous) {new,old in
      let a=Int((unit(old.r)*255).rounded()),b=Int((unit(new.r)*255).rounded()),value:Int
      switch mode {case .replace:value=b;case .add:value=max(a,b);case .subtract:value=max(0,a-b);case .intersect:value=min(a,b)}
      let v=Float(value)/255;return Pixel(v,v,v)
    }
    return Self(quantized:try mapped.retaggedCoverageStorage())
  }
  func inverted()throws->Self {
    try Task.checkCancellation()
    let mapped=try surface.mappedStoredSamples {p in let b=255-Int((unit(p.r)*255).rounded());let v=Float(b)/255;return Pixel(v,v,v)}
    return Self(quantized:try mapped.retaggedCoverageStorage())
  }
  func transformed(by delta:Transform2D,width:Int,height:Int)throws->Self {
    _ = try Surface(width:width,height:height);try Task.checkCancellation()
    let inverse=try delta.inverted(),canvas=IntRect(x:0,y:0,width:width,height:height)
    if let grid=RasterGridMap(delta,inverse:inverse,width:self.width,height:self.height,bounds:canvas) {
      return Self(quantized:try surface.permutingGrid(grid,width:width,height:height))
    }
    let corners=[inverse.point(0.5,0.5),inverse.point(Double(width)-0.5,0.5),inverse.point(0.5,Double(height)-0.5),inverse.point(Double(width)-0.5,Double(height)-0.5)]
    if surface.tileCount==0,corners.allSatisfy({$0.x>=0.5 && $0.y>=0.5 && $0.x<=Double(self.width)-0.5 && $0.y<=Double(self.height)-0.5}) {
      return Self(quantized:try surface.reframedImplicitValue(width:width,height:height))
    }
    let regions:[IntRect]
    if surface.defaultPixel.r==0,surface.tileCount<=RasterGeometry.sparseGridSourceTileLimit {
      regions=try surface.projectedGeometrySupport(delta,bounds:canvas,halo:1)
    } else {
      let support=[delta.point(-1,-1),delta.point(Double(self.width)+1,-1),delta.point(-1,Double(self.height)+1),delta.point(Double(self.width)+1,Double(self.height)+1)]
      let x0=max(0,min(Double(width),floor(support.map(\.x).min()!)-1)),x1=max(0,min(Double(width),ceil(support.map(\.x).max()!)+1))
      let y0=max(0,min(Double(height),floor(support.map(\.y).min()!)-1)),y1=max(0,min(Double(height),ceil(support.map(\.y).max()!)+1))
      regions=[IntRect(x:Int(x0),y:Int(y0),width:Int(x1-x0),height:Int(y1-y0))]
    }
    return try Self.assemble(width:width,height:height,regions:regions) {x,y in
      let p=inverse.point(Double(x)+0.5,Double(y)+0.5),px=p.x-0.5,py=p.y-0.5
      guard px > -2,py > -2,px<Double(self.width),py<Double(self.height) else {return 0}
      let ix=Int(floor(px)),iy=Int(floor(py)),fx=Float(px-floor(px)),fy=Float(py-floor(py))
      func coverage(_ x:Int,_ y:Int)->Float {Float(byte(x:x,y:y))/255}
      let top=coverage(ix,iy)*(1-fx)+coverage(ix+1,iy)*fx
      let bottom=coverage(ix,iy+1)*(1-fx)+coverage(ix+1,iy+1)*fx
      return UInt8((unit(top*(1-fy)+bottom*fy)*255).rounded())
    }
  }
  func feathered(radius:Double)throws->Self {
    guard radius.isFinite,(0...100).contains(radius) else {throw CraftError.invalid("Feather must be 0–100 pixels.")}
    try Task.checkCancellation();guard radius>0,let box=try bounds else {return self}
    let sigma=max(0.05,radius/2),r=Int(ceil(max(0.05,radius/2)*3))
    var weights=(-r...r).map {exp(-Double($0*$0)/(2*sigma*sigma))};let sum=weights.reduce(0,+);weights=weights.map {$0/sum}
    let x0=max(0,box.x-r),x1=min(width,box.x+box.width+r),y0=max(0,box.y-r),y1=min(height,box.y+box.height+r)
    let implicit=UInt8((unit(surface.defaultPixel.r)*255).rounded()),v=Float(implicit)/255
    let builder=try Surface.PagedBuilder(width:width,height:height,depth:.u8,fill:Pixel(v,v,v))
    var support=[IntRect(x:x0,y:y0,width:x1-x0,height:y1-y0)]
    if surface.tileCount<=RasterGeometry.sparseGridSourceTileLimit {
      support=try surface.projectedGeometrySupport(.identity,bounds:IntRect(x:0,y:0,width:width,height:height),halo:r)
      if implicit>0 {support += [IntRect(x:0,y:0,width:width,height:min(r,height)),IntRect(x:0,y:max(0,height-r),width:width,height:min(r,height)),IntRect(x:0,y:0,width:min(r,width),height:height),IntRect(x:max(0,width-r),y:0,width:min(r,width),height:height)]}
    }
    for region in GeometryPatchRegions(width:width,height:height,rectangles:support) {
      let hy0=max(box.y,region.y-r),hy1=min(box.y+box.height,region.y+region.height+r)
      var horizontal=[Float](repeating:0,count:region.width*max(0,hy1-hy0))
      if hy1>hy0 {for y in hy0..<hy1 {try Task.checkCancellation();for x in region.x..<region.x+region.width {
        var value=0.0
        for k in -r...r where x+k>=0 && x+k<width {value+=Double(byte(x:x+k,y:y))*weights[k+r]}
        horizontal[(y-hy0)*region.width+x-region.x]=Float(value)
      }}}
      var patch=try Surface(width:region.width,height:region.height,depth:.u8,fill:Pixel(v,v,v))
      for y in region.y..<region.y+region.height {try Task.checkCancellation();for x in region.x..<region.x+region.width {
        var value=0.0
        for k in -r...r where y+k>=hy0 && y+k<hy1 {value+=Double(horizontal[(y+k-hy0)*region.width+x-region.x])*weights[k+r]}
        let b=UInt8(min(255,max(0,value.rounded())));if b != implicit {let value=Float(b)/255;patch.setPixel(x:x-region.x,y:y-region.y,Pixel(value,value,value))}
      }}
      try builder.append(patch,atX:region.x,atY:region.y)
    }
    return Self(quantized:try builder.finish())
  }
}
