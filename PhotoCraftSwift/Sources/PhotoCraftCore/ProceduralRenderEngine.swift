import Foundation

public struct ProceduralRenderRequest:Codable,Equatable,Sendable {
  public var settings:ProceduralRenderSettings
  public var layerID:UUID?
  public var newLayer=false
  public var path:VectorPath?
  public init(_ settings:ProceduralRenderSettings,layerID:UUID?=nil,newLayer:Bool=false,path:VectorPath?=nil) {self.settings=settings;self.layerID=layerID;self.newLayer=newLayer;self.path=path}
  public func validate()throws {try settings.validate();try path?.validate();if settings.kind != .flame && path != nil {throw CraftError.invalid("Only Flame accepts a path.")}}
}
public enum ProceduralRenderEngine {
  public static let maximumPixels=8_388_608
  typealias Geometry=ProceduralGeometry
  struct Paint {var rect:IntRect,values:[Geometry.Color],count:Int}
  static func primitives(_ settings:ProceduralRenderSettings,width:Int,height:Int,paths:[[PathPoint]])throws->[Geometry.Primitive] {
    try settings.validate();guard width>0,height>0,width<=Surface.maxDimension,height<=Surface.maxDimension,width<=maximumPixels/height else {throw CraftError.unsupported("Procedural Render supports canvases up to8,388,608 pixels.")}
    switch settings.kind {
    case .flame:guard !paths.isEmpty else{throw CraftError.invalid("Flame requires a path. Draw or select a path before rendering.")};return try Geometry.flame(settings.flame,paths:paths.map{$0.map{Geometry.Point(Float($0.x),Float($0.y))}})
    case .tree:return try Geometry.tree(settings.tree,width:width,height:height)
    case .pictureFrame:return try Geometry.pictureFrame(settings.frame,width:width,height:height)
    }
  }
  static func paint(_ settings:ProceduralRenderSettings,width:Int,height:Int,paths:[[PathPoint]],clip:IntRect?=nil)throws->Paint? {
    let primitives=try primitives(settings,width:width,height:height,paths:paths),clip=(clip ?? IntRect(x:0,y:0,width:width,height:height)).clipped(toWidth:width,height:height)
    var x0=width,y0=height,x1=0,y1=0
    for p in primitives {let b=p.bounds.clipped(toWidth:width,height:height),left=max(b.x,clip.x),top=max(b.y,clip.y),right=min(b.x+b.width,clip.x+clip.width),bottom=min(b.y+b.height,clip.y+clip.height)
      if right>left && bottom>top{x0=min(x0,left);y0=min(y0,top);x1=max(x1,right);y1=max(y1,bottom)}}
    guard x1>x0,y1>y0 else{return nil}
    let rect=IntRect(x:x0,y:y0,width:x1-x0,height:y1-y0)
    return Paint(rect:rect,values:try Geometry.rasterize(primitives,in:rect),count:primitives.count)
  }
  static func over(_ paint:Geometry.Color,_ before:Pixel,coverage:Float,preserve:Bool)->Pixel {
    let sa=Geometry.clamp(paint.w)*coverage;guard sa>0,!preserve || before.a>0 else{return before}
    let inv:Float=1/max(paint.w,1e-6),sc=SIMD3<Float>(Geometry.clamp(paint.x*inv),Geometry.clamp(paint.y*inv),Geometry.clamp(paint.z*inv))
    // Transparency locking changes colors only; untouched transparent RGB bits remain intact.
    if preserve {let c=sc*sa+before.rgb*(1-sa);return Pixel(c.x,c.y,c.z,before.a)}
    let oa=sa+before.a*(1-sa)
    func mix(_ s:Float,_ d:Float)->Float {oa>1e-7 ? (s*sa+d*before.a*(1-sa))/oa:0}
    return Pixel(mix(sc.x,before.r),mix(sc.y,before.g),mix(sc.z,before.b),oa)
  }
  static func composite(_ paint:Paint,into pixels:inout Surface,transform:Transform2D,coverage:(Int,Int)->Float,preserve:Bool)throws->Bool {
    guard pixels.width<=maximumPixels/pixels.height else{throw CraftError.unsupported("Expanded Render storage exceeds8,388,608 pixels.")}
    var changed=false
    for y in 0..<pixels.height {try Task.checkCancellation();for x in 0..<pixels.width {
      let q=transform.point(Double(x)+0.5,Double(y)+0.5),dx=Int(floor(q.x)),dy=Int(floor(q.y))
      guard paint.rect.contains(dx,dy) else{continue};let mask=coverage(dx,dy);guard mask>0 else{continue}
      let p=paint.values[(dy-paint.rect.y)*paint.rect.width+dx-paint.rect.x];guard p.w>0 else{continue}
      let before=pixels.pixel(x:x,y:y);guard before.isFinite,max(abs(before.r),abs(before.g),abs(before.b))<=1e12 else{throw CraftError.invalid("Render input exceeds supported numeric limits.")}
      let value=over(p,before,coverage:mask,preserve:preserve)
      if !value.hasSameBits(as:before){pixels.setPixel(x:x,y:y,value);changed=true}
    }};return changed
  }
  public static func render(_ source:Surface,settings:ProceduralRenderSettings,paths:[[PathPoint]]=[] )throws->Surface {
    guard let paint=try paint(settings,width:source.width,height:source.height,paths:paths) else{return source};var result=source
    _=try composite(paint,into:&result,transform:.identity,coverage:{_,_ in 1},preserve:false);return result
  }
  public static func resolvedPath(_ request:ProceduralRenderRequest,in document:CraftDocument)->VectorPath? {
    request.path ?? document.paths?.first(where:{$0.isWorkPath})?.path ?? document.paths?.first?.path
  }
  static func apply(_ request:ProceduralRenderRequest,to document:inout CraftDocument)throws {
    try request.validate();let original=document;var candidate=document
    if let id=request.layerID {guard candidate.layers.contains(where:{$0.id==id}) else{throw CraftError.invalid("Render layer no longer exists.")};candidate.activeLayerID=id}
    let paths:[[PathPoint]]
    if request.settings.kind == .flame {
      guard let path=resolvedPath(request,in:original) else{throw CraftError.invalid("Flame requires a path.")}
      paths=try path.components.map {try PathConstruction.flattened($0,tolerance:0.5)}
    }else{paths=[]}
    guard candidate.width<=maximumPixels/candidate.height else{throw CraftError.unsupported("Render canvas exceeds8,388,608 pixels.")}
    if request.newLayer {var layer=try NewPixelLayerOptions(name:request.settings.kind.title).layer(in:candidate)
      if candidate.depth == .f32 {layer.content = .raster(try Surface(width:candidate.width,height:candidate.height,depth:.f32,colorEncoding:.linearRGB))}
      try candidate.insertNewLayer(layer)
    }
    guard let index=candidate.activeIndex else{throw CraftError.invalid("Choose a pixel layer or create a new layer.")}
    var layer=candidate.layers[index]
    guard !candidate.isImageLocked(layer.id),!candidate.isLocked(layer.id) else{throw CraftError.invalid("Unlock this layer and its parents before rendering.")}
    guard case .raster=layer.content,layer.smartObject==nil else{throw CraftError.unsupported("Rasterize the target or choose New Layer; these Render effects are not Smart Filters.")}
    let clip=(candidate.selection ?? IntRect(x:0,y:0,width:candidate.width,height:candidate.height)).clipped(toWidth:candidate.width,height:candidate.height)
    guard let paint=try paint(request.settings,width:candidate.width,height:candidate.height,paths:paths,clip:clip) else{return}
    let preserve=candidate.isTransparencyLocked(layer.id)
    let changed=try ClonePainter.paintTarget(mask:false,bounds:paint.rect,on:&layer,clipping:clip,preserveTransparency:preserve) {pixels,transform,_ in
      try composite(paint,into:&pixels,transform:transform,coverage:{original.selectionCoverage(x:$0,y:$1)},preserve:preserve)
    }
    guard changed else{return};candidate.layers[index]=layer
    // A targeted edit does not change the user's active layer unless a new layer was created.
    if !request.newLayer {candidate.activeLayerID=original.activeLayerID}
    try Task.checkCancellation();try candidate.validate();document=candidate
  }
}
