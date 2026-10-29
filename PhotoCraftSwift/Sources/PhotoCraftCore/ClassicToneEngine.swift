import Foundation

/// Licensed PhotoCraft tone.rs/color conversion/Equalize algorithms translated into Swift.
public enum ClassicToneEngine {
  public typealias Sample=SIMD4<Float>
  public static let maximumPixels=8_388_608
  static func unit(_ x:Float)->Float {min(1,max(0,x))}
  static func luma(_ p:Sample)->Float {0.299*p.x+0.587*p.y+0.114*p.z}
  static func smooth(_ a:Float,_ b:Float,_ x:Float)->Float {let t=unit((x-a)/(b-a));return t*t*(3-2*t)}
  static func lab(_ p:Sample)->SIMD3<Float> {
    let a=SIMD3<Float>(SRGBTransfer.linear(p.x),SRGBTransfer.linear(p.y),SRGBTransfer.linear(p.z))
    let xyz=SIMD3<Float>((0.436074*a.x+0.385064*a.y+0.143080*a.z)/0.96422,0.222504*a.x+0.716878*a.y+0.060618*a.z,(0.013932*a.x+0.097104*a.y+0.714173*a.z)/0.82521)
    let delta:Float=6/29
    func f(_ t:Float)->Float {t>delta*delta*delta ? cbrt(t):t/(3*delta*delta)+4/29}
    let x=f(xyz.x),y=f(xyz.y),z=f(xyz.z);return SIMD3(116*y-16,500*(x-y),200*(y-z))
  }
  static func rgb(_ lab:SIMD3<Float>)->SIMD3<Float> {
    let y=(lab.x+16)/116,x=y+lab.y/500,z=y-lab.z/200,d:Float=6/29
    func f(_ t:Float)->Float {t>d ? t*t*t:3*d*d*(t-4/29)}
    let a=SIMD3<Float>(f(x)*0.96422,f(y),f(z)*0.82521)
    return SIMD3(SRGBTransfer.encoded(unit(3.133856*a.x-1.616867*a.y-0.490615*a.z)),SRGBTransfer.encoded(unit(-0.978768*a.x+1.916142*a.y+0.033454*a.z)),SRGBTransfer.encoded(unit(0.071945*a.x-0.228991*a.y+1.405243*a.z)))
  }
  /// Source Gaussian uses all three horizontal passes before all vertical passes.
  static func gaussian(_ pixels:[Float],_ w:Int,_ h:Int,_ sigma:Float)throws->[Float] {
    if sigma<0.3{return pixels}
    var lower=Int(floor(sqrt(12*sigma*sigma/3+1)));if lower%2==0{lower-=1};lower=max(1,lower)
    let l=Float(lower),m=Int(min(3,max(0,((12*sigma*sigma-3*l*l-12*l-9)/(-4*l-4)).rounded())))
    let radii=(0..<3).map{(($0<m ? lower:lower+2)-1)/2};var out=pixels
    for vertical in [false,true] {for r in radii where r>0 {
      let length=vertical ? h:w,lines=vertical ? w:h,norm=1/Double(2*r+1)
      for line in 0..<lines {try Task.checkCancellation()
        let row=(0..<length).map{out[vertical ? $0*w+line:line*w+$0]}
        func at(_ i:Int)->Double {Double(row[min(length-1,max(0,i))])}
        var acc=(-r...r).reduce(0.0){$0+at($1)}
        for i in 0..<length {out[vertical ? i*w+line:line*w+i]=Float(acc*norm);acc+=at(i+r+1)-at(i-r)}
      }
    }};return out
  }
  public static func statistics(_ source:Surface,mask:[Float]?=nil)throws->ToneColorStatistics {
    try statistics(try samples(source),mask:mask)
  }
  static func statistics(_ pixels:[Sample],mask:[Float]?=nil)throws->ToneColorStatistics {
    if let mask {guard mask.count==pixels.count,mask.allSatisfy({$0.isFinite && (0...1).contains($0)}) else{throw CraftError.invalid("Invalid statistics selection.")}}
    var sum=SIMD3<Double>.zero,sq=SIMD3<Double>.zero,total=0.0
    for (i,p) in pixels.enumerated(){if i%4096==0{try Task.checkCancellation()};let w=Double(p.w*(mask?[i] ?? 1));if w<=0{continue};let c=lab(p),v=SIMD3<Double>(Double(c.x),Double(c.y),Double(c.z));sum+=v*w;sq+=v*v*w;total+=w}
    guard total>0 else{throw CraftError.invalid("The statistics source has no selected opaque pixels.")}
    let mean=(0..<3).map{Float(sum[$0]/total)},std=(0..<3).map{Float(sqrt(max(0,sq[$0]/total-pow(sum[$0]/total,2))))}
    let result=ToneColorStatistics(mean:mean,standardDeviation:std);try result.validate();return result
  }
  static func samples(_ source:Surface)throws->[Sample] {
    guard source.width<=maximumPixels/source.height else{throw CraftError.unsupported("Tone adjustments support up to8,388,608 pixels.")}
    var result=[Sample]();result.reserveCapacity(source.width*source.height)
    for y in 0..<source.height {try Task.checkCancellation();for x in 0..<source.width {let p=source.pixel(x:x,y:y);guard p.isFinite,max(abs(p.r),abs(p.g),abs(p.b))<=1e12 else{throw CraftError.invalid("Tone input exceeds the supported numeric range.")};result.append(Sample(p.r,p.g,p.b,p.a))}}
    return result
  }
  static func shadows(_ input:[Sample],_ w:Int,_ h:Int,_ s:ClassicToneSettings)throws->[Sample] {
    let ls=try gaussian(input.map(luma),w,h,Float(s.shadowRadius)/2),lh=abs(s.highlightRadius-s.shadowRadius)<0.001 ? ls:try gaussian(input.map(luma),w,h,Float(s.highlightRadius)/2)
    let sa=Float(s.shadowAmount)/100,ha=Float(s.highlightAmount)/100,st=max(0.01,Float(s.shadowTone)/100),ht=max(0.01,Float(s.highlightTone)/100),color=Float(s.colorCorrection)/100,mid=Float(s.midtone)/100
    var out=input
    for i in out.indices {if i%w==0{try Task.checkCancellation()};if out[i].w<=0{continue};let ms=1-smooth(0,st,ls[i]),mh=smooth(1-ht,1,lh[i]);var p=out[i]
      if sa>0,ms>0 {let g=1/(1+2*sa*ms);for c in 0..<3{p[c]=pow(max(0,p[c]),g)}}
      if ha>0,mh>0 {let g=1/(1+2*ha*mh);for c in 0..<3{p[c]=1-pow(1-min(1,p[c]),g)}}
      if mid != 0 {let k=1+mid*unit(1-ms-mh);for c in 0..<3{p[c]=(p[c]-0.5)*k+0.5}}
      let changed=min(1,ms*sa+mh*ha)
      if color != 0,changed>0 {let l=luma(p),k=1+color*changed;for c in 0..<3{p[c]=l+(p[c]-l)*k}}
      for c in 0..<3{p[c]=unit(p[c])};out[i]=p
    }
    if s.blackClip>0 || s.whiteClip>0 {
      var histogram=[Int](repeating:0,count:1024),n=0
      for p in out where p.w>0 {histogram[Int((unit(luma(p))*1023).rounded())]+=1;n+=1}
      if n>0 {
        func find(_ percentage:Double,_ reverse:Bool)->Float {let target=Int(Float(percentage)/100*Float(n));var acc=0;for k in 0..<1024{let i=reverse ? 1023-k:k;acc+=histogram[i];if acc>target{return Float(i)/1023}};return reverse ? 0:1}
        let lo=find(s.blackClip,false),hi=find(s.whiteClip,true)
        if hi-lo>=0.001 {for i in out.indices where out[i].w>0 {if i%w==0{try Task.checkCancellation()};for c in 0..<3{out[i][c]=unit((out[i][c]-lo)/(hi-lo))}}}
      }
    };return out
  }
  public static func replacementMask(_ source:Surface,settings s:ClassicToneSettings,origin:PathPoint=PathPoint(0,0),canvasSize:PathPoint?=nil)throws->[Float] {
    try s.validate();guard s.kind == .replaceColor else{throw CraftError.invalid("Replace Color settings required.")}
    return try replacementMask(samples(source),width:source.width,height:source.height,settings:s,origin:origin,canvasSize:canvasSize)
  }
  static func replacementMask(_ input:[Sample],width w:Int,height h:Int,settings s:ClassicToneSettings,origin:PathPoint,canvasSize:PathPoint?)throws->[Float] {
    let cw=Float(canvasSize?.x ?? Double(w)),ch=Float(canvasSize?.y ?? Double(h)),f=Float(s.fuzziness)+1
    var result=[Float](repeating:0,count:input.count)
    for (i,p) in input.enumerated() {if i%w==0{try Task.checkCancellation()};if p.w<=0{continue};var add:Float=0,subtract:Float=0
      for sample in s.samples {let c=sample.color,d=max(abs(p.x-c.r),max(abs(p.y-c.g),abs(p.z-c.b)))*255;var k=unit(1-d/f)
        if s.localized,let point=sample.point {let dx=Float(i%w)+Float(origin.x)-Float(point.x)*cw,dy=Float(i/w)+Float(origin.y)-Float(point.y)*ch;k*=unit(1-sqrt(dx*dx+dy*dy)/Float(s.localRadius))}
        if sample.subtract{subtract=max(subtract,k)}else{add=max(add,k)}
      };result[i]=max(0,add-subtract)
    };return result
  }
  static func hdr(_ input:[Sample],_ w:Int,_ h:Int,_ s:ClassicToneSettings)throws->[Sample] {
    if s.method != .localAdaptation {
      var settings=HDRMergeSettings();settings.method=s.method;settings.gamma=Float(s.gamma);settings.exposure=Float(s.exposure)
      let linear=input.map{Sample(SRGBTransfer.linear($0.x),SRGBTransfer.linear($0.y),SRGBTransfer.linear($0.z),$0.w)}
      return try HDRMergeMath.toneMap(linear,width:w,height:h,settings:settings)
    }
    let logs=input.map{log(max(0,luma($0))+1e-4)},base=try gaussian(logs,w,h,Float(s.radius)/2),n=max(1,input.filter{$0.w>0}.count)
    let mean=input.indices.filter{input[$0].w>0}.reduce(Float(0)){$0+base[$1]}/Float(n),compress=1/(1+Float(s.strength)),detail=1+Float(s.detail)/100,exposure=pow(Float(2),Float(s.exposure)),gamma=Float(s.gamma)
    func curve(_ value:Float)->Float {if s.curve.count<2{return value};if value<=s.curve[0][0]{return s.curve[0][1]};for i in 1..<s.curve.count where value<=s.curve[i][0]{let a=s.curve[i-1],b=s.curve[i];return a[1]+(b[1]-a[1])*(value-a[0])/max(1e-6,b[0]-a[0])};return s.curve.last![1]}
    var out=input
    for i in out.indices {if i%w==0{try Task.checkCancellation()};if out[i].w<=0{continue};let l0=max(0,luma(input[i]))+1e-4,newLog=mean+(base[i]-mean)*compress+(logs[i]-base[i])*detail
      var l1=pow(max(0,exp(newLog)*exposure),gamma);l1+=Float(s.shadow)/100*pow(1-l1,3)*0.5-Float(s.highlight)/100*pow(l1,3)*0.5;l1=curve(unit(l1))
      var p=input[i];for c in 0..<3{p[c]*=l1/l0};let ll=luma(p),hi=max(p.x,p.y,p.z),lo=min(p.x,p.y,p.z),sat=hi>0 ? (hi-lo)/hi:0,k=max(0,1+Float(s.hdrSaturation)/100+Float(s.vibrance)/100*(1-sat))
      for c in 0..<3{out[i][c]=unit(ll+(p[c]-ll)*k)}
    };return out
  }
  public static func render(_ source:Surface,settings s:ClassicToneSettings,statisticsMask:[Float]?=nil,origin:PathPoint=PathPoint(0,0),canvasSize:PathPoint?=nil)throws->Surface {
    try s.validate();let input=try samples(source),w=source.width,h=source.height
    if let mask=statisticsMask {guard mask.count==input.count,mask.allSatisfy({$0.isFinite && (0...1).contains($0)}) else{throw CraftError.invalid("Invalid statistics mask.")}}
    var output=input
    switch s.kind {
    case .shadowsHighlights:output=try shadows(input,w,h,s)
    case .hdrToning:output=try hdr(input,w,h,s)
    case .replaceColor:
      let mask=try replacementMask(input,width:w,height:h,settings:s,origin:origin,canvasSize:canvasSize)
      for i in output.indices {if i%w==0{try Task.checkCancellation()};let k=mask[i];if k<=0{continue};let p=input[i],v=OtherVideoEngine.encode(p,to:.hsl),sat=Float(s.saturation),light=Float(s.lightness)
        let ss=sat>=0 ? v.y+(1-v.y)*sat/100:v.y*(1+sat/100),ll=light>=0 ? v.z+(1-v.z)*light/100:v.z*(1+light/100)
        let q=OtherVideoEngine.rgb(Sample(OtherVideoEngine.rem(v.x+Float(s.hue)/360,1),unit(ss),unit(ll),p.w),from:.hsl)
        for c in 0..<3{output[i][c]=unit(p[c]+(q[c]-p[c])*k)}
      }
    case .matchColor:
      if s.sourceStatistics==nil,s.luminance==100,s.intensity==100,s.fade==0,!s.neutralize{return source}
      let target=try statistics(input,mask:s.useSelectionInTarget ? statisticsMask:nil),src=s.sourceStatistics ?? target,fade=Float(s.fade)/100
      for i in output.indices {if i%w==0{try Task.checkCancellation()};if input[i].w<=0{continue};let p=lab(input[i]);var q=SIMD3<Float>.zero
        for c in 0..<3{let scale=target.standardDeviation[c]>1e-4 ? src.standardDeviation[c]/target.standardDeviation[c]:1,mean=s.neutralize && c>0 ? 0:src.mean[c];q[c]=((p[c]-target.mean[c])*scale+mean)*Float(c==0 ? s.luminance:s.intensity)/100};q.x=min(100,max(0,q.x));let o=rgb(q)
        for c in 0..<3{output[i][c]=unit(o[c]+(input[i][c]-o[c])*fade)}
      }
    case .equalize:
      var histogram=[Double](repeating:0,count:256)
      for (i,p) in input.enumerated() where p.w>0 && (statisticsMask?[i] ?? 1)>0 {if i%w==0{try Task.checkCancellation()};for c in 0..<3{histogram[Int((unit(p[c])*255).rounded())]+=1}}
      let total=histogram.reduce(0,+),first=histogram.first(where:{$0>0}) ?? 0;if total<=first{return source};var acc=0.0,lut=[Float](repeating:0,count:256)
      for i in 0..<256{acc+=histogram[i];lut[i]=Float(min(1,max(0,(acc-first)/(total-first))))}
      for i in output.indices {if i%w==0{try Task.checkCancellation()};if input[i].w<=0{continue};for c in 0..<3{output[i][c]=lut[Int((unit(input[i][c])*255).rounded())]}}
    }
    var result=source
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {let i=y*w+x,q=output[i];if q==input[i]{continue};let p=Pixel(q.x,q.y,q.z,q.w);guard p.isFinite else{throw CraftError.invalid("Tone result exceeds supported numeric limits.")};result.setPixel(x:x,y:y,p)}};return result
  }
  public static func validateTarget(_ request:ClassicToneRequest,in d:CraftDocument)throws->Int {
    try request.validate();guard d.width<=maximumPixels/d.height else{throw CraftError.unsupported("Tone adjustments support up to8,388,608 canvas pixels.")}
    guard request.settings.kind != .hdrToning,let id=request.layerID ?? d.activeLayerID,let i=d.layers.firstIndex(where:{$0.id==id}),case .raster=d.layers[i].content,!d.isLocked(id),!d.isImageLocked(id) else{throw CraftError.invalid("Choose an unlocked pixel layer for this adjustment.")}
    guard d.layers[i].smartObject==nil || request.settings.kind == .shadowsHighlights else{throw CraftError.unsupported("This adjustment requires ordinary pixels; rasterize the Smart Object first.")};return i
  }
  static func apply(_ request:ClassicToneRequest,to document:inout CraftDocument)throws {
    let i=try validateTarget(request,in:document),s=request.settings,id=document.layers[i].id
    if document.layers[i].smartObject != nil {var f=RasterFilter(.shadowsHighlights);f.tone=s;try SmartFilterEngine.append(f,to:id,in:&document);return}
    guard case .raster(let source)=document.layers[i].content else{return}
    let original=document,extent=try SmartFilterEngine.renderBounds(document.layers[i],in:document)
    let ignore=s.kind == .equalize && s.equalizeEntireImage || s.kind == .matchColor && s.ignoreSelection
    let area=(ignore ? IntRect(x:0,y:0,width:document.width,height:document.height):document.selection ?? IntRect(x:0,y:0,width:document.width,height:document.height)).clipped(toWidth:document.width,height:document.height)
    guard area.width>0,area.height>0 else{return};var layer=document.layers[i]
    let mapped:Surface=layer.affine==nil ? try source.expanded(to:IntRect(x:extent.x-layer.x,y:extent.y-layer.y,width:extent.width,height:extent.height),fill:.clear):try RasterGeometry.render(source,transform:layer.coordinateTransform,bounds:extent,method:.bicubic,clampEdges:false)
    guard mapped.width<=maximumPixels/mapped.height else{throw CraftError.unsupported("Expanded tone target exceeds8,388,608 pixels.")}
    var mask=[Float]();mask.reserveCapacity(mapped.width*mapped.height)
    for y in 0..<mapped.height{try Task.checkCancellation();for x in 0..<mapped.width{mask.append(document.selectionCoverage(x:x+extent.x,y:y+extent.y))}}
    let output=try render(mapped,settings:s,statisticsMask:mask,origin:PathPoint(Double(extent.x),Double(extent.y)),canvasSize:PathPoint(Double(document.width),Double(document.height)))
    if output==mapped{return};let protect=document.isTransparencyLocked(id)
    _=try ClonePainter.paintTarget(mask:false,bounds:area,on:&layer,clipping:area,preserveTransparency:protect){pixels,transform,_ in
      guard pixels.width<=maximumPixels/pixels.height else{throw CraftError.unsupported("Expanded tone storage exceeds8,388,608 pixels.")};var changed=false
      for y in 0..<pixels.height{try Task.checkCancellation();for x in 0..<pixels.width{let q=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(q.x)),dy=Int(floor(q.y));guard area.contains(dx,dy) else{continue}
        let coverage=ignore ? 1:original.selectionCoverage(x:dx,y:dy);if coverage<=0{continue};let before=pixels.pixel(x:x,y:y);if protect && before.a==0{continue}
        var after=output.pixel(x:dx-extent.x,y:dy-extent.y);after.a=before.a
        let value=coverage>=1 ? after:before.mixing(after,coverage:coverage);if value.hasSameBits(as:before){continue};changed=true;pixels.setPixel(x:x,y:y,value)
      }};return changed
    };document.layers[i]=layer
  }
}
public struct HDRToningEdit:Sendable {
  public let source:CraftDocument
  public let result:CraftDocument
  public init(source:CraftDocument,result:CraftDocument){self.source=source;self.result=result}
  public func applied(to d:CraftDocument)throws->CraftDocument{try Task.checkCancellation();guard d==source else{throw CraftError.invalid("The document changed during HDR Toning.")};try result.validate();return result}
}
