import Foundation

/// Color-aware deposition uses PhotoCraft's replace/bg_erase/mixer models.
/// Pattern Stamp is an independent native implementation over the shared tips.
public enum PaintToolPainter {
  static func distance(_ a:Pixel,_ b:Pixel)->Float { max(abs(a.r-b.r),max(abs(a.g-b.g),abs(a.b-b.b))) }
  static func gray(_ p:Pixel)->Pixel { let v=unit(p.r*0.2126+p.g*0.7152+p.b*0.0722);return Pixel(v,v,v,p.a) }
  static func connected(_ weights:inout [Float],width:Int,height:Int,x:Int,y:Int) throws {
    let first=min(height-1,max(0,y))*width+min(width-1,max(0,x))
    guard weights[first]>0 else { weights=Array(repeating:0,count:weights.count);return }
    var seen=Array(repeating:false,count:weights.count),stack=[first];seen[first]=true
    var visits=0
    while let i=stack.popLast() {
      visits += 1;if visits%16384==0 {try Task.checkCancellation()}
      let x=i%width,y=i/width
      for j in [x>0 ? i-1:-1,x+1<width ? i+1:-1,y>0 ? i-width:-1,y+1<height ? i+width:-1] where j>=0 {
        if !seen[j] && weights[j]>0 { seen[j]=true;stack.append(j) }
      }
    }
    for i in weights.indices where !seen[i] { weights[i]=0 }
  }
  public static func stroke(surface:inout Surface,request:PaintToolRequest,brush:Brush,transform:Transform2D,canvasWidth:Int,canvasHeight:Int,
    selection:IntRect?,selectionMask:SelectionMask?,grayscale:Bool,preserveTransparency:Bool,
    sample:Surface?,mixer:inout MixerPaint) throws {
    try request.validate();try transform.validated();guard !request.points.isEmpty,let b=brush.settings else { return }
    if request.options.sampleAllLayers && sample==nil { throw CraftError.invalid("The all-layer sample is missing.") }
    try sample?.validated();let o=request.options,original=surface,inverse=try transform.inverted()
    var work=surface,state=mixer,visits=0,left=surface.width,top=surface.height,right = -1,bottom = -1
    func selectionAt(_ x:Int,_ y:Int)->Float {
      let p=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(p.x)),dy=Int(floor(p.y))
      if let selection,!selection.contains(dx,dy) { return 0 };return selectionMask?.coverage(x:dx,y:dy) ?? 1
    }
    if request.tool == .magicEraser {
      guard let point=request.points.first else { return }
      let width=canvasWidth,height=canvasHeight
      guard width>0,height>0,width<=16_777_216/height else { throw CraftError.invalid("Magic Eraser sampling is limited to 16 megapixels.") }
      var options=ColorMatchOptions();options.tolerance=Int((o.tolerance*255).rounded());options.contiguous=o.contiguous;options.antiAlias=o.antiAlias
      let source=CloneSample(surface:sample ?? original,transform:sample==nil ? transform:.identity)
      let region=try ColorRegion.selection(source:source,width:width,height:height,seed:PathPoint(point.x,point.y),options:options)
      for y in 0..<work.height { try Task.checkCancellation();for x in 0..<work.width {
        let p=transform.point(Double(x)+0.5,Double(y)+0.5),k=region.coverage(x:Int(floor(p.x)),y:Int(floor(p.y)))*selectionAt(x,y)*brush.opacity
        guard k>0 else { continue };let before=original.pixel(x:x,y:y)
        if preserveTransparency { var ink=brush.backgroundColor ?? .white;ink.a=k;work.setPixel(x:x,y:y,ProtectedPixels.composite(.normal,backdrop:before,source:ink)) }
        else { work.setPixel(x:x,y:y,Pixel(before.r,before.g,before.b,before.a*(1-k))) }
      } }
      try Task.checkCancellation();surface=work;return
    }
    var generator=BrushDabGenerator(brush),dabs=try generator.push(request.points);let tail=try generator.finish();dabs.0 += tail.0;dabs.1 += tail.1
    let pattern=try request.pattern.map{try PatternSampler($0,placement:o.placement)}
    var once:Pixel?,onceSampled=false
    if request.tool == .mixerBrush && o.loadAfterStroke && state.reservoir==nil { state.load(brush.color) }
    for pass in BrushPainter.symmetry(b.symmetry) {
      let undoPass=try pass.inverted(),toLocal=inverse*pass,toBrush=undoPass*transform
      func rect(_ dab:BrushDab,_ bitmap:BrushBitmap?)->IntRect? {
        let reach=dab.radius*(bitmap==nil ? 1:sqrt(2))+1,p=toLocal.point(dab.x,dab.y)
        let rx=reach*hypot(toLocal.a,toLocal.c),ry=reach*hypot(toLocal.b,toLocal.d)
        let x0=Int(max(0,min(Double(work.width),floor(p.x-rx)))),x1=Int(max(-1,min(Double(work.width-1),ceil(p.x+rx))))
        let y0=Int(max(0,min(Double(work.height),floor(p.y-ry)))),y1=Int(max(-1,min(Double(work.height-1),ceil(p.y+ry))))
        return x0<=x1 && y0<=y1 ? .init(x:x0,y:y0,width:x1-x0+1,height:y1-y0+1):nil
      }
      func admit(_ area:Int) throws {
        guard area<=134_217_728-visits else { throw CraftError.invalid("Painting stroke exceeds the raster work limit.") };visits += area;try Task.checkCancellation()
      }
      var dual=try Surface(width:work.width,height:work.height,depth:.u8)
      if b.dual.enabled {
        for dab in dabs.1 {
          guard let box=rect(dab,b.dual.tip) else { continue };try admit(box.width*box.height)
          for y in box.y..<(box.y+box.height) { for x in box.x..<(box.x+box.width) {
            let p=toBrush.point(Double(x)+0.5,Double(y)+0.5),c=BrushPainter.tipCoverage(dab,p,bitmap:b.dual.tip,hardness:b.dual.hardness,aliased:false).0
            guard c>0 else { continue };let old=dual.pixel(x:x,y:y).a,k=old+Float(c*dab.flow)*(Float(dab.opacity)-old)
            dual.setPixel(x:x,y:y,Pixel(1,1,1,k))
          } }
          guard dual.allocatedBytes<=128*1024*1024 else { throw CraftError.invalid("Dual brush coverage exceeds 128 MiB.") }
        }
      }
      for dab in dabs.0 {
        guard let box=rect(dab,b.tip) else { continue };try admit(box.width*box.height)
        guard box.width*box.height<=16_777_216 else { throw CraftError.invalid("A transformed brush tip exceeds 16 megapixels.") }
        left=min(left,box.x);top=min(top,box.y);right=max(right,box.x+box.width-1);bottom=max(bottom,box.y+box.height-1)
        let center=toLocal.point(dab.x,dab.y),cx=Int(floor(center.x)),cy=Int(floor(center.y))
        var coverage=[Float](repeating:0,count:box.width*box.height)
        for y in 0..<box.height { for x in 0..<box.width {
          let lx=x+box.x,ly=y+box.y,p=toBrush.point(Double(lx)+0.5,Double(ly)+0.5),doc=transform.point(Double(lx)+0.5,Double(ly)+0.5)
          var (v,rn)=BrushPainter.tipCoverage(dab,p,bitmap:b.tip,hardness:Double(brush.hardness),aliased:b.aliased || (request.tool == .colorReplacement && !o.antiAlias))
          if b.texture.enabled { v=b.texture.mode.combine(v,BrushPainter.texture(b.texture,doc.x,doc.y),b.texture.eachTip ? dab.depth:b.texture.depth) }
          if b.dual.enabled { v=b.dual.mode.combine(v,Double(dual.pixel(x:lx,y:ly).a),1) }
          if b.noise && v<1 { v += ((BrushRandom.pixel(Int(floor(doc.x)),Int(floor(doc.y)),0x6E6F697365)<v ? 1:0)-v)*0.7 }
          if b.wetEdges { v *= 0.5+0.5*BrushPainter.smooth((rn-0.5)*2) }
          coverage[y*box.width+x]=Float(v*dab.flow*dab.opacity)
        } }
        if request.tool == .colorReplacement || request.tool == .backgroundEraser {
          let source=request.tool == .colorReplacement ? original:work
          let sampled:Pixel?
          switch o.sampling {
          case .backgroundSwatch:sampled=brush.backgroundColor ?? .white
          case .once:
            if !onceSampled { onceSampled=true;let c=source.pixel(x:cx,y:cy);once=c.a>0 ? c:nil };sampled=once
          case .continuous:let c=source.pixel(x:cx,y:cy);sampled=c.a>0 ? c:nil
          }
          guard let sampled else { continue }
          var weights=[Float](repeating:0,count:coverage.count)
          for y in 0..<box.height { for x in 0..<box.width where coverage[y*box.width+x]>0 {
            let c=source.pixel(x:x+box.x,y:y+box.y),distance=Self.distance(c,sampled),t=Float(o.tolerance)
            guard c.a>0,distance<=t else { continue }
            if request.tool == .backgroundEraser && o.protectForeground && Self.distance(c,brush.color)<=t { continue }
            weights[y*box.width+x]=(o.antiAlias && o.limits != .findEdges && t>0) ? unit((t-distance)/(t*0.25)):1
          } }
          if o.limits != .discontiguous { try connected(&weights,width:box.width,height:box.height,x:cx-box.x,y:cy-box.y) }
          for i in coverage.indices { coverage[i] *= weights[i] }
        }
        var mixerInk:Pixel?,deposit=Float(1)
        if request.tool == .mixerBrush {
          var color=SIMD3<Float>.zero,alpha:Float=0,total:Float=0
          for y in 0..<box.height { for x in 0..<box.width {
            let k=coverage[y*box.width+x];guard k>0 else { continue }
            let lx=x+box.x,ly=y+box.y,p=transform.point(Double(lx)+0.5,Double(ly)+0.5)
            let c=sample?.pixel(x:Int(floor(p.x)),y:Int(floor(p.y))) ?? work.pixel(x:lx,y:ly)
            color += SIMD3(c.r,c.g,c.b)*(k*c.a);alpha += k*c.a;total += k
          } }
          if alpha>0.000001 && o.wet>0 {
            let c=color/alpha,canvas=Pixel(c.x,c.y,c.z)
            if let pickup=state.pickup { state.pickup=pickup.mixing(canvas,coverage:Float(0.25*o.wet)*alpha/max(0.000001,total)) } else { state.pickup=canvas }
          }
          let wr=state.reservoir==nil ? 0:state.amount*(1-o.mix*o.wet),wp=state.pickup==nil ? 0:o.mix*o.wet,sum=wr+wp
          if sum>0.000001 {
            let a=state.reservoir ?? .clear,c=state.pickup ?? .clear,k=Float(wr/sum),j=Float(wp/sum)
            mixerInk=Pixel(a.r*k+c.r*j,a.g*k+c.g*j,a.b*k+c.b*j);deposit=Float(min(1,sum)*o.flow)
          }
        }
        let impression=pattern?.sample(x:dab.x,y:dab.y)
        for y in 0..<box.height { for x in 0..<box.width {
          let k=coverage[y*box.width+x];guard k>0 else { continue }
          let lx=x+box.x,ly=y+box.y,before=work.pixel(x:lx,y:ly)
          if preserveTransparency && before.a<=0 { continue }
          let doc=transform.point(Double(lx)+0.5,Double(ly)+0.5)
          switch request.tool {
          case .backgroundEraser:work.setPixel(x:lx,y:ly,Pixel(before.r,before.g,before.b,before.a*(1-unit(k))))
          case .colorReplacement:
            var ink=brush.color;ink.a=1
            let edited=o.replacementMode.composite(backdrop:Pixel(before.r,before.g,before.b),source:ink)
            work.setPixel(x:lx,y:ly,Pixel(before.r+(edited.r-before.r)*k,before.g+(edited.g-before.g)*k,before.b+(edited.b-before.b)*k,before.a))
          case .mixerBrush,.patternStamp:
            var ink:Pixel
            if request.tool == .patternStamp { ink=o.impressionist ? impression ?? .clear:pattern?.sample(x:doc.x,y:doc.y) ?? .clear }
            else {
              guard let loaded=mixerInk else { continue };ink=loaded
              if let tip=state.tip,let reservoir=state.reservoir {
                let p=toBrush.point(Double(lx)+0.5,Double(ly)+0.5),u=(p.x-dab.x)/(2*dab.radius)+0.5,v=(p.y-dab.y)/(2*dab.radius)+0.5
                let c=tip.pixel(x:min(tip.width-1,max(0,Int(u*Double(tip.width)))),y:min(tip.height-1,max(0,Int(v*Double(tip.height)))))
                let weight=Float(1-o.mix*o.wet);ink.r += (c.r-reservoir.r)*weight;ink.g += (c.g-reservoir.g)*weight;ink.b += (c.b-reservoir.b)*weight
              }
            }
            if grayscale { ink=gray(ink) };ink.a *= unit(k*deposit)
            let mode=request.tool == .mixerBrush ? BlendMode.normal:b.mode
            work.setPixel(x:lx,y:ly,preserveTransparency ? ProtectedPixels.composite(mode,backdrop:before,source:ink):mode.composite(backdrop:before,source:ink))
          default:break
          }
        } }
        if request.tool == .mixerBrush { state.amount *= 1-0.08*(1-o.load) }
      }
    }
    guard left<=right,top<=bottom else { return }
    guard (right-left+1)*(bottom-top+1)<=134_217_728 else { throw CraftError.invalid("Painting stroke bounds exceed the work limit.") }
    let opacity:Float=[.mixerBrush,.backgroundEraser].contains(request.tool) ? 1:brush.opacity
    var result=original
    for y in top...bottom { try Task.checkCancellation();for x in left...right {
      let k=selectionAt(x,y)*opacity;guard k>0 else { continue }
      var p=original.pixel(x:x,y:y).mixing(work.pixel(x:x,y:y),coverage:k)
      if grayscale { p=gray(p);p.a=1 }
      p=p.quantized(surface.depth)
      if !p.hasSameBits(as:original.pixel(x:x,y:y)) { result.setPixel(x:x,y:y,p) }
    } }
    try Task.checkCancellation();surface=result;mixer=state
  }
}
