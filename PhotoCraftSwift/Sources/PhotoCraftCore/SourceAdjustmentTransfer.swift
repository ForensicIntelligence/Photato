import Foundation

/// Native Swift translation of original PhotoCraft compose/adjust.rs. This
/// renderer preserves source controls and operation order, not Photoshop parity.
public struct SourceAdjustmentTransfer:Sendable {
  private let value:SourceAdjustment
  private let depth:PixelDepth
  private let tables:[[Float]]
  public init(_ value:SourceAdjustment,depth:PixelDepth)throws {
    try value.validate()
    guard value.space == .rgb else {throw CraftError.unsupported("Original CMYK/Lab tone records require their source color conversions before evaluation.")}
    self.value=value;self.depth=depth
    let identity=(0..<4096).map{Float($0)/4095}
    if value.kind == .levels {
      let rows=value.records["channels"]!,master=rows[0]
      tables=(1...3).map{c in identity.map{let out=Self.level(rows[c],Self.level(master,$0,depth),depth);return depth == .f32 ? unit(out):out}}
    } else if value.kind == .curves {
      let master=Self.curve(value.records["master"]!)
      tables=["red","green","blue"].map{key in Self.curve(value.records[key]!).map{Self.lookup(master,$0)}}
    } else if value.kind == .hueSaturation, value.options["colorize"]==false,
      value.records["ranges"]!.contains(where:{$0.prefix(3).contains(where:{$0 != 0})}) {
      let ranges=value.records["ranges"]!
      let rows=identity.map{t -> [Float] in
        var v=[Float](repeating:0,count:3)
        for r in ranges where r[0] != 0 || r[1] != 0 || r[2] != 0 {
          let w=Self.weight(r,t*360);v[0]+=w*r[0];v[1]+=w*r[1]/100;v[2]+=w*r[2]/100
        };return v
      };tables=(0..<3).map{i in rows.map{$0[i]}}
    } else {tables=[]}
  }
  public func apply(_ p:Pixel,x:Int=0,y:Int=0)->Pixel {
    guard p.isFinite,p.a>0,!value.isOpaque else {return p}
    let input=depth == .f32 ? SRGBTransfer.linear(p):p
    let result=applySourceSample(input,x:x,y:y)
    return depth == .f32 ? SRGBTransfer.encoded(result):result
  }
  /// Original working samples, used before native storage encoding.
  public func applySourceSample(_ p:Pixel,x:Int=0,y:Int=0)->Pixel {
    guard p.isFinite,p.a>0,!value.isOpaque else {return p}
    let original=p
    let c=[original.r,original.g,original.b],v=value.parameters,r=value.records,o=value.options
    var out=c
    func luma(_ a:[Float])->Float {0.299*a[0]+0.587*a[1]+0.114*a[2]}
    func map(_ f:(Float)->Float)->[Float] {c.map(f)}
    switch value.kind {
    case .invert:out=map{1-$0}
    case .threshold:
      let t=(v["level"]!*255).rounded(),a:Float=(luma(c)*255).rounded()>=t ? 1:0;out=[a,a,a]
    case .posterize:
      let n=v["levels"]!;out=map{a in let x=(unit(a)*255).rounded();let bin=min(n-1,floor(x*n/256));return floor(bin*255/(n-1))/255}
    case .brightnessContrast:
      let b=v["brightness"]!,contrast=v["contrast"]!
      if o["legacy"]==true {
        let t=min(99,max(-100,contrast)),k:Float=t>=0 ? 1/(1-t/100):1+t/100
        out=map{unit(($0-0.5)*k+0.5+b/255)}
      } else {out=map{unit(Self.contrast(Self.brightness($0,b),contrast))}}
    case .exposure:
      let multiplier=pow(Float(2),v["exposure"]!),gamma=max(0.01,v["gamma"]!),power:Float=depth == .f32 ? 1:2.2
      out=map{a in let lin=pow(max(0,pow(max(0,a),power)*multiplier+v["offset"]!),1/gamma);return unit(pow(max(0,lin),1/power))}
    case .levels,.curves:out=(0..<3).map{Self.lookup(tables[$0],c[$0])}
    case .hueSaturation:
      var delta=[Float](repeating:0,count:3)
      if !tables.isEmpty {let h=Self.hsl(c)[0],chroma=min(1,(c.max()!-c.min()!)*4);delta=(0..<3).map{Self.lookup(tables[$0],h)*chroma}}
      out=Self.hue(c,hue:v["hue"]!+delta[0],s:min(1,max(-1,v["saturation"]!/100+delta[1])),l:min(1,max(-1,v["lightness"]!/100+delta[2])),colorize:o["colorize"]!)
    case .vibrance:
      let h=Self.hsl(c),boost=v["vibrance"]!/100*(1-h[1]);let saturation=unit(h[1]*(1+v["saturation"]!/100)+boost*max(h[1],0.1));out=Self.rgb(h[0],saturation,h[2])
    case .channelMixer:
      let m=r["matrix"]!
      out=(0..<3).map{i in let a=m[o["monochrome"]! ? 0:i];return unit(a[0]*c[0]+a[1]*c[1]+a[2]*c[2]+a[3])}
    case .photoFilter:
      let d=v["density"]!,color=r["color"]![0];out=(0..<3).map{c[$0]*(1-d)+c[$0]*color[$0]*d}
      if o["preserveLuminosity"]! {let before=luma(c),after=max(luma(out),1e-6);out=out.map{unit($0*before/after)}}
    case .blackWhite:
      let hi=c.max()!,lo=c.min()!,mid=c[0]+c[1]+c[2]-hi-lo
      let primary=c[0]>=c[1] && c[0]>=c[2] ? 0:c[1]>=c[2] ? 2:4
      let secondary=c[2]<=c[0] && c[2]<=c[1] ? 1:c[0]<=c[1] ? 3:5,w=r["weights"]![0]
      let g=unit(lo+(mid-lo)*w[secondary]/100+(hi-mid)*w[primary]/100)
      out=[g,g,g];if let tint=r["tint"]?.first {out=(0..<3).map{unit(g*tint[$0]*2)*0.5+g*0.5}}
    case .gradientMap:
      var t=luma(c);if o["reverse"]! {t=1-t};let stops=r["stops"]!
      if stops.isEmpty {out=[t,t,t]}
      else if stops.count==1 || t<=stops[0][0] {out=Array(stops[0].dropFirst())}
      else if let i=(1..<stops.count).first(where:{t<=stops[$0][0]}) {
        let a=stops[i-1],b=stops[i],k=b[0]>a[0] ? (t-a[0])/(b[0]-a[0]):0
        out=(1...3).map{a[$0]+(b[$0]-a[$0])*k}
      } else {out=Array(stops.last!.dropFirst())}
      if o["dither"]! {let d=Self.dither(x,y)/255;out=out.map{unit($0+d)}}
    case .colorBalance:
      let l=luma(c),ws=unit(1-l*2),wh=unit(l*2-1),wm=1-ws-wh
      let s=r["shadows"]![0],m=r["midtones"]![0],h=r["highlights"]![0]
      out=(0..<3).map{i in unit(c[i]+(s[i]*ws+m[i]*wm+h[i]*wh)/100*0.5)}
      if o["preserveLuminosity"]! {let ratio=max(luma(out),1e-6);out=out.map{unit($0*l/ratio)}}
    case .selectiveColor:
      let hi=c.max()!,lo=c.min()!,mid=c[0]+c[1]+c[2]-hi-lo
      func top(_ i:Int)->Float {c[i]>=hi ? hi-mid:0};func bottom(_ i:Int)->Float {c[i]<=lo ? mid-lo:0}
      let weights=[top(0),bottom(2),top(1),bottom(0),top(2),bottom(1),max(0,(lo-0.5)*2),unit(1-abs(hi-0.5)-abs(lo-0.5)),max(0,(0.5-hi)*2)]
      var delta=[Float](repeating:0,count:3)
      for j in 0..<9 where weights[j]>0 {let a=r["adjustments"]![j].map{$0/100};for i in 0..<3 {let d=o["relative"]! ? (a[i]+a[3])*(1-c[i]):a[i]+a[3];delta[i]+=d*weights[j]}}
      out=(0..<3).map{unit(c[$0]-delta[$0])}
    case .colorLookup:
      out=Self.lut3D(r["lut"]![0],Int(v["size"]!),c,o["tetrahedral"]!)
      if o["dither"]! {let d=Self.dither(x,y)/255;out=out.map{unit($0+d)}}
    case .unsupported:return p
    }
    let result=Pixel(out[0],out[1],out[2],p.a)
    return result
  }
  static func lookup(_ table:[Float],_ v:Float)->Float {
    let x=unit(v)*Float(table.count-1),i=Int(floor(x)),f=x-Float(i)
    return table[i]*(1-f)+table[min(i+1,table.count-1)]*f
  }
  static func level(_ a:[Float],_ x:Float,_ depth:PixelDepth)->Float {
    let range=max(1e-6,a[1]-a[0]),g=max(0.01,a[2]),t:Float
    if depth == .f32 {let v=(x-a[0])/range;t=(v<0 ? -1:1)*pow(abs(v),1/g)}
    else {
      let q:Float=depth == .u8 ? 255:32768,v=(x*q).rounded()/q,u=floor(unit((v-a[0])/range)*q+0.5+1e-3)/q
      let power=pow(u,1/g)
      if g>1 {let line=0.93*pow(Float(2),g)*u;t=power<=1e-6 || line<=1e-6 ? min(power,line):pow(pow(power,-10)+pow(line,-10),-0.1)} else {t=power}
    }
    return a[3]+t*(a[4]-a[3])
  }
  static func curve(_ input:[[Float]])->[Float] {
    let sorted=input.enumerated().sorted{a,b in a.element[0]==b.element[0] ? a.offset<b.offset:a.element[0]<b.element[0]};var points=[[Float]]()
    for item in sorted {if points.last.map({abs($0[0]-item.element[0])<1e-6}) != true {points.append(item.element)}}
    let n=points.count;if n<2 {return (0..<4096).map{Float($0)/4095}}
    let x=points.map{Double($0[0])},y=points.map{Double($0[1])};var second=[Double](repeating:0,count:n)
    if n>2 {
      var c=second,d=second
      for i in 1..<(n-1) {let h0=x[i]-x[i-1],h1=x[i+1]-x[i],a=h0/6,b=(h0+h1)/3,cc=h1/6,r=(y[i+1]-y[i])/h1-(y[i]-y[i-1])/h0,denom=b-a*c[i-1];c[i]=cc/denom;d[i]=(r-a*d[i-1])/denom}
      for i in stride(from:n-2,through:1,by:-1) {second[i]=d[i]-c[i]*second[i+1]}
    }
    return (0..<4096).map{k in
      let v=Float(k)/4095
      if v<=points[0][0] {return unit(points[0][1])};if v>=points[n-1][0] {return unit(points[n-1][1])}
      let i=(0..<(n-1)).first(where:{v<=points[$0+1][0]}) ?? n-2,h=x[i+1]-x[i],t=Double(v),a=(x[i+1]-t)/h,b=(t-x[i])/h
      let result=a*y[i]+b*y[i+1]+((a*a*a-a)*second[i]+(b*b*b-b)*second[i+1])*h*h/6
      return unit(Float(result))
    }
  }
  static func brightness(_ value:Float,_ b:Float)->Float {
    if b==0 {return value};let s=pow(Float(1.375),b/50),p:Float=b>=0 ? max(2,4.5-0.013*b):5-0.072*b,v=unit(value)
    return unit(s*v+(1-s)*pow(v,p))
  }
  static func contrast(_ value:Float,_ c:Float)->Float {
    if c==0 {return value};let k=c/128,end=1-k,mid=1+k,v=unit(value)
    func half(_ t:Float)->Float {end*0.5*(t*t*t-2*t*t+t)+(-2*t*t*t+3*t*t)*0.5+mid*0.5*(t*t*t-t*t)}
    return v<=0.5 ? half(v/0.5):1-half((1-v)/0.5)
  }
  static func wrap(_ x:Float,_ period:Float)->Float {let r=x.truncatingRemainder(dividingBy:period);return r<0 ? r+period:r}
  static func hsl(_ c:[Float])->[Float] {
    let hi=c.max()!,lo=c.min()!,l=(hi+lo)/2,d=hi-lo
    if abs(d)<1e-7 {return [0,0,l]};let s=l>0.5 ? d/(2-hi-lo):d/(hi+lo),h:Float
    if hi==c[0] {h=wrap((c[1]-c[2])/d,6)} else if hi==c[1] {h=(c[2]-c[0])/d+2} else {h=(c[0]-c[1])/d+4}
    return [h/6,s,l]
  }
  static func rgb(_ h:Float,_ s:Float,_ l:Float)->[Float] {
    if s<=0 {return [l,l,l]};let q=l<0.5 ? l*(1+s):l+s-l*s,p=2*l-q
    func f(_ t:Float)->Float {let t=wrap(t,1);if t<1/6 {return p+(q-p)*6*t};if t<0.5 {return q};if t<2/3 {return p+(q-p)*(2/3-t)*6};return p}
    return [f(h+1/3),f(h),f(h-1/3)]
  }
  static func hue(_ c:[Float],hue:Float,s:Float,l:Float,colorize:Bool)->[Float] {
    let hsl=hsl(c),h=colorize ? wrap(hue,360)/360:wrap(hsl[0]+hue/360,1),sat=colorize ? max(abs(s),0.25):unit(hsl[1]*(1+s))
    var out=rgb(h,sat,hsl[2]);if l>0 {out=out.map{$0+(1-$0)*l}} else if l<0 {out=out.map{$0*(1+l)}};return out
  }
  static func weight(_ r:[Float],_ degree:Float)->Float {
    let a=r[3];func rel(_ v:Float)->Float {wrap(v-a,360)}
    let b=rel(r[4]),c=max(b,rel(r[5])),d=max(c,rel(r[6])),h=rel(degree)
    if h<=b {return b<=0 ? 1:h/b};if h<=c {return 1};if h<=d {return d<=c ? 1:(d-h)/(d-c)};return 0
  }
  static func dither(_ x:Int,_ y:Int)->Float {let m:[Float]=[0,8,2,10,12,4,14,6,3,11,1,9,15,7,13,5];return (m[(y&3)*4+(x&3)]+0.5)/16-0.5}
  static func lut3D(_ table:[Float],_ n:Int,_ c:[Float],_ tetrahedral:Bool)->[Float] {
    let pos=c.map{unit($0)*Float(n-1)},i=pos.map{min(n-2,Int(floor($0)))},f=(0..<3).map{pos[$0]-Float(i[$0])}
    func at(_ r:Int,_ g:Int,_ b:Int)->[Float] {let k=(((i[2]+b)*n+i[1]+g)*n+i[0]+r)*3;return Array(table[k..<(k+3)])}
    func mix(_ terms:[(Float,[Float])])->[Float] {(0..<3).map{i in terms.reduce(Float(0)){$0+$1.0*$1.1[i]}}}
    let r=f[0],g=f[1],b=f[2]
    if tetrahedral {
      let a=at(0,0,0),z=at(1,1,1)
      if r>g {
        if g>b {return mix([(1-r,a),(r-g,at(1,0,0)),(g-b,at(1,1,0)),(b,z)])}
        if r>b {return mix([(1-r,a),(r-b,at(1,0,0)),(b-g,at(1,0,1)),(g,z)])}
        return mix([(1-b,a),(b-r,at(0,0,1)),(r-g,at(1,0,1)),(g,z)])
      }
      if b>g {return mix([(1-b,a),(b-g,at(0,0,1)),(g-r,at(0,1,1)),(r,z)])}
      if b>r {return mix([(1-g,a),(g-b,at(0,1,0)),(b-r,at(0,1,1)),(r,z)])}
      return mix([(1-g,a),(g-r,at(0,1,0)),(r-b,at(1,1,0)),(b,z)])
    }
    func lerp(_ a:[Float],_ b:[Float],_ t:Float)->[Float] {(0..<3).map{a[$0]+(b[$0]-a[$0])*t}}
    return lerp(lerp(lerp(at(0,0,0),at(1,0,0),r),lerp(at(0,1,0),at(1,1,0),r),g),lerp(lerp(at(0,0,1),at(1,0,1),r),lerp(at(0,1,1),at(1,1,1),r),g),b)
  }
}
