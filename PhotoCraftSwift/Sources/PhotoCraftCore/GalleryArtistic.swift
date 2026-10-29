import Foundation

extension GalleryMath {
  static func artistic(_ e:GalleryEffect,_ input:[V],_ w:Int,_ h:Int)throws->[V]{
    var c=input;let g=e.get,fg=e.foreground.rgb,bg=e.background.rgb
    switch e.filter {
    case .coloredPencil:
      let width=g("pencilWidth"),pressure=g("strokePressure")/15,paper=bg*(0.7+0.3*g("paperBrightness")/50),l=c.map(lum),edge=try gradient(l,w,h)
      for i in c.indices{try poll(i);let x=i%w,y=i/w,d=1-l[i],a=stroke(x,y,(1,1),5+width*3,0.5+width*0.45,11),b=stroke(x,y,(1,-1),5+width*3,0.5+width*0.45,12),hatch=max(a,b*smooth(0.3,0.8,d)),coverage=clamp(d*(0.55+pressure)+edge[i]*3-(1-hatch)*0.8+0.25);c[i]=mix(paper,c[i]*0.88,coverage)}
    case .cutout:
      c=try blur3(c,w,h,0.5+g("edgeSimplicity")*(1.1-0.3*g("edgeFidelity")));let levels=g("numberOfLevels").rounded()
      for i in c.indices{try poll(i);let l=max(lum(c[i]),1e-4),k=poster(l,levels)/l;c[i]=map(c[i]){poster(clamp($0*k),levels*2)}}
    case .dryBrush,.fresco:
      let fresco=e.filter == .fresco;c=try kuwahara(c,w,h,1+Int(g("brushSize")));c=try unsharp(c,w,h,1,fresco ? 0.9:0.5)
      let levels=3+g("brushDetail"),amp:Float=0.02+(g("texture")-1)*0.05,edge=fresco ? try gradient(c.map(lum),w,h):[]
      for i in c.indices{try poll(i);let n=(hash(i%w,i/w,0,21)-0.5)*amp;var p=map(c[i]){poster($0,levels)*0.6+$0*0.4+n};if fresco{p=map(p){pow(clamp(($0-0.5)*1.3+0.45),1.15)*(1-clamp(edge[i]*2.5)*0.6)}};c[i]=p}
    case .filmGrain:
      let grain=g("grain")/20,area=g("highlightArea"),intensity=g("intensity")
      for i in c.indices{try poll(i);let l=lum(c[i]),n=(hash(i%w,i/w,0,31)-0.5)*grain*0.5*(0.3+2.8*l*(1-l));c[i]=highlight(map(c[i]){$0+n},l,area,intensity)}
    case .neonGlow:
      let size=g("glowSize"),brightness=g("glowBrightness")/50,l=c.map(lum),glow=e.glowColor.rgb,m=try blur(size>=0 ? l:l.map{1-$0},w,h,1,abs(size)*0.6+0.5)
      for i in c.indices{try poll(i);let base=mix(fg,bg,l[i]),k=clamp(m[i]*1.2)*brightness*2;c[i]=V(1-(1-base.x)*(1-clamp(glow.x*k)),1-(1-base.y)*(1-clamp(glow.y*k)),1-(1-base.z)*(1-clamp(glow.z*k)))}
    case .paintDaubs:
      let type=e.choice("brushType"),wide=["wideSharp","wideBlurry"].contains(type),radius=max(1,Int(g("brushSize")/2*(wide ? 1.5:1))),sharp=g("sharpness")/40
      c=try kuwahara(c,w,h,radius)
      if type=="wideBlurry"{c=try blur3(c,w,h,1.5)}else{c=try unsharp(c,w,h,type=="wideSharp" ? 1.5:1.2,sharp*(type=="wideSharp" ? 4:2.5))}
      if ["lightRough","darkRough","sparkle"].contains(type){let edge=type=="sparkle" ? try gradient(c.map(lum),w,h):[]
        for i in c.indices{try poll(i);let x=i%w,y=i/w,n=fbm(Float(x)/2,Float(y)/2,41)-0.5
          if type=="lightRough"{c[i]=map(c[i]){$0+max(0,n)*0.35}}
          else if type=="darkRough"{c[i] *= 1-max(0,n)*0.7}
          else{let add=clamp(edge[i]*4)*smooth(0.75,0.95,hash(x,y,0,42))*0.8;c[i]=map(c[i]){$0+add}}
        }
      }
    case .paletteKnife:
      c=try kuwahara(c,w,h,max(1,Int(g("strokeSize")/3)));let levels=2+g("strokeDetail")*3
      for i in c.indices{try poll(i);c[i]=map(c[i]){poster($0,levels)*0.5+$0*0.5}};c=try blur3(c,w,h,g("softness")*0.5)
    case .plasticWrap:
      let hs=g("highlightStrength")/20,l=try blur(c.map(lum),w,h,1,0.5+g("smoothness")*0.5+(15-g("detail"))*0.2),(gx,gy)=try sobel(l,w,h),lv=normalized(V(-0.45,-0.65,1)),hv=normalized(V(lv.x,lv.y,lv.z+1))
      for i in c.indices{try poll(i);let n=normalized(V(-14*gx[i],-14*gy[i],1)),ndh=max(0,n.x*hv.x+n.y*hv.y+n.z*hv.z),tilt=1-n.z,spec=pow(ndh,30)*smooth(0.01,0.12,tilt)+smooth(0.25,0.6,tilt)*0.25;c[i]=map(c[i]){$0*0.88+spec*hs*1.3}}
    case .posterEdges:
      let l=try blur(c.map(lum),w,h,1,0.6+g("edgeThickness")*0.6),edge=try gradient(l,w,h),intensity=g("edgeIntensity")/10,levels=g("posterization")+2
      for i in c.indices{try poll(i);let ink=smooth(0.015,0.06,edge[i]*(1+intensity*3))*(0.55+intensity*0.45);c[i]=map(c[i]){poster($0,levels)*(1-ink)}}
    case .roughPastels:
      let length=g("strokeLength"),detail=g("strokeDetail")/20;c=try line3(c,w,h,(1,-1),Int(length/2))
      for i in c.indices{try poll(i);let n=stroke(i%w,i/w,(1,-1),3+length*0.8,1.1,51)-0.5,p=mix(c[i],input[i],detail*0.5);c[i]=map(p){$0+n*0.3}};c=try texturize(c,w,e)
    case .smudgeStick:
      c=try line3(c,w,h,(1,1),Int(g("strokeLength")*1.5));let area=g("highlightArea"),intensity=g("intensity")
      for i in c.indices{try poll(i);let l=lum(c[i]);c[i]=highlight(c[i]*(0.7+0.3*l),l,area,intensity)}
    case .sponge:
      c=try kuwahara(c,w,h,1+Int(g("brushSize")));let definition=g("definition")/25,scale=1.5+g("smoothness")*0.5
      for i in c.indices{try poll(i);let n=fbm(Float(i%w)/scale,Float(i/w)/scale,61),hole=smooth(0.58,0.75,n);c[i]=map(c[i]){clamp(($0-0.5)*(1+definition*0.6)+0.5)*(1-hole*definition*0.4)}}
    case .underpainting:
      c=try blur3(c,w,h,0.5+g("brushSize")*0.4)
      for i in c.indices{try poll(i);c[i]=saturate(mix(input[i],c[i],0.8),1.15)};c=try texturize(c,w,e,g("relief")*(0.5+g("textureCoverage")/40*1.5))
    case .watercolor:
      c=try kuwahara(c,w,h,1+Int((15-g("brushDetail"))/2.5));let shadow=g("shadowIntensity")/10,edge=try gradient(c.map(lum),w,h),amp=(g("texture")-1)*0.04
      for i in c.indices{try poll(i);let n=(fbm(Float(i%w)/3,Float(i/w)/3,71)-0.5)*amp,k=1-clamp(edge[i]*(3+shadow*8))*0.6;c[i]=map(saturate(c[i],1.2)){pow(clamp($0*k+n),1.1+shadow*0.6)}}
    default:throw CraftError.invalid("Not an Artistic gallery effect.")
    };return c
  }
}
