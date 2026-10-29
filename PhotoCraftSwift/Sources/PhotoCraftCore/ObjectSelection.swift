import Foundation

extension SelectionSegmentation {
  /// Iterated GrabCut with source full-covariance color models, extended to lasso initialization.
  public static func object(_ source:Surface,region:SelectionMask,workPixels:Int=160_000)throws->SelectionMask {
    try check(source)
    guard region.width==source.width,region.height==source.height,workPixels>0,workPixels<=workingPixels else{throw CraftError.invalid("Invalid Object Selection region or work budget.")}
    guard let rect=region.bounds,rect.width>=2,rect.height>=2 else{return try .init(width:source.width,height:source.height,bytes:Array(repeating:0,count:source.width*source.height))}
    let margin=max(8,Int(ceil(Float(max(rect.width,rect.height))*0.15))),window=inflate(rect,margin,source.width,source.height)
    let step=max(1,Int(ceil(sqrt(Double(window.width*window.height)/Double(workPixels))))),image=try SelectionImage(source,rect:window,step:step),w=image.width,h=image.height
    var trimap=[UInt8](repeating:0,count:w*h),background=false
    for y in 0..<h {for x in 0..<w {
      let inside=region.coverage(x:window.x+x*step+step/2,y:window.y+y*step+step/2)>=0.5
      if inside{trimap[y*w+x]=3}else{background=true}
    }}
    if !background {
      let ring=max(1,min(w,h)/50)
      for y in 0..<h {for x in 0..<w where x<ring || y<ring || x+ring>=w || y+ring>=h {trimap[y*w+x]=0}}
    }
    guard let (fg,bg)=try grabcut(image,trimap:&trimap,iterations:8) else {throw CraftError.invalid("Object Selection needs distinct foreground and background regions.")}
    let low=try clean(trimap.map{$0==1 || $0==3},w,h)
    return try finish(source,window:window,step:step,low:low,width:w,height:h,foreground:fg,background:bg)
  }
  static func grabcut(_ image:SelectionImage,trimap:inout [UInt8],iterations:Int)throws->(SelectionColorModel,SelectionColorModel)? {
    let b=try beta(image),fixed: [UInt8]=trimap.map{$0==1 ? 1:($0==0 ? 2:0)}
    var models:(SelectionColorModel,SelectionColorModel)?
    for _ in 0..<max(1,iterations) {
      try Task.checkCancellation();var fs:[SelectionRGB]=[],bs:[SelectionRGB]=[]
      for i in trimap.indices {if trimap[i]==1 || trimap[i]==3 {fs.append(image.pixels[i])}else{bs.append(image.pixels[i])}}
      fs=subsample(fs,40_000);bs=subsample(bs,40_000)
      let fg:SelectionColorModel,bg:SelectionColorModel
      if let (f,b)=models {fg=try f.refit(fs) ?? f;bg=try b.refit(bs) ?? b}
      else {guard let f=try SelectionColorModel.fit(fs,count:5,ridge:2e-5),let b=try SelectionColorModel.fit(bs,count:5,ridge:2e-5) else{return nil};fg=f;bg=b}
      let cf=image.pixels.map{fg.cost($0)},cb=image.pixels.map{bg.cost($0)}
      let cut=try gridCut(image,foreground:cf,background:cb,fixed:fixed,beta:b);var changed=0
      for i in trimap.indices where trimap[i]==2 || trimap[i]==3 {let label:UInt8=cut[i] ? 3:2;if label != trimap[i]{changed+=1};trimap[i]=label}
      models=(fg,bg);if changed*2000<trimap.count {break}
    }
    return models
  }
}
