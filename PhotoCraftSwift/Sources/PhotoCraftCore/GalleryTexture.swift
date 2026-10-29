import Foundation

extension GalleryMath {
  static func textured(_ e:GalleryEffect,_ input:[V],_ w:Int,_ h:Int)throws->[V]{
    var c=input;let g=e.get,fg=e.foreground.rgb,bg=e.background.rgb
    switch e.filter {
    case .craquelure:
      let cell=g("crackSpacing")*1.3+1,depth=g("crackDepth")/10,brightness=g("crackBrightness")/10,width=0.8+depth*0.8
      func crack(_ x:Float,_ y:Float)->Float{let(a,b,_,_)=voronoi(x,y,cell,201);return 1-smooth(0,width,b-a)}
      for i in c.indices{try poll(i);let x=Float(i%w)+0.5,y=Float(i/w)+0.5,a=crack(x,y),gx=crack(x+1,y)-a,gy=crack(x,y+1)-a,f=clamp(shade(-gx,-gy,light("topLeft"),depth*2),0,2);c[i] *= (0.55+brightness*0.5)*(1-a*depth*0.6)*f}
    case .grain:
      let intensity=g("intensity")/100,contrast=g("contrast")/100,type=e.choice("grainType")
      for i in c.indices{try poll(i);let x=i%w,y=i/w,p=c[i];func hc(_ channel:UInt32)->Float{hash(x,y,channel,211)-0.5};let q:V
        switch type{
        case "soft":q=p+V(hc(0),hc(1),hc(2))*intensity*0.4
        case "sprinkles":q=hash(x,y,3,211)<intensity*0.15 ? bg:p
        case "clumped":let n=(noise(Float(x)/2,Float(y)/2,212)-0.5)*intensity*1.2;q=map(p){$0+n}
        case "contrasty":q=map(p){($0-0.5)*(1+intensity*2)+0.5+hc(4)*intensity*0.5}
        case "enlarged":let fx=Float(x)/3,fy=Float(y)/3;q=p+V(noise(fx,fy,213)-0.5,noise(fx,fy,214)-0.5,noise(fx,fy,215)-0.5)*intensity
        case "stippled":q=mix(p,lum(p)>hash(x,y,5,211) ? bg:fg,0.3+intensity*0.7)
        case "horizontal":let n=(noise(Float(x)/25,Float(y),216)-0.5)*intensity;q=map(p){$0+n}
        case "vertical":let n=(noise(Float(x),Float(y)/25,217)-0.5)*intensity;q=map(p){$0+n}
        case "speckle":q=hash(x,y,6,211)<intensity*0.1 ? mix(p,fg,0.85):p
        default:q=p+V(hc(0),hc(1),hc(2))*intensity*0.8
        };c[i]=map(q){($0-0.5)*(0.5+contrast)+0.5}
      }
    case .mosaicTiles:
      let size=g("tileSize"),width=g("groutWidth"),brightness=g("lightenGrout")/10
      func edge(_ x:Float,_ y:Float)->Float{let jx=x+(noise(x/size*0.7,y/size*0.7,221)-0.5)*size*0.3,jy=y+(noise(x/size*0.7,y/size*0.7,222)-0.5)*size*0.3,u=mod(jx,size),v=mod(jy,size);return min(min(u,size-u),min(v,size-v))}
      func height(_ x:Float,_ y:Float)->Float{smooth(width*0.5,width*0.5+2.5,edge(x,y))}
      for i in c.indices{try poll(i);let x=Float(i%w)+0.5,y=Float(i/w)+0.5,grout=smooth(width*0.5+0.7,width*0.5-0.3,edge(x,y)),s=(height(x-1,y-1)-height(x+1,y+1))*0.35,gc=V(repeating:clamp(lum(c[i])*0.5+brightness*0.45));c[i]=mix(c[i]*(1+s),gc,grout)}
    case .patchwork:
      let size=3+g("squareSize")*1.5,relief=g("relief")/25
      func height(_ x:Float,_ y:Float)->Float{let bx=Int(floor(x/size)),by=Int(floor(y/size)),u=mod(x,size),v=mod(y,size),bevel=smooth(0,1.5,min(min(u,size-u),min(v,size-v)));return hash(bx,by,0,231)*bevel}
      for i in c.indices{try poll(i);let x=Float(i%w)+0.5,y=Float(i/w)+0.5,bx=floor(x/size),by=floor(y/size),p=at(input,w,h,Int((bx+0.5)*size),Int((by+0.5)*size)),s=(height(x-1,y-1)-height(x+1,y+1))*relief*1.5;c[i]=p*(1+s)}
    case .stainedGlass:
      let cell=g("cellSize")*1.6+1,thickness=g("borderThickness"),light=g("lightIntensity")/10,cx=Float(w)/2,cy=Float(h)/2,half=max(1,Float(max(w,h))/2)
      for i in c.indices{try poll(i);let x=Float(i%w)+0.5,y=Float(i/w)+0.5,(a,b,px,py)=voronoi(x,y,cell,241),border=smooth(thickness*0.5+0.6,thickness*0.5-0.4,(b-a)*0.5),distance=min(1,sqrt((x-cx)*(x-cx)+(y-cy)*(y-cy))/half),color=at(input,w,h,Int(px),Int(py))*(1+light*0.6*(1-distance));c[i]=mix(color,fg,border)}
    case .texturizer:c=try texturize(c,w,e)
    default:throw CraftError.invalid("Not a Texture gallery effect.")
    };return c
  }
}
