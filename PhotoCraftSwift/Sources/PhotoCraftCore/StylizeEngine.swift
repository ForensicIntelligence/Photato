import Foundation

/// RGB translation of PhotoCraft stylize.rs/stylize2.rs (MIT OR Apache-2.0).
/// Original-source equivalence is distinct from Photoshop pixel qualification.
public enum StylizeEngine {
  typealias Sample=SIMD4<Float>
  static func luma(_ p:Sample)->Float {0.299*p.x+0.587*p.y+0.114*p.z}
  static func hash(_ x:Int,_ y:Int,_ channel:UInt32,_ seed:UInt32)->Float {PixelateEngine.hash(x,y,channel,seed)}
  static func clamp(_ value: Float) -> Float { min(1,max(0,value)) }
  public static func render(_ source: Surface, kind: RasterFilter.Kind, settings: StylizeSettings) throws -> Surface {
    try settings.validate(kind:kind)
    guard source.width <= RasterFilterEngine.maximumPixels/source.height else { throw CraftError.unsupported("Stylize filters support up to 8,388,608 pixels.") }
    let w=source.width,h=source.height,linear=source.depth == .f32
    var input=[Sample]();input.reserveCapacity(w*h)
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let p=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      guard p.isFinite,max(abs(p.r),abs(p.g),abs(p.b))<=1e12 else { throw CraftError.invalid("Stylize input exceeds the supported numeric range.") }
      input.append(Sample(p.r,p.g,p.b,p.a))
    }}
    var nativeSettings=settings
    if linear { let p=settings.background;nativeSettings.background=Pixel(SRGBTransfer.linear(p.r),SRGBTransfer.linear(p.g),SRGBTransfer.linear(p.b),p.a);let f=settings.foreground;nativeSettings.foreground=Pixel(SRGBTransfer.linear(f.r),SRGBTransfer.linear(f.g),SRGBTransfer.linear(f.b),f.a) }
    let output=try process(input,width:w,height:h,kind:kind,settings:nativeSettings)
    var result=source
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let p=output[y*w+x],value=Pixel(p.x,p.y,p.z,p.w)
      guard value.isFinite else { throw CraftError.invalid("Nonfinite Stylize result.") }
      let before=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      if value.hasSameBits(as:before) {continue}
      if linear { result.setLinearPixel(x:x,y:y,value) } else { result.setPixel(x:x,y:y,value) }
    }}
    return result
  }

  static func process(_ input:[Sample],width w:Int,height h:Int,kind:RasterFilter.Kind,settings s:StylizeSettings)throws->[Sample] {
    if kind == .oilPaint {return try OilPaintEngine.process(input,width:w,height:h,settings:s)}
    if kind == .extrude {return try extrude(input,width:w,height:h,settings:s)}
    var output=input
    func get(_ x:Int,_ y:Int)->Sample {input[min(h-1,max(0,y))*w+min(w-1,max(0,x))]}
    let ring=[(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1),(0,-1),(1,-1)]
    let angle=Float(s.angle)*(Float.pi/180),edx=Int((cos(angle)*Float(s.height)).rounded()),edy=Int((-sin(angle)*Float(s.height)).rounded())
    let tileSize=max(1,Float(min(w,h))/Float(s.count)),offset=Float(s.maxOffset)/100*tileSize
    let fg=Sample(s.foreground.r,s.foreground.g,s.foreground.b,s.foreground.a),bg=Sample(s.background.r,s.background.g,s.background.b,s.background.a)
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      if x & 255 == 0 {try Task.checkCancellation()};let i=y*w+x,p=input[i]
      switch kind {
      case .diffuse:
        if s.mode == .anisotropic {
          let me=luma(p),start=Int(hash(x,y,3,s.seed)*8);var best=Float.greatestFiniteMagnitude,chosen=p
          for k in 0..<8 {let (dx,dy)=ring[(start+k)%8],v=get(x+dx,y+dy),distance=abs(luma(v)-me);if distance<best {best=distance;chosen=v}}
          output[i]=(p+chosen)*0.5
        } else {
          let dx=Int(hash(x,y,1,s.seed)*3)-1,dy=Int(hash(x,y,2,s.seed)*3)-1,v=get(x+dx,y+dy)
          if v.w<=0 && p.w>0 && s.mode != .normal {continue}
          if s.mode == .normal || (s.mode == .darkenOnly && luma(v)<luma(p)) || (s.mode == .lightenOnly && luma(v)>luma(p)) {output[i]=v}
        }
      case .emboss:
        let g=clamp(0.5+Float(s.amount)/100*(luma(get(x+edx,y+edy))-luma(get(x-edx,y-edy))));output[i]=Sample(g,g,g,p.w)
      case .findEdges:
        for c in 0..<3 {
          let gx=(get(x+1,y-1)[c]+2*get(x+1,y)[c]+get(x+1,y+1)[c])-(get(x-1,y-1)[c]+2*get(x-1,y)[c]+get(x-1,y+1)[c])
          let gy=(get(x-1,y+1)[c]+2*get(x,y+1)[c]+get(x+1,y+1)[c])-(get(x-1,y-1)[c]+2*get(x,y-1)[c]+get(x+1,y-1)[c])
          output[i][c]=clamp(1-sqrt(gx*gx+gy*gy)/4)
        }
      case .solarize:for c in 0..<3 {output[i][c]=p[c]>0.5 ? 1-p[c]:p[c]}
      case .traceContour:
        for c in 0..<3 {let threshold=Float(s.level)/255,me=p[c]>threshold,line=me == (s.edge == .upper) && [(1,0),(-1,0),(0,1),(0,-1)].contains{dx,dy in (get(x+dx,y+dy)[c]>threshold) != me};output[i][c]=line ? 0:1}
      case .tiles:
        let fx=Float(x)+0.5,fy=Float(y)+0.5,gx=Int(floor(fx/tileSize)),gy=Int(floor(fy/tileSize));var hit:(x:Int,y:Int,ox:Float,oy:Float)?
        for dy in -1...1 {for dx in -1...1 {
          let cx=gx+dx,cy=gy+dy,ox=(hash(cx,cy,31,s.seed)*2-1)*offset,oy=(hash(cx,cy,32,s.seed)*2-1)*offset,u=fx-ox-Float(cx)*tileSize,v=fy-oy-Float(cy)*tileSize
          if u>=0 && v>=0 && u<tileSize && v<tileSize && Float(cx)*tileSize<Float(w) && Float(cy)*tileSize<Float(h) && cx>=0 && cy>=0 {
            if hit==nil || cy>hit!.y || (cy==hit!.y && cx>hit!.x) {hit=(cx,cy,ox,oy)}
          }
        }}
        if let hit {output[i]=get(Int(floor(fx-hit.ox)),Int(floor(fy-hit.oy)))} else {switch s.fill {case .background:output[i]=bg;case .foreground:output[i]=fg;case .inverse:for c in 0..<3 {output[i][c]=1-p[c]};case .unaltered:break}}
      case .wind:
        let length=s.method == .wind ? 16:s.method == .blast ? 40:12,d=s.direction == .fromRight ? -1:1
        if s.method == .stagger {
          let segmentLength=8+Int(hash(0,y,41,s.seed)*32),phase=Int(hash(1,y,42,s.seed)*Float(segmentLength)),segment=PixelateEngine.floorDiv(x*d+phase,segmentLength),random=hash(segment,y,43,s.seed),shift=Int(random*random*Float(length));output[i]=get(x-d*shift,y)
        } else {
          let strength:Float=s.method == .blast ? 8:4;var best:Float=0,sourceX=x
          for k in 1...length {let sx=x-d*k,random=hash(sx,y,44,s.seed),len=max(1,random*random*Float(length));if Float(k)>len {continue};let edge=min(1,abs(luma(get(sx,y))-luma(get(sx-d,y)))*strength),weight=edge*(1-Float(k)/(len+1));if weight>best {best=weight;sourceX=sx}}
          if best>0 {output[i]=p+(get(sourceX,y)-p)*best}
        }
      default:throw CraftError.invalid("Unknown Stylize operation.")
      }
    }}
    return output
  }

  /// Precompute cell averages once, preserving the source algorithm's traversal/tie order.
  private static func extrude(_ input:[Sample],width w:Int,height h:Int,settings s:StylizeSettings)throws->[Sample] {
    let cs=Int(s.size),gw=(w+cs-1)/cs,gh=(h+cs-1)/cs,half=Float(cs)/2,bcx=Float(w)/2,bcy=Float(h)/2
    let halfDiagonal=max(1,hypot(Float(w),Float(h))/2),reach=Float(s.depth)*0.25
    func get(_ x:Int,_ y:Int)->Sample {input[min(h-1,max(0,y))*w+min(w-1,max(0,x))]}
    var colors=[Sample](repeating:.zero,count:gw*gh),heights=[Float](repeating:0,count:gw*gh),output=input
    for gy in 0..<gh {try Task.checkCancellation();for gx in 0..<gw {
      if gx & 255 == 0 {try Task.checkCancellation()};var sum=Sample.zero,count:Float=0
      for y in stride(from:gy*cs,to:min(h,(gy+1)*cs),by:max(1,cs/8)) {for x in stride(from:gx*cs,to:min(w,(gx+1)*cs),by:max(1,cs/8)) {let p=get(x,y);sum+=Sample(p.x*p.w,p.y*p.w,p.z*p.w,p.w);count+=1}}
      if count>0 {sum/=count};let a=sum.w;if a>1e-7 {sum.x/=a;sum.y/=a;sum.z/=a} else {sum.x=0;sum.y=0;sum.z=0}
      colors[gy*gw+gx]=sum;heights[gy*gw+gx]=s.depthMode == .levelBased ? clamp(luma(sum)):hash(gx,gy,21,s.seed)
    }}
    func included(_ gx:Int,_ gy:Int)->Bool {gx>=0 && gy>=0 && gx<gw && gy<gh && (!s.maskIncompleteBlocks || ((gx+1)*cs<=w && (gy+1)*cs<=h))}
    func shaded(_ p:Sample,_ k:Float)->Sample {Sample(clamp(p.x*k),clamp(p.y*k),clamp(p.z*k),p.w)}
    func interval(_ p:Float,_ m:Float,_ o:Float)->(Float,Float)? {
      if abs(o)<1e-6 {return abs(p-m)<=half ? (0,1):nil}
      let a=(p-m-half)/o,b=(p-m+half)/o,lo=max(0,min(a,b)),hi=min(1,max(a,b));return lo<=hi ? (lo,hi):nil
    }
    let radius=Int(ceil(reach/Float(cs)))+1
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      if x & 63 == 0 {try Task.checkCancellation()};let i=y*w+x,gx=x/cs,gy=y/cs,fx=Float(x)+0.5,fy=Float(y)+0.5
      if s.type == .pyramids {
        guard included(gx,gy) else {continue};let ci=gy*gw+gx,u=fx-(Float(gx*cs)+half),v=fy-(Float(gy*cs)+half),height=heights[ci]*Float(s.depth)/255*Float(cs)
        let nx:Float=abs(u)>=abs(v) ? (u<0 ? -height:height):0,ny:Float=abs(u)>=abs(v) ? 0:(v<0 ? -height:height)
        let norm=sqrt(nx*nx+ny*ny+half*half),lambert=max(0,(nx * -0.5+ny * -0.5+half*Float(1/sqrt(2.0)))/norm)
        output[i]=shaded(colors[ci],0.35+0.9*lambert);continue
      }
      var best:(height:Float,x:Int,y:Int,face:Int)?
      for cy in max(0,gy-radius)...min(gh-1,gy+radius) {for cx in max(0,gx-radius)...min(gw-1,gx+radius) {
        guard included(cx,cy) else {continue};let height=heights[cy*gw+cx];if let best,best.height>=height {continue}
        let mx=Float(cx*cs)+half,my=Float(cy*cs)+half,off=reach*height/halfDiagonal,ox=(mx-bcx)*off,oy=(my-bcy)*off
        guard let ix=interval(fx,mx,ox),let iy=interval(fy,my,oy),max(ix.0,iy.0)<=min(ix.1,iy.1) else {continue}
        let face=min(ix.1,iy.1)>=1 ? 0:ix.1<iy.1 ? (ox>0 ? 1:2):(oy>0 ? 3:4);best=(height,cx,cy,face)
      }}
      guard let best else {continue};let col=colors[best.y*gw+best.x]
      if best.face==0 && !s.solidFrontFaces {
        let mx=Float(best.x*cs)+half,my=Float(best.y*cs)+half,off=reach*best.height/halfDiagonal
        let sx=min((best.x+1)*cs-1,max(best.x*cs,Int(floor(fx-(mx-bcx)*off)))),sy=min((best.y+1)*cs-1,max(best.y*cs,Int(floor(fy-(my-bcy)*off))))
        output[i]=get(sx,sy)
      } else {let strength:Float=best.face==0 ? 1:best.face==1 ? 0.85:best.face==2 ? 0.55:best.face==3 ? 0.95:0.45;output[i]=shaded(col,strength)}
    }}
    return output
  }

  static func apply(_ settings: StylizeSettings, kind: RasterFilter.Kind, source: Surface, layerID: UUID, index: Int, document: inout CraftDocument) throws {
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
