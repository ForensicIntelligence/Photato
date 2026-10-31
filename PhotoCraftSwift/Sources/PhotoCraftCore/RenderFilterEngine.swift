import Foundation

/// Native translation of PhotoCraft extra_cmds.rs and render.rs (MIT OR Apache-2.0).
/// Source equality does not establish Photoshop numerical equivalence.
public enum RenderFilterEngine {
  // Swift6.4 CopyPropagation cannot verify the expanded storage borrows in
  // paintTarget's throwing closure. Isolate just this filter's sample boundary;
  // ordinary Surface/brush loops keep their optimized direct storage path.
  @inline(never)
  private static func readTarget(_ surface:Surface,x:Int,y:Int,linear:Bool) -> Pixel {
    linear ? surface.linearPixel(x:x,y:y):surface.pixel(x:x,y:y)
  }
  @inline(never)
  private static func writeTarget(_ surface:inout Surface,x:Int,y:Int,pixel:Pixel,linear:Bool) {
    if linear {surface.setLinearPixel(x:x,y:y,pixel)}else{surface.setPixel(x:x,y:y,pixel)}
  }
  static func clamp(_ value: Float) -> Float {min(1,max(0,value))}
  static func smoothstep(_ e0:Float,_ e1:Float,_ x:Float)->Float {
    // Preserve the upstream helper's explicit reversed-edge fallback.
    if e1<=e0 {return x>=e1 ? 1:0}
    let t=clamp((x-e0)/(e1-e0));return t*t*(3-2*t)
  }
  static func cloudHash(_ x: Int,_ y: Int,_ seed: UInt32) -> Float {
    var h=UInt32(truncatingIfNeeded:x) &* 0x8da6b343 ^ UInt32(truncatingIfNeeded:y) &* 0xd8163841 ^ seed &* 0xcb1ab31f
    h ^= h >> 13;h = h &* 0x5bd1e995;h ^= h >> 15
    return Float(h & 0x00ffffff)/Float(0x00ffffff)
  }
  static func noise(_ x: Float,_ y: Float,_ seed: UInt32,cloud: Bool) -> Float {
    let ix=Int(floor(x)),iy=Int(floor(y)),tx=x-Float(ix),ty=y-Float(iy),sx=tx*tx*(3-2*tx),sy=ty*ty*(3-2*ty)
    func hash(_ a: Int,_ b: Int) -> Float {cloud ? cloudHash(a,b,seed):PixelateEngine.hash(a,b,0,seed)}
    let top=hash(ix,iy)+(hash(ix+1,iy)-hash(ix,iy))*sx,bot=hash(ix,iy+1)+(hash(ix+1,iy+1)-hash(ix,iy+1))*sx
    return top+(bot-top)*sy
  }
  static func clouds(_ x: Float,_ y: Float,_ base: Float,_ seed: UInt32) -> Float {
    var sum:Float=0,amp:Float=1,freq:Float=1/base,norm:Float=0
    for o in 0..<8 {sum+=noise(x*freq,y*freq,seed &+ UInt32(o)*7919,cloud:true)*amp;norm+=amp;amp*=0.5;freq*=2}
    return clamp((sum/norm-0.5)*2.2+0.5)
  }
  static func fibers(_ x: Float,_ y: Float,_ s: RenderSettings) -> Float {
    let variance=Float(s.variance),strength=Float(s.strength),fx:Float=0.08+variance/64*0.6,fy=fx/(2+strength*1.5)*(0.5+variance/32)
    var sum:Float=0,amp:Float=1,norm:Float=0,ax=fx,ay=fy
    for o in 0..<4 {sum+=noise(x*ax,y*ay,s.seed &+ UInt32(o)*977,cloud:false)*amp;norm+=amp;amp*=0.55;ax*=2;ay*=2}
    let grain=noise(x*0.9,y*fy*0.25,s.seed ^ 0x5bd1,cloud:false)-0.5
    return clamp((sum/norm-0.5)*(1.6+variance/40)+0.5+grain*0.25)
  }
  struct Ghost {var t:Float;var r:Float;var tint:SIMD3<Float>;var k:Float}
  struct Flare {
    var cx:Float,cy:Float,mx:Float,my:Float,scale:Float,bright:Float
    var core:Float,glow:Float,ring:Float,ringWidth:Float,rays:Float,streak:Float
    var ghosts:[Ghost]
    init(_ s:RenderSettings,width:Int,height:Int) {
      let w=Float(width),h=Float(height);cx=Float(s.centerX)*w;cy=Float(s.centerY)*h;mx=w/2;my=h/2;scale=max(1,hypot(w,h))/1000;bright=Float(s.brightness)/100
      switch s.lens {
      case .zoom:(core,glow,ring,ringWidth,rays,streak)=(14,90,0,0,0.5,0)
        ghosts=[Ghost(t:0.35,r:10,tint:SIMD3(0.6,0.8,1),k:0.18),Ghost(t:0.6,r:26,tint:SIMD3(0.5,1,0.6),k:0.10),Ghost(t:0.85,r:6,tint:SIMD3(1,0.7,0.4),k:0.25),Ghost(t:1.25,r:40,tint:SIMD3(0.7,0.5,1),k:0.08),Ghost(t:1.5,r:16,tint:SIMD3(0.7,0.7,1),k:0.15),Ghost(t:1.9,r:70,tint:SIMD3(0.5,0.7,1),k:0.06)]
      case .prime35:(core,glow,ring,ringWidth,rays,streak)=(12,70,90,6,0.3,0)
        ghosts=[Ghost(t:0.7,r:18,tint:SIMD3(0.6,1,0.7),k:0.12),Ghost(t:1.4,r:30,tint:SIMD3(1,0.7,0.5),k:0.09)]
      case .prime105:(core,glow,ring,ringWidth,rays,streak)=(22,130,0,0,0.8,0)
        ghosts=[Ghost(t:0.5,r:14,tint:SIMD3(1,0.8,0.5),k:0.12),Ghost(t:1.6,r:50,tint:SIMD3(0.6,0.7,1),k:0.07)]
      case .moviePrime:(core,glow,ring,ringWidth,rays,streak)=(10,60,0,0,0.2,1)
        ghosts=[Ghost(t:0.4,r:8,tint:SIMD3(0.5,0.7,1),k:0.2),Ghost(t:1,r:20,tint:SIMD3(0.4,0.6,1),k:0.12),Ghost(t:1.6,r:12,tint:SIMD3(0.5,0.7,1),k:0.16)]
      }
    }
    func sample(_ p:Pixel,x:Float,y:Float)->Pixel {
      let dx=x+0.5-cx,dy=y+0.5-cy,d=(dx*dx+dy*dy).squareRoot(),q=d/(core*scale)
      let g=exp(-q*q)+0.35*exp(-d/(glow*scale));var f=SIMD3<Float>(g,g*0.95,g*0.85)
      if rays>0 {
        let th=atan2(dy,dx),a=sin(th*12)*0.5+0.5,b=sin(th*7+1.3)*0.5+0.5,a2=a*a,a4=a2*a2,b2=b*b,b4=b2*b2
        let m=a4*a4+b4*b4*b4*0.6,rr=rays*m*exp(-d/(glow*1.6*scale));f+=SIMD3(repeating:rr*0.6)
      }
      if streak>0 {let st=exp(-abs(dy)/(2.5*scale))*exp(-abs(dx)/(450*scale));f+=SIMD3(st*0.5,st*0.7,st)}
      if ring>0 {for (k,offset) in [Float(1.04),1,0.96].enumerated() {let rd=(d-ring*scale*offset)/(ringWidth*scale);f[k]+=0.18*exp(-rd*rd)}}
      for gh in ghosts {
        let gx=cx+(mx-cx)*gh.t*2,gy=cy+(my-cy)*gh.t*2,gdx=x+0.5-gx,gdy=y+0.5-gy,gd=(gdx*gdx+gdy*gdy).squareRoot()/(gh.r*scale)
        if gd<1.2 {let e=RenderFilterEngine.smoothstep(1,0.85,gd)*(0.6+0.4*gd);for c in 0..<3 {f[c]+=e*gh.k*gh.tint[c]}}
      }
      var result=p
      result.r=1-(1-p.r)*(1-min(1,max(0,f.x*bright)))
      result.g=1-(1-p.g)*(1-min(1,max(0,f.y*bright)))
      result.b=1-(1-p.b)*(1-min(1,max(0,f.z*bright)))
      return result
    }
  }
  static func settingsForDepth(_ s:RenderSettings,_ depth:PixelDepth)->RenderSettings {
    var result=s;if depth == .f32 {result.foreground=SRGBTransfer.linear(s.foreground);result.background=SRGBTransfer.linear(s.background)};return result
  }
  static func pixel(_ before:Pixel,x:Float,y:Float,kind:RasterFilter.Kind,settings s:RenderSettings,width:Int,height:Int,flare:Flare)->Pixel {
    if kind == .lensFlare {return flare.sample(before,x:x,y:y)}
    let t=kind == .fibers ? fibers(x,y,s):clouds(x,y,min(512,max(16,Float(max(width,height))/4)),s.seed)
    let color=s.foreground.rgb+(s.background.rgb-s.foreground.rgb)*t
    if kind == .differenceClouds {return Pixel(abs(before.r-color.x),abs(before.g-color.y),abs(before.b-color.z),before.a)}
    return Pixel(color.x,color.y,color.z,1)
  }
  public static func render(_ source:Surface,kind:RasterFilter.Kind,settings:RenderSettings,canvasWidth:Int?=nil,canvasHeight:Int?=nil,pixelToDocument:Transform2D = .identity)throws->Surface {
    try settings.validate(kind:kind);try pixelToDocument.validated()
    guard source.width<=RasterFilterEngine.maximumPixels/source.height else {throw CraftError.unsupported("Render filters support up to8,388,608 pixels.")}
    let w=canvasWidth ?? source.width,h=canvasHeight ?? source.height
    guard w>0,h>0,w<=RasterFilterEngine.maximumPixels/h else {throw CraftError.unsupported("Render canvas exceeds8,388,608 pixels.")}
    let linear=source.depth == .f32,s=settingsForDepth(settings,source.depth),flare=Flare(s,width:w,height:h);var result=source
    for y in 0..<source.height {try Task.checkCancellation();for x in 0..<source.width {
      let q=pixelToDocument.point(Double(x)+0.5,Double(y)+0.5)
      if kind != .lensFlare && (q.x<0 || q.y<0 || q.x>=Double(w) || q.y>=Double(h)) {continue}
      let before=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      guard before.isFinite,max(abs(before.r),abs(before.g),abs(before.b))<=1e12 else {throw CraftError.invalid("Render input exceeds the supported numeric range.")}
      let value=pixel(before,x:Float(q.x-0.5),y:Float(q.y-0.5),kind:kind,settings:s,width:w,height:h,flare:flare)
      guard value.isFinite else {throw CraftError.invalid("Nonfinite Render result.")};if value.hasSameBits(as:before) {continue}
      if linear {result.setLinearPixel(x:x,y:y,value)} else {result.setPixel(x:x,y:y,value)}
    }};return result
  }
  static func apply(_ settings:RenderSettings,kind:RasterFilter.Kind,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws {
    let original=document,linear=document.depth == .f32,protect=document.isTransparencyLocked(layerID)
    guard document.width<=RasterFilterEngine.maximumPixels/document.height else {throw CraftError.unsupported("Render canvas exceeds8,388,608 pixels.")}
    var layer=document.layers[index]
    if kind == .lensFlare {
      let edited=try render(source,kind:kind,settings:settings,canvasWidth:document.width,canvasHeight:document.height,pixelToDocument:layer.coordinateTransform);var result=source
      for y in 0..<source.height {try Task.checkCancellation();for x in 0..<source.width {
        let q=layer.coordinateTransform.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)))
        if coverage<=0 {continue};let before=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
        if protect && before.a==0 {continue};let after=linear ? edited.linearPixel(x:x,y:y):edited.pixel(x:x,y:y)
        if before.hasSameBits(as:after) {continue};let value=before.mixing(after,coverage:coverage)
        if linear {result.setLinearPixel(x:x,y:y,value)} else {result.setPixel(x:x,y:y,value)}
      }};document.layers[index].content = .raster(result);return
    }
    let clipping=(document.selection ?? IntRect(x:0,y:0,width:document.width,height:document.height)).clipped(toWidth:document.width,height:document.height)
    guard clipping.width>0,clipping.height>0 else {return}
    let s=settingsForDepth(settings,document.depth),flare=Flare(s,width:document.width,height:document.height)
    _ = try ClonePainter.paintTarget(mask:false,bounds:clipping,on:&layer,clipping:clipping,preserveTransparency:protect) {pixels,transform,_ in
      guard pixels.width<=RasterFilterEngine.maximumPixels/pixels.height else {throw CraftError.unsupported("Expanded Render target exceeds8,388,608 pixels.")}
      var changed=false
      for y in 0..<pixels.height {try Task.checkCancellation();for x in 0..<pixels.width {
        let q=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(q.x)),dy=Int(floor(q.y))
        guard dx>=clipping.x,dy>=clipping.y,dx<clipping.x+clipping.width,dy<clipping.y+clipping.height else {continue}
        let coverage=original.selectionCoverage(x:dx,y:dy);if coverage<=0 {continue}
        let before=readTarget(pixels,x:x,y:y,linear:linear)
        guard before.isFinite,max(abs(before.r),abs(before.g),abs(before.b))<=1e12 else {throw CraftError.invalid("Render input exceeds the supported numeric range.")}
        if protect && before.a==0 {continue}
        var after=pixel(before,x:Float(q.x-0.5),y:Float(q.y-0.5),kind:kind,settings:s,width:original.width,height:original.height,flare:flare)
        if protect {after.a=before.a};let value=before.mixing(after,coverage:coverage)
        if value.hasSameBits(as:before) {continue};changed=true
        writeTarget(&pixels,x:x,y:y,pixel:value,linear:linear)
      }};return changed
    }
    document.layers[index]=layer
  }
}
