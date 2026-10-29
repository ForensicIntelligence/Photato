import Foundation

public enum LensBlurEngine {
  typealias V=SIMD4<Double>
  struct Span { let y:Int,left:Int,right:Int }
  struct Iris { var spans:[Span];var count:Double }
  static func iris(radius:Float,blades:Int,curvature:Float,rotation:Float)->Iris {
    guard radius>=0.5 else { return Iris(spans:[.init(y:0,left:0,right:0)],count:1) }
    let r=Int(ceil(radius)),sector=2*Float.pi/Float(blades),rot=rotation*Float.pi/180-Float.pi/2
    var spans=[Span](),count=0.0
    for y in -r...r { var start:Int?
      for x in -r...(r+1) {
        let u=Float(x)/radius,v=Float(y)/radius,theta=atan2(v,u)-rot,angle=theta-floor(theta/sector)*sector-sector/2,polygon=cos(Float.pi/Float(blades))/cos(angle),edge=polygon+(1-polygon)*curvature
        let inside=x<=r && sqrt(u*u+v*v)<=edge
        if inside && start==nil { start=x } else if !inside,let left=start { spans.append(.init(y:y,left:left,right:x-1));count+=Double(x-left);start=nil }
      }
    }
    if spans.isEmpty { return Iris(spans:[.init(y:0,left:0,right:0)],count:1) };return Iris(spans:spans,count:count)
  }
  /// The native setting refers to the actual document channel, not a temporary RGB canvas.
  public static func depthValues(_ settings:LensBlurSettings,source:Surface,layer:Layer,document:CraftDocument,pixelToDocument:Transform2D)throws->[Float]? {
    try settings.validateSources(layer:layer,document:document);try pixelToDocument.validated()
    if settings.depthSource == .none { return nil }
    var sampler:MaskSampler?
    if settings.depthSource == .layerMask {
      var raw=layer;var properties=layer.effectiveMaskProperties;properties.enabled=true;properties.inverted=false;properties.density=1;properties.feather=0;raw.maskProperties=properties;sampler=try MaskSampler(layer:raw,feather:false)
    }
    let channel=document.alphaChannels?.first{$0.id==settings.depthChannelID}
    var values=[Float](repeating:0,count:source.width*source.height)
    for y in 0..<source.height { try Task.checkCancellation();for x in 0..<source.width {
      let p=pixelToDocument.point(Double(x)+0.5,Double(y)+0.5),value:Float
      switch settings.depthSource {
      case .none:value=0
      case .transparency:value=source.pixel(x:x,y:y).a
      case .layerMask:value=sampler!.coverage(x:p.x,y:p.y)
      case .alphaChannel:value=MaskSampler.sample(channel!.pixels,x:p.x,y:p.y,outside:0)
      };values[y*source.width+x]=unit(value)
    } };return values
  }
  public static func render(_ source:Surface,settings s:LensBlurSettings,depth:[Float]?=nil)throws->Surface {
    try s.validate();let w=source.width,h=source.height,n=w*h
    guard source.depth != .f32 else { throw CraftError.unsupported("Lens Blur supports 8-bit and 16-bit RGB images.") }
    guard w<=RasterFilterEngine.maximumPixels/h else { throw CraftError.unsupported("Lens Blur supports layers up to 8 MP.") }
    if let depth { guard depth.count==n,depth.allSatisfy({$0.isFinite && (0...1).contains($0)}) else { throw CraftError.invalid("Invalid Lens Blur depth map.") } }
    guard s.depthSource == .none || s.depthSource == .transparency || depth != nil else { throw CraftError.invalid("Lens Blur needs its selected depth map.") }
    if s.isIdentity { return source }
    let levels=(0...8).map{iris(radius:Float(s.radius)*Float($0)/8,blades:s.blades,curvature:Float(s.bladeCurvature/100),rotation:Float(s.rotation))}
    var prefixes=[V](repeating:.zero,count:(w+1)*h),leftEdge=[V](repeating:.zero,count:h),rightEdge=leftEdge
    let boost=Float(s.brightness/100)*4,threshold=Float(s.threshold/255)
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let p=source.pixel(x:x,y:y);guard p.isFinite else { throw CraftError.invalid("Invalid Lens Blur source.") }
      let luma=0.299*p.r+0.587*p.g+0.114*p.b,t=max(0,min(1,(luma-threshold)/0.02)),gain=1+boost*t*t*(3-2*t),a=Double(p.a),value=V(Double(p.r*gain)*a,Double(p.g*gain)*a,Double(p.b*gain)*a,a)
      prefixes[y*(w+1)+x+1]=prefixes[y*(w+1)+x]+value
      if x==0 { leftEdge[y]=value };if x==w-1 { rightEdge[y]=value }
    } }
    func mean(_ kernel:Iris,_ x:Int,_ y:Int)->V {
      var sum=V.zero
      for span in kernel.spans { let yy=min(h-1,max(0,y+span.y)),a=x+span.left,b=x+span.right+1,lo=max(0,min(w,a)),hi=max(0,min(w,b)),row=yy*(w+1)
        sum += prefixes[row+hi]-prefixes[row+lo]
        if a<0 { sum += leftEdge[yy]*Double(min(b,0)-a) }
        if b>w { sum += rightEdge[yy]*Double(b-max(a,w)) }
      };return sum/kernel.count
    }
    var result=source;let focal=Float(s.focalDistance/255),amount=Float(s.noiseAmount/100)*0.25
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let original=source.pixel(x:x,y:y),raw=s.depthSource == .none ? nil:(depth?[y*w+x] ?? original.a)
      let d=raw.map{s.invert ? 1-$0:$0},level=d.map{min(8,abs($0-focal)*8)} ?? 8,lo=Int(floor(level)),fraction=Double(level-Float(lo))
      if level==0 && boost==0 && amount==0 { continue }
      var value=mean(levels[lo],x,y)
      if fraction>0.0001 && lo<8 { value += (mean(levels[lo+1],x,y)-value)*fraction }
      guard value.w>1e-12 else { result.setPixel(x:x,y:y,.clear);continue }
      var rgb=SIMD3<Float>(Float(value.x/value.w),Float(value.y/value.w),Float(value.z/value.w))
      if amount>0 { for c in 0..<3 { let channel=UInt32(s.monochromatic ? 0:c),noise:Float
        if s.distribution == .uniform { noise=(GalleryMath.hash(x,y,channel+200,s.seed)-0.5)*2*amount }
        else { let u1=max(1e-7,GalleryMath.hash(x,y,channel*2+301,s.seed)),u2=GalleryMath.hash(x,y,channel*2+302,s.seed);noise=sqrt(-2*log(u1))*cos(2*Float.pi*u2)*amount*0.5 };rgb[c]+=noise
      } }
      let p=Pixel(rgb.x,rgb.y,rgb.z,Float(value.w));guard p.isFinite else { throw CraftError.invalid("Nonfinite Lens Blur output.") };result.setPixel(x:x,y:y,p)
    } };return result
  }
  static func apply(_ settings:LensBlurSettings,source:Surface,layerID:UUID,index:Int,document:inout CraftDocument)throws {
    let layer=document.layers[index],matrix=layer.coordinateTransform,depth=try depthValues(settings,source:source,layer:layer,document:document,pixelToDocument:matrix),edited=try render(source,settings:settings,depth:depth),protect=document.isTransparencyLocked(layerID)
    var result=source
    for y in 0..<source.height { try Task.checkCancellation();for x in 0..<source.width {
      let point=matrix.point(Double(x)+0.5,Double(y)+0.5),coverage=document.selectionCoverage(x:Int(floor(point.x)),y:Int(floor(point.y)));if coverage<=0 { continue }
      let a=source.pixel(x:x,y:y);if protect && a.a==0 { continue };var b=edited.pixel(x:x,y:y);if protect { b.a=a.a };result.setPixel(x:x,y:y,coverage>=1 ? b:a.mixing(b,coverage:coverage))
    } };document.layers[index].content = .raster(result)
  }
  static func validateMaskRemoval(_ layer:Layer)throws { guard !usesLayerMask(layer) else { throw CraftError.invalid("This mask supplies Lens Blur depth. Change the filter depth source before removing or applying it.") } }
  public static func usesLayerMask(_ layer:Layer)->Bool { layer.smartFilters?.filters.contains{$0.filter.lensBlur?.depthSource == .layerMask} == true }
  public static func usesChannel(_ id:UUID,in document:CraftDocument)->Bool { document.layers.contains{$0.smartFilters?.filters.contains{$0.filter.lensBlur?.depthChannelID==id} == true} }
}
