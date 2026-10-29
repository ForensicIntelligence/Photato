import Foundation

/// Native Swift translation of licensed PhotoCraft other.rs/other2.rs/video.rs.
public enum OtherVideoEngine {
  typealias Sample=SIMD4<Float>
  static func positive(_ n:Int,_ d:Int)->Int {let r=n%d;return r<0 ? r+d:r}
  static func rem(_ x:Float,_ d:Float)->Float {let r=x.truncatingRemainder(dividingBy:d);return r<0 ? r+d:r}
  static func hue(_ p:Sample,_ mx:Float,_ delta:Float)->Float {
    if delta<=0 {return 0}
    return (mx==p.x ? rem((p.y-p.z)/delta,6):mx==p.y ? (p.z-p.x)/delta+2:(p.x-p.y)/delta+4)/6
  }
  static func rgb(_ p:Sample,from model:OtherVideoSettings.ColorModel)->Sample {
    if model == .rgb {return p}
    let c=model == .hsb ? p.z*p.y:(1-abs(2*p.z-1))*p.y,m=model == .hsb ? p.z-c:p.z-c/2
    let hp=rem(p.x,1)*6,x=c*(1-abs(rem(hp,2)-1));let v:Sample
    switch Int(hp) {case 0:v=Sample(c,x,0,p.w);case 1:v=Sample(x,c,0,p.w);case 2:v=Sample(0,c,x,p.w);case 3:v=Sample(0,x,c,p.w);case 4:v=Sample(x,0,c,p.w);default:v=Sample(c,0,x,p.w)}
    return Sample(v.x+m,v.y+m,v.z+m,p.w)
  }
  static func encode(_ p:Sample,to model:OtherVideoSettings.ColorModel)->Sample {
    if model == .rgb {return p}
    let mx=max(p.x,max(p.y,p.z)),mn=min(p.x,min(p.y,p.z)),d=mx-mn,l=(mx+mn)/2
    if model == .hsb {return Sample(hue(p,mx,d),mx>0 ? d/mx:0,mx,p.w)}
    let s=d<=0 ? 0:d/max(1e-7,1-abs(2*l-1));return Sample(hue(p,mx,d),min(1,max(0,s)),l,p.w)
  }
  static func pick(_ a:Sample,_ b:Sample,maximum:Bool)->Sample {
    var r=a;for c in 0..<4 {r[c]=maximum ? max(a[c],b[c]):min(a[c],b[c])};return r
  }
  /// van Herk/Gil-Werman prefix and suffix extrema; linear work independent of window width.
  static func running(_ input:[Sample],window k:Int,maximum:Bool)->[Sample] {
    if k<=1 {return input};guard input.count>=k else {return []}
    var pre=input,suf=input
    for i in 1..<input.count where i%k != 0 {pre[i]=pick(pre[i-1],input[i],maximum:maximum)}
    for i in stride(from:input.count-2,through:0,by:-1) where (i+1)%k != 0 {suf[i]=pick(suf[i+1],input[i],maximum:maximum)}
    return (0...(input.count-k)).map{pick(suf[$0],pre[$0+k-1],maximum:maximum)}
  }
  static func extrema(_ input:[Sample],width w:Int,height h:Int,settings s:OtherVideoSettings,maximum:Bool)throws->[Sample] {
    let radius=Float(s.radius),r=Int(floor(radius));if r==0 {return input}
    if s.preserve == .squareness {
      var tmp=input,result=input
      for y in 0..<h {try Task.checkCancellation();let row=running((-r..<(w+r)).map{input[y*w+min(w-1,max(0,$0))]},window:2*r+1,maximum:maximum);tmp.replaceSubrange(y*w..<(y+1)*w,with:row)}
      for x in 0..<w {try Task.checkCancellation();let col=running((-r..<(h+r)).map{tmp[min(h-1,max(0,$0))*w+x]},window:2*r+1,maximum:maximum);for y in 0..<h {result[y*w+x]=col[y]}}
      return result
    }
    guard w*h<=268_435_456/(2*r+1) else {throw CraftError.unsupported("Roundness exceeds the bounded processing budget; reduce the radius or image size.")}
    var output=[Sample](repeating:Sample(repeating:maximum ? -Float.greatestFiniteMagnitude:Float.greatestFiniteMagnitude),count:w*h)
    for dy in -r...r {
      let hw=Int(floor(sqrt(max(0,radius*radius-Float(dy*dy)))+0.0001))
      for y in 0..<h {try Task.checkCancellation();let sy=min(h-1,max(0,y+dy)),row=running((-hw..<(w+hw)).map{input[sy*w+min(w-1,max(0,$0))]},window:2*hw+1,maximum:maximum)
        for x in 0..<w {output[y*w+x]=pick(output[y*w+x],row[x],maximum:maximum)}
      }
    };return output
  }
  public static func render(_ source:Surface,kind:RasterFilter.Kind,settings s:OtherVideoSettings,area:IntRect?=nil)throws->Surface {
    try s.validate(kind:kind)
    let w=source.width,h=source.height,linear=source.depth == .f32,b=(area ?? IntRect(x:0,y:0,width:w,height:h)).clipped(toWidth:w,height:h)
    guard w<=RasterFilterEngine.maximumPixels/h else {throw CraftError.unsupported("Other/Video filters support up to8,388,608 pixels.")}
    if b.width==0 || b.height==0 || (kind == .offset && s.horizontal==0 && s.vertical==0) || (kind == .hsbHsl && s.inputMode==s.outputMode) {return source}
    if kind == .customFilter && (s.kernel.allSatisfy{$0==0} || (s.kernel.enumerated().allSatisfy{$0.element == ($0.offset==12 ? 1:0)} && s.scale==1 && s.offset==0)) {return source}
    var input=[Sample]();input.reserveCapacity(w*h)
    for y in 0..<h {try Task.checkCancellation();for x in 0..<w {
      let p=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y)
      guard p.isFinite,max(abs(p.r),max(abs(p.g),abs(p.b)))<=1e12 else {throw CraftError.invalid("Other/Video input exceeds the supported numeric range.")}
      input.append(Sample(p.r,p.g,p.b,p.a))
    }}
    func get(_ x:Int,_ y:Int)->Sample {input[min(h-1,max(0,y))*w+min(w-1,max(0,x))]}
    let extreme:[Sample]? = [RasterFilter.Kind.maximum,.minimum].contains(kind) ? try extrema(input,width:w,height:h,settings:s,maximum:kind == .maximum):nil
    let coefficients=s.kernel.enumerated().filter{$0.element != 0}.map{(dx:$0.offset%5-2,dy:$0.offset/5-2,value:Float($0.element))}
    var result=source
    for y in b.y..<(b.y+b.height) {try Task.checkCancellation();for x in b.x..<(b.x+b.width) {
      let p=input[y*w+x];var q=p
      switch kind {
      case .customFilter:
        for c in 0..<3 {var sum:Float=0;for k in coefficients {sum+=get(x+k.dx,y+k.dy)[c]*k.value};q[c]=sum/Float(s.scale)+Float(s.offset)/255}
      case .hsbHsl:
        let clamped=Sample(min(1,max(0,p.x)),min(1,max(0,p.y)),min(1,max(0,p.z)),p.w)
        q=encode(rgb(clamped,from:s.inputMode),to:s.outputMode)
      case .maximum,.minimum:q=extreme![y*w+x]
      case .offset:
        var sx=x-s.horizontal,sy=y-s.vertical
        if sx<b.x || sy<b.y || sx>=b.x+b.width || sy>=b.y+b.height {
          switch s.undefinedAreas {
          case .transparent:q = .zero
          case .wrap:sx=b.x+positive(sx-b.x,b.width);sy=b.y+positive(sy-b.y,b.height);q=get(sx,sy)
          case .repeatEdge:q=get(min(b.x+b.width-1,max(b.x,sx)),min(b.y+b.height-1,max(b.y,sy)))
          }
        } else {q=get(sx,sy)}
      case .deInterlace:
        let odd=(y-b.y)%2==0
        if odd == (s.eliminate == .even) {continue}
        let above=y>b.y ? y-1:nil,below=y+1<b.y+b.height ? y+1:nil
        let rows:[Int]
        if s.createBy == .interpolation,let above,let below {rows=[above,below]}
        else if let above {rows=[above]} else if let below {rows=[below]} else {continue}
        q = .zero;let weight:Float=1/Float(rows.count)
        for row in rows {let v=get(x,row);q+=Sample(v.x*v.w,v.y*v.w,v.z*v.w,v.w)*weight}
        if q.w>1e-7 {q.x/=q.w;q.y/=q.w;q.z/=q.w} else {q.x=0;q.y=0;q.z=0}
      case .ntscColors:
        let yy=0.299*p.x+0.587*p.y+0.114*p.z,ii=0.595716*p.x-0.274453*p.y-0.321263*p.z,qq=0.211456*p.x-0.522591*p.y+0.311135*p.z
        let chroma=sqrt(ii*ii+qq*qq);if chroma<=1e-7 {continue}
        let upper:Float=(120-7.5)/92.5,lower:Float=(-20-7.5)/92.5;var k:Float=1
        if yy+chroma>upper {k=min(k,max(0,(upper-yy)/chroma))};if yy-chroma<lower {k=min(k,max(0,(yy-lower)/chroma))};if k>=1 {continue}
        let i=ii*k,j=qq*k;q=Sample(yy+0.9563*i+0.6210*j,yy-0.2721*i-0.6474*j,yy-1.1070*i+1.7046*j,p.w)
      default:throw CraftError.invalid("Unknown Other/Video operation.")
      }
      let value=Pixel(q.x,q.y,q.z,q.w);guard value.isFinite else {throw CraftError.invalid("Nonfinite Other/Video result.")}
      if q==p {continue};if linear {result.setLinearPixel(x:x,y:y,value)} else {result.setPixel(x:x,y:y,value)}
    }};return result
  }
  static func apply(_ s:OtherVideoSettings,kind:RasterFilter.Kind,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws {
    if kind == .offset {guard (-2*document.width...2*document.width).contains(s.horizontal),(-2*document.height...2*document.height).contains(s.vertical) else {throw CraftError.invalid("Offset cannot exceed twice the document width or height.")}}
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
