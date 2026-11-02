import Foundation
import PhotoCraftCore

/// Editable translation of the licensed source ShapeLayer, without interpreting
/// cache pixels as its geometry or discarding an unrepresented field.
enum PcraftShapes {
  static func layer(_ node:PcraftNode,name:String,project:PcraftProject,patterns:[RasterPattern],depth:PixelDepth,canvas:IntRect,budget:inout Int)throws->Layer {
    try node.keys("kind fill cache psd_raw path stroke live")
    let original=try PcraftPaths.path(node.field("path"))
    var path=original;path.inverted=false
    var component=try regularComponent(path)
    if let live=node.optional("live"){component=try liveComponent(live,path:path)}
    var definition=ShapeDefinition(geometry:component.geometry,fill:try paint(node.optional("fill"),patterns:patterns))
    definition.components=[component];definition.fillRule=original.fillRule
    if original.inverted{definition.inverted=true;definition.inversionBounds=canvas}
    let points=original.components.flatMap(\.knots).flatMap{[$0.anchor,$0.incoming,$0.outgoing]}
    if let first=points.first {
      let x0=points.map(\.x).min() ?? first.x,y0=points.map(\.y).min() ?? first.y
      definition.paintFrame = .init(x:x0,y:y0,width:(points.map(\.x).max() ?? x0)-x0,height:(points.map(\.y).max() ?? y0)-y0)
    }
    if let stroke=node.optional("stroke"){definition.stroke=try self.stroke(stroke,patterns:patterns)}
    try definition.validate()
    var shape=try ShapeContent(definition:definition)
    var appearance=ImportedShapeAppearance(definition:definition)
    if let cache=node.optional("cache") {
      try PcraftSamples.validateSchema(cache)
      guard let source=project.surfaces[cache.path],try PcraftSamples.depth(source.sample)==depth else{throw cache.unsupported("Shape cache depth must match the document.")}
      let placed=try PcraftSamples.placed(source,mask:false,budget:&budget)
      appearance.pixels=placed.surface;appearance.x=placed.x;appearance.y=placed.y
    }
    if let raw=node.optional("psd_raw") {
      guard let data=project.blobs[try raw.string()],data.count<=4*1024*1024 else{throw raw.invalid}
      appearance.vectorRecord=data
    }
    if appearance.pixels != nil || appearance.vectorRecord != nil{shape.importedAppearance=appearance}
    let bounds=try shape.renderBounds();shape.width=bounds.width;shape.height=bounds.height
    var layer=Layer(name:name,content:.shape(shape));layer.x=bounds.x;layer.y=bounds.y
    return layer
  }
  static func paint(_ node:PcraftNode?,patterns:[RasterPattern])throws->ShapePaint {
    guard let node else{return .none}
    let content=try PcraftFills.content(node,patterns:patterns)
    switch content {
    case .fill(let pixel):return .init(color:pixel)
    case .gradientFill(let gradient):var paint=ShapePaint();paint.kind = .gradient;paint.gradient=gradient;return paint
    case .patternFill(let pattern):var paint=ShapePaint();paint.kind = .pattern;paint.pattern=pattern;return paint
    default:throw node.unsupported("Unsupported shape paint.")
    }
  }
  static func stroke(_ node:PcraftNode,patterns:[RasterPattern])throws->ShapeStroke {
    try node.keys("width paint opacity align cap join miter_limit dashes dash_offset")
    var stroke=ShapeStroke()
    stroke.width=Double(try node.optional("width")?.float() ?? 3)
    if let paint=node.optional("paint"){stroke.paint=try self.paint(paint,patterns:patterns)}else{stroke.paint = .init(color:.black)}
    stroke.opacity=try node.optional("opacity")?.float() ?? 1
    func enumeration<T:RawRepresentable>(_ key:String,_ fallback:T)throws->T where T.RawValue==String {
      guard let field=node.optional(key)else{return fallback}
      guard let value=T(rawValue:try field.string().lowercased())else{throw field.unsupported("Unknown shape stroke option.")};return value
    }
    stroke.alignment=try enumeration("align",.center);stroke.cap=try enumeration("cap",.butt);stroke.join=try enumeration("join",.miter)
    stroke.miterLimit=Double(try node.optional("miter_limit")?.float() ?? 100)
    stroke.dash=try node.optional("dashes")?.array().map{Double(try $0.float())} ?? []
    stroke.phase=Double(try node.optional("dash_offset")?.float() ?? 0)
    stroke.pathContours=true;stroke.widthRelativeDashes=true
    try stroke.validate();return stroke
  }
  static func regularComponent(_ path:VectorPath)throws->ShapeComponent {try ShapeDefinition.regularPathComponent(path)}
  static func liveComponent(_ node:PcraftNode,path:VectorPath)throws->ShapeComponent {
    let kind=try node.field("kind").string()
    var geometry=ShapeGeometry(),transform=Transform2D.identity
    func numbers(_ key:String,_ count:Int)throws->[Double]{let a=try node.field(key).array();guard a.count==count else{throw node.invalid};return try a.map{try $0.double()}}
    switch kind {
    case "rect","ellipse","polygon":
      try node.keys(kind=="rect" ? "kind rect radii":kind=="ellipse" ? "kind rect":"kind rect sides star_ratio")
      let rect=try numbers("rect",4);geometry = .init(kind:kind=="rect" ? .rectangle:kind=="ellipse" ? .ellipse:.polygon,width:rect[2],height:rect[3]);transform = .translation(rect[0],rect[1])
      if kind=="rect"{geometry.radii=try numbers("radii",4)}
      if kind=="polygon"{geometry.sides=try node.field("sides").integer();geometry.starRatio=try node.field("star_ratio").double();if geometry.starRatio>0,geometry.starRatio<1{geometry.kind = .star}}
    case "line":
      try node.keys("kind from to weight")
      let from=try numbers("from",2),to=try numbers("to",2),dx=to[0]-from[0],dy=to[1]-from[1]
      geometry = .init(kind:.line,width:hypot(dx,dy),height:0);geometry.lineWeight=try node.field("weight").double()
      transform = .translation(from[0],from[1]) * .rotation(atan2(dy,dx))
    default:throw node.unsupported("Unknown live shape primitive.")
    }
    try geometry.validate();try transform.validated()
    var result=ShapeComponent(geometry:geometry,transform:transform);result.pathOverride=path;result.pathReferenceTransform=transform
    return result
  }
}
