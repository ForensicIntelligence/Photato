import Foundation

extension GalleryMath {
  static func sketch(_ e:GalleryEffect,_ input:[V],_ w:Int,_ h:Int)throws->[V]{
    var c=input;let g=e.get,fg=e.foreground.rgb,bg=e.background.rgb
    switch e.filter {
    case .basRelief:
      let original=c.map(lum),l=try blur(original,w,h,1,0.3+g("smoothness")*0.5+(15-g("detail"))*0.12),(gx,gy)=try sobel(l,w,h),light=light(e.choice("light")),k=3+g("detail")*0.4
      for i in c.indices{try poll(i);let t=clamp(original[i]*0.5+0.25-k*(gx[i]*light.0+gy[i]*light.1));c[i]=mix(fg,bg,t)}
    case .chalkCharcoal:
      let charcoal=g("charcoalArea")/20,chalk=g("chalkArea")/20,pressure=g("strokePressure")/5,mid=mix(fg,bg,0.5)
      for i in c.indices{try poll(i);let x=i%w,y=i/w,l=lum(c[i]),cn=stroke(x,y,(1,1),9,0.9,121)-0.5,kn=stroke(x,y,(1,-1),9,0.9,122)-0.5,cc=smooth(0.25,0.6,(1-l)*(0.4+charcoal*1.2)+cn*(0.6+pressure*0.4)-0.15),kc=smooth(0.25,0.6,l*(0.4+chalk*1.2)+kn*(0.6+pressure*0.4)-0.15);c[i]=mix(mix(mid,fg,cc),bg,kc*(1-cc))}
    case .charcoal:
      let thickness=g("charcoalThickness"),detail=g("detail")/5,balance=g("lightDarkBalance")/100,l=try blur(c.map(lum),w,h,1,1),edge=try gradient(l,w,h)
      for i in c.indices{try poll(i);let n=stroke(i%w,i/w,(1,1),8+thickness*3,0.6+thickness*0.5,131)-0.5,coverage=smooth(1-balance-0.2,1-balance+0.2,1-l[i]+n*0.6)+clamp(edge[i]*detail*6);c[i]=mix(bg,fg,clamp(coverage))}
    case .chrome:
      let detail=g("detail")/10,l=try blur(c.map(lum),w,h,1,1+g("smoothness")/10*4),edge=try gradient(l,w,h)
      for i in c.indices{try poll(i);let v:Float=0.5+0.5*sin((l[i]*(2.5+detail*3)+edge[i]*6)*2 * .pi);c[i]=V(repeating:smooth(0.05,0.95,v))}
    case .conteCrayon:
      let fl=g("foregroundLevel")/15,bl=g("backgroundLevel")/15,mid=mix(fg,bg,0.5)
      for i in c.indices{try poll(i);let l=lum(c[i]),n=stroke(i%w,i/w,(1,-1),7,1,141)-0.5,a=clamp((0.6-l)*2*fl*1.4+n*0.5),b=clamp((l-0.4)*2*bl*1.4-n*0.5);c[i]=mix(mix(mid,fg,a),bg,b*(1-a))};c=try texturize(c,w,e)
    case .graphicPen:
      let radius=Int(g("strokeLength")/2),balance=g("lightDarkBalance")/100,l=c.map(lum),n=try line(c.indices.map{hash($0%w,$0/w,0,151)},w,h,1,direction(e.choice("strokeDirection")),radius),sd:Float=0.2887/sqrt(Float(2*radius+1))
      for i in c.indices{try poll(i);let z=(n[i]-0.5)/sd;c[i]=mix(bg,fg,smooth(balance+0.04,balance-0.04,l[i]+z*0.16))}
    case .halftonePattern:
      let size=g("size"),contrast=g("contrast")/50,cell=3+size*2,l=try blur(c.map(lum),w,h,1,0.5+size*0.3),cx=Float(w)/2,cy=Float(h)/2,type=e.choice("patternType")
      for i in c.indices{try poll(i);let x=Float(i%w)+0.5,y=Float(i/w)+0.5,d=clamp((1-l[i]-0.5)*(1+contrast*3)+0.5),aa=1/cell;let ink:Float
        if type=="circle"{let r=sqrt((x-cx)*(x-cx)+(y-cy)*(y-cy))/cell,q=abs(fract(r)-0.5)*2;ink=smooth(d+aa,d-aa,q)}
        else if type=="line"{ink=smooth(d+aa,d-aa,abs(fract(y/cell)-0.5)*2)}
        else{let u=fract(x/cell)-0.5,v=fract(y/cell)-0.5,q=sqrt(u*u+v*v)*2,r=sqrt(d)*1.15;ink=smooth(r+aa,r-aa,q)};c[i]=mix(bg,fg,ink)
      }
    case .notePaper:
      let balance=g("imageBalance")/50,grain=g("graininess")/20,relief=g("relief")/25,l=try blur(c.map(lum),w,h,1,1),m=try blur(l.map{smooth(balance-0.05,balance+0.05,$0)},w,h,1,1.2),(gx,gy)=try sobel(m,w,h)
      for i in c.indices{try poll(i);let n=(hash(i%w,i/w,0,161)-0.5)*grain*0.3,f=clamp(shade(gx[i],gy[i],light("topLeft"),relief*6),0,2);c[i]=map(mix(fg,bg,m[i])){($0+n)*f}}
    case .photocopy:
      let detail=g("detail"),darkness=g("darkness")/50,l=c.map(lum),b=try blur(l,w,h,1,1+detail*0.5)
      for i in c.indices{try poll(i);let hp=l[i]-b[i],ink=smooth(0,0.06,-hp*(1+darkness*8))+smooth(0.35,0.05,l[i])*darkness*1.5;c[i]=mix(bg,fg,clamp(ink))}
    case .plaster:
      let balance=g("imageBalance")/50,l=try blur(c.map(lum),w,h,1,0.5+g("smoothness")*0.8),m=try blur(l.map{smooth(balance+0.1,balance-0.1,$0)},w,h,1,1.5),(gx,gy)=try sobel(m,w,h),lt=light(e.choice("light"))
      for i in c.indices{try poll(i);let f=clamp(shade(gx[i],gy[i],lt,6),0,2);c[i]=mix(bg,fg,m[i]*0.6)*f}
    case .reticulation:
      let density=g("density")/50,fl=g("foregroundLevel")/50,bl=g("backgroundLevel")/50,ink=mix(bg,fg,0.3+fl*0.7),paper=mix(bg,fg,bl*0.6)
      for i in c.indices{try poll(i);let x=i%w,y=i/w,n=0.5*hash(x,y,0,171)+0.5*noise(Float(x)/1.8,Float(y)/1.8,172),t=1-lum(c[i])+(n-0.5)*(0.4+density*1.2);c[i]=mix(paper,ink,smooth(0.45,0.55,t))}
    case .stamp:
      let balance=g("lightDarkBalance")/50,l=try blur(c.map(lum),w,h,1,0.3+g("smoothness")*0.3)
      for i in c.indices{try poll(i);c[i]=mix(bg,fg,smooth(balance+0.02,balance-0.02,l[i]))}
    case .tornEdges:
      let balance=g("imageBalance")/50,rough=(16-g("smoothness"))/15*0.35,aa=0.25/g("contrast"),l=try blur(c.map(lum),w,h,1,1)
      for i in c.indices{try poll(i);let t=l[i]+(fbm(Float(i%w)/2,Float(i/w)/2,181)-0.5)*rough;c[i]=mix(bg,fg,smooth(balance+aa,balance-aa,t))}
    case .waterPaper:
      let length=g("fiberLength"),brightness=g("brightness")/100,contrast=g("contrast")/100,radius=Int(length/6);c=try line3(c,w,h,(1,0),radius);c=try line3(c,w,h,(0,1),radius)
      for i in c.indices{try poll(i);let x=i%w,y=i/w,fiber=max(stroke(x,y,(1,0),length,1,191),stroke(x,y,(0,1),length,1,192));c[i]=map(c[i]){($0*(0.85+0.25*fiber)-0.5)*(contrast*1.6+0.2)+0.5+(brightness-0.5)*0.8}}
    default:throw CraftError.invalid("Not a Sketch gallery effect.")
    };return c
  }
}
