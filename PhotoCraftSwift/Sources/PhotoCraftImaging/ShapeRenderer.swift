import Foundation
import CoreGraphics
import PhotoCraftCore

public enum ShapeRenderer {
  /// Layer caches are bounded by the visible canvas while editable path and
  /// transform state stay in the original layer's coordinates.
  public static func rasterInput(_ layer: Layer, in document: CraftDocument) throws -> Layer {
    try layer.framingShapeExterior(to: .init(x: 0, y: 0, width: document.width, height: document.height))
  }

  /// Solve each primitive's internal contours before applying the layer's component operation.
  public static func outline(_ definition:ShapeDefinition)throws->CGPath{
    try definition.validate()
    if let frame = definition.exteriorFrame {
      let region = try VectorPathGeometry.filledRegion(definition.path())
      return region.inverted ? exterior(frame).subtracting(region.path) : region.path
    }
    var result:CGPath?
    for part in definition.components {
      var primitive=try part.path();primitive.fillRule=definition.fillRule
      let next=try VectorRasterizer.filledPath(primitive)
      guard let previous=result else{result=next;continue}
      switch part.operation {case .combine,.join:result=previous.union(next);case .subtract:result=previous.subtracting(next);case .intersect:result=previous.intersection(next);case .exclude:result=previous.symmetricDifference(next)}
    }
    let combined=result ?? CGMutablePath()
    if definition.inverted == true,let bounds=definition.inversionBounds {
      let frame=CGPath(rect:CGRect(x:bounds.x,y:bounds.y,width:bounds.width,height:bounds.height),transform:nil)
      return frame.subtracting(combined)
    }
    return combined
  }
  public static func vectorPath(_ definition:ShapeDefinition)throws->VectorPath{
    let outline=try outline(definition)
    if outline.isEmpty{return VectorPath()}
    let (path,bounds)=try FrameRenderer.normalized(outline)
    return path.transformed(.translation(Double(bounds.x),Double(bounds.y)) * .scale(Double(bounds.width),Double(bounds.height)))
  }
  private static func exterior(_ frame: Transform2D) -> CGPath {
    var transform = CGAffineTransform(a: frame.a, b: frame.b, c: frame.c, d: frame.d, tx: frame.tx, ty: frame.ty)
    return CGPath(rect: CGRect(x: 0, y: 0, width: 1, height: 1), transform: &transform)
  }

