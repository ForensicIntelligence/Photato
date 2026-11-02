import Foundation
import PhotoCraftCore

/// Native translation of PhotoCraft compose/effects.rs (MIT OR Apache-2.0).
/// Advanced records opt into the source stack; legacy styles keep their renderer.
enum SourceLayerStyleRenderer {
  static let maximumMapPixels = 16_777_216
  static let maximumScratchBytes = 512 * 1024 * 1024
  private struct Prepared {
    let effect:LayerEffect
    let advanced:LayerEffectAdvanced
    let paint:SourceEffectSampler.Shader
    let map:SourceEffectMap?
    let bevel:SourceEffectBevel?
  }
  /// Source Normal has a deliberately different floating-point evaluation order
  /// from the generic W3C path. Do not fold it into the native legacy compositor.
  static func blend(_ mode:BlendMode,_ b:Pixel,_ s:Pixel,_ opacity:Float)->Pixel {
    let a=s.a*opacity,ab=b.a
    if a<=0{return b}
    let ao=a+ab*(1-a)
    if ao<=0{return .clear}
    if mode == .normal {
      let kb=ab*(1-a),inv:Float=1/ao
      return Pixel((kb*b.r+a*s.r)*inv,(kb*b.g+a*s.g)*inv,(kb*b.b+a*s.b)*inv,ao)
    }
    let c=mode.rgb(b.rgb,s.rgb)
    func channel(_ b:Float,_ s:Float,_ c:Float)->Float {((1-a)*ab*b+(1-ab)*a*s+a*ab*c)/ao}
    return Pixel(channel(b.r,s.r,c.x),channel(b.g,s.g,c.y),channel(b.b,s.b,c.z),ao)
  }
  static func mix(_ a:Pixel,_ b:Pixel,_ k:Float)->Pixel {
    let alpha=a.a+(b.a-a.a)*k
    if alpha<=0{return .clear}
    func c(_ x:Float,_ y:Float)->Float {(x*a.a+(y*b.a-x*a.a)*k)/alpha}
    return Pixel(c(a.r,b.r),c(a.g,b.g),c(a.b,b.b),alpha)
  }
  static func widths(_ effect:LayerEffect,scale:Float)->(Float,Float) {
    let size=Float(effect.size)*scale
    switch effect.position {case .inside:return(size,0);case .outside:return(0,size);case .center:return(size/2,size/2)}
  }
  /// Original bounds::content_bounds scans every stored component against the
  /// clear default, including hidden RGB. Finite native nonzero defaults span
  /// their whole surface; source imports reject unbounded nonzero defaults.
  static func sourceBounds(_ surface:Surface)throws->IntRect? {
    if !surface.defaultPixel.hasSameBits(as:.clear){return IntRect(x:0,y:0,width:surface.width,height:surface.height)}
    let side=Surface.tileSide,columns=(surface.width+side-1)/side
    var x0=surface.width,y0=surface.height,x1=0,y1=0
    for key in surface.storedTileKeys {
      try Task.checkCancellation();let left=key%columns*side,top=key/columns*side
      for y in top..<min(top+side,surface.height) {for x in left..<min(left+side,surface.width) {
        let p=surface.colorEncoding == .linearRGB ? surface.linearPixel(x:x,y:y):surface.pixel(x:x,y:y)
        if !p.hasSameBits(as:.clear){x0=min(x0,x);y0=min(y0,y);x1=max(x1,x+1);y1=max(y1,y+1)}
      }}
    }
    return x1>x0 && y1>y0 ? IntRect(x:x0,y:y0,width:x1-x0,height:y1-y0):nil
  }
  static func composite(_ layer:Layer,clips:[Layer]=[],in document:CraftDocument,over backdrop:Surface,region:IntRect,cache:GroupRenderCache = GroupRenderCache(),frameOverride:IntRect?=nil)throws->Surface {
    guard let style=layer.style else{return backdrop}
    try style.validate(in:document)
    let w=document.width,h=document.height,n=w*h
    guard w<=LayerStyleRenderer.maximumPixels/h else {throw CraftError.unsupported("Advanced layer styles need bounded source preparation; large style processing remains in development.")}
    let effects=style.enabled ? style.effects.filter(\.enabled):[],scale=Float(style.scale/100)
    var reach:Float=0
    for e in effects {
      let r:Float
      switch e.kind {
      case .dropShadow,.innerShadow,.satin:r=Float(e.distance+e.size)*scale
      case .outerGlow,.innerGlow,.stroke:r=Float(e.size)*scale
      case .bevelEmboss:r=Float(e.size+e.soften)*scale
      default:r=0
      }
      reach=max(reach,r)
    }
    let pad=Int(ceil(min(max(reach,0),512)))+2,mw=w+2*pad,mh=h+2*pad
    let mapCount=effects.reduce(1){$0+($1.kind == .bevelEmboss ? 2:[.dropShadow,.innerShadow,.outerGlow,.innerGlow,.satin].contains($1.kind) ? 1:0)}+(effects.contains{$0.kind == .stroke} ? 2:0)
    // Include distance-transform temporaries and the pixel/coverage accumulators,
    // before allocating source maps. This is an operation budget, not document admission.
    guard mw<=maximumMapPixels/mh,(mapCount+16)*4<=maximumScratchBytes/(mw*mh),n*80<=maximumScratchBytes-(mapCount+16)*4*mw*mh else {throw CraftError.unsupported("Advanced effect maps exceed the current512MiB scratch budget; larger style processing remains in development.")}
    var plain=layer;plain.style=nil;plain.opacity=1;plain.blendMode = .normal
    var content=try Renderer.isolatedContent(plain,in:document,cache:cache)
    if !clips.isEmpty {content=try Renderer.compositeClips(clips,onto:content,in:document,cache:cache)}
    let linear=document.depth == .f32
    func read(_ s:Surface,_ x:Int,_ y:Int)->Pixel {linear ? s.linearPixel(x:x,y:y):s.pixel(x:x,y:y)}
    var shape=SourceEffectMap(mw,mh),body=[Pixel](repeating:.clear,count:n),before=body
    var x0=w,y0=h,x1=0,y1=0
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let i=y*w+x,p=read(content,x,y);shape.v[(y+pad)*mw+x+pad]=p.a;body[i]=Pixel(p.r,p.g,p.b,p.a>SourceEffectMap.insideEPS ? style.fillOpacity:0);before[i]=read(backdrop,x,y)
      if p.a>SourceEffectMap.insideEPS {x0=min(x0,x);y0=min(y0,y);x1=max(x1,x+1);y1=max(y1,y+1)}
    }}
    let shapeBounds=x1>x0 && y1>y0 ? IntRect(x:x0,y:y0,width:x1-x0,height:y1-y0):IntRect(x:0,y:0,width:w,height:h)
    let frame:IntRect
    if let frameOverride {frame=frameOverride}
    else if case .fill=layer.content {frame=IntRect(x:0,y:0,width:w,height:h)}
    else if case .gradientFill=layer.content {frame=IntRect(x:0,y:0,width:w,height:h)}
    else if case .patternFill=layer.content {frame=IntRect(x:0,y:0,width:w,height:h)}
    else {
      let pixels=try Renderer.layerSurface(plain,in:document),bounds=try sourceBounds(pixels) ?? IntRect(x:0,y:0,width:1,height:1)
      frame=try (layer.coordinateTransform * .translation(Double(bounds.x),Double(bounds.y))).bounds(width:bounds.width,height:bounds.height)
    }
    let reference=style.referenceOffset.map{layer.coordinateTransform.point($0.x,$0.y)},anchor=reference.map{PathPoint($0.x,$0.y)} ?? PathPoint(Double(frame.x),Double(frame.y)),sampler=SourceEffectSampler(document:document,anchor:anchor)
    let originalLight=document.globalLight ?? GlobalLight(angle:style.lightAngle,altitude:style.lightAltitude)
    let light=GlobalLight(angle:PSDGlobalLight.angle(originalLight.angle),altitude:originalLight.altitude)
    func mi(_ i:Int)->Int {(i/w+pad)*mw+i%w+pad}
    func alpha(_ i:Int)->Float {shape.v[mi(i)]}
    func relative(_ map:SourceEffectMap,_ i:Int)->Float {let a=alpha(i);return a>SourceEffectMap.insideEPS ? min(map.v[mi(i)]/a,1):0}
    var prepared:[Prepared]=[]
    for effect in effects {
      try Task.checkCancellation()
      let advanced=effect.advanced ?? LayerEffectAdvanced(),map:SourceEffectMap?,bevel:SourceEffectBevel?
      switch effect.kind {
      case .dropShadow,.innerShadow:map=try shape.shadow(effect,advanced,angle:Float(effect.useGlobalLight ? light.angle:effect.angle),scale:scale,inner:effect.kind == .innerShadow);bevel=nil
      case .innerGlow,.outerGlow:map=try shape.glow(effect,advanced,scale:scale,inner:effect.kind == .innerGlow);bevel=nil
      case .satin:map=try shape.satin(effect,advanced,scale:scale);bevel=nil
      case .bevelEmboss:map=nil;bevel=try SourceEffectBevel.make(shape,effect:effect,advanced:advanced,light:light,scale:scale,sampler:sampler,origin:PathPoint(Double(-pad),Double(-pad)))
      default:map=nil;bevel=nil
      }
      let paintFrame:IntRect
      if effect.kind == .stroke {let grow=max(0,Int(ceil(min(widths(effect,scale:scale).1,512)))-1);paintFrame=IntRect(x:shapeBounds.x-grow,y:shapeBounds.y-grow,width:shapeBounds.width+2*grow,height:shapeBounds.height+2*grow)}else{paintFrame=frame}
      let paint:SourceEffectSampler.Shader
      if effect.advanced == nil,let g=effect.gradient {paint = .legacyGradient(try GradientFillSampler(g,layer:layer,document:document))}
      else if effect.advanced == nil,let p=effect.pattern {paint = .legacyPattern(try PatternFillSampler(p,in:document))}
      else {paint=sampler.prepare(effect,advanced:advanced,frame:paintFrame)}
      prepared.append(Prepared(effect:effect,advanced:advanced,paint:paint,map:map,bevel:bevel))
    }
    func paint(_ target:inout [Pixel],shader:SourceEffectSampler.Shader,mode:BlendMode,opacity:Float,coverage:(Int)->Float)throws {
      if opacity<=0{return}
      for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
        let i=y*w+x,k=coverage(i);if k<=0{continue};var p=shader.sample(x:x,y:y);p.a *= k
        target[i]=blend(mode,target[i],p,opacity)
      }}
    }
    func bevel(_ target:inout [Pixel],_ entry:Prepared,relativeShape:Bool)throws {
      guard let b=entry.bevel else{return};let e=entry.effect,a=entry.advanced
      // Source stores but does not execute the highlight/shadow enabled fields.
      // Retain those fields; independent Photoshop behavior remains a separate gate.
      try paint(&target,shader:.color(e.highlightColor),mode:a.highlightBlendMode,opacity:e.highlightOpacity,coverage:{relativeShape ? relative(b.highlight,$0):b.highlight.v[mi($0)]})
      try paint(&target,shader:.color(e.shadowColor),mode:a.shadowBlendMode,opacity:e.shadowOpacity,coverage:{relativeShape ? relative(b.shadow,$0):b.shadow.v[mi($0)]})
    }
    var work=before
    for p in prepared.reversed() where p.effect.kind == .dropShadow {
      try paint(&work,shader:p.paint,mode:p.effect.blendMode,opacity:p.effect.opacity,coverage:{p.map!.v[mi($0)]*(p.advanced.knocksOut ? 1-alpha($0)*(1-style.fillOpacity):1)})
    }
    for p in prepared.reversed() where p.effect.kind == .outerGlow {try paint(&work,shader:p.paint,mode:p.effect.blendMode,opacity:p.effect.opacity,coverage:{p.map!.v[mi($0)]})}
    for kind:LayerEffect.Kind in [.patternOverlay,.gradientOverlay,.colorOverlay,.satin,.innerGlow,.innerShadow] {
      for p in prepared.reversed() where p.effect.kind == kind {
        try paint(&body,shader:p.paint,mode:p.effect.blendMode,opacity:p.effect.opacity,coverage:{i in p.map.map{relative($0,i)} ?? (alpha(i)>SourceEffectMap.insideEPS ? 1:0)})
      }
    }
    let strokes=prepared.filter{$0.effect.kind == .stroke},din=strokes.isEmpty ? []:try shape.inside(chamfer:true),dout=strokes.isEmpty ? []:try shape.outside(chamfer:true)
    for p in strokes.reversed() {
      let width=widths(p.effect,scale:scale).0
      if width>0 {try paint(&body,shader:p.paint,mode:p.effect.blendMode,opacity:p.effect.opacity,coverage:{alpha($0)>SourceEffectMap.insideEPS ? unit(width+0.5-din[mi($0)]):0})}
    }
    for p in prepared.reversed() where p.bevel?.paint == .inner {try bevel(&body,p,relativeShape:true)}
    for i in body.indices {body[i].a *= min(alpha(i),1)}
    if strokes.contains(where:{widths($0.effect,scale:scale).1>0}) {
      let base=work;var acc=[SIMD4<Float>](repeating:.zero,count:n),cover=[Float](repeating:0,count:n)
      for p in strokes {
        let width=widths(p.effect,scale:scale).1;if width<=0{continue}
        for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
          let i=y*w+x,band=unit(width+0.5-dout[mi(i)]),k=alpha(i)>SourceEffectMap.insideEPS ? (layer.shape == nil ? Float(1):0):band,share=k*p.effect.opacity*(1-cover[i]);cover[i] += share
          if share<=0{continue};let b=blend(p.effect.blendMode,base[i],p.paint.sample(x:x,y:y),1)
          acc[i].x += share*b.r*b.a;acc[i].y += share*b.g*b.a;acc[i].z += share*b.b*b.a;acc[i].w += share*b.a
        }}
      }
      for i in work.indices where cover[i]>0 {
        let p=work[i],a=acc[i],k=1-min(cover[i],1),alpha=p.a*k+a.w
        if alpha>0 {work[i]=Pixel((p.r*p.a*k+a.x)/alpha,(p.g*p.a*k+a.y)/alpha,(p.b*p.a*k+a.z)/alpha,min(alpha,1))}
      }
    }
    for p in prepared.reversed() where p.bevel?.paint == .outer {try bevel(&work,p,relativeShape:false)}
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {let i=y*w+x;if body[i].a>0 {work[i]=blend(layer.blendMode,work[i],body[i],1)}}}
    for p in prepared.reversed() where p.bevel?.paint == .both {try bevel(&work,p,relativeShape:false)}
    var result=backdrop
    let rx0=max(0,region.x),ry0=max(0,region.y),rx1=min(w,region.x+region.width),ry1=min(h,region.y+region.height)
    if rx1>rx0 && ry1>ry0 {for y in ry0..<ry1 {try Task.checkCancellation();for x in rx0..<rx1 {
      let i=y*w+x,p=mix(before[i],work[i],layer.opacity)
      guard p.isFinite else {throw CraftError.invalid("Advanced effect result exceeds the floating-point range.")}
      if linear {result.setLinearPixel(x:x,y:y,p)}else{result.setPixel(x:x,y:y,p)}
    }}}
    return result
  }
}
