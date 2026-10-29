import Foundation

/// PhotoCraft pixelate.rs, noise.rs and fxutil.rs (MIT OR Apache-2.0), RGB path.
/// This source port does not imply numerical equivalence to Adobe Photoshop.
public enum PixelateEngine {
  typealias Sample = SIMD4<Float>
  static func hash(_ x: Int, _ y: Int, _ channel: UInt32, _ seed: UInt32) -> Float {
    var h = UInt32(truncatingIfNeeded:x) &* 0x8da6b343 ^ UInt32(truncatingIfNeeded:y) &* 0xd8163841 ^ channel &* 0xcb1ab31f ^ seed &* 0x9e3779b9
    h ^= h >> 16; h = h &* 0x7feb352d; h ^= h >> 15; h = h &* 0x846ca68b; h ^= h >> 16
    return Float(h >> 8) / 16777216
  }
  static func cellPoint(_ x: Int, _ y: Int, _ size: Float, _ seed: UInt32) -> SIMD2<Float> {
    SIMD2((Float(x)+0.1+0.8*hash(x,y,11,seed))*size,(Float(y)+0.1+0.8*hash(x,y,12,seed))*size)
  }
  static func floorDiv(_ x: Int, _ divisor: Int) -> Int { x / divisor - (x % divisor < 0 ? 1:0) }
  static func threshold(_ pattern: PixelateSettings.Pattern, _ x: Int, _ y: Int, _ c: UInt32, _ seed: UInt32) -> Float {
    func line(_ length: Int) -> Float { let phase=Int(hash(0,y,c+40,seed)*Float(length));return hash(floorDiv(x+phase,length),y,c,seed) }
    func stroke(_ length: Int) -> Float { let d=x-y,phase=Int(hash(d,0,c+50,seed)*Float(length));return hash(floorDiv(x+y+phase,length),d,c+60,seed) }
    switch pattern {
    case .fineDots: return hash(x,y,c,seed)
    case .mediumDots: return hash(floorDiv(x,2),floorDiv(y,2),c,seed)
    case .grainyDots: return 0.5*hash(x,y,c,seed)+0.5*hash(floorDiv(x,3),floorDiv(y,3),c+7,seed)
    case .coarseDots: return hash(floorDiv(x,3),floorDiv(y,3),c,seed)
    case .shortLines: return line(6)
    case .mediumLines: return line(14)
    case .longLines: return line(32)
    case .shortStrokes: return stroke(5)
    case .mediumStrokes: return stroke(10)
    case .longStrokes: return stroke(20)
    }
  }
  static func clamp(_ value: Float) -> Float { min(1,max(0,value)) }
  public static func render(_ source: Surface, kind: RasterFilter.Kind, settings: PixelateSettings) throws -> Surface {
    try settings.validate(kind:kind)
    guard source.width <= RasterFilterEngine.maximumPixels/source.height else { throw CraftError.unsupported("Pixelate filters support up to 8,388,608 pixels.") }
    let w=source.width,h=source.height,linear=source.depth == .f32
    var input=[Sample]();input.reserveCapacity(w*h)
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let p=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      guard p.isFinite,max(abs(p.r),abs(p.g),abs(p.b))<=1e12 else { throw CraftError.invalid("Pixelate input exceeds the supported numeric range.") }
      input.append(Sample(p.r,p.g,p.b,p.a))
    }}
    var nativeSettings=settings
    if linear { let p=settings.background;nativeSettings.background=Pixel(SRGBTransfer.linear(p.r),SRGBTransfer.linear(p.g),SRGBTransfer.linear(p.b),p.a) }
    let output=try process(input,width:w,height:h,kind:kind,settings:nativeSettings)
    var result=source
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let p=output[y*w+x],value=Pixel(p.x,p.y,p.z,p.w)
      guard value.isFinite else { throw CraftError.invalid("Nonfinite Pixelate result.") }
      let before=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      if value.hasSameBits(as:before) {continue}
      if linear { result.setLinearPixel(x:x,y:y,value) } else { result.setPixel(x:x,y:y,value) }
    }}
    return result
  }
  static func process(_ input: [Sample], width w: Int, height h: Int, kind: RasterFilter.Kind, settings s: PixelateSettings) throws -> [Sample] {
    var output=input
    func get(_ x:Int,_ y:Int)->Sample { input[min(h-1,max(0,y))*w+min(w-1,max(0,x))] }
    if kind == .crystallize {
      let cell=Float(s.cellSize),gw=Int(ceil(Float(w)/cell))+2,gh=Int(ceil(Float(h)/cell))+2
      var points=[SIMD2<Float>]();points.reserveCapacity(gw*gh)
      for y in -1..<(gh-1) {for x in -1..<(gw-1) {points.append(cellPoint(x,y,cell,s.seed))}}
      var sums=[Sample](repeating:.zero,count:gw*gh),counts=[UInt32](repeating:0,count:gw*gh),owners=[Int32](repeating:0,count:w*h)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        if x & 1023 == 0 {try Task.checkCancellation()}
        let p=SIMD2(Float(x)+0.5,Float(y)+0.5),cx=Int(floor(p.x/cell)),cy=Int(floor(p.y/cell))
        var best=Float.greatestFiniteMagnitude,owner=0
        for dy in -1...1 {for dx in -1...1 {
          let i=(cy+dy+1)*gw+cx+dx+1,d=points[i]-p,dist=d.x*d.x+d.y*d.y
          if dist<best {best=dist;owner=i}
        }}
        let v=input[y*w+x];sums[owner]+=Sample(v.x*v.w,v.y*v.w,v.z*v.w,v.w);counts[owner]+=1;owners[y*w+x]=Int32(owner)
      }}
      for i in sums.indices where counts[i]>0 {
        sums[i]/=Float(counts[i]);let a=sums[i].w
        if a>1e-7 {sums[i].x/=a;sums[i].y/=a;sums[i].z/=a} else {sums[i].x=0;sums[i].y=0;sums[i].z=0}
      }
      for i in output.indices {if i & 4095 == 0 {try Task.checkCancellation()};output[i]=sums[Int(owners[i])]}
      return output
    }
    let radius=Float(s.maxRadius),cell=radius*Float(2).squareRoot()
    let rotations=s.angles.prefix(3).map {angle -> (Float,Float) in let radians=Float(angle)*(Float.pi/180);return (sin(radians),cos(radians)) }
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      if x & 1023 == 0 {try Task.checkCancellation()}
      let i=y*w+x
      switch kind {
      case .fragment:
        var sum=Sample.zero
        for (dx,dy) in [(-4,0),(4,0),(0,-4),(0,4)] {let v=get(x+dx,y+dy);sum+=Sample(v.x*v.w,v.y*v.w,v.z*v.w,v.w)*0.25}
        if sum.w>1e-7 {sum.x/=sum.w;sum.y/=sum.w;sum.z/=sum.w} else {sum.x=0;sum.y=0;sum.z=0};output[i]=sum
      case .facet:
        var best=Float.greatestFiniteMagnitude,result=Sample.zero
        for (qx,qy) in [(-2,-2),(0,-2),(-2,0),(0,0)] {
          var sum=Sample.zero,luma:Float=0,squares:Float=0
          for yy in (y+qy)...(y+qy+2) {for xx in (x+qx)...(x+qx+2) {
            let p=get(xx,yy),l=p.x*0.299+p.y*0.587+p.z*0.114;sum+=p;luma+=l;squares+=l*l
          }}
          let mean=luma/9,variance=squares/9-mean*mean
          if variance<best {best=variance;result=sum/9}
        }
        output[i]=result
      case .mezzotint:
        for c in 0..<3 {output[i][c]=input[i][c]>threshold(s.pattern,x,y,UInt32(c),s.seed) ? 1:0}
      case .colorHalftone:
        let fx=Float(x)+0.5,fy=Float(y)+0.5
        for c in 0..<3 {
          let (sn,cs)=rotations[c],u=fx*cs+fy*sn,v = -fx*sn+fy*cs,cu=floor(u/cell),cv=floor(v/cell)
          var coverage:Float=0
          for dj in -1...1 {for di in -1...1 {
            let mu=(cu+Float(di)+0.5)*cell,mv=(cv+Float(dj)+0.5)*cell,du=u-mu,dv=v-mv,d=(du*du+dv*dv).squareRoot()
            if d>=radius+0.5 {continue}
            let px=mu*cs-mv*sn,py=mu*sn+mv*cs,delta=cell*0.25
            var raw:Float=0
            for (dx,dy) in [(Float(0),Float(0)),(-delta,-delta),(delta,-delta),(-delta,delta),(delta,delta)] {raw+=get(Int(floor(px+dx)),Int(floor(py+dy)))[c]}
            let ink=1-clamp(raw/5),touch=Float.pi/4
            let r:Float = ink<=touch ? cell*(ink/Float.pi).squareRoot():cell*(0.5+(ink-touch)/(1-touch)*(1/Float(2).squareRoot()-0.5))
            coverage=max(coverage,min(clamp(r-d+0.5),Float.pi*r*r))
          }}
          output[i][c]=1-coverage
        }
      case .pointillize:
        let size=Float(s.cellSize),p=SIMD2(Float(x)+0.5,Float(y)+0.5),cx=Int(floor(p.x/size)),cy=Int(floor(p.y/size))
        var best: (depth:Float,x:Int,y:Int,point:SIMD2<Float>)?
        for dy in -1...1 {for dx in -1...1 {
          let gx=cx+dx,gy=cy+dy,q=cellPoint(gx,gy,size,s.seed),rad=size*(0.45+0.35*hash(gx,gy,13,s.seed)),d=q-p,depth=rad-(d.x*d.x+d.y*d.y).squareRoot()
          if depth > -0.5 && (best == nil || depth>best!.depth) {best=(depth,gx,gy,q)}
        }}
        let bg=s.background
        var canvas=Sample(bg.r,bg.g,bg.b,max(input[i].w,min(bg.a,1)))
        if let b=best {
          var dot=get(Int(floor(b.point.x)),Int(floor(b.point.y)))
          let jitter=(hash(b.x,b.y,17,s.seed)-0.5)*0.08
          for c in 0..<3 {dot[c]=clamp(dot[c]+jitter)}
          canvas+=(dot-canvas)*clamp(b.depth+0.5)
        }
        output[i]=canvas
      default: throw CraftError.invalid("Unknown Pixelate operation.")
      }
    }}
    return output
  }
  static func apply(_ settings: PixelateSettings, kind: RasterFilter.Kind, source: Surface, layerID: UUID, index: Int, document: inout CraftDocument) throws {
    let edited=try render(source,kind:kind,settings:settings),matrix=document.layers[index].coordinateTransform,protect=document.isTransparencyLocked(layerID),linear=document.depth == .f32
    var result=source
    for y in 0..<source.height {try Task.checkCancellation();for x in 0..<source.width {
      let q=matrix.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(q.x)),y:Int(floor(q.y)))
      if coverage<=0 {continue}
      let before=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      var after=linear ? edited.linearPixel(x:x,y:y):edited.pixel(x:x,y:y)
      if before==after {continue};if protect {if before.a==0 {continue};after.a=before.a}
      let value=before.mixing(after,coverage:coverage)
      if linear {result.setLinearPixel(x:x,y:y,value)} else {result.setPixel(x:x,y:y,value)}
    }}
    document.layers[index].content = .raster(result)
  }
}
