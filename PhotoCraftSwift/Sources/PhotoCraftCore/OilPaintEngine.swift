import Foundation

/// Native RGB translation of PhotoCraft oil.rs and fxutil.rs (MIT OR Apache-2.0).
/// Tile halos preserve field/brush neighborhoods; this is not an Adobe implementation.
enum OilPaintEngine {
  typealias Sample=SIMD4<Float>
  static func radii(_ sigma:Float)->[Int] {
    let n:Float=3,ideal=sqrt(12*sigma*sigma/n+1);var lower=Int(floor(ideal));if lower%2==0 {lower-=1};lower=max(1,lower)
    let upper=lower+2,lo=Float(lower)
    let m=Int(min(n,max(0,((12*sigma*sigma-n*Float(lower*lower)-4*n*lo-3*n)/(-4*lo-4)).rounded())))
    return (0..<3).map{$0<m ? (lower-1)/2:(upper-1)/2}
  }
  static func blur(_ values:inout [Sample],width w:Int,height h:Int,sigma:Float)throws {
    if sigma<0.3 {return}
    for vertical in [false,true] {for r in radii(sigma) where r>0 {
      let length=vertical ? h:w,lines=vertical ? w:h,norm=1.0/Double(2*r+1)
      var scratch=[Sample](repeating:.zero,count:length)
      for line in 0..<lines {
        try Task.checkCancellation()
        for j in 0..<length {scratch[j]=values[vertical ? j*w+line:line*w+j]}
        func at(_ i:Int,_ c:Int)->Double {Double(scratch[min(length-1,max(0,i))][c])}
        for c in 0..<4 {
          var acc:Double=0;for j in -r...r {acc+=at(j,c)}
          for j in 0..<length {values[vertical ? j*w+line:line*w+j][c]=Float(acc*norm);acc+=at(j+r+1,c)-at(j-r,c)}
        }
      }
    }}
  }
  static func process(_ input:[Sample],width w:Int,height h:Int,settings s:StylizeSettings)throws->[Sample] {
    let length:Float=1.5+max(0.1,Float(s.stylization))*2,sigma:Float=0.8+max(0.1,Float(s.scale))*0.6
    let halo=Int(ceil(length+3*sigma+3*2.5+4))+1
    var result=input
    for y in stride(from:0,to:h,by:256) {for x in stride(from:0,to:w,by:256) {
      try Task.checkCancellation();let tw=min(256,w-x),th=min(256,h-y)
      let tile=try processTile(input,width:w,height:h,x:x,y:y,width:tw,height:th,halo:halo,settings:s)
      for row in 0..<th {result.replaceSubrange((y+row)*w+x..<(y+row)*w+x+tw,with:tile[row*tw..<(row+1)*tw])}
    }}
    return result
  }
  private static func processTile(_ input:[Sample],width w:Int,height h:Int,x tx:Int,y ty:Int,width tw:Int,height th:Int,halo:Int,settings s:StylizeSettings)throws->[Sample] {
    let ww=tw+2*halo,wh=th+2*halo,originX=tx-halo,originY=ty-halo
    var p=[Sample](repeating:.zero,count:ww*wh)
    for y in 0..<wh {try Task.checkCancellation();for x in 0..<ww {
      let v=input[min(h-1,max(0,originY+y))*w+min(w-1,max(0,originX+x))];p[y*ww+x]=Sample(v.x*v.w,v.y*v.w,v.z*v.w,v.w)
    }}
    try blur(&p,width:ww,height:wh,sigma:Float(s.cleanliness)*0.25)
    let lum=p.map{($0.x+$0.y+$0.z)/3};var tensor=[Sample](repeating:.zero,count:ww*wh)
    for y in 1..<(wh-1) {try Task.checkCancellation();for x in 1..<(ww-1) {
      func l(_ dx:Int,_ dy:Int)->Float {lum[(y+dy)*ww+x+dx]}
      let gx=(l(1,-1)+2*l(1,0)+l(1,1))-(l(-1,-1)+2*l(-1,0)+l(-1,1))
      let gy=(l(-1,1)+2*l(0,1)+l(1,1))-(l(-1,-1)+2*l(0,-1)+l(1,-1))
      tensor[y*ww+x]=Sample(gx*gx,gx*gy,gy*gy,0)
    }}
    try blur(&tensor,width:ww,height:wh,sigma:0.8+max(0.1,Float(s.scale))*0.6)
    var tangents=[SIMD2<Float>]();tangents.reserveCapacity(ww*wh)
    for (i,t) in tensor.enumerated() {
      if i & 4095 == 0 {try Task.checkCancellation()}
      let e=t.x,f=t.y,g=t.z,l1:Float=0.5*(e+g+sqrt((e-g)*(e-g)+4*f*f)),dx=l1-e,dy = -f,m=sqrt(dx*dx+dy*dy)
      tangents.append(m<1e-6 || l1-(e+g-l1)<1e-6 ? SIMD2(repeating:Float(1/sqrt(2.0))):SIMD2(dx/m,dy/m))
    }
    tensor=[]
    let rw=tw+2,rh=th+2,len:Float=1.5+max(0.1,Float(s.stylization))*2,step=max(1,len/10),steps=Int(ceil(len/step))
    var colors=[Sample](repeating:.zero,count:rw*rh),bristles=[Float](repeating:0,count:rw*rh)
    func sample(_ x:Float,_ y:Float,_ weight:Float)->Sample {
      let fx=min(Float(ww-1),max(0,x)),fy=min(Float(wh-1),max(0,y)),x0=Int(floor(fx)),y0=Int(floor(fy)),x1=min(ww-1,x0+1),y1=min(wh-1,y0+1),ax=fx-Float(x0),ay=fy-Float(y0)
      let w00=(1-ax)*(1-ay)*weight,w10=ax*(1-ay)*weight,w01=(1-ax)*ay*weight,w11=ax*ay*weight
      return p[y0*ww+x0]*w00+p[y0*ww+x1]*w10+p[y1*ww+x0]*w01+p[y1*ww+x1]*w11
    }
    for y in 0..<rh {try Task.checkCancellation();for x in 0..<rw {
      let dx=Float(halo-1+x),dy=Float(halo-1+y);var acc=sample(dx,dy,1),weight:Float=1,noise=StylizeEngine.hash(originX+Int(dx),originY+Int(dy),71,0)
      for direction:Float in [1,-1] {
        var qx=dx,qy=dy,px:Float=0,py:Float=0
        for k in 1...steps {
          let index=Int(min(Float(wh-1),max(0,qy.rounded())))*ww+Int(min(Float(ww-1),max(0,qx.rounded())))
          var t=tangents[index]
          if k==1 {t*=direction} else if t.x*px+t.y*py<0 {t = -t}
          px=t.x;py=t.y;qx+=t.x*step;qy+=t.y*step
          let wk:Float=1-Float(k)/Float(steps+1);acc+=sample(qx,qy,wk);weight+=wk
          noise+=wk*StylizeEngine.hash(originX+Int(qx.rounded()),originY+Int(qy.rounded()),71,0)
        }
      }
      colors[y*rw+x]=acc/weight;bristles[y*rw+x]=noise/weight-0.5
    }}
    let angle=Float(s.angle)*(Float.pi/180),elevation:Float=45*(Float.pi/180),light=SIMD3(cos(angle)*cos(elevation),-sin(angle)*cos(elevation),sin(elevation))
    let v=SIMD3(light.x,light.y,light.z+1),m=sqrt(v.x*v.x+v.y*v.y+v.z*v.z),half=v/m,amp=Float(s.bristleDetail)/10,shine=Float(s.shine)/10,flatSpec=pow(half.z,40)
    func height(_ x:Int,_ y:Int)->Float {let col=colors[y*rw+x];return (col.x+col.y+col.z)/3*2+bristles[y*rw+x]*amp*6}
    var result=[Sample]();result.reserveCapacity(tw*th)
    for y in 0..<th {try Task.checkCancellation();for x in 0..<tw {
      let rx=x+1,ry=y+1;var px=colors[ry*rw+rx];let a=px.w
      if a>1e-7 {px.x/=a;px.y/=a;px.z/=a} else {px.x=0;px.y=0;px.z=0};px.w=input[(ty+y)*w+tx+x].w
      if s.lighting {
        let hx=height(rx+1,ry)-height(rx-1,ry),hy=height(rx,ry+1)-height(rx,ry-1),nx = -hx*0.5,ny = -hy*0.5,norm=sqrt(nx*nx+ny*ny+1)
        let ndl=(nx*light.x+ny*light.y+light.z)/norm,ndh=max(0,(nx*half.x+ny*half.y+half.z)/norm),shade:Float=1+(ndl-light.z)*1.2,spec:Float=shine*max(0,pow(ndh,40)-flatSpec)*0.8
        px.x=px.x*shade+spec;px.y=px.y*shade+spec;px.z=px.z*shade+spec
      }
      result.append(px)
    }}
    return result
  }
}
