import Foundation

public enum PixelPaintTarget:Codable,Equatable,Sendable{case layer(UUID),mask(UUID),channel(ChannelPlaneTarget)}
public enum PixelPaintKind:String,Codable,CaseIterable,Sendable{case fill,stroke;public var title:String{self == .fill ? "Fill":"Stroke"}}
public enum PixelStrokeLocation:String,Codable,CaseIterable,Sendable{case inside="Inside",center="Center",outside="Outside"}
public struct PixelPaintSettings:Codable,Equatable,Sendable{
  public var color:Pixel
  public var opacity:Float=1
  public var mode:BlendMode = .normal
  public var preserveTransparency=false
  public var width:Int=1
  public var location:PixelStrokeLocation = .center
  public init(color:Pixel = .black){self.color=color}
  public func validate(_ kind:PixelPaintKind)throws{guard color.isFinite,(0...1).contains(color.a),opacity.isFinite,(0...1).contains(opacity),kind != .stroke || (1...250).contains(width) else{throw CraftError.invalid("Use a finite color, opacity0–1 and Stroke width1–250 pixels.")}}
}
public struct PixelPaintRequest:Codable,Equatable,Sendable{
  public var kind:PixelPaintKind,target:PixelPaintTarget,settings:PixelPaintSettings
  public var pattern:RasterPattern?
  public var patternPlacement:PatternPlacement?
  public init(_ kind:PixelPaintKind,target:PixelPaintTarget,settings:PixelPaintSettings,pattern:RasterPattern?=nil,placement:PatternPlacement?=nil){self.kind=kind;self.target=target;self.settings=settings;self.pattern=pattern;self.patternPlacement=placement}
}
public enum PixelFillStroke{
  public static func available(_ document:CraftDocument,target:PixelPaintTarget)->Bool{
    guard document.animation==nil,document.videoTimeline==nil,!document.colorMode.isRestricted else{return false}
    switch target{
    case .channel(let target):return (try? document.channel(target)) != nil
    case .layer(let id):guard document.colorMode == .rgb,document.inkMode==nil,let layer=document.layers.first(where:{$0.id==id}),case .raster=layer.content else{return false};return layer.smartObject==nil && layer.nativeMode==nil && !document.isImageLocked(id) && layer.video==nil && !layer.hasGeometryKeyframes
    case .mask(let id):return document.layers.contains{$0.id==id && $0.mask != nil} && !document.isLocked(id)
    }
  }
  public static func apply(_ request:PixelPaintRequest,to document:inout CraftDocument)throws{
    try Task.checkCancellation();try request.settings.validate(request.kind)
    guard available(document,target:request.target) else{throw CraftError.unsupported("Choose an unlocked raster layer, pixel mask or auxiliary channel in a supported static document. Rasterize live content explicitly first.")}
    guard request.pattern==nil || request.kind == .fill,request.pattern != nil || request.patternPlacement==nil else{throw CraftError.invalid("Only Pattern Fill accepts a captured pattern and placement.")}
    let sampler=try request.pattern.map{try PatternSampler($0,placement:request.patternPlacement ?? .init())}
    let uniformInk:Pixel?=request.pattern.flatMap{pattern in pattern.surface.tileCount==0 ? pattern.surface.defaultPixel:pattern.surface.width==1 && pattern.surface.height==1 ? pattern.surface.pixel(x:0,y:0):nil}
    if request.settings.opacity==0 || request.pattern==nil && request.settings.color.a==0{return}
    let canvas=IntRect(x:0,y:0,width:document.width,height:document.height),settings=request.settings
    var coverage:Surface
    if let selection=try document.coverageSelection(){coverage=try selection.coverageSurface()}
    else if request.kind == .stroke,case .layer(let id)=request.target,let layer=document.layers.first(where:{$0.id==id}),case .raster(let source)=layer.content{
      let alpha=try source.mappedStoredSamples(encoding:.sRGB){Pixel($0.a,$0.a,$0.a)}
      coverage=try ScalarPlaneProjection.render(alpha,placement:.init(layer.coordinateTransform),bounds:canvas,exterior:0,interpolation:.bilinear).quantizedCoverageStorage()
    }else{coverage=try Surface(width:document.width,height:document.height,fill:.white)}
    if request.kind == .stroke{coverage=try outline(coverage,width:settings.width,location:settings.location)}
    guard let bounds=try coverage.scalarCoverageBounds() else{return}
    var candidate=document
    switch request.target{
    case .channel(let target):
      var channel=try document.channel(target)
      try paint(&channel.pixels,transform:.identity,coverage:coverage,settings:settings,scalar:true,preserve:false,invert:channel.display(0)>0.5,pattern:sampler,uniformInk:uniformInk)
      if let originalGray=channel.psdSpotGray{var edited=originalGray;try paint(&edited,transform:.identity,coverage:coverage,settings:settings,scalar:true,preserve:false,pattern:sampler,uniformInk:uniformInk);channel.psdSpotGray=edited}
      try candidate.setChannel(channel,at:target)
    case .layer(let id),.mask(let id):
      let index=candidate.layers.firstIndex{$0.id==id}!,isMask:Bool;if case .mask=request.target{isMask=true}else{isMask=false};var layer=candidate.layers[index]
      let preserve = !isMask && (settings.preserveTransparency || document.isTransparencyLocked(id))
      try ClonePainter.paintTarget(mask:isMask,bounds:bounds,on:&layer,clipping:canvas,preserveTransparency:preserve){pixels,transform,_ in
        let original=pixels;try paint(&pixels,transform:transform,coverage:coverage,settings:settings,scalar:isMask,preserve:preserve,pattern:sampler,uniformInk:uniformInk);return pixels != original
      }
      candidate.layers[index]=layer
    }
    try candidate.validate();try Task.checkCancellation();document=candidate
  }
  static func outline(_ source:Surface,width:Int,location:PixelStrokeLocation)throws->Surface{
    func extremum(_ radius:Int,_ maximum:Bool)throws->Surface{try SelectionModification.strokeExtremum(source,radius:radius,maximum:maximum)}
    func subtract(_ a:Surface,_ b:Surface)throws->Surface{try a.combiningStoredSamples(with:b){x,y in let v=max(0,x.r-y.r);return Pixel(v,v,v)}}
    switch location{
    case .inside:return try subtract(source,extremum(width,false))
    case .outside:return try subtract(extremum(width,true),source)
    case .center:
      func band(_ radius:Int)throws->Surface{try subtract(extremum(radius,true),extremum(radius,false))}
      let lower=width/2,upper=(width+1)/2,a=try band(lower),b=try upper==lower ? a:band(upper)
      return try a.combiningStoredSamples(with:b){x,y in let v=(x.r+y.r)/2;return Pixel(v,v,v)}
    }
  }
  static func paint(_ pixels:inout Surface,transform:Transform2D,coverage:Surface,settings:PixelPaintSettings,scalar:Bool,preserve:Bool,invert:Bool=false,pattern:PatternSampler?=nil,uniformInk:Pixel?=nil)throws{
    let inverse=try transform.inverted(),old=pixels,canvas=IntRect(x:0,y:0,width:coverage.width,height:coverage.height),local=IntRect(x:0,y:0,width:pixels.width,height:pixels.height)
    let linear = !scalar && pixels.depth == .f32
    var constant=settings.color;if scalar{let gray=unit(0.2126*constant.r+0.7152*constant.g+0.0722*constant.b);constant=Pixel(gray,gray,gray,constant.a)}
    func painted(_ p:Pixel,_ amount:Float,_ x:Int,_ y:Int)->Pixel{
      guard amount>0,!preserve || p.a>0 else{return p}
      var color=constant
      if let sampled=uniformInk ?? pattern?.sample(x:Double(x)+0.5,y:Double(y)+0.5){color=sampled;if scalar{let gray=unit(0.2126*sampled.r+0.7152*sampled.g+0.0722*sampled.b);color=Pixel(gray,gray,gray,sampled.a)}}
      guard color.a>0 else{return p}
      if settings.mode == .normal,amount*settings.opacity==1,color.a==1{if scalar{let gray=unit(invert ? 1-color.r:color.r);return Pixel(gray,gray,gray)};return Pixel(color.r,color.g,color.b,preserve ? p.a:1)}
      let gray=unit(invert ? 1-p.r:p.r),base=scalar ? Pixel(gray,gray,gray):p,back=linear ? SRGBTransfer.linear(base):base,ink=linear ? SRGBTransfer.linear(color):color
      let value=preserve ? ProtectedPixels.composite(settings.mode,backdrop:back,source:ink,opacity:amount*settings.opacity,x:x,y:y):settings.mode.composite(backdrop:back,source:ink,opacity:amount*settings.opacity,x:x,y:y)
      let result=linear ? SRGBTransfer.encoded(value):value
      let out=unit(invert ? 1-result.r:result.r);return scalar ? Pixel(out,out,out):result
    }
    let placed=try transform.bounds(width:pixels.width,height:pixels.height)
    if (pattern==nil || uniformInk != nil),coverage.tileCount==0,coverage.defaultPixel.r>0,settings.mode != .dissolve,placed.x>=0,placed.y>=0,placed.x+placed.width<=canvas.width,placed.y+placed.height<=canvas.height{
      let encoding=pixels.colorEncoding,depth=pixels.depth
      pixels=try pixels.mappedStoredSamples{stored in let p=encoding == .linearRGB ? SRGBTransfer.encoded(stored):stored,result=painted(p,coverage.defaultPixel.r,0,0);if result.hasSameBits(as:p){return stored};return encoding == .linearRGB ? SRGBTransfer.linear(result):result}.quantizedStoredDepth(depth);return
    }
    let supports=coverage.defaultPixel.r==0 ? try coverage.projectedGeometrySupport(inverse,bounds:local,halo:1):[try inverse.bounds(width:coverage.width,height:coverage.height).clipped(toWidth:pixels.width,height:pixels.height)]
    for region in GeometryPatchRegions(width:pixels.width,height:pixels.height,rectangles:supports){
      for y in region.y..<region.y+region.height{try Task.checkCancellation();for x in region.x..<region.x+region.width{
        let q=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(q.x)),dy=Int(floor(q.y));guard canvas.contains(dx,dy) else{continue}
        let k=unit(coverage.pixel(x:dx,y:dy).r);guard k>0 else{continue};let before=old.pixel(x:x,y:y),after=painted(before,k,dx,dy)
        guard after.isFinite else{throw CraftError.invalid("Non-finite Fill/Stroke sample.")};if !after.hasSameBits(as:before){pixels.setPixel(x:x,y:y,after)}
      }}
    }
  }
}
public enum ActionPixelPaintTarget:Codable,Equatable,Sendable{
  case layer(ActionLayerTarget),mask(ActionLayerTarget),channel(ActionChannelTarget)
  public init(_ target:PixelPaintTarget,in document:CraftDocument){switch target{case .layer(let id):self = .layer(.init(id,in:document));case .mask(let id):self = .mask(.init(id,in:document));case .channel(let target):self = .channel(.init(target,in:document))}}
  public func resolve(in document:CraftDocument)throws->PixelPaintTarget{switch self{case .layer(let target):return .layer(try target.resolve(in:document));case .mask(let target):return .mask(try target.resolve(in:document));case .channel(let target):return .channel(try target.resolve(in:document))}}
}