  static func strokeOutline(_ definition: ShapeDefinition, fillPath: CGPath,
                            visibleContours: CGPath? = nil) throws -> CGPath? {
    let stroke = definition.stroke
    guard stroke.paint.kind != .none, stroke.width > 0, (stroke.opacity ?? 1) > 0 else { return nil }
    let sourcePath = try definition.path()
    let centerline = try stroke.pathContours == true ? VectorRasterizer.outline(sourcePath) : visibleContours ?? fillPath
    let factor = stroke.widthRelativeDashes == true ? stroke.width : 1
    let line = stroke.dash.isEmpty ? centerline : centerline.copy(dashingWithPhase: stroke.phase * factor, lengths: stroke.dash.map { CGFloat($0 * factor) })
    let aligned = stroke.pathContours != true || sourcePath.components.allSatisfy { $0.closed }
    let alignment = aligned ? stroke.alignment : .center
    let cap: CGLineCap = stroke.cap == .butt ? .butt : stroke.cap == .round ? .round : .square
    let join: CGLineJoin = stroke.join == .miter ? .miter : stroke.join == .round ? .round : .bevel
    let edge = line.copy(strokingWithWidth: stroke.width * (alignment == .center ? 1 : 2),
      lineCap: cap, lineJoin: join, miterLimit: stroke.miterLimit)
    if alignment == .inside { return edge.intersection(fillPath) }
    if alignment == .outside { return edge.subtracting(fillPath) }
    return edge
  }
  static func surface(_ definition:ShapeDefinition,layer:Layer,document:CraftDocument)throws->Surface{
    try definition.validate(in:document)
    if let shape=layer.shape,let original=shape.importedAppearance,original.definition==definition,let pixels=original.pixels {return pixels}
    let bounds = try definition.renderBounds()
    var frame: CGPath?, visibleContours: CGPath?
    let path: CGPath
    if let mapping = definition.exteriorFrame {
      let region = try VectorPathGeometry.filledRegion(definition.path())
      if region.inverted {
        let clip = exterior(mapping)
        if let sparse = try sparseExterior(definition, holes: region.path, frame: clip,
                                            mapping: mapping, bounds: bounds, depth: document.depth) {
          return sparse
        }
        guard bounds.width <= Surface.maximumDensePixels / bounds.height else {
          throw CraftError.unsupported("Large shape exteriors currently require an integer-aligned solid fill without a visible stroke.")
        }
        frame = clip
        visibleContours = region.path
        path = clip.subtracting(region.path)
      } else {
        path = region.path
      }
    } else {
      path = try outline(definition)
    }
    let fillMask=try FrameRenderer.coverage(path,region:bounds)
    let stroke = definition.stroke
    let strokeMask = try strokeOutline(definition, fillPath: path, visibleContours: visibleContours).map { edge in
      try FrameRenderer.coverage(frame?.intersection(edge) ?? edge, region: bounds)
    }
    let fill=try Paint(definition.fill,bounds:bounds,frame:definition.paintFrame,layer:layer,document:document),edge=try Paint(stroke.paint,bounds:bounds,frame:definition.paintFrame,layer:layer,document:document)
    var output=try Surface(width:bounds.width,height:bounds.height,depth:document.depth)
    for y in 0..<bounds.height {try Task.checkCancellation();for x in 0..<bounds.width {
      let i=y*bounds.width+x,lx=x+bounds.x,ly=y+bounds.y
      var pixel=fill.sample(lx,ly);pixel.a *= Float(fillMask.byte(at:i))/255
      if let strokeMask,strokeMask.byte(at:i)>0 {var color=edge.sample(lx,ly);color.a *= Float(strokeMask.byte(at:i))/255 * (stroke.opacity ?? 1);pixel=Renderer.compositePixel(.normal,backdrop:pixel,source:color,opacity:1,depth:document.depth,x:lx,y:ly)}
      if pixel.a>0{output.setPixel(x:x,y:y,pixel)}
    }}
    return output
  }
  private static func sparseExterior(_ definition: ShapeDefinition, holes: CGPath, frame: CGPath,
                                     mapping: Transform2D, bounds: IntRect, depth: PixelDepth) throws -> Surface? {
    let storage = CGRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height)
    guard definition.fill.kind == .solid || definition.fill.kind == .none,
          definition.stroke.paint.kind == .none || definition.stroke.width == 0 || definition.stroke.opacity == 0,
          frame.boundingBoxOfPath == storage,
          (mapping.b == 0 && mapping.c == 0) || (mapping.a == 0 && mapping.d == 0) else { return nil }
    let fill = definition.fill.kind == .none ? Pixel.clear : definition.fill.color
    var surface = try Surface(width: bounds.width, height: bounds.height, depth: depth, fill: fill.a == 0 ? .clear : fill)
    let holeBounds = holes.boundingBoxOfPath
    guard fill.a > 0, !holeBounds.isNull else { return surface }
    let overlap = storage.intersection(holeBounds.integral)
    guard !overlap.isNull, !overlap.isEmpty else { return surface }
    let patch = IntRect(x: Int(overlap.minX), y: Int(overlap.minY), width: Int(overlap.width), height: Int(overlap.height))
    // Render the same complemented path over the smaller window. Subtracting
    // a quantized mask from 255 can round the antialiased edge differently.
    let mask = try FrameRenderer.coverage(frame.subtracting(holes), region: patch)
    try surface.mapPixels(in: .init(x: patch.x - bounds.x, y: patch.y - bounds.y, width: patch.width, height: patch.height)) { x, y, _ in
      let i = (y + bounds.y - patch.y) * patch.width + x + bounds.x - patch.x
      var pixel = fill
      pixel.a *= Float(mask.byte(at: i)) / 255
      return pixel.a > 0 ? pixel : .clear
    }
    return surface
  }
  private struct Paint{
    let paint:ShapePaint,transform:Transform2D
    let sourceFrame:ShapePaintFrame?
    let ramp:GradientRamp?,field:GradientField?,pattern:PatternFillSampler?
    init(_ paint:ShapePaint,bounds:IntRect,frame:ShapePaintFrame?,layer:Layer,document:CraftDocument)throws{
      self.paint=paint;sourceFrame=frame;transform=try layer.shapeTransform()
      if let gradient=paint.gradient {
        ramp=try GradientRamp(gradient.gradient)
        let frame=gradient.aligned ? bounds:IntRect(x:0,y:0,width:document.width,height:document.height)
        field=try GradientField(gradient.placement,frame:frame)
      }else{ramp=nil;field=nil}
      pattern=try paint.pattern.map{try PatternFillSampler($0,in:document)}
    }
    func sourceParameter(_ frame:ShapePaintFrame,x:Double,y:Double)->Float {
      let p=paint.gradient!.placement,w=max(1,frame.width),h=max(1,frame.height)
      let a=Double(p.angle)*Double.pi/180,s=sin(a),c=cos(a)
      let dx=x-(frame.x+w/2+Double(p.offsetX)*w),dy=y-(frame.y+h/2+Double(p.offsetY)*h)
      let along=dx*c-dy*s,across=dx*s+dy*c,len=max(1,hypot(c*w,s*h))*Double(max(0.001,p.scale))
      let t:Double
      switch p.style {
      case .linear:t=along/len+0.5
      case .reflected:t=abs(along/(len/2))
      case .radial:t=hypot(dx,dy)/(len/2)
      case .diamond:t=(abs(along)+abs(across))/(len/2)
      case .angle:let raw=(a-atan2(-dy,dx))/(2*Double.pi);t=raw-floor(raw)
      }
      let value=Float(min(1,max(0,t)));return p.reverse ? 1-value:value
    }
    func sample(_ x:Int,_ y:Int)->Pixel{
      switch paint.kind{
      case .none:return .clear
      case .solid:return paint.color
      case .gradient:
        let p=paint.gradient!.aligned ? (x:Double(x)+0.5,y:Double(y)+0.5):transform.point(Double(x)+0.5,Double(y)+0.5)
        let color=ramp!.sample((paint.gradient!.aligned ? sourceFrame.map{sourceParameter($0,x:p.x,y:p.y)}:nil) ?? field!.parameter(x:Float(p.x),y:Float(p.y)))
        return paint.gradient!.dither ? GradientRamp.dither(color,x:x,y:y):color
      case .pattern:
        let p=paint.pattern!.linked ? (x:Double(x)+0.5,y:Double(y)+0.5):transform.point(Double(x)+0.5,Double(y)+0.5)
        return pattern!.sample(x:p.x,y:p.y)
      }
    }
  }
  public static func creation(_ definition:ShapeDefinition,name:String,placement:Transform2D,mode:ShapeOutputMode,target:UUID?,document:CraftDocument,patterns:[RasterPattern]=[])throws->Command{
    try definition.validate();try placement.validated()
    switch mode{
    case .shape:return .shape(.create(name,definition,placement,patterns:patterns))
    case .path:
      let editable = try definition.path()
      let outline = try editable.components.first?.operation == .subtract ? editable : vectorPath(definition)
      var path=NamedPath(name:name,path:outline.transformed(placement),isWorkPath:true)
      if let old=document.paths?.first(where:\.isWorkPath){path.id=old.id}
      return .savePath(path)
    case .pixels:
      guard let id=target,let layer=document.layers.first(where:{$0.id==id}),!document.isImageLocked(id),!document.isLocked(id),layer.smartObject==nil,case .raster(var pixels)=layer.content else{throw CraftError.invalid("Pixels mode requires an unlocked raster layer.")}
      var rendered=document;try Command.shape(.create(name,definition,placement,patterns:patterns)).apply(to:&rendered)
      let drawn=rendered.layers.first{$0.id==rendered.activeLayerID}!,source=try Renderer.layerSurface(drawn,in:rendered),inverse=try drawn.coordinateTransform.inverted()
      let surfaceToDocument=layer.coordinateTransform
      for y in 0..<pixels.height {try Task.checkCancellation();for x in 0..<pixels.width{
        let p=surfaceToDocument.point(Double(x)+0.5,Double(y)+0.5),q=inverse.point(p.x,p.y)
        var color=RasterGeometry.sample(source,x:q.x,y:q.y,method:.bilinear)
        color.a *= document.selectionMask?.coverage(x:Int(floor(p.x)),y:Int(floor(p.y))) ?? (document.selection.map{$0.contains(Int(floor(p.x)),Int(floor(p.y))) ? Float(1):0} ?? 1)
        let old=pixels.pixel(x:x,y:y)
        if document.isTransparencyLocked(id){color.a *= old.a}
        var result=Renderer.compositePixel(.normal,backdrop:old,source:color,opacity:1,depth:document.depth,x:x,y:y)
        if document.isTransparencyLocked(id){result.a=old.a}
        pixels.setPixel(x:x,y:y,result)
      }}
      return .replaceContent(id,.raster(pixels))
    }
  }
}
