import Foundation

// All primitive calculations use Float to retain the licensed source's numeric contract.
enum ProceduralGeometry {
  typealias Point = SIMD2<Float>
  typealias Color = SIMD4<Float>
  // Rust f32::consts::PI rounds to nearest; Swift Float.pi rounds down.
  static let sourcePi=Float(bitPattern:0x40490fdb)
  static let maximumPrimitives=200_000
  static func clamp(_ x:Float)->Float {min(1,max(0,x))}
  static func color(_ p:Pixel)->Color {Color(p.r,p.g,p.b,p.a)}
  static func shade(_ c:SIMD3<Float>,_ k:Float)->Color {Color(clamp(c.x*k),clamp(c.y*k),clamp(c.z*k),1)}
  static func rgb(_ c:Color)->SIMD3<Float>{SIMD3(c.x,c.y,c.z)}
  static func length(_ p:Point)->Float {(p.x*p.x+p.y*p.y).squareRoot()}
  struct RNG {
    var value:UInt64
    init(_ seed:UInt32,_ salt:UInt64){value=(UInt64(seed)<<32) ^ (salt &* 0x9e3779b97f4a7c15) ^ 0x2545f4914f6cdd1d}
    init(raw:UInt64){value=raw}
    mutating func next()->UInt64 {value = value &+ 0x9e3779b97f4a7c15;var z=value;z=(z ^ (z>>30)) &* 0xbf58476d1ce4e5b9;z=(z ^ (z>>27)) &* 0x94d049bb133111eb;return z ^ (z>>31)}
    mutating func f()->Float {Float(next()>>40)/16777216}
    mutating func range(_ a:Float,_ b:Float)->Float {a+(b-a)*f()}
    mutating func sym()->Float {f()*2-1}
  }
  static func noise(_ x:Float,_ seed:UInt64)->Float {
    func h(_ i:Int64)->Float {var r=RNG(raw:(UInt64(bitPattern:i) &* 0xd6e8feb86659fd93) ^ seed);return r.sym()}
    let base=floor(x),f=x-base,i=Int64(base),t=f*f*(3-2*f);return h(i)+(h(i+1)-h(i))*t
  }
  static func fbm(_ x:Float,_ seed:UInt64)->Float {(noise(x,seed)+0.5*noise(x*2.13+7.1,seed ^ 0xa5a5))/1.5}
  enum Shape:Equatable {case capsule(Point,Point,Float,Float),ellipse(Point,Float,Float,Float)}
  enum Blend:Equatable {case normal,add,lighten}
  struct Primitive:Equatable {
    var shape:Shape,c0:Color,c1:Color,soft:Float=1,blend:Blend = .normal
    static func capsule(_ a:Point,_ b:Point,_ ra:Float,_ rb:Float,_ c0:Color,_ c1:Color)->Self {Self(shape:.capsule(a,b,ra,rb),c0:c0,c1:c1)}
    static func ellipse(_ c:Point,_ rx:Float,_ ry:Float,_ angle:Float,_ c0:Color,_ c1:Color)->Self {Self(shape:.ellipse(c,rx,ry,angle),c0:c0,c1:c1)}
    static func disc(_ c:Point,_ r:Float,_ color:Color)->Self {ellipse(c,r,r,0,color,color)}
    func softened(_ s:Float,_ blend:Blend = .normal)->Self {var p=self;p.soft=s;p.blend=blend;return p}
    var origin:Point {switch shape {case .capsule(let a,_,_,_):a;case .ellipse(let c,_,_,_):c}}
    var bounds:IntRect {
      let s=max(soft,1)+1;let lo:Point,hi:Point
      switch shape {
      case .capsule(let a,let b,let ra,let rb):let r=max(ra,rb)+s;lo=Point(min(a.x,b.x)-r,min(a.y,b.y)-r);hi=Point(max(a.x,b.x)+r,max(a.y,b.y)+r)
      case .ellipse(let c,let rx,let ry,let angle):
        let sn=sin(angle),cs=cos(angle),ex=((rx*cs)*(rx*cs)+(ry*sn)*(ry*sn)).squareRoot()+s,ey=((rx*sn)*(rx*sn)+(ry*cs)*(ry*cs)).squareRoot()+s;lo=c-Point(ex,ey);hi=c+Point(ex,ey)
      }
      guard [lo.x,lo.y,hi.x,hi.y].allSatisfy(\.isFinite) else{return IntRect(x:0,y:0,width:0,height:0)}
      let x=Int(max(-1e8,min(1e8,floor(lo.x)))),y=Int(max(-1e8,min(1e8,floor(lo.y)))),right=Int(max(-1e8,min(1e8,ceil(hi.x)))),bottom=Int(max(-1e8,min(1e8,ceil(hi.y))))
      return IntRect(x:x,y:y,width:max(0,right-x),height:max(0,bottom-y))
    }
    func eval(_ x:Float,_ y:Float)->(Float,Float) {
      let soft=max(soft,1)
      switch shape {
      case .capsule(let a,let b,let ra,let rb):
        let delta=b-a,l2=delta.x*delta.x+delta.y*delta.y,t:Float=l2>1e-9 ? clamp(((x-a.x)*delta.x+(y-a.y)*delta.y)/l2):0
        let d=length(a+delta*t-Point(x,y)),r=ra+(rb-ra)*t
        return (clamp((max(r,0.5)-d)/soft+0.5)*clamp(2*r),t)
      case .ellipse(let c,let rx0,let ry0,let angle):
        let s=sin(angle),co=cos(angle),dx=x-c.x,dy=y-c.y,u=dx*co+dy*s,v = -dx*s+dy*co,rx=max(rx0,0.05),ry=max(ry0,0.05)
        let e=((u/rx)*(u/rx)+(v/ry)*(v/ry)).squareRoot(),edge=(1-e)*min(rx,ry)
        return (clamp(edge/soft+0.5)*clamp(2*min(rx,ry)),min(e,1))
      }
    }
  }
  struct Spine {
    var points:[Point],cumulative:[Float]
    init(_ p:[Point]){points=p;cumulative=[0];if p.count>1 {for i in 1..<p.count {cumulative.append(cumulative.last!+length(p[i]-p[i-1]))}}}
    var total:Float {cumulative.last ?? 0}
    func at(_ s0:Float)->(Point,Point) {
      guard points.count>1 else{return(points.first ?? .zero,points.isEmpty ? Point(1,0):Point(0,-1))}
      let s=min(total,max(0,s0));var low=0,high=cumulative.count
      while low<high {let mid=(low+high)/2;if cumulative[mid]<=s {low=mid+1}else{high=mid}}
      let k=min(points.count-2,max(0,low-1)),a=points[k],b=points[k+1],seg=max(cumulative[k+1]-cumulative[k],1e-6),t=clamp((s-cumulative[k])/seg),delta=b-a
      return(a+delta*t,delta/max(length(delta),1e-6))
    }
  }
  /// The transparent paint buffer is accumulated before it is composited over source pixels.
  static func rasterize(_ primitives:[Primitive],in rect:IntRect)throws->[Color] {
    guard primitives.count<=maximumPrimitives,rect.width>0,rect.height>0,rect.width<=8_388_608/rect.height else{throw CraftError.unsupported("Procedural rendering exceeds its geometry or pixel budget.")}
    var result=[Color](repeating:.zero,count:rect.width*rect.height)
    var samples=0
    for p in primitives {
      try Task.checkCancellation();let b=p.bounds
      let x0=max(rect.x,b.x),y0=max(rect.y,b.y),x1=min(rect.x+rect.width,b.x+b.width),y1=min(rect.y+rect.height,b.y+b.height)
      if x1<=x0 || y1<=y0 {continue}
      samples+=(x1-x0)*(y1-y0);guard samples<=268_435_456 else{throw CraftError.unsupported("Procedural render exceeds268 million coverage samples; reduce size or complexity.")}
      for y in y0..<y1 {try Task.checkCancellation();for x in x0..<x1 {
        let (coverage,t)=p.eval(Float(x)+0.5,Float(y)+0.5);if coverage<=0 {continue}
        let c=p.c0==p.c1 ? p.c0:p.c0+(p.c1-p.c0)*t,a=clamp(c.w*coverage);if a<=0{continue}
        let i=(y-rect.y)*rect.width+x-rect.x,d=result[i]
        switch p.blend {
        case .normal:result[i]=Color(c.x*a+d.x*(1-a),c.y*a+d.y*(1-a),c.z*a+d.z*(1-a),a+d.w*(1-a))
        case .add:result[i]=Color(d.x+c.x*a,d.y+c.y*a,d.z+c.z*a,d.w+a*(1-d.w))
        case .lighten:result[i]=Color(max(d.x,c.x*a),max(d.y,c.y*a),max(d.z,c.z*a),max(d.w,a))
        }
      }}
    };return result
  }
}
