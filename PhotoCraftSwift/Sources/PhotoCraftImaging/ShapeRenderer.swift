import Foundation
import CoreGraphics
import PhotoCraftCore

public enum ShapeRenderer {
  /// Layer caches are bounded by the visible canvas while editable path and
  /// transform state stay in the original layer's coordinates.
  public static func rasterInput(_ layer: Layer, in document: CraftDocument) throws -> Layer {
    try layer.repaintingUnlinkedShapePattern()
      .framingShapeExterior(to: .init(x: 0, y: 0, width: document.width, height: document.height))
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
  static func surface(_ definition: ShapeDefinition, layer: Layer, document: CraftDocument) throws -> Surface {
    try definition.validate(in: document)
    if let pixels = cachedPixels(definition, layer: layer) { return pixels }
    let plan = try RasterPlan(definition, layer: layer, document: document)
    // Direct layer readers use the supplied layer's bounds and placement. The
    // document compositor prepares a rebased layer before sampling it.
    if let appearance = layer.shape?.importedAppearance, appearance.definition == definition,
      let previous = appearance.documentPatternPlacement, previous != layer.coordinateTransform,
      let shape = layer.shape {
      return try plan.render(shape.renderBounds())
    }
    if let solid = try plan.solidExterior() { return solid }
    let bounds = plan.bounds
    if !isLarge(bounds) { return try plan.render(bounds) }
    return try plan.pagedSurface(fill: .clear,
      support: [.init(x: 0, y: 0, width: bounds.width, height: bounds.height)])
  }

  /// Preserve the fast implicit-color path for aligned solid exteriors. Other
  /// live exteriors sample just the local raster required by the compositor.
  public static func usesViewportRaster(_ layer: Layer) -> Bool {
    guard let shape = layer.shape, let definition = shape.definition,
          let frame = definition.exteriorFrame, cachedPixels(definition, layer: layer) == nil else { return false }
    return exteriorDefault(definition) == nil || !integerRectangle(frame)
      || (visibleStroke(definition.stroke) && shape.width > Surface.maximumDensePixels / shape.height)
  }

  static func hasImplicitExterior(_ definition: ShapeDefinition) -> Bool {
    guard let frame = definition.exteriorFrame else { return false }
    return exteriorDefault(definition) != nil && integerRectangle(frame)
  }

  /// Large live exteriors can report their visible geometry without rasterizing
  /// the entire layer for Move, Free Transform or alignment.
  public static func largeExteriorBounds(_ layer: Layer, in document: CraftDocument) throws -> IntRect? {
    let layer = try rasterInput(layer, in: document)
    guard let shape = layer.shape, let definition = shape.definition,
          definition.exteriorFrame != nil, shape.width > Surface.maximumDensePixels / shape.height else { return nil }
    let plan = try RasterPlan(definition, layer: layer, document: document)
    let t = try layer.shapeTransform()
    var transform = CGAffineTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty)
    let paths = [definition.fill.kind == .none ? nil : plan.fillPath, plan.strokePath]
    let box = paths.compactMap { $0?.copy(using: &transform)?.boundingBoxOfPath }
      .reduce(CGRect.null) { $0.union($1) }
    return intersect(box.integral, .init(x: 0, y: 0, width: document.width, height: document.height))
  }

  struct RasterPatch {
    let surface: Surface
    /// Offset within the layer's raster, before the layer placement.
    let x: Int
    let y: Int
  }

