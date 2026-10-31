import Foundation
import PhotoCraftCore

public struct PreparedChannelArithmetic: Sendable {
  public let command: Command?
  public let newDocument: CraftDocument?
  public let channelID: UUID?
}

public enum ChannelArithmeticPreparation {
  public static func input(_ spec: ChannelArithmeticSource, destination: CraftDocument,
    sources: [CraftDocument], gray: Bool = false) throws -> ChannelArithmeticInput {
    let id=spec.documentID ?? destination.id
    guard let document=([destination]+sources).first(where:{$0.id==id}) else {
      throw CraftError.invalid("The source document is no longer available.")
    }
    try document.validate()
    guard document.width==destination.width, document.height==destination.height,
      document.depth==destination.depth else {
      throw CraftError.invalid("Source images must have matching pixel dimensions and depth.")
    }
    guard !document.colorMode.isRestricted else {
      throw CraftError.unsupported("Convert Indexed/Bitmap sources before channel blending.")
    }
    let layerID=spec.layerID ?? document.activeLayerID
    func layer() throws -> Layer {
      guard let layerID,let value=document.layers.first(where:{$0.id==layerID}) else {
        throw CraftError.invalid("The source layer is no longer available.")
      };return value
    }
    var samples:Surface, components=1
    switch spec.channel {
    case .alpha(let id):samples=try numeric(document.channel(.alpha(id)).pixels)
    case .quickMask:samples=try numeric(document.channel(.quickMask).pixels)
    case .selection:
      samples=try AlphaChannel.coverage(document.coverageSelection(),width:document.width,height:document.height,depth:.f32)
    case .ink(let target):
      samples=try document.inkChannel(target).surface().mappedStoredSamples {p in
        let v=target.inverted ? 1-p.r:p.r;return Pixel(v,v,v)
      }
    case .layerMask:
      let target=try layer()
      guard let mask=target.mask else{throw CraftError.invalid("The source layer has no pixel mask.")}
      let opaque=try numeric(mask)
      let projected=try RasterGeometry.render(opaque,transform:target.maskCoordinateTransform,
        bounds:.init(x:0,y:0,width:document.width,height:document.height),method:.nearest)
      let outside=target.effectiveMaskProperties.outside
      samples=try projected.mappedStoredSamples {p in let v=p.a==0 ? outside:p.r;return Pixel(v,v,v)}
    case .vectorMask:
      guard let mask=try layer().vectorMask else{throw CraftError.invalid("The source layer has no vector mask.")}
      samples=try VectorRasterizer.coverage(mask.path,width:document.width,height:document.height,
        emptyRevealsAll:true).coverageSurface()
    case .transparency:
      let target=try renderedLayer(try layer(),in:document)
      let surface=try Renderer.layerSurface(target,in:document)
      let projected=try RasterGeometry.render(surface,transform:target.coordinateTransform,
        bounds:.init(x:0,y:0,width:document.width,height:document.height),method:.nearest)
      samples=try projected.mappedStoredSamples {p in Pixel(p.a,p.a,p.a)}
    case .component(let c):
      guard (0..<document.colorMode.componentCount).contains(c) else{throw CraftError.invalid("Source component not found.")}
      samples=try component(c,layerID:spec.layerID,in:document)
    case .gray:
      if document.colorMode == .grayscale || document.colorMode == .duotone {
        samples=try component(0,layerID:spec.layerID,in:document)
      } else {
        let surface=try rgb(layerID:spec.layerID,in:document)
        let linear=document.depth == .f32 && surface.colorEncoding == .sRGB
        samples=try surface.mappedStoredSamples(encoding:.sRGB) {raw in
          let p=linear ? SRGBTransfer.linear(raw):raw
          let v=0.299*p.r+0.587*p.g+0.114*p.b;return Pixel(v,v,v)
        }
      }
    case .composite:
      if gray {
        var changed=spec;changed.channel = .gray;changed.invert=false
        samples=try input(changed,destination:destination,sources:sources).samples
      } else if document.colorMode == .rgb {
        components=3
        let surface=try rgb(layerID:spec.layerID,in:document)
        let linear=document.depth == .f32 && surface.colorEncoding == .sRGB
        samples=try surface.mappedStoredSamples(encoding:.sRGB) {raw in
          let p=linear ? SRGBTransfer.linear(raw):raw;return Pixel(p.r,p.g,p.b)
        }
      } else {
        let count=document.colorMode.componentCount
        guard [1,3,4].contains(count) else{throw CraftError.unsupported("Use an individual printing plate for this source mode.")}
        components=count
        var planes=[Surface]()
        for c in 0..<count {planes.append(try component(c,layerID:spec.layerID,in:document))}
        samples=planes[0]
        for c in 1..<count {
          samples=try samples.combiningStoredSamples(with:planes[c]) {p,q in
            var value=p;if c==1{value.g=q.r}else if c==2{value.b=q.r}else{value.a=q.r};return value
          }
        }
      }
    }
    if gray,components>1 {throw CraftError.invalid("Calculations requires a single source plane.")}
    if spec.invert {
      let count=components
      samples=try samples.mappedStoredSamples(encoding:.sRGB) {p in
        Pixel(1-p.r,1-p.g,1-p.b,count==4 ? 1-p.a:1)
      }
    }
    return .init(samples:samples,components:components,mode:document.colorMode)
  }

