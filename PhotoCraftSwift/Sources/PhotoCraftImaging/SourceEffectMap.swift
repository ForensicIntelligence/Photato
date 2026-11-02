import Foundation
import PhotoCraftCore

/// Native translation of PhotoCraft compose/effects.rs map kernels (MIT OR Apache-2.0).
/// Map and document capacity are distinct; callers bound scratch before allocation.
struct SourceEffectMap:Sendable {
  static let insideEPS:Float=0.5/255
  let w:Int,h:Int
  var v:[Float]
  init(_ w:Int,_ h:Int,fill:Float=0){self.w=w;self.h=h;v=Array(repeating:fill,count:w*h)}
  func get(_ x:Int,_ y:Int)->Float {x>=0 && y>=0 && x<w && y<h ? v[y*w+x]:0}
  func mapped(_ f:(Float)->Float)->Self {var out=self;out.v=v.map(f);return out}
  func shifted(_ dx:Float,_ dy:Float,outside:Float=0)throws->Self {
    var out=Self(w,h);let fx=Int(floor(dx)),fy=Int(floor(dy)),ax=dx-Float(fx),ay=dy-Float(fy)
    func at(_ x:Int,_ y:Int)->Float {x>=0 && y>=0 && x<w && y<h ? v[y*w+x]:outside}
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let sx=x-fx,sy=y-fy,top=at(sx,sy)*(1-ax)+at(sx-1,sy)*ax,bot=at(sx,sy-1)*(1-ax)+at(sx-1,sy-1)*ax
      out.v[y*w+x]=top*(1-ay)+bot*ay
    }};return out
  }
  static func dt(_ f:[Float])->([Float],[Int]) {
    let n=f.count;var out=[Float](repeating:0,count:n),near=[Int](repeating:0,count:n),v=[Int](repeating:0,count:n),z=[Float](repeating:0,count:n+1),k=0
    z[0] = -.infinity;z[1] = .infinity
    if n>1 {for q in 1..<n {while true {
      let p=v[k],s=((f[q]+Float(q*q))-(f[p]+Float(p*p)))/(2*Float(q)-2*Float(p))
      if s<=z[k] && k>0 {k-=1;continue}
      if s<=z[k] {v[0]=q;z[0] = -.infinity;z[1] = .infinity;break}
      k+=1;v[k]=q;z[k]=s;z[k+1] = .infinity;break
    }}}
    k=0;for q in 0..<n {while z[k+1]<Float(q){k+=1};let p=v[k],d=Float(q)-Float(p);out[q]=d*d+f[p];near[q]=p}
    return(out,near)
  }
  func euclidean(_ inside:[Bool])throws->([Float],[Int]) {
    var g=inside.map{$0 ? Float(0):Float(1e20)},nearRow=[Int](repeating:0,count:w*h),nearest=nearRow
    for x in 0..<w {try Task.checkCancellation();let row=(0..<h).map{g[$0*w+x]},(o,n)=Self.dt(row);for y in 0..<h {g[y*w+x]=o[y];nearRow[y*w+x]=n[y]}}
    for y in 0..<h {try Task.checkCancellation();let(o,n)=Self.dt(Array(g[y*w..<(y+1)*w]));for x in 0..<w {g[y*w+x]=sqrt(o[x]);let px=n[x];nearest[y*w+x]=nearRow[y*w+px]*w+px}}
    return(g,nearest)
  }
  func chamfer(_ start:[Float])throws->[Float] {
    let offsets:[(Int,Int,Float)]=[(-1,0,1),(-1,-1,sqrt(2)),(0,-1,1),(1,-1,sqrt(2)),(-1,-2,2.236068),(1,-2,2.236068),(-2,-1,2.236068),(2,-1,2.236068)]
    var d=start
    for sign in [1,-1] {for row in 0..<h {try Task.checkCancellation();let y=sign==1 ? row:h-1-row
      for col in 0..<w {let x=sign==1 ? col:w-1-col,i=y*w+x;var best=d[i]
        for(ox,oy,weight)in offsets {let nx=x+ox*sign,ny=y+oy*sign;if nx>=0 && ny>=0 && nx<w && ny<h {let value=d[ny*w+nx]+weight;if value<best {best=value}}};d[i]=best
      }
    }};return d
  }
  func outside(chamfer:Bool=false)throws->[Float] {
    if chamfer {let start=v.map{$0>Self.insideEPS ? 1-min($0,1):Float(1e20)},d=try self.chamfer(start);return d.indices.map{v[$0]>Self.insideEPS ? -0.5:d[$0]-0.5}}
    let inside=v.map{$0>Self.insideEPS},(d,nearest)=try euclidean(inside)
    return d.indices.map{inside[$0] ? -0.5:d[$0]-0.5+(1-min(v[nearest[$0]],1))}
  }
  func localCoverage()throws->Self {
    var out=self
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {let a=get(x,y);if a<=Self.insideEPS {continue};var maximum=a
      for dy in -1...1 {for dx in -1...1 {maximum=max(maximum,get(x+dx,y+dy))}};out.v[y*w+x]=min(a/maximum,1)
    }};return out
  }
  func inside(chamfer:Bool=false)throws->[Float] {
    if chamfer {let coverage=try localCoverage(),start=v.indices.map{i -> Float in v[i]<=Self.insideEPS ? 0:coverage.v[i]<1-Self.insideEPS ? coverage.v[i]:1e20},d=try self.chamfer(start);return d.indices.map{v[$0]<=Self.insideEPS ? -0.5:d[$0]-0.5}}
    let outside=v.map{$0<=Self.insideEPS},(d,_)=try euclidean(outside);return d.indices.map{outside[$0] ? -0.5:d[$0]-0.5}
  }
  func dilated(_ radius:Float)throws->Self {
    if radius<=0 {return self};let d=try outside(chamfer:true);var out=self
    for i in v.indices {if i&4095==0{try Task.checkCancellation()};out.v[i]=d[i]<0 ? min(v[i]+radius,1):max(v[i],unit(radius+0.5-d[i]))};return out
  }
  static func box(_ source:[Double],x0:Int,count:Int,width:Float)->[Double] {
    let width=max(1,width),half=width/2,r=max(0,Int(ceil(half-0.5))),f=Double(min(1,max(0,half-(Float(r)-0.5)))),norm=1/Double(width)
    func at(_ i:Int)->Double {i>=0 && i<source.count ? source[i]:0}
    if r==0 {return (0..<count).map{at(x0+$0)}}
    var inner=(x0-(r-1)...x0+(r-1)).reduce(0.0){$0+at($1)},out=[Double](repeating:0,count:count)
    for k in 0..<count {let x=x0+k;out[k]=(inner+f*(at(x-r)+at(x+r)))*norm;inner+=at(x+r)-at(x-r+1)};return out
  }
  static func tentLine(_ source:[Float],width:Float)->[Float] {
    let r=max(0,Int(ceil(max(width,1)/2-0.5)))
    if r==0{return source};let middle=box(source.map(Double.init),x0:-r,count:source.count+2*r,width:width)
    return box(middle,x0:r,count:source.count,width:width).map(Float.init)
  }
  func blurred(_ size:Float)throws->Self {
    if size<=1{return self};var out=self
    for y in 0..<h {try Task.checkCancellation();let row=Self.tentLine(Array(v[y*w..<(y+1)*w]),width:size);out.v.replaceSubrange(y*w..<(y+1)*w,with:row)}
    let horizontal=out.v
    for x in 0..<w {try Task.checkCancellation();let row=Self.tentLine((0..<h).map{horizontal[$0*w+x]},width:size);for y in 0..<h {out.v[y*w+x]=row[y]}};return out
  }
  static func lookup(_ table:[Float],_ value:Float)->Float {
    let x=unit(value)*Float(table.count-1),i=Int(floor(x)),j=min(i+1,table.count-1)
    return table[i]+(table[j]-table[i])*(x-Float(i))
  }
  func contoured(_ contour:EffectContour,range:Float=1)throws->Self {
    var table=try contour.table()
    let range=min(1,max(0.01,range))
    if range<0.999 {let base=table;table=(0..<4096).map{k in let v=min(Float(k)/4095/range,1);return base.map{Self.lookup($0,v)} ?? v}}
    guard let table else{return self};return mapped{Self.lookup(table,$0)}
  }
  static func offset(_ angle:Float,_ distance:Float)->(Float,Float) {let r=angle*(Float.pi/180);return((-cos(r)*distance).rounded(),(sin(r)*distance).rounded())}
  func shadow(_ effect:LayerEffect,_ advanced:LayerEffectAdvanced,angle:Float,scale:Float,inner:Bool)throws->Self {
    let(dx,dy)=Self.offset(angle,Float(effect.distance)*scale),source=inner ? mapped{1-$0}:self
    var result=try source.shifted(dx,dy,outside:inner ? 1:0);let size=Float(effect.size)*scale,spread=Float(effect.spread/100),r=(size*spread).rounded()
    result=try result.dilated(r).blurred(size*(1-spread)).contoured(advanced.contour)
    if inner {for i in v.indices {result.v[i]*=v[i]}};return result
  }
  func glow(_ effect:LayerEffect,_ advanced:LayerEffectAdvanced,scale:Float,inner:Bool)throws->Self {
    let source=inner && advanced.glowSource == .edge ? mapped{1-$0}:self,size=Float(effect.size)*scale,spread=Float(effect.spread/100)
    var result:Self
    if advanced.glowTechnique == .precise {
      let d=try inner && advanced.glowSource == .edge ? inside():source.outside(),solid=size*spread,soft=max(1e-3,size-solid)
      result=self;result.v=d.map{$0<=solid ? 1:unit(1-($0-solid)/soft)}
      if inner && advanced.glowSource == .center {result=result.mapped{1-$0}}
    } else {
      let r=(size*spread).rounded(),width=size*(1-spread);result=try source.dilated(r).blurred(width)
      if inner && advanced.glowSource == .center {result=try mapped{1-$0}.dilated(r).blurred(width).mapped{1-$0}}
    }
    result=try result.contoured(advanced.contour,range:advanced.range)
    if inner {for i in v.indices {result.v[i]*=v[i]}};return result
  }
  func satin(_ effect:LayerEffect,_ advanced:LayerEffectAdvanced,scale:Float)throws->Self {
    let(dx,dy)=Self.offset(Float(effect.angle),Float(effect.distance)*scale),a=try shifted(dx,dy).blurred(Float(effect.size)*scale),b=try shifted(-dx,-dy).blurred(Float(effect.size)*scale)
    var result=self;result.v=v.indices.map{abs(a.v[$0]-b.v[$0])};if advanced.satinInverted {result=result.mapped{1-$0}}
    result=try result.contoured(advanced.contour);for i in v.indices {result.v[i]*=v[i]};return result
  }
}
