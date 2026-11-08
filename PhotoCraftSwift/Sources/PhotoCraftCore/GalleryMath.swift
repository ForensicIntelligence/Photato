import Foundation

/// Float32 kernels translated from PhotoCraft artistic_fx.rs/fxutil.rs/noise.rs.
/// Double running sums retain the source's stable box-window accumulation.
enum GalleryMath {
  typealias V=SIMD3<Float>
  static func poll(_ i:Int)throws{if i & 4095 == 0{try Task.checkCancellation()}}
  static func clamp(_ v:Float,_ lo:Float=0,_ hi:Float=1)->Float{min(hi,max(lo,v))}
  static func lum(_ p:V)->Float{0.299*p.x+0.587*p.y+0.114*p.z}
  static func map(_ p:V,_ f:(Float)->Float)->V{V(f(p.x),f(p.y),f(p.z))}
  static func mix(_ a:V,_ b:V,_ t:Float)->V{a+(b-a)*t}
  static func smooth(_ a:Float,_ b:Float,_ x:Float)->Float{if abs(b-a)<1e-9{return x>=b ? 1:0};let t=clamp((x-a)/(b-a));return t*t*(3-2*t)}
  static func poster(_ v:Float,_ levels:Float)->Float{let l=max(levels-1,1);return (clamp(v)*l).rounded()/l}
  static func saturate(_ p:V,_ k:Float)->V{let l=lum(p);return map(p){l+($0-l)*k}}
  static func normalized(_ p:V)->V{p/max(1e-9,sqrt(p.x*p.x+p.y*p.y+p.z*p.z))}
  static func mod(_ x:Float,_ p:Float)->Float{x-floor(x/p)*p}
  static func fract(_ x:Float)->Float{x-x.rounded(.towardZero)}
  static func hash(_ x:Int,_ y:Int,_ channel:UInt32=0,_ seed:UInt32)->Float{
    var h=(UInt32(truncatingIfNeeded:x) &* 0x8da6b343) ^ (UInt32(truncatingIfNeeded:y) &* 0xd8163841) ^ (channel &* 0xcb1ab31f) ^ (seed &* 0x9e3779b9)
    h ^= h >> 16;h = h &* 0x7feb352d;h ^= h >> 15;h = h &* 0x846ca68b;h ^= h >> 16;return Float(h >> 8)/16777216
  }
  static func noise(_ x:Float,_ y:Float,_ seed:UInt32)->Float{let ix=Int(floor(x)),iy=Int(floor(y)),tx=x-Float(ix),ty=y-Float(iy),sx=tx*tx*(3-2*tx),sy=ty*ty*(3-2*ty);let a=hash(ix,iy,0,seed),b=hash(ix,iy+1,0,seed);let top=a+(hash(ix+1,iy,0,seed)-a)*sx,bot=b+(hash(ix+1,iy+1,0,seed)-b)*sx;return top+(bot-top)*sy}
  static func fbm(_ x:Float,_ y:Float,_ seed:UInt32)->Float{noise(x,y,seed)*0.57+noise(x*2.03,y*2.03,seed ^ 0x51)*0.29+noise(x*4.1,y*4.1,seed ^ 0xa3)*0.14}
  static func stroke(_ x:Int,_ y:Int,_ d:(Int,Int),_ length:Float,_ width:Float,_ seed:UInt32)->Float{let dx=Float(d.0),dy=Float(d.1),l=max(1e-6,sqrt(dx*dx+dy*dy)),ux=dx/l,uy=dy/l;return noise((Float(x)*ux+Float(y)*uy)/max(0.5,length),(-Float(x)*uy+Float(y)*ux)/max(0.3,width),seed)}
  static func direction(_ name:String)->(Int,Int){switch name{case "horizontal":(1,0);case "vertical":(0,1);case "leftDiagonal":(1,1);default:(1,-1)}}
  static func light(_ name:String)->(Float,Float){let s:Float=1/sqrt(2);switch name{case "bottom":return(0,1);case "bottomLeft":return(-s,s);case "left":return(-1,0);case "topLeft":return(-s,-s);case "topRight":return(s,-s);case "right":return(1,0);case "bottomRight":return(s,s);default:return(0,-1)}}
  static func shade(_ gx:Float,_ gy:Float,_ l:(Float,Float),_ k:Float)->Float{let nx = -k*gx,ny = -k*gy,n=sqrt(nx*nx+ny*ny+1);return (nx*l.0+ny*l.1+1)/n}
  static func weave(_ x:Float,_ y:Float,_ p:Float,_ amplitude:Float)->Float{let cx=Int(floor(x/p)),cy=Int(floor(y/p)),ridge=sin((cx+cy)%2==0 ? mod(y,p)/p * .pi:mod(x,p)/p * .pi);return ridge*(1-amplitude)+noise(x/(p*0.7),y/(p*2),97)*amplitude}
  static func texture(_ name:String,_ xx:Float,_ yy:Float,_ scale:Float)->Float{
    let x=xx/scale,y=yy/scale
    switch name{
    case "brick":let xo=x+(Int(floor(y/12))%2==0 ? 0:12),u=mod(xo,24),v=mod(y,12),d=min(min(u,24-u),min(v,12-v));return smooth(0.6,2.2,d)*(0.85+0.15*noise(x/3,y/3,91))
    case "burlap":return weave(x,y,7,0.35)
    case "canvas":return weave(x,y,3.5,0.18)
    case "sandstone":return fbm(x/7,y/7,93)*0.7+hash(Int(x),Int(y),0,94)*0.3
    case "blocks":let u=mod(x,18)/18,v=mod(y,18)/18;return min(1,min(min(u,1-u),min(v,1-v))*4)
    case "frosted":return fbm(x/2.5,y/2.5,95)
    case "tinyLens":let u=(mod(x,12)/12-0.5)*2,v=(mod(y,12)/12-0.5)*2;return sqrt(max(0,1-u*u-v*v))
    default:return 0.5
    }
  }
  static func voronoi(_ x:Float,_ y:Float,_ cell:Float,_ seed:UInt32)->(Float,Float,Float,Float){
    let cx=Int(floor(x/cell)),cy=Int(floor(y/cell));var first=Float.greatestFiniteMagnitude,second=first,px=x,py=y
    for j in -1...1{for i in -1...1{let a=cx+i,b=cy+j,qx=(Float(a)+0.1+0.8*hash(a,b,11,seed))*cell,qy=(Float(b)+0.1+0.8*hash(a,b,12,seed))*cell,d=sqrt((qx-x)*(qx-x)+(qy-y)*(qy-y));if d<first{second=first;first=d;px=qx;py=qy}else if d<second{second=d}}};return(first,second,px,py)
  }
  static func highlight(_ p:V,_ l:Float,_ area:Float,_ intensity:Float)->V{guard area>0 else{return p};let m=smooth(1-area/20*0.75,1.02,l)*(1-intensity/10*0.6);return map(p){$0+(1-$0)*m}}
  static func sample(_ p:[V],_ w:Int,_ h:Int,_ x:Float,_ y:Float)->V{let fx=clamp(x-0.5,0,Float(w-1)),fy=clamp(y-0.5,0,Float(h-1)),x0=Int(floor(fx)),y0=Int(floor(fy)),x1=min(w-1,x0+1),y1=min(h-1,y0+1),a=fx-Float(x0),b=fy-Float(y0);return mix(mix(p[y0*w+x0],p[y0*w+x1],a),mix(p[y1*w+x0],p[y1*w+x1],a),b)}
  static func at(_ p:[V],_ w:Int,_ h:Int,_ x:Int,_ y:Int)->V{p[min(h-1,max(0,y))*w+min(w-1,max(0,x))]}
  static func line(_ input:[Float],_ w:Int,_ h:Int,_ n:Int,_ d:(Int,Int),_ radius:Int)throws->[Float]{
    guard radius>0 else{return input};var output=input
    func inside(_ x:Int,_ y:Int)->Bool{x>=0 && y>=0 && x<w && y<h}
    let scale=1/Double(2*radius+1)
    for sy in 0..<h{try Task.checkCancellation();for sx in 0..<w where !inside(sx-d.0,sy-d.1){
      var indices:[Int]=[];var x=sx,y=sy
      while inside(x,y){indices.append((y*w+x)*n);x += d.0;y += d.1}
      for c in 0..<n{func v(_ i:Int)->Double{Double(input[indices[min(indices.count-1,max(0,i))]+c])};var sum=(-radius...radius).reduce(0.0){$0+v($1)}
        for (i,index)in indices.enumerated(){output[index+c]=Float(sum*scale);sum += v(i+radius+1)-v(i-radius)}
      }
    }};return output
  }
  static func line3(_ p:[V],_ w:Int,_ h:Int,_ d:(Int,Int),_ radius:Int)throws->[V]{guard radius>0 else{return p};let values=try line(p.flatMap{[$0.x,$0.y,$0.z]},w,h,3,d,radius);return stride(from:0,to:values.count,by:3).map{V(values[$0],values[$0+1],values[$0+2])}}
  static func radii(_ sigma:Float)->[Int]{let ideal=sqrt(12*sigma*sigma/3+1);var lower=Int(floor(ideal));if lower%2==0{lower -= 1};lower=max(1,lower);let l=Float(lower),m=Int(clamp(((12*sigma*sigma-3*l*l-12*l-9)/(-4*l-4)).rounded(),0,3));return (0..<3).map{$0<m ? (lower-1)/2:(lower+1)/2}}
  static func blur(_ p:[Float],_ w:Int,_ h:Int,_ n:Int,_ sigma:Float)throws->[Float]{guard sigma>=0.3 else{return p};var result=p;let rs=radii(sigma);for r in rs{result=try line(result,w,h,n,(1,0),r)};for r in rs{result=try line(result,w,h,n,(0,1),r)};return result}
  static func blur3(_ p:[V],_ w:Int,_ h:Int,_ sigma:Float)throws->[V]{guard sigma>=0.3 else{return p};let data=try blur(p.flatMap{[$0.x,$0.y,$0.z]},w,h,3,sigma);return stride(from:0,to:data.count,by:3).map{V(data[$0],data[$0+1],data[$0+2])}}
  static func sobel(_ p:[Float],_ w:Int,_ h:Int)throws->([Float],[Float]){var gx=p,gy=p;func at(_ x:Int,_ y:Int)->Float{p[min(h-1,max(0,y))*w+min(w-1,max(0,x))]};for y in 0..<h{try Task.checkCancellation();for x in 0..<w{gx[y*w+x]=((at(x+1,y-1)+2*at(x+1,y)+at(x+1,y+1))-(at(x-1,y-1)+2*at(x-1,y)+at(x-1,y+1)))/8;gy[y*w+x]=((at(x-1,y+1)+2*at(x,y+1)+at(x+1,y+1))-(at(x-1,y-1)+2*at(x,y-1)+at(x+1,y-1)))/8}};return(gx,gy)}
  static func gradient(_ p:[Float],_ w:Int,_ h:Int)throws->[Float]{let (x,y)=try sobel(p,w,h);return zip(x,y).map{sqrt($0*$0+$1*$1)}}
  static func unsharp(_ p:[V],_ w:Int,_ h:Int,_ sigma:Float,_ amount:Float)throws->[V]{guard amount>0 else{return p};let b=try blur3(p,w,h,sigma);return zip(p,b).map{$0+($0-$1)*amount}}
  static func kuwahara(_ p:[V],_ w:Int,_ h:Int,_ radius:Int)throws->[V]{
    let offset=max(1,(radius+1)/2);var moments:[Float]=[];moments.reserveCapacity(w*h*5)
    for c in p{let l=lum(c);moments += [c.x,c.y,c.z,l,l*l]}
    moments=try line(line(moments,w,h,5,(1,0),offset),w,h,5,(0,1),offset)
    var out=p
    for y in 0..<h{try Task.checkCancellation();for x in 0..<w{var best=Float.greatestFiniteMagnitude
      for(dx,dy)in [(-offset,-offset),(offset,-offset),(-offset,offset),(offset,offset)]{let i=(min(h-1,max(0,y+dy))*w+min(w-1,max(0,x+dx)))*5,v=moments[i+4]-moments[i+3]*moments[i+3];if v<best{best=v;out[y*w+x]=V(moments[i],moments[i+1],moments[i+2])}}
    }};return out
  }
  static func texturize(_ input:[V],_ w:Int,_ e:GalleryEffect,_ relief:Float?=nil)throws->[V]{
    if let texture=e.texture {return try customTexturize(input,w,e,texture,relief)}
    let r=relief ?? e.get("relief");guard r>0 else{return input};let scale=clamp(e.get("scaling")/100,0.5,2),l=light(e.choice("light")),k=r/50*3,sign:Float=e.flag("invert") ? -1:1,kind=e.choice("texture");var out=input
    for i in input.indices{try poll(i);let x=Float(i%w),y=Float(i/w),gx=(texture(kind,x+1,y,scale)-texture(kind,x-1,y,scale))*0.5*sign,gy=(texture(kind,x,y+1,scale)-texture(kind,x,y-1,scale))*0.5*sign;out[i]=input[i]*clamp(shade(gx,gy,l,k),0,2)};return out
  }
}