  private static func numeric(_ surface:Surface) throws -> Surface {
    try surface.mappedStoredSamples(encoding:.sRGB) {p in Pixel(p.r,p.r,p.r)}
  }
  private static func renderedLayer(_ layer:Layer,in document:CraftDocument)throws->Layer {
    if layer.smartObject?.pdfSource != nil {return try PDFSmartObjectIO.renderedLayer(layer,in:document)}
    if layer.smartFilters != nil || layer.warp != nil {return try SmartFilterEngine.renderedLayer(layer,in:document)}
    return layer
  }
  private static func rgb(layerID:UUID?,in document:CraftDocument)throws->Surface {
    guard let layerID else{return try Renderer.composite(document)}
    guard let original=document.layers.first(where:{$0.id==layerID}) else{throw CraftError.invalid("Source layer not found.")}
    if original.isGroup || {if case .adjustment=original.content{return true};return false}() {
      var proxy=document;let ids=Set(document.subtreeIDs(layerID));proxy.layers=document.layers.filter{ids.contains($0.id)}
      let i=proxy.layers.firstIndex(where:{$0.id==layerID})!
      proxy.layers[i].parentID=nil;proxy.layers[i].clipped=false;proxy.layers[i].visible=true
      proxy.activeLayerID=layerID;return try Renderer.composite(proxy)
    }
    let layer=try renderedLayer(original,in:document)
    return try RasterGeometry.render(Renderer.layerSurface(layer,in:document),
      transform:layer.coordinateTransform,
      bounds:.init(x:0,y:0,width:document.width,height:document.height),method:.nearest)
  }
  private static func component(_ c:Int,layerID:UUID?,in document:CraftDocument)throws->Surface {
    if document.colorMode == .rgb {
      let source=try rgb(layerID:layerID,in:document)
      let linear=document.depth == .f32 && source.colorEncoding == .sRGB
      return try source.mappedStoredSamples(encoding:.sRGB) {raw in
        let p=linear ? SRGBTransfer.linear(raw):raw
        let v=c==0 ? p.r:c==1 ? p.g:p.b;return Pixel(v,v,v)
      }
    }
    let candidate=layerID.flatMap{id in document.layers.first{$0.id==id}}
      ?? (document.layers.count==1 ? document.layers.first:nil)
    if let layer=candidate,
      let native=layer.nativeMode,layer.smartFilters==nil,layer.smartObject==nil,layer.warp==nil {
      let source=try native.channel(c).mappedStoredSamples {p in
        let v=native.mode == .cmyk ? 1-p.r:p.r;return Pixel(v,v,v)
      }
      return try RasterGeometry.render(source,transform:layer.coordinateTransform,
        bounds:.init(x:0,y:0,width:document.width,height:document.height),method:.nearest)
        .mappedStoredSamples {p in let v=p.a==0 && native.mode == .cmyk ? 1:p.r;return Pixel(v,v,v)}
    }
    if document.inkMode != nil {
      guard document.colorMode == .duotone else{throw CraftError.invalid("Select an individual printing plate.")}
      return try numeric(document.inkChannel(.duotone).surface())
    }
    var proxy=document
    if let layerID {
      let ids=Set(document.subtreeIDs(layerID));proxy.layers=document.layers.filter{ids.contains($0.id)}
      guard let i=proxy.layers.firstIndex(where:{$0.id==layerID}) else{throw CraftError.invalid("Source layer not found.")}
      proxy.layers[i].parentID=nil;proxy.layers[i].clipped=false;proxy.layers[i].visible=true;proxy.activeLayerID=layerID
    }
    return try numeric(ModeChannelPresentation.singleComponent(proxy,component:c))
  }

  @inline(never)
  public static func prepare(_ request:ChannelArithmeticRequest,target:ChannelArithmeticTarget?,
    document:CraftDocument,sources:[CraftDocument]=[]) throws -> PreparedChannelArithmetic {
    try request.validate();try document.validate()
    let calculation=request.kind == .calculations
    let first=try input(request.source1,destination:document,sources:sources,gray:calculation)
    let mask=try request.mask.map{try input($0,destination:document,sources:sources,gray:true).samples}
    var result=document;var channelID:UUID?
    if !calculation {
      guard let target else{throw CraftError.invalid("Choose an Apply Image destination.")}
      try ChannelArithmeticEngine.apply(first,mask:mask,options:request.options,target:target,to:&result)
    } else {
      let second=try input(request.source2,destination:document,sources:sources,gray:true)
      let output=try ChannelArithmeticEngine.calculate(first.samples,second.samples,
        mask:mask,options:request.options,depth:document.depth)
      switch request.result {
      case .newChannel:
        let channel=AlphaChannel(name:request.name ?? document.suggestedChannelName,pixels:output)
        try Command.channel(.create(channel)).apply(to:&result);channelID=channel.id
      case .selection:
        let mask=try AlphaChannel(name:"Calculations",pixels:output).selection()
        try Command.selectionCoverage(mask,.replace).apply(to:&result)
      case .newDocument:
        var created=try CraftDocument(width:document.width,height:document.height,depth:document.depth)
        created.name=request.name ?? "Untitled"
        created.resolution=document.resolution
        var native=try NativeModeRaster(width:document.width,height:document.height,mode:.grayscale,depth:document.depth)
        for y in 0..<document.height {try Task.checkCancellation();for x in 0..<document.width {
          let i=y*document.width+x;try native.set(output.pixel(x:x,y:y).r,component:0,index:i)
          try native.set(1,component:1,index:i)
        }}
        created.modeDescriptor=try .init(mode:.grayscale,depth:document.depth,profile:native.profile)
        created.layers[0].nativeMode=native;created.layers[0].content = .raster(try native.surface())
        created.layers[0].name="Background";created.layers[0].protection = .transparency
        try created.validate();return .init(command:nil,newDocument:created,channelID:nil)
      }
    }
    return .init(command:.channelArithmetic(.init(source:document,result:result,title:request.title)),
      newDocument:nil,channelID:channelID)
  }
}
