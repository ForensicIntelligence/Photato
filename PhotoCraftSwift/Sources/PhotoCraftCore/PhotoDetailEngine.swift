import Foundation

/// Native photo-finishing operations. Rust-derived denoising and Gaussian sharpening;
/// Lens/Motion are Photato deconvolution extensions, not Adobe algorithm equivalence.
public enum PhotoDetailEngine {
  public static func render(_ source:Surface,filter:RasterFilter,transform:Transform2D = .identity)throws->Surface {
    try filter.validate();guard filter.kind == .smartSharpen || filter.kind == .reduceNoise else { throw CraftError.invalid("Expected a photo detail filter.") }
    if filter.sharpen?.isIdentity == true || filter.denoise?.isIdentity == true { return source }
    try transform.validated()
    let w=source.width,h=source.height,n=w*h,linear=source.depth == .f32
    guard w<=RasterFilterEngine.maximumPixels/h else { throw CraftError.unsupported("Photo detail filters support layers up to8MP.") }
    var rgb=[[Float]](repeating:[Float](repeating:0,count:n),count:3),alpha=[Float](repeating:0,count:n)
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let p=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y);guard p.isFinite,max(abs(p.r),abs(p.g),abs(p.b))<=1e6 else { throw CraftError.invalid("Invalid photo detail input.") };let i=y*w+x;rgb[0][i]=p.r;rgb[1][i]=p.g;rgb[2][i]=p.b;alpha[i]=p.a } }
    if let settings=filter.sharpen { rgb=try sharpen(rgb,alpha,w,h,settings) }
    if let settings=filter.denoise { rgb=try denoise(rgb,w,h,settings,transform) }
    var result=source
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let i=y*w+x;guard alpha[i]>0 else { continue };let p=Pixel(rgb[0][i],rgb[1][i],rgb[2][i],alpha[i]);guard p.isFinite else { throw CraftError.invalid("Nonfinite photo detail output.") };if linear { result.setLinearPixel(x:x,y:y,p) } else { result.setPixel(x:x,y:y,p) } } }
    return result
  }
  static func apply(_ filter:RasterFilter,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws {
    let matrix=document.layers[index].coordinateTransform
    let edited=try render(source,filter:filter,transform:matrix),protect=document.isTransparencyLocked(layerID),linear=document.depth == .f32
    var result=source
    for y in 0..<source.height { try Task.checkCancellation();for x in 0..<source.width { let q=matrix.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)));if coverage<=0 { continue }
      let a=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y);if protect && a.a==0 { continue };let b=linear ? edited.linearPixel(x:x,y:y):edited.pixel(x:x,y:y),value=coverage>=1 ? b:a.mixing(b,coverage:coverage)
      if linear { result.setLinearPixel(x:x,y:y,value) } else { result.setPixel(x:x,y:y,value) }
    } };document.layers[index].content = .raster(result)
  }
  static func sharpen(_ input:[[Float]],_ alpha:[Float],_ w:Int,_ h:Int,_ s:SmartSharpenSettings)throws->[[Float]] {
    var detail=input
    if s.remove == .gaussian {
      let a=try MattingFilters.gaussian(alpha,w,h,Float(s.radius))
      for c in 0..<3 { let premult=zip(input[c],alpha).map(*);let blurred=try MattingFilters.gaussian(premult,w,h,Float(s.radius));for i in alpha.indices { detail[c][i]=input[c][i]-(a[i]>1e-6 ? blurred[i]/a[i]:input[c][i]) } }
    } else {
      var planes=input.map{zip($0,alpha).map(*)};planes.append(alpha)
      let restored=try DetailDeconvolution.restore(planes,w,h,s)
      for c in 0..<3 { for i in alpha.indices { detail[c][i]=(restored[3][i]>1e-4 ? restored[c][i]/restored[3][i]:input[c][i])-input[c][i] } }
    }
    var weight=[Float](repeating:1,count:alpha.count)
    if s.shadows.fadeAmount>0 || s.highlights.fadeAmount>0 {
      let luma=alpha.indices.map{0.299*input[0][$0]+0.587*input[1][$0]+0.114*input[2][$0]}
      for (t,shadow) in [(s.shadows,true),(s.highlights,false)] where t.fadeAmount>0 {
        let smooth=try GalleryMath.blur(luma,w,h,1,Float(t.radius)),width=Float(t.tonalWidth/100),fade=Float(t.fadeAmount/100)
        for i in weight.indices { let tone=shadow ? smooth[i]:1-smooth[i];let mask=max(0,min(1,1-tone/width));weight[i] *= 1-fade*mask }
      }
    }
    var output=input;let amount=Float(s.amount/100),noise=Float(s.reduceNoise/100)
    for c in 0..<3 { try Task.checkCancellation();for i in alpha.indices { let d=detail[c][i],keep=1-noise*exp(-abs(d)*40);output[c][i] += amount*d*keep*weight[i] } }
    return output
  }
  static func box(_ input:[Float],_ w:Int,_ h:Int,_ channels:Int,_ radius:Int)throws->[Float] {
    try GalleryMath.line(GalleryMath.line(input,w,h,channels,(1,0),radius),w,h,channels,(0,1),radius)
  }
  static func guided(_ guide:[Float],_ plane:[Float],_ w:Int,_ h:Int,_ radius:Int,_ epsilon:Float)throws->[Float] {
    let n=guide.count;var m=[Float](repeating:0,count:n*4)
    for i in 0..<n { m[i*4]=guide[i];m[i*4+1]=plane[i];m[i*4+2]=guide[i]*guide[i];m[i*4+3]=guide[i]*plane[i] }
    m=try box(m,w,h,4,radius);var ab=[Float](repeating:0,count:n*2)
    for i in 0..<n { let g=m[i*4],p=m[i*4+1],variance=max(0,m[i*4+2]-g*g),a=(m[i*4+3]-g*p)/(variance+epsilon);ab[i*2]=a;ab[i*2+1]=p-a*g }
    ab=try box(ab,w,h,2,radius);return (0..<n).map{ab[$0*2]*guide[$0]+ab[$0*2+1]}
  }
  static func smooth(_ plane:[Float],_ w:Int,_ h:Int,_ strength:Double,_ preserve:Double)throws->[Float] {
    guard strength>0 else{return plane};let s=Float(strength/10),eps=pow(0.004+0.05*s,2)*(1.05-Float(preserve/100)),r=min(5,Int((1+strength*0.4).rounded())),d=try guided(plane,plane,w,h,r,eps),k=sqrt(s)
    return zip(plane,d).map{$0+($1-$0)*k}
  }
  static func denoise(_ input:[[Float]],_ w:Int,_ h:Int,_ s:ReduceNoiseSettings,_ matrix:Transform2D)throws->[[Float]] {
    let n=w*h;var luma=(0..<n).map{0.299*input[0][$0]+0.587*input[1][$0]+0.114*input[2][$0]},cb=zip(input[2],luma).map(-),cr=zip(input[0],luma).map(-)
    if s.removeJpegArtifact,w>2,h>2 { let original=luma
      for y in 1..<(h-1) { try Task.checkCancellation();for x in 1..<(w-1) { let p=matrix.point(Double(x)+0.5,Double(y)+0.5),dx=((Int(floor(p.x))%8)+8)%8,dy=((Int(floor(p.y))%8)+8)%8
        if dx==0 || dx==7 || dy==0 || dy==7 { var total:Float=0;for j in -1...1 { for k in -1...1 { total += original[(y+j)*w+x+k] } };luma[y*w+x]=0.5*original[y*w+x]+0.5*total/9 }
      } }
    }
    luma=try smooth(luma,w,h,s.strength,s.preserveDetails)
    if s.reduceColorNoise>0 { let col=Float(s.reduceColorNoise/100),r=min(9,Int((1+col*8).rounded())),eps=pow(0.01+0.05*col,2)
      let b=try guided(luma,cb,w,h,r,eps),rplane=try guided(luma,cr,w,h,r,eps);for i in 0..<n { cb[i]+=(b[i]-cb[i])*col;cr[i]+=(rplane[i]-cr[i])*col }
    }
    if s.sharpenDetails>0 { let blurred=try GalleryMath.blur(luma,w,h,1,1),k=Float(s.sharpenDetails/100)*1.2;for i in 0..<n { luma[i]+=(luma[i]-blurred[i])*k } }
    var output=input
    for i in 0..<n { output[0][i]=cr[i]+luma[i];output[2][i]=cb[i]+luma[i];output[1][i]=(luma[i]-0.299*output[0][i]-0.114*output[2][i])/0.587 }
    for (c,key) in ReduceNoiseSettings.channels.enumerated() { if let settings=s.perChannel[key] { output[c]=try smooth(output[c],w,h,settings.strength,settings.preserveDetails) } }
    return output
  }
}
