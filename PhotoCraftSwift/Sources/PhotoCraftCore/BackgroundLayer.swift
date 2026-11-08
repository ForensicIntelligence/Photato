import Foundation

public enum BackgroundLayerEdit:Codable,Equatable,Sendable {
  case toLayer(UUID,NewPixelLayerOptions)
  case fromLayer(UUID,Pixel)
  case clear(UUID,Pixel)
  public var layerID:UUID {switch self{case .toLayer(let id,_),.fromLayer(let id,_),.clear(let id,_):id}}
  public var label:String {switch self{case .toLayer:"Layer from Background";case .fromLayer:"Background from Layer";case .clear:"Clear"}}
}
extension Layer {
  public var isBackground:Bool {background == true}
  public func backgroundBrush(_ incoming:Brush)->Brush {
    guard isBackground,incoming.erase else{return incoming}
    var brush=incoming;brush.erase=false;brush.color=incoming.backgroundColor ?? .white;return brush
  }
}
public enum BackgroundLayer {
  public static func canConvert(_ document:CraftDocument,layerID:UUID)->Bool {
    guard document.animation==nil,document.videoTimeline==nil,
      let layer=document.layers.first(where:{$0.id==layerID}),case .raster=layer.content else{return false}
    if layer.isBackground{return true}
    return document.colorMode == .rgb && !document.layers.contains(where:{$0.isBackground}) && !document.isImageLocked(layerID) && !document.isPositionLocked(layerID)
      && layer.parentID==nil && !layer.isClipped && layer.mask==nil && layer.vectorMask==nil && layer.style==nil
      && layer.smartObject==nil && layer.sourceProjection==nil && layer.warp==nil && layer.smartFilters==nil
  }
  public static func apply(_ edit:BackgroundLayerEdit,to document:inout CraftDocument)throws {
    try Task.checkCancellation()
    guard let i=document.layers.firstIndex(where:{$0.id==edit.layerID}) else{throw CraftError.invalid("Layer no longer exists.")}
    switch edit {
    case .toLayer(_,let options):
      guard document.layers[i].isBackground,!options.clipped,!options.neutralFill else{throw CraftError.invalid("Select the Background layer.")}
      _ = try options.layer(in:document)
      var layer=document.layers[i];layer.background=nil;layer.protection=[];layer.name=options.name;layer.opacity=options.opacity;layer.blendMode=options.mode
      if options.color != .none || layer.colorLabel != .none{layer.colorLabel=options.color}
      if layer.sourceTags?["lyid"]==Data(repeating:0,count:4){layer.sourceTags?.removeValue(forKey:"lyid")}
      document.layers[i]=layer
    case .fromLayer(_,let color):
      guard canConvert(document,layerID:edit.layerID),!document.layers[i].isBackground,case .raster(let source)=document.layers[i].content else{throw CraftError.unsupported("Convert one unlocked ordinary RGB raster layer without masks/styles into Background. Other contexts require separate preparation.")}
      try validate(color)
      let aligned=try RasterGeometry.render(source,transform:document.layers[i].coordinateTransform,bounds:.init(x:0,y:0,width:document.width,height:document.height),method:.nearest)
      var layer=document.layers.remove(at:i);layer.content = .raster(try opaque(aligned,over:color));layer.nativeMode=nil;layer.background=true;layer.name="Background";layer.parentID=nil;layer.clipped=nil;layer.blendMode = .normal;layer.opacity=1;layer.protection=[];layer.x=0;layer.y=0;layer.affine=nil
      layer.sourceTags=layer.sourceTags ?? [:];layer.sourceTags?["lyid"]=Data(repeating:0,count:4)
      document.layers.insert(layer,at:0)
    case .clear(_,let color):
      guard (document.colorMode == .rgb || (document.colorMode == .grayscale && document.layers[i].nativeMode != nil)),document.layers[i].isBackground,!document.isImageLocked(edit.layerID),case .raster(let source)=document.layers[i].content else{throw CraftError.invalid("Choose an editable Background pixel layer.")};try validate(color)
      let area=document.selection ?? .init(x:0,y:0,width:document.width,height:document.height),mask=try document.coverageSelection(),linear=source.colorEncoding == .linearRGB,fill=linear ? SRGBTransfer.linear(color):color
      if mask==nil {document.layers[i].content = .raster(try Surface(width:source.width,height:source.height,depth:source.depth,fill:color,colorEncoding:source.colorEncoding));return}
      var result=source
      let support=try mask!.coverageSurface(),regions=support.defaultPixel.r==0 && support.tileCount<=RasterGeometry.sparseGridSourceTileLimit ? try support.projectedGeometrySupport(.identity,bounds:area,halo:0).map{IntRect(x:$0.x+area.x,y:$0.y+area.y,width:$0.width,height:$0.height)}:[area]
      for rect in GeometryPatchRegions(width:source.width,height:source.height,rectangles:regions) {for y in rect.y..<(rect.y+rect.height){try Task.checkCancellation();for x in rect.x..<(rect.x+rect.width){let k=mask!.coverage(x:x,y:y);if k==0{continue};let old=linear ? source.linearPixel(x:x,y:y):source.pixel(x:x,y:y),p=Pixel(old.r*(1-k)+fill.r*k,old.g*(1-k)+fill.g*k,old.b*(1-k)+fill.b*k,1);if linear{result.setLinearPixel(x:x,y:y,p)}else{result.setPixel(x:x,y:y,p)}}}}
      document.layers[i].content = .raster(result)
    }
  }
  public static func validate(_ color:Pixel)throws {guard color.isFinite,color.a==1 else{throw CraftError.invalid("Background fill must be an opaque finite color.")}}
  public static func opaque(_ source:Surface,over color:Pixel)throws->Surface {
    try validate(color)
    if try source.isOpaque() { return source }
    let linear = source.colorEncoding == .linearRGB
    let fill = linear ? SRGBTransfer.linear(color) : color
    func opaque(_ p: Pixel) -> Pixel {
      if p.a == 1 { return p }
      if p.a <= 0 { return fill }
      return Pixel(p.r*p.a+fill.r*(1-p.a), p.g*p.a+fill.g*(1-p.a), p.b*p.a+fill.b*(1-p.a), 1)
    }
    let rawDefault = linear ? try source.interpretingSamples(as: .sRGB).defaultPixel : source.defaultPixel
    let newDefault = opaque(rawDefault)
    let template = try Surface(width:source.width,height:source.height,depth:source.depth,fill:newDefault).interpretingSamples(as:source.colorEncoding)
    let builder = try Surface.PagedBuilder(template:template)
    let side = Surface.tileSide, columns = (source.width+side-1)/side
    for key in source.storedTileKeys {
      try Task.checkCancellation()
      let left = key%columns*side, top = key/columns*side
      let width = min(side,source.width-left), height = min(side,source.height-top)
      var patch = try Surface(width:width,height:height,depth:source.depth,fill:newDefault).interpretingSamples(as:source.colorEncoding)
      for y in 0..<height { for x in 0..<width {
        let p = linear ? source.linearPixel(x:left+x,y:top+y) : source.pixel(x:left+x,y:top+y)
        if p.a == 1 { patch.copyStoredSample(from:source,x:left+x,y:top+y,toX:x,toY:y) }
        else { let value = opaque(p); if linear {patch.setLinearPixel(x:x,y:y,value)} else {patch.setPixel(x:x,y:y,value)} }
      } }
      try builder.append(patch,atX:left,atY:top)
    }
    return try builder.finish()
  }
}
extension CraftDocument {
  func validateBackground()throws {
    let backgrounds=layers.enumerated().filter{$0.element.isBackground};guard backgrounds.count<=1 else{throw CraftError.invalid("A document has only one Background layer.")}
    guard let (i,layer)=backgrounds.first else{return}
    guard i==0,layer.parentID==nil,!layer.isClipped,layer.opacity==1,layer.blendMode == .normal,layer.x==0,layer.y==0,layer.affine==nil,
      layer.mask==nil,layer.vectorMask==nil,layer.style==nil,layer.smartObject==nil,layer.smartFilters==nil,layer.warp==nil,layer.sourceProjection==nil,case .raster(let pixels)=layer.content,pixels.width==width,pixels.height==height,try pixels.isOpaque() else{throw CraftError.invalid("Background must remain the opaque bottom canvas layer. Convert it to a regular layer first.")}
  }
}

