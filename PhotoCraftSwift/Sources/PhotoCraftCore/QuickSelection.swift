import Foundation

extension SelectionSegmentation {
  /// Source Quick Selection: seed colors plus geodesic barriers and an edge-aware min-cut.
  public static func quick(_ source:Surface,points:[SelectionPoint],size:Double,workPixels:Int=160_000)throws->SelectionMask {
    try check(source)
    guard !points.isEmpty,points.count<=4096,size.isFinite,(1...5000).contains(size),points.allSatisfy({$0.x.isFinite && $0.y.isFinite && abs($0.x)<=1_000_000 && abs($0.y)<=1_000_000}),workPixels>0,workPixels<=workingPixels else {throw CraftError.invalid("Invalid Quick Selection stroke or work budget.")}
    let radius=Float(size)/2,x0=floor(points.map{Float($0.x)-radius}.min()!),y0=floor(points.map{Float($0.y)-radius}.min()!),x1=ceil(points.map{Float($0.x)+radius}.max()!)+1,y1=ceil(points.map{Float($0.y)+radius}.max()!)+1
    let bbox=clampRect(.init(x:Int(x0),y:Int(y0),width:Int(x1-x0),height:Int(y1-y0)),source.width,source.height)
    if bbox.width==0 || bbox.height==0{return try .init(width:source.width,height:source.height,bytes:Array(repeating:0,count:source.width*source.height))}
    let window=inflate(bbox,Int(max(Float(size)*6,512)),source.width,source.height)
    let step=max(1,Int(ceil(sqrt(Double(window.width*window.height)/Double(workPixels))))),image=try SelectionImage(source,rect:window,step:step)
    let samples=points.map{SIMD2<Float>((Float($0.x)-Float(window.x))/Float(step),(Float($0.y)-Float(window.y))/Float(step))}
    let seeds=try strokeSeeds(samples,radius:max(0.75,radius/Float(step)),width:image.width,height:image.height)
    let (fg,bg,low)=try quickSegment(image,seeds:seeds)
    return try finish(source,window:window,step:step,low:low,width:image.width,height:image.height,foreground:fg,background:bg)
  }
  static func strokeSeeds(_ points:[SIMD2<Float>],radius:Float,width w:Int,height h:Int)throws->[Bool] {
    var mask=[Bool](repeating:false,count:w*h)
    for index in 0..<max(1,points.count-1) {
      try Task.checkCancellation();let a=points[index],b=points[min(index+1,points.count-1)]
      let x0=min(w,max(0,Int(floor(min(a.x,b.x)-radius)))),y0=min(h,max(0,Int(floor(min(a.y,b.y)-radius))))
      let x1=min(w,max(0,Int(ceil(max(a.x,b.x)+radius)))),y1=min(h,max(0,Int(ceil(max(a.y,b.y)+radius))))
      let dx=b.x-a.x,dy=b.y-a.y,length=dx*dx+dy*dy
      for y in y0..<max(y0,y1) {for x in x0..<max(x0,x1) {
        let px=Float(x)+0.5,py=Float(y)+0.5,t=length>0 ? min(1,max(0,((px-a.x)*dx+(py-a.y)*dy)/length)):0
        let qx=a.x+t*dx-px,qy=a.y+t*dy-py
        if qx*qx+qy*qy<=radius*radius {mask[y*w+x]=true}
      }}
    }
    for p in points where p.x>=0 && p.y>=0 && p.x<Float(w) && p.y<Float(h) {mask[Int(p.y)*w+Int(p.x)]=true}
    return mask
  }
  static func quickSegment(_ image:SelectionImage,seeds:[Bool])throws->(SelectionColorModel,SelectionColorModel,[Bool]) {
    let geo=try geodesic(image,seeds:seeds)
    let fs=subsample(image.pixels.indices.filter{seeds[$0]}.map{image.pixels[$0]},20_000)
    let bs=subsample(image.pixels.indices.filter{geo[$0]>0.06}.map{image.pixels[$0]},20_000)
    let fg=try SelectionColorModel.fit(fs,count:min(4,max(1,fs.count/40)),ridge:6e-4) ?? SelectionColorModel.broad()
    let bg=bs.count>=30 ? try SelectionColorModel.fit(bs,count:6,ridge:6e-4):nil
    var cf=[Float](repeating:0,count:seeds.count),cb=cf
    for i in seeds.indices {
      if i%1024==0{try Task.checkCancellation()};let p=image.pixels[i]
      cf[i]=fg.cost(p)+2*min(4,geo[i]/0.06)
      if let bg {cb[i] = -Float(log(0.85*exp(bg.logProbability(p))+0.15))}
    }
    let cut=try gridCut(image,foreground:cf,background:cb,fixed:seeds.map{$0 ? 1:0},beta:beta(image))
    return try (fg,bg ?? SelectionColorModel.broad(),keepSeeded(cut,seeds:seeds,image.width,image.height))
  }
  private static func blur(_ image:SelectionImage)throws->SelectionImage {
    let w=image.width,h=image.height;var tmp=image,out=image
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {tmp.pixels[y*w+x]=(image.at(max(0,x-1),y)+image.at(x,y)+image.at(min(w-1,x+1),y))/3}}
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {out.pixels[y*w+x]=(tmp.at(x,max(0,y-1))+tmp.at(x,y)+tmp.at(x,min(h-1,y+1)))/3}}
    return out
  }
  static func geodesic(_ image:SelectionImage,seeds:[Bool])throws->[Float] {
    let w=image.width,h=image.height,sm=try blur(blur(image));var near=[Bool](repeating:false,count:w*h),g=[Float](repeating:0,count:w*h)
    for i in seeds.indices where seeds[i] {let x=i%w,y=i/w;for yy in max(0,y-2)..<min(h,y+3){for xx in max(0,x-2)..<min(w,x+3){near[yy*w+xx]=true}}}
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      g[y*w+x]=sqrt((selectionDistance(sm.at(max(0,x-1),y),sm.at(min(w-1,x+1),y))+selectionDistance(sm.at(x,max(0,y-1)),sm.at(x,min(h-1,y+1))))*0.25)
    }}
    let samples=g.indices.filter{near[$0]}.map{g[$0]}.sorted(),median=samples.isEmpty ? 0:samples[samples.count/2],threshold=max(2*median,0.03)
    let e=g.map{max(0,$0-threshold)};var distance=seeds.map{$0 ? Float(0):Float.infinity}
    func cost(_ i:Int,_ j:Int,_ length:Float)->Float {length*(0.5*(e[i]+e[j])+1e-6)}
    let squareRoot=Float(2).squareRoot()
    for _ in 0..<2 {
      for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
        let i=y*w+x;var v=distance[i]
        if x>0{v=min(v,distance[i-1]+cost(i,i-1,1))}
        if y>0{v=min(v,distance[i-w]+cost(i,i-w,1));if x>0{v=min(v,distance[i-w-1]+cost(i,i-w-1,squareRoot))};if x+1<w{v=min(v,distance[i-w+1]+cost(i,i-w+1,squareRoot))}}
        distance[i]=v
      }}
      for y in (0..<h).reversed() {try Task.checkCancellation();for x in (0..<w).reversed() {
        let i=y*w+x;var v=distance[i]
        if x+1<w{v=min(v,distance[i+1]+cost(i,i+1,1))}
        if y+1<h{v=min(v,distance[i+w]+cost(i,i+w,1));if x+1<w{v=min(v,distance[i+w+1]+cost(i,i+w+1,squareRoot))};if x>0{v=min(v,distance[i+w-1]+cost(i,i+w-1,squareRoot))}}
        distance[i]=v
      }}
    }
    return distance
  }
}