  static func viewportRaster(_ layer: Layer, in document: CraftDocument,
                             region: IntRect) throws -> RasterPatch? {
    guard let definition = layer.shape?.definition else { return nil }
    let plan = try RasterPlan(definition, layer: layer, document: document)
    let inverse = try layer.coordinateTransform.inverted()
    let farX = Double(region.x + region.width), farY = Double(region.y + region.height)
    let corners = [inverse.point(Double(region.x), Double(region.y)),
                   inverse.point(farX, Double(region.y)),
                   inverse.point(Double(region.x), farY),
                   inverse.point(farX, farY)]
    let left = corners.map(\.x).min()!, top = corners.map(\.y).min()!
    let right = corners.map(\.x).max()!, bottom = corners.map(\.y).max()!
    // Bilinear sampling can read the adjoining source pixel on each side.
    let halo = layer.affine == nil ? 0.0 : 1.0
    let sourceBox = CGRect(x: floor(left - halo), y: floor(top - halo),
      width: ceil(right + halo) - floor(left - halo), height: ceil(bottom + halo) - floor(top - halo))
    guard let patch = intersect(sourceBox, .init(x: 0, y: 0, width: plan.bounds.width,
                                                height: plan.bounds.height)) else { return nil }
    let work = IntRect(x: patch.x + plan.bounds.x, y: patch.y + plan.bounds.y,
                       width: patch.width, height: patch.height)
    if !isLarge(work) { return .init(surface: try plan.render(work), x: patch.x, y: patch.y) }
    return .init(surface: try plan.pagedSurface(fill: .clear,
      support: [.init(x: 0, y: 0, width: patch.width, height: patch.height)], bounds: work),
      x: patch.x, y: patch.y)
  }

  /// Match the canvas's pixel hit test without preparing a full painted source.
  public static func viewportPixel(_ layer: Layer, in document: CraftDocument, x: Int, y: Int) throws -> Pixel {
    let layer = try rasterInput(layer, in: document)
    let point = try layer.coordinateTransform.inverted().point(Double(x) + 0.5, Double(y) + 0.5)
    guard let patch = try viewportRaster(layer, in: document, region: .init(x: x, y: y, width: 1, height: 1)) else {
      return .clear
    }
    if layer.affine != nil {
      return RasterGeometry.sample(patch.surface, x: point.x - Double(patch.x),
                                   y: point.y - Double(patch.y), method: .bilinear)
    }
    return patch.surface.pixel(x: Int(floor(point.x)) - patch.x, y: Int(floor(point.y)) - patch.y)
  }

