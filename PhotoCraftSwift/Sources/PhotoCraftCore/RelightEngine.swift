import Foundation

/// Native translation of PhotoCraft algo/relight.rs (MIT OR Apache-2.0).
/// Retinex shading recovery followed by a directional Lambertian light.
public enum RelightEngine {
  public static let tileSize=128
  public static let maximumScratchPixels=1_048_576
  static func normal(_ v:SIMD3<Float>)->SIMD3<Float> {
    let n=sqrt(v.x*v.x+v.y*v.y+v.z*v.z);return n.isFinite && n>=1e-9 ? v/n:SIMD3(0,0,1)
  }
  static func kernel(_ sigma:Float)->[Float] {
    let r=Int(ceil(sigma*3));var k=(-r...r).map{exp(-Float($0*$0)/(2*sigma*sigma))};var sum:Float=0
    for v in k{sum+=v};for i in k.indices{k[i]/=sum};return k
  }
  @inline(never) static func read(_ source:Surface,x:Int,y:Int)->Pixel {
    let xx=max(0,min(source.width-1,x)),yy=max(0,min(source.height-1,y));return source.depth == .f32 ? source.linearPixel(x:xx,y:yy):source.pixel(x:xx,y:yy)
  }
  @inline(never) static func write(_ result:inout Surface,x:Int,y:Int,value:Pixel) {
    if result.depth == .f32{result.setLinearPixel(x:x,y:y,value)}else{result.setPixel(x:x,y:y,value)}
  }
  public static func render(_ source:Surface,settings:RelightSettings,canvasWidth:Int?=nil,canvasHeight:Int?=nil)throws->Surface {
    try settings.validate();try Task.checkCancellation();if settings.isIdentity{return source}
    guard source.width<=RasterFilterEngine.maximumPixels/source.height else{throw CraftError.unsupported("Relight processing retains its8,388,608-pixel source limit.")}
    let cw=canvasWidth ?? source.width,ch=canvasHeight ?? source.height
    guard cw>0,ch>0,cw<=Surface.maxDimension,ch<=Surface.maxDimension else{throw CraftError.invalid("Invalid Relight reference canvas.")}
    let sig=min(96,max(2,(Float(settings.softness)/100)*0.08*Float(min(cw,ch)))),radius=Int(ceil(sig*3)),step=Int(min(32,max(1,sig.rounded())))
    let weights=kernel(sig),radians=Float.pi/180,a=Float(settings.angle)*radians,e=Float(settings.elevation)*radians
    let direction=normal(SIMD3(cos(a)*cos(e),-sin(a)*cos(e),sin(e))),warm=Float(settings.warmth)/100
    let color:SIMD3<Float> = warm>=0 ? SIMD3(1+0.15*warm,1-0.05*warm,1-0.25*warm):SIMD3(1+0.20*warm,1+0.10*warm,1-0.15*warm)
    let ambient=Float(settings.ambient)/100,intensity=Float(settings.intensity)/100
    var result=source
    for ty in stride(from:0,to:source.height,by:tileSize){for tx in stride(from:0,to:source.width,by:tileSize){
      try Task.checkCancellation();let out=IntRect(x:tx,y:ty,width:min(tileSize,source.width-tx),height:min(tileSize,source.height-ty))
      let padding=step+radius,rect=IntRect(x:out.x-padding,y:out.y-padding,width:out.width+2*padding,height:out.height+2*padding),w=rect.width,h=rect.height
      guard w<=maximumScratchPixels/h else{throw CraftError.unsupported("Relight scratch tile exceeds its bounded memory limit.")}
      var luminance=[Float](repeating:.nan,count:w*h)
      for y in 0..<h{try Task.checkCancellation();for x in 0..<w{
        let p=read(source,x:rect.x+x,y:rect.y+y)
        guard p.isFinite,max(abs(p.r),abs(p.g),abs(p.b))<=1e12 else{throw CraftError.invalid("Relight input exceeds the supported numeric range.")}
        if p.a>0{luminance[y*w+x]=0.2126*p.r+0.7152*p.g+0.0722*p.b}
      }}
      let horizontal=try convolve(luminance,width:w,height:h,weights:weights,vertical:false)
      let shading=try convolve(horizontal,width:w,height:h,weights:weights,vertical:true)
      func sample(_ x:Int,_ y:Int)->Float {let value=shading[max(0,min(h-1,y-rect.y))*w+max(0,min(w-1,x-rect.x))];return value.isFinite ? value:0.04}
      for y in out.y..<out.y+out.height{try Task.checkCancellation();for x in out.x..<out.x+out.width{
        let p=read(source,x:x,y:y);if p.a<=0{continue}
        let s=max(0.04,sample(x,y)),nx=(sample(x-step,y)-sample(x+step,y))*2,ny=(sample(x,y-step)-sample(x,y+step))*2
        let n=normal(SIMD3(nx,ny,1)),dot=max(0,n.x*direction.x+n.y*direction.y+n.z*direction.z),light=ambient+intensity*dot
        let c=SIMD3(p.r,p.g,p.b)/s*light*color,value=Pixel(c.x,c.y,c.z,p.a)
        guard value.isFinite else{throw CraftError.invalid("Nonfinite Relight result.")}
        if !value.hasSameBits(as:p){write(&result,x:x,y:y,value:value)}
      }}
    }};return result
  }
  private static func convolve(_ input:[Float],width:Int,height:Int,weights:[Float],vertical:Bool)throws->[Float] {
    var result=[Float](repeating:0,count:input.count);let radius=weights.count/2
    for y in 0..<height{try Task.checkCancellation();for x in 0..<width{
      var sum=0.0,weight=0.0
      for i in weights.indices {
        let xx=vertical ? x:x+i-radius,yy=vertical ? y+i-radius:y
        if xx<0 || yy<0 || xx>=width || yy>=height{continue}
        let value=input[yy*width+xx];if !value.isFinite{continue}
        sum+=Double(value)*Double(weights[i]);weight+=Double(weights[i])
      };result[y*width+x]=weight>1e-12 ? Float(sum/weight):0.5
    }};return result
  }
  static func apply(_ settings:RelightSettings,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws {
    guard document.colorMode == .rgb,document.inkMode==nil,document.restrictedMode==nil else{throw CraftError.unsupported("Relight currently supports RGB editing.")}
    let edited=try render(source,settings:settings,canvasWidth:document.width,canvasHeight:document.height),matrix=document.layers[index].coordinateTransform,protect=document.isTransparencyLocked(layerID)
    var result=source
    for y in 0..<source.height{try Task.checkCancellation();for x in 0..<source.width{
      let q=matrix.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)))
      if coverage<=0{continue};let p=read(source,x:x,y:y);if protect && p.a==0{continue};let after=read(edited,x:x,y:y),value=coverage>=1 ? after:p.mixing(after,coverage:coverage)
      if !value.hasSameBits(as:p){write(&result,x:x,y:y,value:value)}
    }};document.layers[index].content = .raster(result)
  }
}
