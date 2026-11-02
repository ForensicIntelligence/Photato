import Foundation

/// Source-derived Blinn–Phong illumination; PhotoCraft MIT OR Apache-2.0.
public enum LightingEngine {
  static func normal(_ v:SIMD3<Float>)->SIMD3<Float>{v/max(1e-9,sqrt(v.x*v.x+v.y*v.y+v.z*v.z))}
  static func dot(_ a:SIMD3<Float>,_ b:SIMD3<Float>)->Float{a.x*b.x+a.y*b.y+a.z*b.z}
  static func read(_ s:Surface,_ x:Int,_ y:Int)->Pixel {let xx=max(0,min(s.width-1,x)),yy=max(0,min(s.height-1,y));return s.depth == .f32 ? s.linearPixel(x:xx,y:yy):s.pixel(x:xx,y:yy)}
  static func write(_ s:inout Surface,_ x:Int,_ y:Int,_ p:Pixel){if s.depth == .f32{s.setLinearPixel(x:x,y:y,p)}else{s.setPixel(x:x,y:y,p)}}
  public static func render(_ source:Surface,settings:LightingSettings,referenceBounds:IntRect?=nil,pixelToDocument:Transform2D = .identity,texture:Surface?=nil)throws->Surface {
    try settings.validate();try Task.checkCancellation()
    guard source.width<=RasterFilterEngine.maximumPixels/source.height else{throw CraftError.unsupported("Lighting Effects retains its8,388,608-pixel source limit.")}
    if settings.texture == .alphaChannel && texture==nil{throw CraftError.invalid("Missing Lighting Effects alpha texture.")}
    let bounds=referenceBounds ?? IntRect(x:0,y:0,width:source.width,height:source.height)
    guard bounds.width>0,bounds.height>0,bounds.width<=Surface.maxDimension,bounds.height<=Surface.maxDimension else{throw CraftError.invalid("Invalid lighting reference bounds.")}
    let inverse=try pixelToDocument.inverted(),bw=Float(bounds.width),bh=Float(bounds.height),short=max(1,min(bw,bh)),bx=Float(bounds.x),by=Float(bounds.y)
    let height=Float(settings.height)/100*0.06*short,gloss=Float(settings.gloss),shininess=pow(2,1+(gloss+100)/200*7),specular=(gloss+100)/200*0.7,metal=(Float(settings.metallic)+100)/200,exposure=pow(2,Float(settings.exposure)/50),ambient=Float(settings.ambience)/100*0.5
    let lights=settings.lights.filter(\.enabled),radians=Float.pi/180
    func bump(_ x:Int,_ y:Int)->Float {
      let q=pixelToDocument.point(Double(x)+0.5,Double(y)+0.5)
      let dx=min((Double(bounds.x)+Double(bounds.width))-0.5,max(Double(bounds.x)+0.5,q.x)),dy=min((Double(bounds.y)+Double(bounds.height))-0.5,max(Double(bounds.y)+0.5,q.y)),local=inverse.point(dx,dy)
      let sx=Int(floor(min(Double(source.width-1),max(0,local.x)))),sy=Int(floor(min(Double(source.height-1),max(0,local.y)))),p=read(source,sx,sy);let value:Float
      switch settings.texture {
      case .none:value=0
      case .red:value=p.r
      case .green:value=p.g
      case .blue:value=p.b
      case .alpha:value=p.a
      case .luminance:value=0.299*p.r+0.587*p.g+0.114*p.b
      case .alphaChannel:
        if let texture{value=texture.pixel(x:Int(floor(min(Double(texture.width-1),max(0,dx)))),y:Int(floor(min(Double(texture.height-1),max(0,dy))))).r}else{value=0}
      };return settings.whiteIsHigh ? value:1-value
    }
    var result=source
    for y in 0..<source.height{try Task.checkCancellation();for x in 0..<source.width{
      if x%128==0{try Task.checkCancellation()}
      let p=read(source,x,y);guard p.isFinite,max(abs(p.r),abs(p.g),abs(p.b))<=1e12 else{throw CraftError.invalid("Lighting input exceeds its supported numeric range.")}
      let q=pixelToDocument.point(Double(x)+0.5,Double(y)+0.5),fx=Float(q.x),fy=Float(q.y)
      var n=SIMD3<Float>(0,0,1)
      if settings.texture != .none && height>0 {
        let hx=(bump(x+1,y)-bump(x-1,y))*0.5*height,hy=(bump(x,y+1)-bump(x,y-1))*0.5*height
        n=normal(SIMD3(-(Float(inverse.a)*hx+Float(inverse.b)*hy),-(Float(inverse.c)*hx+Float(inverse.d)*hy),1))
      }
      let base=SIMD3(p.r,p.g,p.b);var lit=SIMD3<Float>(repeating:ambient),highlight=SIMD3<Float>(repeating:0)
      for light in lights {
        let position=SIMD3(bx+Float(light.x)*bw,by+Float(light.y)*bh,Float(light.z)*short),v=position-SIMD3(fx,fy,0)
        let direction:SIMD3<Float>,attenuation:Float
        switch light.kind {
        case .infinite:
          let a=Float(light.angle)*radians,e=Float(light.elevation)*radians;direction=normal(SIMD3(cos(a)*cos(e),-sin(a)*cos(e),sin(e)));attenuation=1
        case .point:
          direction=normal(v);let reach=max(1,Float(light.radius)*short),distance=sqrt(v.x*v.x+v.y*v.y),f=min(1,max(0,1-distance/reach));attenuation=f*f
        case .spot:
          direction=normal(v);let target=SIMD3(bx+Float(light.targetX)*bw,by+Float(light.targetY)*bh,0),axis=normal(target-position),cosine = -dot(direction,axis),outer=cos(Float(light.cone)*radians),inner=max(outer+1e-4,cos((Float(light.cone)*(Float(light.hotspot)/100))*radians)),t=min(1,max(0,(cosine-outer)/(inner-outer)));attenuation=t*t*(3-2*t)
        }
        if attenuation<=0{continue}
        let intensity=Float(light.intensity)/50*attenuation,ndl=max(0,dot(n,direction)),halfway=normal(SIMD3(direction.x,direction.y,direction.z+1)),shine=pow(max(0,dot(n,halfway)),shininess)*specular
        for k in 0..<3{lit[k]+=ndl*intensity*light.color[k];let color=light.color[k]*(1-metal)+base[k]*metal;highlight[k]+=shine*max(0,intensity)*color}
      }
      let c=SIMD3(max(0,(base.x*lit.x+highlight.x)*exposure),max(0,(base.y*lit.y+highlight.y)*exposure),max(0,(base.z*lit.z+highlight.z)*exposure)),after=Pixel(c.x,c.y,c.z,p.a)
      guard fx.isFinite,fy.isFinite,after.isFinite else{throw CraftError.invalid("Nonfinite lighting geometry or result.")}
      if !after.hasSameBits(as:p){write(&result,x,y,after)}
    }};return result
  }
  static func apply(_ settings:LightingSettings,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws {
    guard document.colorMode == .rgb,document.inkMode==nil,document.restrictedMode==nil else{throw CraftError.unsupported("Lighting Effects requires an RGB image target.")}
    try settings.validateReferences(in:document)
    let matrix=document.layers[index].coordinateTransform,reference=document.selection.flatMap{$0.width>0 && $0.height>0 ? $0:nil} ?? IntRect(x:0,y:0,width:document.width,height:document.height),texture=settings.textureChannelID.flatMap{id in document.alphaChannels?.first{$0.id==id}?.pixels}
    let edited=try render(source,settings:settings,referenceBounds:reference,pixelToDocument:matrix,texture:texture),protect=document.isTransparencyLocked(layerID);var result=source
    for y in 0..<source.height{try Task.checkCancellation();for x in 0..<source.width{
      let q=matrix.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)));if coverage<=0{continue}
      let p=read(source,x,y);if protect && p.a==0{continue};let after=read(edited,x,y),value=coverage>=1 ? after:p.mixing(after,coverage:coverage)
      if !value.hasSameBits(as:p){write(&result,x,y,value)}
    }};document.layers[index].content = .raster(result)
  }
}
