import CoreGraphics
import Foundation

/// Licensed PhotoCraft blur.rs, blur2.rs, noise.rs and sharpen.rs translated to native Swift.
public enum ClassicDetailEngine {
  typealias Sample=SIMD4<Float>
  static let maximumVisits=268_435_456
  static let pi=Float(bitPattern:0x40490fdb),tau=Float(bitPattern:0x40c90fdb)
  struct Input {
    var pixels:[Sample];var width:Int;var height:Int
    @inline(__always) func get(_ x:Int,_ y:Int)->Sample {pixels[min(height-1,max(0,y))*width+min(width-1,max(0,x))]}
    func sample(_ x:Float,_ y:Float)->Sample {
      let fx=x-0.5,fy=y-0.5,x0=Int(floor(fx)),y0=Int(floor(fy)),ax=fx-Float(x0),ay=fy-Float(y0)
      var q=Sample.zero
      for(dx,dy,k) in [(0,0,(1-ax)*(1-ay)),(1,0,ax*(1-ay)),(0,1,(1-ax)*ay),(1,1,ax*ay)] where k>0 {
        let xx=x0+dx,yy=y0+dy
        guard xx>=0,yy>=0,xx<width,yy<height else {continue}
        let p=get(xx,yy);for c in 0..<3 {q[c]+=p[c]*p.w*k};q.w+=p.w*k
      }
      if q.w>0 {for c in 0..<3 {q[c]/=q.w}};return q
    }
  }
  static func premul(_ p:Sample)->Sample {Sample(p.x*p.w,p.y*p.w,p.z*p.w,p.w)}
  static func straight(_ p:Sample)->Sample {p.w>1e-7 ? Sample(p.x/p.w,p.y/p.w,p.z/p.w,p.w):Sample(0,0,0,p.w)}
  static func budget(_ n:Int)throws {guard n<=maximumVisits else {throw CraftError.unsupported("This filter exceeds the supported neighborhood-processing budget.")}}
  static func gaussian(_ input:Input,radius:Float)throws->[Sample] {
    let r=Int(ceil(radius*3)),w=input.width,h=input.height
    var kernel=(-r...r).map{exp(-Float($0*$0)/(2*radius*radius))};let total=kernel.reduce(Float(0),+);kernel=kernel.map{$0/total}
    try budget(w*(h+2*r)*kernel.count+w*h*kernel.count)
    var temp=[Sample](repeating:.zero,count:w*(h+2*r)),result=[Sample](repeating:.zero,count:w*h)
    for y in -r..<(h+r) {try Task.checkCancellation();for x in 0..<w {var p=Sample.zero;for i in kernel.indices {p+=premul(input.get(x+i-r,y))*kernel[i]};temp[(y+r)*w+x]=p}}
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {var p=Sample.zero;for i in kernel.indices {p+=temp[(y+i)*w+x]*kernel[i]};result[y*w+x]=straight(p)}}
    return result
  }
  static func radial(_ input:Input,settings s:ClassicDetailSettings,area b:IntRect)throws->[Sample] {
    let cap=s.radialQuality == .draft ? 16:s.radialQuality == .good ? 32:64
    try budget(b.width*b.height*(cap+1));let cx=Float(b.x)+Float(b.width)*Float(s.centerX),cy=Float(b.y)+Float(b.height)*Float(s.centerY),amount=Float(s.amount)
    var result=input.pixels
    for y in b.y..<(b.y+b.height){try Task.checkCancellation();for x in b.x..<(b.x+b.width){
      let dx=Float(x)+0.5-cx,dy=Float(y)+0.5-cy,r=sqrt(dx*dx+dy*dy),arc=amount*(pi/180),span=amount/200
      let n=min(cap,max(1,Int(ceil((s.method == .spin ? arc:span)*r))))
      var acc=Sample.zero
      for i in 0...n {
        let sx:Float,sy:Float
        if s.method == .spin {let t=(Float(i)/Float(n)-0.5)*arc,ss=sin(t),cc=cos(t);sx=cx+dx*cc-dy*ss;sy=cy+dx*ss+dy*cc}
        else {let k=1-span*Float(i)/Float(n);sx=cx+dx*k;sy=cy+dy*k}
        acc+=premul(input.sample(sx,sy))
      }
      result[y*input.width+x]=straight(acc*(1/Float(n+1)))
    }};return result
  }
  static func shapeInside(_ u:Float,_ v:Float,_ shape:ClassicDetailSettings.Shape)->Bool {
    switch shape {
    case .circle:return u*u+v*v<=1
    case .ring:let d=u*u+v*v;return d>=0.36 && d<=1
    case .square:return true
    case .diamond:return abs(u)+abs(v)<=1
    case .triangle:return v<=0.75 && abs(u)<=(v+1)/1.75
    case .hexagon:
      let segment=tau/6,theta=atan2(v,u),rem=theta.truncatingRemainder(dividingBy:segment),a=(rem<0 ? rem+segment:rem)-segment/2
      return sqrt(u*u+v*v)<=cos(pi/6)/cos(a)
    case .heart:let x=u*1.2,y = -v*1.2+0.15,q=x*x+y*y-1;return q*q*q-x*x*y*y*y<=0
    case .cross:return abs(u)<=0.3 || abs(v)<=0.3
    case .star:
      var points=[(Float,Float)]()
      for i in 0..<10 {let r:Float=i%2==0 ? 1:0.42,a = -pi/2+Float(i)*pi/5;points.append((r*cos(a),r*sin(a)))}
      var inside=false,j=9
      for i in 0..<10 {let(xi,yi)=points[i],(xj,yj)=points[j];if (yi>v) != (yj>v),u<(xj-xi)*(v-yi)/(yj-yi)+xi {inside.toggle()};j=i};return inside
    }
  }
  static func shape(_ input:Input,settings s:ClassicDetailSettings,area b:IntRect)throws->[Sample] {
    if let kernel=s.kernel {return try customShape(input,kernel:kernel,radius:Int(s.radius),area:b)}
    let radius=Float(s.radius),r=Int(ceil(radius)),w=input.width,h=input.height
    var spans=[(dy:Int,lo:Int,hi:Int)](),count=0
    for dy in -r...r {try Task.checkCancellation();var start:Int?
      for dx in -r...(r+1) {let hit=dx<=r && shapeInside(Float(dx)/radius,Float(dy)/radius,s.shape)
        if hit,start==nil {start=dx};if !hit,let lo=start {spans.append((dy,lo,dx-1));count+=dx-lo;start=nil}
      }
    }
    if spans.isEmpty {return input.pixels};try budget(b.width*b.height*spans.count)
    var prefix=[SIMD4<Double>](repeating:.zero,count:(w+1)*h)
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {let p=premul(input.get(x,y));prefix[y*(w+1)+x+1]=prefix[y*(w+1)+x]+SIMD4<Double>(Double(p.x),Double(p.y),Double(p.z),Double(p.w))}}
    func row(_ y:Int,_ lo:Int,_ hi:Int)->SIMD4<Double> {
      let yy=min(h-1,max(0,y)),a=min(w,max(0,lo)),z=min(w,max(0,hi+1));var sum=prefix[yy*(w+1)+z]-prefix[yy*(w+1)+a]
      if lo<0 {let p=premul(input.get(0,yy));sum+=SIMD4<Double>(Double(p.x),Double(p.y),Double(p.z),Double(p.w))*Double(max(0,min(hi+1,0)-lo))}
      if hi>=w {let p=premul(input.get(w-1,yy));sum+=SIMD4<Double>(Double(p.x),Double(p.y),Double(p.z),Double(p.w))*Double(hi-max(lo,w)+1)}
      return sum
    }
    var result=input.pixels
    for y in b.y..<(b.y+b.height){try Task.checkCancellation();for x in b.x..<(b.x+b.width){var acc=SIMD4<Double>.zero;for span in spans {acc+=row(y+span.dy,x+span.lo,x+span.hi)};acc/=Double(count);result[y*w+x]=straight(Sample(Float(acc.x),Float(acc.y),Float(acc.z),Float(acc.w)))}}
    return result
  }
  static func customShape(_ input:Input,kernel:ShapeBlurKernel,radius:Int,area b:IntRect)throws->[Sample] {
    let side=2*radius+1,w=input.width,h=input.height
    try budget(side*side*max(1,kernel.path.knotCount))
    let coverage=try kernel.coverage(radius:radius)
    var spans=[(dy:Int,lo:Int,hi:Int,weight:Double)](),total=0.0
    for y in 0..<side {try Task.checkCancellation();var x=0
      while x<side {
        let value=coverage[y*side+x],start=x;x+=1
        while x<side && coverage[y*side+x]==value{x+=1}
        if value>0 {spans.append((y-radius,start-radius,x-1-radius,Double(value)));total+=Double(value)*Double(x-start)}
      }
    }
    try budget(b.width*b.height*spans.count)
    var prefix=[SIMD4<Double>](repeating:.zero,count:(w+1)*h)
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {let p=premul(input.get(x,y));prefix[y*(w+1)+x+1]=prefix[y*(w+1)+x]+SIMD4<Double>(Double(p.x),Double(p.y),Double(p.z),Double(p.w))}}
    func row(_ y:Int,_ lo:Int,_ hi:Int)->SIMD4<Double> {
      let yy=min(h-1,max(0,y)),a=min(w,max(0,lo)),z=min(w,max(0,hi+1));var sum=prefix[yy*(w+1)+z]-prefix[yy*(w+1)+a]
      if lo<0 {let p=premul(input.get(0,yy));sum+=SIMD4<Double>(Double(p.x),Double(p.y),Double(p.z),Double(p.w))*Double(max(0,min(hi+1,0)-lo))}
      if hi>=w {let p=premul(input.get(w-1,yy));sum+=SIMD4<Double>(Double(p.x),Double(p.y),Double(p.z),Double(p.w))*Double(hi-max(lo,w)+1)}
      return sum
    }
    var result=input.pixels
    for y in b.y..<(b.y+b.height){try Task.checkCancellation();for x in b.x..<(b.x+b.width){
      var acc=SIMD4<Double>.zero
      // Convolution preserves the kernel's orientation around an impulse.
      for span in spans {acc+=row(y-span.dy,x-span.hi,x-span.lo)*span.weight}
      acc/=total;result[y*w+x]=straight(Sample(Float(acc.x),Float(acc.y),Float(acc.z),Float(acc.w)))
    }}
    return result
  }
  static func smart(_ input:Input,settings s:ClassicDetailSettings,area b:IntRect)throws->[Sample] {
    let r=Float(s.radius),ri=Int(ceil(r)),t=Float(s.threshold)/255,target=s.quality == .low ? 4:s.quality == .medium ? 7:12,step=max(1,(ri+target-1)/target)
    var offsets=[(Int,Int)]();for dy in stride(from:-ri,through:ri,by:step){for dx in stride(from:-ri,through:ri,by:step) where Float(dx*dx+dy*dy)<=r*r+0.5{offsets.append((dx,dy))}}
    try budget(b.width*b.height*(s.mode == .normal ? offsets.count:4));var result=input.pixels
    for y in b.y..<(b.y+b.height){try Task.checkCancellation();for x in b.x..<(b.x+b.width){let me=input.get(x,y)
      func differs(_ q:Sample)->Bool {(0..<3).contains{abs(q[$0]-me[$0])>t}}
      if s.mode != .normal {let edge=[(1,0),(0,1),(-1,0),(0,-1)].contains{differs(input.get(x+$0.0,y+$0.1))};if edge{result[y*input.width+x]=Sample(1,1,1,me.w)}else if s.mode == .edgeOnly{result[y*input.width+x]=Sample(0,0,0,me.w)};continue}
      var acc=Sample.zero,n:Float=0
      for(dx,dy) in offsets {let q=input.get(x+dx,y+dy);if differs(q){continue};acc+=premul(q);n+=1}
      if n>0 {result[y*input.width+x]=straight(acc/n)}
    }};return result
  }
  static func surface(_ input:Input,radius:Int,threshold:Float,depth:PixelDepth,area b:IntRect)throws->[Sample] {
    let r=radius,side=2*r+1,t=(max(1,threshold)/255)*2.5,reach=min(255,Int(ceil(t*255)))
    let useHistogram=depth == .u8 && side*side>2*reach+1+4*side
    try budget(useHistogram ? b.height*side*side+b.width*b.height*(2*side+2*reach+1):b.width*b.height*side*side)
    var result=input.pixels
    if useHistogram {
      for y in b.y..<(b.y+b.height){try Task.checkCancellation();for c in 0..<3 {
        var histogram=[Int](repeating:0,count:257)
        func column(_ x:Int,_ sign:Int){for yy in (y-r)...(y+r){let p=input.get(x,yy),k=p.w<=0 ? 256:Int((p[c]*255).rounded());histogram[k]+=sign}}
        for xx in (b.x-r)...(b.x+r){column(xx,1)}
        for x in b.x..<(b.x+b.width){let v0=input.get(x,y)[c],k0=Int((v0*255).rounded());var acc:Double=0,wsum:Double=0
          for k in max(0,k0-reach)...min(255,k0+reach) where histogram[k]>0 {let v=Float(k)/255,w=max(0,1-abs(v-v0)/t);acc+=Double(v*w)*Double(histogram[k]);wsum+=Double(w)*Double(histogram[k])}
          result[y*input.width+x][c]=wsum>0 ? Float(acc/wsum):v0
          if x+1<b.x+b.width{column(x-r,-1);column(x+r+1,1)}
        }
      }}
    }else{
      for y in b.y..<(b.y+b.height){try Task.checkCancellation();for x in b.x..<(b.x+b.width){let p=input.get(x,y)
        for c in 0..<3 {var acc:Float=0,wsum:Float=0;for yy in (y-r)...(y+r){for xx in (x-r)...(x+r){let q=input.get(xx,yy);if q.w<=0{continue};let weight=max(0,1-abs(q[c]-p[c])/t);acc+=q[c]*weight;wsum+=weight}};result[y*input.width+x][c]=wsum>0 ? acc/wsum:p[c]}
      }}
    };return result
  }
  struct Counts {
    var tree:[Int]
    init(_ n:Int){tree=Array(repeating:0,count:n+1)}
    mutating func add(_ k:Int,_ amount:Int){var i=k+1;while i<tree.count{tree[i]+=amount;i+=i & -i}}
    func rank(_ target:Int)->Int {var index=0,total=0,step=(tree.count-1);while step>0{let next=index+step;if next<tree.count,total+tree[next]<target{index=next;total+=tree[next]};step>>=1};return index}
  }
  static func median(_ input:Input,radius:Int,threshold:Float?,depth:PixelDepth,area b:IntRect)throws->[Sample] {
    let r=radius,levels=depth == .u8 ? 256:65536,maxLevel=Float(levels-1)
    let rows=(-r...r).map{($0,Int(floor(sqrt(Double(r*r+r-$0*$0)))))};let count=rows.reduce(0){$0+2*$1.1+1}
    try budget(b.height*count+b.width*b.height*rows.count*2);var result=input.pixels
    for y in b.y..<(b.y+b.height){try Task.checkCancellation();for c in 0..<4 {
      var counts=Counts(levels)
      func level(_ x:Int,_ y:Int)->Int {min(levels-1,max(0,Int((input.get(x,y)[c]*maxLevel).rounded())))}
      for(dy,rx) in rows{for dx in -rx...rx{counts.add(level(b.x+dx,y+dy),1)}}
      for x in b.x..<(b.x+b.width){let m=Float(counts.rank(count/2+1))/maxLevel,o=input.get(x,y)[c]
        if threshold == nil || abs(o-m)>threshold! {result[y*input.width+x][c]=m}
        if x+1<b.x+b.width{for(dy,rx) in rows{counts.add(level(x-rx,y+dy),-1);counts.add(level(x+rx+1,y+dy),1)}}
      }
    }};return result
  }
  public static func render(_ source:Surface,kind:RasterFilter.Kind,settings s:ClassicDetailSettings,area:IntRect?=nil)throws->Surface {
    try s.validate(kind:kind)
    guard ClassicDetailSettings.depths(kind).contains(source.depth) else {throw CraftError.unsupported("\(kind.title) is unavailable at this document depth.")}
    let w=source.width,h=source.height,b=(area ?? IntRect(x:0,y:0,width:w,height:h)).clipped(toWidth:w,height:h),linear=source.depth == .f32
    guard w<=RasterFilterEngine.maximumPixels/h else{throw CraftError.unsupported("This filter supports up to8,388,608 pixels.")};if b.width==0 || b.height==0{return source}
    var pixels=[Sample]();pixels.reserveCapacity(w*h)
    for y in 0..<h{try Task.checkCancellation();for x in 0..<w{let p=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y);guard p.isFinite,max(abs(p.r),max(abs(p.g),abs(p.b)))<=1e12 else {throw CraftError.invalid("Filter input exceeds the supported numeric range.")};pixels.append(Sample(p.r,p.g,p.b,p.a))}}
    let input=Input(pixels:pixels,width:w,height:h);var output:[Sample]
    switch kind {
    case .blur,.blurMore:output=try gaussian(input,radius:kind == .blur ? 0.6:1.4)
    case .sharpen,.sharpenMore,.sharpenEdges:
      let radius:Float=kind == .sharpen ? 0.5:kind == .sharpenMore ? 0.6:0.8,k:Float=kind == .sharpen ? 0.6:kind == .sharpenMore ? 1.5:1,t:Float=kind == .sharpenEdges ? 6/255:0
      let blur=try gaussian(input,radius:radius);output=input.pixels
      for i in output.indices{if i%w==0{try Task.checkCancellation()};if output[i].w<=0{continue};for c in 0..<3{let d=output[i][c]-blur[i][c];if abs(d)+1e-6>=t{output[i][c]+=k*d}}}
    case .radialBlur:output=try radial(input,settings:s,area:b)
    case .shapeBlur:output=try shape(input,settings:s,area:b)
    case .smartBlur:output=try smart(input,settings:s,area:b)
    case .surfaceBlur,.despeckle:output=try surface(input,radius:kind == .despeckle ? 2:Int(s.radius),threshold:kind == .despeckle ? 12:Float(s.threshold),depth:source.depth,area:b)
    case .median,.dustAndScratches:output=try median(input,radius:Int(s.radius),threshold:kind == .median ? nil:Float(s.threshold)/255,depth:source.depth,area:b)
    default:throw CraftError.invalid("Unknown Blur, Noise or Sharpen operation.")
    }
    var result=source
    for y in b.y..<(b.y+b.height){try Task.checkCancellation();for x in b.x..<(b.x+b.width){let q=output[y*w+x];if q==input.pixels[y*w+x]{continue};let p=Pixel(q.x,q.y,q.z,q.w);guard p.isFinite else {throw CraftError.invalid("Nonfinite filter result.")};if linear{result.setLinearPixel(x:x,y:y,p)}else{result.setPixel(x:x,y:y,p)}}};return result
  }
  static func apply(_ s:ClassicDetailSettings,kind:RasterFilter.Kind,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws {
    let original=document,extent=try SmartFilterEngine.renderBounds(document.layers[index],in:document),linear=document.depth == .f32
    let area=(document.selection ?? IntRect(x:0,y:0,width:document.width,height:document.height)).clipped(toWidth:document.width,height:document.height)
    guard area.width>0,area.height>0 else {return}
    var layer=document.layers[index];let mapped:Surface
    if layer.affine == nil {mapped=try source.expanded(to:IntRect(x:extent.x-layer.x,y:extent.y-layer.y,width:extent.width,height:extent.height),fill:.clear)}
    else {mapped=try RasterGeometry.render(source,transform:layer.coordinateTransform,bounds:extent,method:.bicubic,clampEdges:false)}
    let output=try render(mapped,kind:kind,settings:s,area:IntRect(x:area.x-extent.x,y:area.y-extent.y,width:area.width,height:area.height))
    if output==mapped {return};let protect=document.isTransparencyLocked(layerID)
    _ = try ClonePainter.paintTarget(mask:false,bounds:area,on:&layer,clipping:area,preserveTransparency:protect) {pixels,transform,_ in
      guard pixels.width<=RasterFilterEngine.maximumPixels/pixels.height else {throw CraftError.unsupported("Expanded filter target exceeds8,388,608 pixels.")}
      var changed=false
      for y in 0..<pixels.height {try Task.checkCancellation();for x in 0..<pixels.width {
        let q=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(q.x)),dy=Int(floor(q.y))
        guard dx>=area.x,dy>=area.y,dx<area.x+area.width,dy<area.y+area.height else {continue}
        let coverage=original.selectionCoverage(x:dx,y:dy);if coverage<=0 {continue}
        let before=linear ? pixels.linearPixel(x:x,y:y):pixels.pixel(x:x,y:y)
        if protect && before.a==0 {continue}
        var after=linear ? output.linearPixel(x:dx-extent.x,y:dy-extent.y):output.pixel(x:dx-extent.x,y:dy-extent.y)
        if protect {after.a=before.a};let value=coverage>=1 ? after:before.mixing(after,coverage:coverage)
        if value.hasSameBits(as:before) {continue};changed=true
        if linear {pixels.setLinearPixel(x:x,y:y,value)} else {pixels.setPixel(x:x,y:y,value)}
      }};return changed
    };document.layers[index]=layer
  }
}