  static func viewportThumbnail(_ layer: Layer, in document: CraftDocument, maximumSize: Int) throws -> Surface? {
    guard let shape = layer.shape, let definition = shape.definition, usesViewportRaster(layer),
          shape.width > Surface.maximumDensePixels / shape.height else { return nil }
    let plan = try RasterPlan(definition, layer: layer, document: document)
    let scale = Double(maximumSize) / Double(max(document.width, document.height))
    let width = max(1, Int((Double(document.width) * scale).rounded(.down)))
    let height = max(1, Int((Double(document.height) * scale).rounded(.down)))
    let matrix = try Transform2D.scale(Double(width) / Double(document.width), Double(height) / Double(document.height))
      * layer.shapeTransform()
    var transform = CGAffineTransform(a: matrix.a, b: matrix.b, c: matrix.c, d: matrix.d, tx: matrix.tx, ty: matrix.ty)
    let region = IntRect(x: 0, y: 0, width: width, height: height)
    let fill = try FrameRenderer.coverage(plan.fillPath.copy(using: &transform) ?? CGMutablePath(), region: region)
    let stroke = try plan.strokePath?.copy(using: &transform).map { try FrameRenderer.coverage($0, region: region) }
    let inverse = try matrix.inverted()
    var preview = try Surface(width: width, height: height, depth: document.depth)
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let i = y * width + x
        let point = inverse.point(Double(x) + 0.5, Double(y) + 0.5)
        let pixel = plan.sample(Int(floor(point.x)), Int(floor(point.y)),
                                coverage: fill.byte(at: i), edge: stroke?.byte(at: i) ?? 0)
        if pixel.a > 0 { preview.setPixel(x: x, y: y, pixel) }
      }
    }
    return preview
  }

  private static func cachedPixels(_ definition: ShapeDefinition, layer: Layer) -> Surface? {
    guard let original = layer.shape?.importedAppearance, original.definition == definition,
      original.documentPatternPlacement.map({ $0 == layer.coordinateTransform }) != false else { return nil }
    return original.pixels
  }

  private static func exteriorDefault(_ definition: ShapeDefinition) -> Pixel? {
    switch definition.fill.kind {
    case .none: return .clear
    case .solid: return definition.fill.color.a == 0 ? .clear : definition.fill.color
    case .gradient, .pattern: return nil
    }
  }

  private static func integerRectangle(_ frame: Transform2D) -> Bool {
    let axisAligned = (frame.b == 0 && frame.c == 0) || (frame.a == 0 && frame.d == 0)
    return axisAligned && [frame.tx, frame.ty, frame.a, frame.b, frame.c, frame.d].allSatisfy { $0.rounded() == $0 }
  }

  private static func visibleStroke(_ stroke: ShapeStroke) -> Bool {
    stroke.paint.kind != .none && stroke.width > 0 && (stroke.opacity ?? 1) > 0
  }

  private static func isLarge(_ bounds: IntRect) -> Bool {
    bounds.width > Surface.maximumDensePixels / bounds.height
  }

  private static func intersect(_ a: CGRect, _ b: IntRect) -> IntRect? {
    let overlap = a.intersection(CGRect(x: b.x, y: b.y, width: b.width, height: b.height))
    guard !overlap.isNull, !overlap.isEmpty else { return nil }
    return .init(x: Int(overlap.minX), y: Int(overlap.minY),
                 width: Int(overlap.width), height: Int(overlap.height))
  }

  private struct RasterPlan {
    let bounds: IntRect
    let holes: CGPath?
    let fillPath: CGPath
    let strokePath: CGPath?
    let fill: Paint
    let stroke: Paint
    let strokeOpacity: Float
    let defaultExterior: Pixel?
    let integerExterior: Bool
    let fixedCoverageGrid: Bool
    let depth: PixelDepth

    init(_ definition: ShapeDefinition, layer: Layer, document: CraftDocument) throws {
      bounds = try definition.renderBounds()
      let clip: CGPath?
      if let frame = definition.exteriorFrame {
        let region = try VectorPathGeometry.filledRegion(definition.path())
        let exterior = region.inverted ? ShapeRenderer.exterior(frame) : nil
        clip = exterior
        holes = exterior == nil ? nil : region.path
        fillPath = exterior?.subtracting(region.path) ?? region.path
        integerExterior = exterior != nil && integerRectangle(frame)
        defaultExterior = integerExterior ? exteriorDefault(definition) : nil
      } else {
        clip = nil
        holes = nil
        fillPath = try outline(definition)
        integerExterior = false
        defaultExterior = nil
      }
      strokePath = try strokeOutline(definition, fillPath: fillPath, visibleContours: holes).map {
        clip?.intersection($0) ?? $0
      }
      fill = try Paint(definition.fill, bounds: bounds, frame: definition.paintFrame, layer: layer, document: document)
      stroke = try Paint(definition.stroke.paint, bounds: bounds, frame: definition.paintFrame, layer: layer, document: document)
      strokeOpacity = definition.stroke.opacity ?? 1
      fixedCoverageGrid = definition.exteriorFrame != nil && (defaultExterior == nil || strokePath != nil)
      depth = document.depth
    }

    func render(_ region: IntRect) throws -> Surface {
      var output = try Surface(width: region.width, height: region.height, depth: depth)
      if !fixedCoverageGrid {
        try paint(region, coverage: region, outputOrigin: region, into: &output)
        return output
      }
      // Quartz clips curves before sampling, so a viewport-sized clip can
      // change edge words as the user pans. Materialization and viewports
      // share a fixed grid based on the shape's original raster bounds.
      let side = 256
      let startX = bounds.x + ((region.x - bounds.x) / side) * side
      let startY = bounds.y + ((region.y - bounds.y) / side) * side
      for y in stride(from: startY, to: region.y + region.height, by: side) {
        try Task.checkCancellation()
        for x in stride(from: startX, to: region.x + region.width, by: side) {
          let tile = IntRect(x: x, y: y, width: min(side, bounds.x + bounds.width - x),
                             height: min(side, bounds.y + bounds.height - y))
          let tileBox = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
          if let work = intersect(tileBox, region) {
            try paint(work, coverage: tile, outputOrigin: region, into: &output)
          }
        }
      }
      return output
    }

    private func paint(_ work: IntRect, coverage tile: IntRect, outputOrigin: IntRect,
                       into output: inout Surface) throws {
      let tileBox = CGRect(x: tile.x, y: tile.y, width: tile.width, height: tile.height)
      let allFilled = integerExterior && holes?.boundingBoxOfPath.intersects(tileBox) == false
      let fillMask = allFilled ? nil : try FrameRenderer.coverage(fillPath, region: tile)
      let strokeMask = try strokePath.flatMap { edge in
        edge.boundingBoxOfPath.intersects(tileBox) ? try FrameRenderer.coverage(edge, region: tile) : nil
      }
      for y in work.y..<(work.y + work.height) {
        try Task.checkCancellation()
        for x in work.x..<(work.x + work.width) {
          let i = (y - tile.y) * tile.width + x - tile.x
          let pixel = sample(x, y, coverage: fillMask?.byte(at: i) ?? 255,
                             edge: strokeMask?.byte(at: i) ?? 0)
          if pixel.a > 0 { output.setPixel(x: x - outputOrigin.x, y: y - outputOrigin.y, pixel) }
        }
      }
    }

    func sample(_ x: Int, _ y: Int, coverage: UInt8, edge: UInt8) -> Pixel {
      var pixel = fill.sample(x, y)
      pixel.a *= Float(coverage) / 255
      if edge > 0 {
        var color = stroke.sample(x, y)
        color.a *= Float(edge) / 255 * strokeOpacity
        pixel = Renderer.compositePixel(.normal, backdrop: pixel, source: color, opacity: 1, depth: depth, x: x, y: y)
      }
      return pixel
    }

    func solidExterior() throws -> Surface? {
      guard let implicit = defaultExterior, let holes else { return nil }
      let items = [implicit.a > 0 ? holes.boundingBoxOfPath : .null, strokePath?.boundingBoxOfPath ?? .null]
      let patches = items.compactMap { intersect($0.integral, bounds) }
      var output = try Surface(width: bounds.width, height: bounds.height, depth: depth, fill: implicit)
      guard !patches.isEmpty else { return output }
      let box = patches.reduce(CGRect.null) { union, next in
        union.union(CGRect(x: next.x, y: next.y, width: next.width, height: next.height))
      }
      let patch = IntRect(x: Int(box.minX), y: Int(box.minY), width: Int(box.width), height: Int(box.height))
      if isLarge(patch) {
        return try pagedSurface(fill: implicit, support: patches.map {
          .init(x: $0.x - bounds.x, y: $0.y - bounds.y, width: $0.width, height: $0.height)
        })
      }
      let pixels = try render(patch)
      try output.mapPixels(in: .init(x: patch.x - bounds.x, y: patch.y - bounds.y,
                                    width: patch.width, height: patch.height)) { x, y, _ in
        pixels.pixel(x: x + bounds.x - patch.x, y: y + bounds.y - patch.y)
      }
      return output
    }

    func pagedSurface(fill: Pixel, support: [IntRect], bounds window: IntRect? = nil) throws -> Surface {
      let extent = window ?? bounds
      let builder = try Surface.PagedBuilder(width: extent.width, height: extent.height, depth: depth, fill: fill)
      for local in GeometryPatchRegions(width: extent.width, height: extent.height, rectangles: support) {
        let pixels = try render(.init(x: local.x + extent.x, y: local.y + extent.y,
                                      width: local.width, height: local.height))
        try builder.append(pixels, atX: local.x, atY: local.y)
      }
      return try builder.finish()
    }
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