public enum BackgroundLayerAction:Codable,Sendable {
  case toLayer(ActionLayerTarget,NewPixelLayerOptions),fromLayer(ActionLayerTarget,Pixel),clear(ActionLayerTarget,Pixel)
  public init(_ edit:BackgroundLayerEdit,in document:CraftDocument) {let target=ActionLayerTarget(edit.layerID,in:document);switch edit {case .toLayer(_,let options):self = .toLayer(target,options);case .fromLayer(_,let color):self = .fromLayer(target,color);case .clear(_,let color):self = .clear(target,color)}}
  public func edit(in document:CraftDocument)throws->BackgroundLayerEdit {switch self{case .toLayer(let target,let options):return .toLayer(try target.resolve(in:document),options);case .fromLayer(let target,let color):return .fromLayer(try target.resolve(in:document),color);case .clear(let target,let color):return .clear(try target.resolve(in:document),color)}}
}

extension CraftDocument {
  mutating func reframeBackground(over color:Pixel = .white)throws {
    guard let i=layers.firstIndex(where:{$0.isBackground}),case .raster(let pixels)=layers[i].content else{return}
    let surface=try RasterGeometry.render(pixels,transform:layers[i].coordinateTransform,bounds:.init(x:0,y:0,width:width,height:height),method:.nearest)
    layers[i].content = .raster(try BackgroundLayer.opaque(surface,over:color));layers[i].x=0;layers[i].y=0;layers[i].affine=nil
  }
}
