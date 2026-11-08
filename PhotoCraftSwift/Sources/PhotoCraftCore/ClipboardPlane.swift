import Foundation

public enum ClipboardPlaneTarget:Equatable,Sendable {
  case alpha(UUID),quickMask,layerMask(UUID),smartFilterMask(UUID)
  public var channel:ChannelPlaneTarget? {switch self{case .alpha(let id):.alpha(id);case .quickMask:.quickMask;default:nil}}
  public var layerID:UUID? {switch self{case .layerMask(let id),.smartFilterMask(let id):id;default:nil}}
}
public struct ClipboardPlaneImage:Sendable {
  public let values:Surface
  public let coverage:Surface
  public let bounds:IntRect
  public init(values:Surface,coverage:Surface,bounds:IntRect)throws {
    guard values.width==coverage.width,values.height==coverage.height,values.width==bounds.width,values.height==bounds.height,values.colorEncoding == .sRGB,coverage.colorEncoding == .sRGB else{throw CraftError.invalid("Clipboard grayscale and opacity layouts differ.")}
    try values.validated();try coverage.validated();self.values=values;self.coverage=coverage;self.bounds=bounds
  }
}
public struct ClipboardPlaneEdit:Sendable {
  public let source:CraftDocument
  public let result:CraftDocument
  public let target:ClipboardPlaneTarget
  public let title:String
  init(source:CraftDocument,result:CraftDocument,target:ClipboardPlaneTarget,title:String){self.source=source;self.result=result;self.target=target;self.title=title}
}
public enum ClipboardPlane {
  public static func available(_ document:CraftDocument,target:ClipboardPlaneTarget,writing:Bool=false)->Bool {
    guard !document.colorMode.isRestricted else{return false}
    if let channel=target.channel{return (try? document.channel(channel)) != nil}
    guard let id=target.layerID,let layer=document.layers.first(where:{$0.id==id}),!writing || !document.isLocked(id)else{return false}
    if case .smartFilterMask=target{return layer.smartFilters?.mask != nil};return layer.mask != nil
  }
  static func projection(_ document:CraftDocument,_ target:ClipboardPlaneTarget)throws->(Surface,Transform2D,Float) {
    guard available(document,target:target)else{throw CraftError.invalid("Choose an existing scalar channel or pixel mask.")}
    if let channel=target.channel {
      let value=try document.channel(channel)
      if let gray=value.psdSpotGray{return(gray,.identity,value.display(value.pixels.defaultPixel.r))}
      let pixels=try value.pixels.mappedStoredSamples{p in let v=value.display(p.r);return Pixel(v,v,v)}
      return(pixels,.identity,value.display(value.pixels.defaultPixel.r))
    }
    let layer=document.layers.first{$0.id==target.layerID}!
    let projected:Layer;if case .smartFilterMask=target{projected=try layer.filterMaskProjection()}else{projected=layer}
    return(projected.mask!,projected.maskCoordinateTransform,projected.effectiveMaskProperties.outside)
  }
  static func project(_ source:Surface,_ transform:Transform2D,area:IntRect,outside:Float)throws->Surface {
    if transform.a==1,transform.b==0,transform.c==0,transform.d==1,transform.tx.rounded()==transform.tx,transform.ty.rounded()==transform.ty {
      let local=IntRect(x:area.x-Int(transform.tx),y:area.y-Int(transform.ty),width:area.width,height:area.height)
      if local==local.clipped(toWidth:source.width,height:source.height){return try source.cropped(to:local)}
    }
    return try ScalarPlaneProjection.render(source,placement:.init(transform),bounds:area,exterior:outside,interpolation:.bilinear)
  }
  public static func copy(_ document:CraftDocument,target:ClipboardPlaneTarget,grayProfile:Data?=nil)throws->ClipboardContent {
    try Task.checkCancellation();try document.validate()
    let area=(document.selection ?? .init(x:0,y:0,width:document.width,height:document.height)).clipped(toWidth:document.width,height:document.height)
    guard area.width>0,area.height>0 else{throw CraftError.invalid("Select nonempty channel content to copy.")}
    let (pixels,transform,outside)=try projection(document,target)
    let values=try project(pixels,transform,area:area,outside:outside).retaggedCoverageStorage(depth:document.depth)
    let coverage:Surface
    if let selection=try document.coverageSelection(){coverage=try project(selection.coverageSurface(),.identity,area:area,outside:0).retaggedCoverageStorage(depth:document.depth)}
    else{coverage=try Surface(width:area.width,height:area.height,depth:document.depth,fill:.white)}
    var native=try NativeModeRaster(width:area.width,height:area.height,mode:.grayscale,depth:document.depth,profile:grayProfile)
    native=try native.replacingChannel(0,with:values).replacingOpacity(with:coverage)
    var d=try CraftDocument(width:area.width,height:area.height,depth:document.depth)
    d.modeDescriptor=try .init(mode:.grayscale,depth:document.depth,profile:native.profile);d.resolution=document.pixelsPerInch
    var layer=Layer(name:"Channel",content:.raster(try native.surface()));layer.nativeMode=native;layer.x=area.x;layer.y=area.y
    d.layers=[layer];d.activeLayerID=layer.id
    return try .init(kind:.pixels,document:d,bounds:area)
  }
  public static func numericImage(_ content:ClipboardContent)throws->ClipboardPlaneImage? {
    try content.validate()
    guard content.kind == .pixels,content.document.colorMode == .grayscale,let native=content.document.layers[0].nativeMode,native.mode == .grayscale else{return nil}
    return try .init(values:native.channel(0),coverage:native.opacityChannel(),bounds:content.bounds)
  }
  public static func cut(_ document:CraftDocument,target:ClipboardPlaneTarget,background:Float)throws->ClipboardPlaneEdit {
    guard background.isFinite,(0...1).contains(background),available(document,target:target,writing:true)else{throw CraftError.invalid("Choose an unlocked mask/channel and a valid gray background.")}
    let area=(document.selection ?? .init(x:0,y:0,width:document.width,height:document.height)).clipped(toWidth:document.width,height:document.height)
    let value=try Surface(width:area.width,height:area.height,depth:document.depth,fill:Pixel(background,background,background))
    let coverage=try Surface(width:area.width,height:area.height,depth:document.depth,fill:.white)
    let image=try ClipboardPlaneImage(values:value,coverage:coverage,bounds:area)
    return try edit(document,target:target,image:image,origin:.init(Double(area.x),Double(area.y)),title:"Cut",replaceSelection:false)
  }
  public static func paste(_ image:ClipboardPlaneImage,into document:CraftDocument,target:ClipboardPlaneTarget,placement:PastePlacement = .centered,center:PathPoint?=nil)throws->ClipboardPlaneEdit {
    guard placement == .centered || placement == .inPlace else{throw CraftError.unsupported("Paste Into/Outside for a channel target requires separate qualification. Use Paste or Paste In Place.")}
    let destination:PathPoint
    if placement == .inPlace{destination = .init(Double(image.bounds.x),Double(image.bounds.y))}
    else {
      let anchor:PathPoint
      if let area=document.selection{anchor = .init(Double(area.x)+Double(area.width)/2,Double(area.y)+Double(area.height)/2)}
      else{anchor=center ?? .init(Double(document.width)/2,Double(document.height)/2)}
      guard anchor.x.isFinite,anchor.y.isFinite,abs(anchor.x)<=1_000_000,abs(anchor.y)<=1_000_000 else{throw CraftError.invalid("Invalid channel paste center.")}
      destination = .init((anchor.x-Double(image.bounds.width)/2).rounded(),(anchor.y-Double(image.bounds.height)/2).rounded())
    }
    return try edit(document,target:target,image:image,origin:destination,title:placement == .inPlace ? "Paste In Place":"Paste",replaceSelection:true)
  }
  static func edit(_ source:CraftDocument,target:ClipboardPlaneTarget,image:ClipboardPlaneImage,origin:PathPoint,title:String,replaceSelection:Bool)throws->ClipboardPlaneEdit {
    try Task.checkCancellation();try source.validate()
    guard available(source,target:target,writing:true),origin.x.isFinite,origin.y.isFinite,abs(origin.x)<=1_000_000,abs(origin.y)<=1_000_000 else{throw CraftError.invalid("The clipboard destination is locked or unavailable.")}
    let canvas=IntRect(x:0,y:0,width:source.width,height:source.height),dx=Int(origin.x),dy=Int(origin.y)
    let area=IntRect(x:dx,y:dy,width:image.values.width,height:image.values.height).clipped(toWidth:source.width,height:source.height)
    guard area.width>0,area.height>0 else{throw CraftError.invalid("The pasted content lies outside the canvas.")}
    let input=try image.values.converted(to:source.depth),alpha=try image.coverage.converted(to:source.depth)
    let local=IntRect(x:area.x-dx,y:area.y-dy,width:area.width,height:area.height)
    var affected=try alpha.cropped(to:local)
    if source.selection != nil || source.selectionMask != nil {
      try affected.mapPixels(in:.init(x:0,y:0,width:affected.width,height:affected.height)){x,y,p in let v=unit(p.r)*source.selectionCoverage(x:x+area.x,y:y+area.y);return Pixel(v,v,v)}
    }
    guard try affected.scalarCoverageBounds() != nil else{return .init(source:source,result:source,target:target,title:title)}
    var result=source
    func paint(_ pixels:inout Surface,transform:Transform2D,invert:Bool=false)throws->Bool {
      let original=pixels,inverse=try transform.inverted()
      if transform == .identity,area == canvas,dx==0,dy==0,input.width==pixels.width,input.height==pixels.height,affected.tileCount==0,affected.defaultPixel.r==1,source.selection==nil,source.selectionMask==nil {
        pixels=try input.mappedStoredSamples{p in let raw=p.r,v=raw>=0 && raw<=1 ? raw:unit(raw),g=invert ? 1-v:v;return Pixel(g,g,g)}.retaggedCoverageStorage(depth:source.depth)
        return pixels != original
      }
      let localArea=try (inverse * .translation(Double(area.x),Double(area.y))).bounds(width:area.width,height:area.height).clipped(toWidth:pixels.width,height:pixels.height)
      try pixels.mapPixels(in:localArea){x,y,p in
        let point=transform.point(Double(x)+0.5,Double(y)+0.5),wx=Int(floor(point.x)),wy=Int(floor(point.y))
        guard area.contains(wx,wy)else{return p}
        let k=unit(affected.pixel(x:wx-area.x,y:wy-area.y).r);guard k>0 else{return p}
        let raw=unit(input.pixel(x:wx-dx,y:wy-dy).r),ink=invert ? 1-raw:raw
        let v=k>=1 ? ink:p.r==ink ? p.r:unit(p.r*(1-k)+ink*k)
        return Pixel(v,v,v).quantized(source.depth)
      }
      return pixels != original
    }
    if let channel=target.channel {
      var value=try source.channel(channel);let inverse=value.display(0)>0.5;_ = try paint(&value.pixels,transform:.identity,invert:inverse)
      if var retained=value.psdSpotGray{_ = try paint(&retained,transform:.identity);value.psdSpotGray=retained}
      try result.setChannel(value,at:channel)
    }else {
      let i=result.layers.firstIndex{$0.id==target.layerID}!,smart:Bool
      var layer=result.layers[i]
      if case .smartFilterMask=target{smart=true;layer=try layer.filterMaskProjection()}else{smart=false}
      _ = try ClonePainter.paintTarget(mask:true,bounds:area,on:&layer,clipping:canvas){pixels,transform,_ in try paint(&pixels,transform:transform)}
      if smart {
        result.layers[i].smartFilters!.mask=layer.mask
        var properties=layer.effectiveMaskProperties;properties.transform=layer.maskCoordinateTransform
        result.layers[i].smartFilters!.maskProperties=properties
      }else{result.layers[i]=layer}
    }
    if replaceSelection {
      let full=try affected.expanded(to:.init(x:-area.x,y:-area.y,width:source.width,height:source.height),fill:.black,preservingFillBits:true)
      result.setCoverageSelection(try SelectionMask(coverage:full))
    }
    try result.validate();try Task.checkCancellation()
    return .init(source:source,result:result,target:target,title:title)
  }
}
extension PreparedEdit {
  public init(clipboardPlane edit:ClipboardPlaneEdit)throws {
    try edit.result.validate()
    try self.init(command:.preparedAction(.init(source:edit.source,result:edit.result,title:edit.title,recording:.unsupported("Mask/channel clipboard recording is not yet supported."))),document:edit.source)
    clipboardPlaneTarget=edit.target
  }
}
