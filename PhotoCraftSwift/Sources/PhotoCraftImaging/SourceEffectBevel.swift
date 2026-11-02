import Foundation
import PhotoCraftCore

struct SourceEffectBevel:Sendable {
  enum Paint:Sendable {case inner,outer,both}
  let highlight:SourceEffectMap
  let shadow:SourceEffectMap
  let paint:Paint
  static func make(_ shape:SourceEffectMap,effect:LayerEffect,advanced:LayerEffectAdvanced,light:GlobalLight,scale:Float,sampler:SourceEffectSampler,origin:PathPoint)throws->Self {
    let size=max(1,Float(effect.size)*scale),emboss=advanced.bevelStyle == .emboss || advanced.bevelStyle == .pillowEmboss
    let paint:Paint=advanced.bevelStyle == .outerBevel ? .outer:emboss ? .both:.inner,width=emboss ? ceil(size/2):size,smooth=advanced.bevelTechnique == .smooth,baseDepth=Float(effect.depth/100),depth=baseDepth*(smooth ? width:size)*(advanced.directionUp ? 1:-1),pillow=advanced.bevelStyle == .pillowEmboss
    var height:SourceEffectMap
    if smooth {height=try shape.blurred(width)}
    else {
      let din=try shape.inside(),dout=try shape.outside();height=shape
      for i in height.v.indices {
        switch paint {
        case .outer:height.v[i]=1-unit(dout[i]/size)
        case .both:height.v[i]=din[i]>0 ? 0.5+0.5*unit(din[i]/(size/2)):0.5-0.5*unit(dout[i]/(size/2))
        case .inner:height.v[i]=unit(din[i]/size)
        }
      }
      if advanced.bevelTechnique == .chiselSoft {height=try height.blurred(max(1,size/4))}
    }
    if let contour=advanced.bevelContour {height=try height.contoured(contour.contour,range:contour.range)}
    if let texture=advanced.texture,texture.pattern.patternID != nil {
      let textureShader=SourceEffectSampler.PatternShader(texture.pattern,sampler:sampler)
      let unit=abs(baseDepth)>1e-6 ? max(abs(depth/baseDepth),1e-3):max(width,1),k=texture.depth/unit
      for y in 0..<shape.h {try Task.checkCancellation();for x in 0..<shape.w {
        let p=textureShader.sample(x:origin.x+Double(x)+0.5,y:origin.y+Double(y)+0.5),l=(0.299*p.r+0.587*p.g+0.114*p.b)*p.a
        height.v[y*shape.w+x]+=k*(texture.inverted ? 1-l:l)
      }}
    }
    if effect.soften*Double(scale)>=1 {height=try height.blurred(Float(effect.soften)*scale)}
    let angle=Float(effect.useGlobalLight ? light.angle:effect.angle)*(Float.pi/180),altitude=(effect.useGlobalLight ? Float(light.altitude):advanced.altitude)*(Float.pi/180),se=sin(altitude),ce=cos(altitude),lv=SIMD3(cos(angle)*ce,-sin(angle)*ce,se)
    func onBevel(_ x:Int,_ y:Int)->Bool {height.get(x,y)>1e-5 || (paint == .both && [(1,0),(-1,0),(0,1),(0,-1)].contains{height.get(x+$0.0,y+$0.1)>1e-5})}
    func shade(_ depth:Float,_ outside:Bool)throws->(SourceEffectMap,SourceEffectMap) {
      var hi=SourceEffectMap(shape.w,shape.h),sh=hi
      for y in 0..<shape.h {try Task.checkCancellation();for x in 0..<shape.w {
        let i=y*shape.w+x,gx=(height.get(x+1,y)-height.get(x-1,y))*0.5*depth,gy=(height.get(x,y+1)-height.get(x,y-1))*0.5*depth,n=SIMD3(-gx,-gy,Float(1)),length=sqrt(n.x*n.x+n.y*n.y+1),v=(n.x*lv.x+n.y*lv.y+n.z*lv.z)/length
        let region=outside ? Float(shape.v[i]<1-SourceEffectMap.insideEPS && onBevel(x,y) ? 1:0):shape.v[i],k=v-se
        if k>0 {hi.v[i]=unit(k/max(1-se,1e-3))*region} else {sh.v[i]=unit(-k/max(se,1e-3))*region}
      }}
      return(try hi.contoured(advanced.glossContour),try sh.contoured(advanced.glossContour))
    }
    let hi:SourceEffectMap,sh:SourceEffectMap
    if paint == .both {
      let(a,b)=try shade(depth,false),(c,d)=try shade(pillow ? -depth:depth,true);var h=a,s=b
      for i in shape.v.indices {h.v[i]=(shape.v[i]>SourceEffectMap.insideEPS ? a.v[i]:0)+c.v[i]*(1-min(shape.v[i],1));s.v[i]=(shape.v[i]>SourceEffectMap.insideEPS ? b.v[i]:0)+d.v[i]*(1-min(shape.v[i],1))};hi=h;sh=s
    } else {(hi,sh)=try shade(depth,paint == .outer)}
    return Self(highlight:hi,shadow:sh,paint:paint)
  }
}
