import Foundation

/// Native parametric geometry. Rectangle/ellipse/polygon construction is adapted from
/// PhotoCraft crates/vector/src/shapes.rs (MIT OR Apache-2.0); arrows and corner controls extend it.
public struct ShapeGeometry: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, CaseIterable, Sendable { case rectangle, ellipse, triangle, polygon, star, line, custom }
  public var kind: Kind = .rectangle
  public var width: Double = 100, height: Double = 100
  public var radii: [Double] = [0,0,0,0]
  public var sides: Int = 5
  public var starRatio: Double = 0.5
  public var cornerRadius: Double = 0
  public var lineWeight: Double = 2
  public var arrowStart = false, arrowEnd = false
  public var arrowWidth: Double = 12, arrowLength: Double = 20, arrowConcavity: Double = 0
  public var customPath: VectorPath?
  public init(kind: Kind = .rectangle, width: Double = 100, height: Double = 100) { self.kind=kind;self.width=width;self.height=height }
  public func validate() throws {
    guard [width,height,lineWeight,arrowWidth,arrowLength,cornerRadius].allSatisfy({$0.isFinite && $0>=0 && $0<=32768}),
      kind == .line || (width>0 && height>0),radii.count==4,radii.allSatisfy({$0.isFinite && (0...32768).contains($0)}),
      (3...100).contains(sides),starRatio.isFinite,(0...1).contains(starRatio),arrowConcavity.isFinite,(0...0.9).contains(arrowConcavity),
      lineWeight>=0,lineWeight<=1000,arrowWidth<=2000,arrowLength<=2000 else {throw CraftError.invalid("Invalid live shape dimensions or geometry.")}
    if kind == .custom {
      guard let customPath,!customPath.inverted,customPath.components.flatMap(\.knots).allSatisfy({[$0.anchor,$0.incoming,$0.outgoing].allSatisfy{abs($0.x)<=10 && abs($0.y)<=10}}) else {throw CraftError.invalid("Custom shapes require a bounded normalized path; inversion belongs to the shape.")}
      try customPath.validate()
      if customPath.components.first?.operation == .subtract { _ = try VectorPathGeometry.filledPath(customPath) }
    } else if customPath != nil {throw CraftError.invalid("Custom geometry requires the Custom shape kind.")}
  }
  public func path() throws -> VectorPath {
    try validate();let w=width,h=height
    func polygon(_ points:[PathPoint]) -> VectorPath { .init(components:[.init(knots:points.map{PathKnot($0)},closed:true)]) }
    switch kind {
    case .custom:return customPath!.transformed(.scale(w,h))
    case .ellipse:
      let x=w/2,y=h/2,k=0.5522847498307934
      return .init(components:[.init(knots:[.init(.init(x,0),incoming:.init(x-k*x,0),outgoing:.init(x+k*x,0),smooth:true),.init(.init(w,y),incoming:.init(w,y-k*y),outgoing:.init(w,y+k*y),smooth:true),.init(.init(x,h),incoming:.init(x+k*x,h),outgoing:.init(x-k*x,h),smooth:true),.init(.init(0,y),incoming:.init(0,y+k*y),outgoing:.init(0,y-k*y),smooth:true)],closed:true)])
    case .rectangle:
      var scale=1.0
      for (a,b,side) in [(0,1,w),(1,2,h),(2,3,w),(3,0,h)] where radii[a]+radii[b]>side {scale=min(scale,side/(radii[a]+radii[b]))}
      let r=radii.map{$0*scale},k=0.5522847498307934
      if r.allSatisfy({$0==0}) {return polygon([.init(0,0),.init(w,0),.init(w,h),.init(0,h)])}
      var knots:[PathKnot]=[]
      func arc(_ a:PathPoint,_ b:PathPoint,_ ca:PathPoint,_ cb:PathPoint,_ radius:Double){if radius==0{knots.append(.init(a))}else{knots.append(.init(a,outgoing:ca));knots.append(.init(b,incoming:cb))}}
      arc(.init(w-r[1],0),.init(w,r[1]),.init(w-r[1]+k*r[1],0),.init(w,r[1]-k*r[1]),r[1])
      arc(.init(w,h-r[2]),.init(w-r[2],h),.init(w,h-r[2]+k*r[2]),.init(w-r[2]+k*r[2],h),r[2])
      arc(.init(r[3],h),.init(0,h-r[3]),.init(r[3]-k*r[3],h),.init(0,h-r[3]+k*r[3]),r[3])
      arc(.init(0,r[0]),.init(r[0],0),.init(0,r[0]-k*r[0]),.init(r[0]-k*r[0],0),r[0])
      return .init(components:[.init(knots:knots,closed:true)])
    case .triangle,.polygon,.star:
      let n=kind == .triangle ? 3:sides,count=kind == .star ? n*2:n
      let points=(0..<count).map { i -> PathPoint in let a=Double(i)*2 * .pi/Double(count) - .pi/2,r=kind == .star && i%2==1 ? starRatio:1;return .init(w/2+w/2*r*cos(a),h/2+h/2*r*sin(a)) }
      if cornerRadius==0{return polygon(points)}
      var knots:[PathKnot]=[]
      for i in points.indices {
        let a=points[(i+count-1)%count],b=points[i],c=points[(i+1)%count],d1=hypot(a.x-b.x,a.y-b.y),d2=hypot(c.x-b.x,c.y-b.y),cut=min(cornerRadius,min(d1,d2)/2)
        let start=b.interpolated(to:a,at:cut/max(d1,1e-9)),end=b.interpolated(to:c,at:cut/max(d2,1e-9))
        knots.append(.init(start,outgoing:start.interpolated(to:b,at:2.0/3)));knots.append(.init(end,incoming:end.interpolated(to:b,at:2.0/3)))
      }
      return .init(components:[.init(knots:knots,closed:true)])
    case .line:
      let length=hypot(w,h),ux=length>0 ? w/length:0,uy=length>0 ? h/length:0,nx = -uy,ny=length>0 ? ux:1,half=lineWeight/2
      func p(_ t:Double,_ n:Double)->PathPoint{.init(ux*t+nx*n,uy*t+ny*n)}
      var result=polygon([p(0,half),p(length,half),p(length,-half),p(0,-half)])
      let al=min(arrowLength,length),aw=max(arrowWidth,lineWeight)/2
      if arrowStart {result.components += polygon([p(0,0),p(al,aw),p(al*(1-arrowConcavity),0),p(al,-aw)]).components}
      if arrowEnd {result.components += polygon([p(length,0),p(length-al,-aw),p(length-al*(1-arrowConcavity),0),p(length-al,aw)]).components}
      return result
    }
  }
}
public struct ShapeComponent: Codable, Equatable, Sendable {
  public var geometry: ShapeGeometry
  public var transform: Transform2D
  public var operation: PathOperation
  /// Exact local path retained alongside live primitive controls.
  public var pathOverride: VectorPath?
  public var pathReferenceTransform: Transform2D?
  public init(geometry:ShapeGeometry,transform:Transform2D = .identity,operation:PathOperation = .combine) {self.geometry=geometry;self.transform=transform;self.operation=operation}
  public var requiresExtendedShapeArchive:Bool {
    pathOverride != nil || pathReferenceTransform != nil || geometry.lineWeight==0 || geometry.starRatio<0.01 || (geometry.width==0 && geometry.height==0) || geometry.customPath?.isEmpty == true || geometry.customPath?.components.contains(where:{!$0.closed}) == true
  }
  public func path()throws->VectorPath {
    guard let pathOverride else{return try geometry.path().transformed(transform)}
    if let reference=pathReferenceTransform {
      if reference==transform{return pathOverride}
      return pathOverride.transformed(try transform * reference.inverted())
    }
    return pathOverride.transformed(transform)
  }
}
public struct ShapePaint: Codable, Equatable, Sendable {
  public enum Kind:String,Codable,CaseIterable,Sendable{case none,solid,gradient,pattern}
  public var kind:Kind = .solid
  public var color:Pixel = .black
  public var gradient:GradientFill?
  public var pattern:PatternFill?
  public init(color:Pixel = .black){self.color=color}
  public static var none:Self{var v=Self();v.kind = .none;return v}
  public func validate(in document:CraftDocument? = nil) throws {
    guard color.isFinite,(0...1).contains(color.a), (kind == .gradient) == (gradient != nil),(kind == .pattern) == (pattern != nil) else{throw CraftError.invalid("Invalid shape paint.")}
    try gradient?.validate();try pattern?.validate()
    if let pattern,let document,document.pattern(pattern.patternID)==nil{throw CraftError.invalid("Missing shape pattern.")}
  }
}
public struct ShapeStroke: Codable, Equatable, Sendable {
  public enum Alignment:String,Codable,CaseIterable,Sendable{case inside,center,outside}
  public enum Cap:String,Codable,CaseIterable,Sendable{case butt,round,square}
  public enum Join:String,Codable,CaseIterable,Sendable{case miter,round,bevel}
  public var paint:ShapePaint = .none
  public var width:Double = 1
  public var alignment:Alignment = .center
  public var cap:Cap = .butt
  public var join:Join = .miter
  public var miterLimit:Double = 4
  /// Dash lengths and phase are pixels in the shape's local coordinates.
  public var dash:[Double] = []
  public var phase:Double = 0
  public var opacity:Float?
  public var pathContours:Bool?
  public var widthRelativeDashes:Bool?
  public init(){}
  public func validate(in document:CraftDocument? = nil)throws{
    try paint.validate(in:document)
    guard width.isFinite,(0...1000).contains(width),miterLimit.isFinite,(1...100).contains(miterLimit),phase.isFinite,abs(phase)<=10000,dash.count<=32,dash.allSatisfy({$0.isFinite && $0>=0 && $0<=10000}),dash.isEmpty || dash.contains(where:{$0>0}),opacity.map({$0.isFinite && (0...1).contains($0)}) != false else{throw CraftError.invalid("Invalid shape stroke.")}
  }
}
public struct ShapeDefinition: Codable, Equatable, Sendable {
  public var components:[ShapeComponent]
  public var fill:ShapePaint
  public var stroke:ShapeStroke
  public var fillRule:PathFillRule = .nonZero
  public var inverted:Bool?
  public var inversionBounds:IntRect?
  public var paintFrame:ShapePaintFrame?
  public init(geometry:ShapeGeometry,fill:ShapePaint = .init(),stroke:ShapeStroke = .init()){components=[.init(geometry:geometry)];self.fill=fill;self.stroke=stroke}
  public var estimatedBytes:Int {components.reduce(256){$0+512+(($1.geometry.customPath?.knotCount ?? 0)+($1.pathOverride?.knotCount ?? 0))*64} + [fill,stroke.paint].reduce(0){$0+($1.gradient?.gradient.colors.count ?? 0)*48+($1.gradient?.gradient.opacity.count ?? 0)*16} + stroke.dash.count*8}
  public var requiresExtendedShapeArchive:Bool {
    inverted != nil || inversionBounds != nil || paintFrame != nil || stroke.opacity != nil || stroke.pathContours != nil || stroke.widthRelativeDashes != nil || stroke.miterLimit>20 || stroke.dash.contains(0) || components.contains(where:\.requiresExtendedShapeArchive)
  }
  public func validate(in document:CraftDocument? = nil)throws{
    guard !components.isEmpty,components.count<=64 else{throw CraftError.invalid("Choose1–64 live shape components.")}
    try fill.validate(in:document);try stroke.validate(in:document)
    for component in components{try component.geometry.validate();try component.transform.validated();try component.pathOverride?.validate();try component.pathReferenceTransform?.validated();guard component.pathReferenceTransform == nil || component.pathOverride != nil else{throw CraftError.invalid("A path reference requires an exact path.")};guard component.pathOverride?.inverted != true else{throw CraftError.invalid("Component inversion belongs to the complete shape.")}}
    if inverted == true {
      guard let f=inversionBounds,f.width>0,f.height>0,f.width<=32768,f.height<=32768,abs(Double(f.x))<=1_000_000,abs(Double(f.y))<=1_000_000,f.width*f.height<=8_388_608 else{throw CraftError.invalid("Inverted shapes require a bounded rasterization frame.")}
    }else if inversionBounds != nil{throw CraftError.invalid("An inversion frame requires an inverted shape.")}
    try paintFrame?.validate()
    try path().validate();_ = try renderBounds()
  }
  public func path()throws->VectorPath{
    var output=VectorPath(components:[],fillRule:fillRule,inverted:inverted ?? false)
    for component in components {
      var path=try component.path()
      // Subpaths of one primitive are grouped before the outer boolean operation.
      if component.pathOverride == nil {for i in path.components.indices {path.components[i].operation = i==0 ? component.operation:.join}}
      else if component.operation != .combine,!path.components.isEmpty {path.components[0].operation=component.operation}
      output.components += path.components
    }
    try output.validate();return output
  }
  public func renderBounds()throws->IntRect{
    let points=try path().components.flatMap(\.knots).flatMap{[$0.anchor,$0.incoming,$0.outgoing]}
    if points.isEmpty{return inversionBounds ?? .init(x:0,y:0,width:1,height:1)}
    let pad=stroke.pathContours == true ? try contourStrokePadding():stroke.paint.kind == .none || stroke.alignment == .inside ? 1:ceil(stroke.width*(stroke.join == .miter ? stroke.miterLimit:1))+2
    let x0=floor(points.map(\.x).min()!)-pad,y0=floor(points.map(\.y).min()!)-pad,x1=ceil(points.map(\.x).max()!)+pad,y1=ceil(points.map(\.y).max()!)+pad
    guard [x0,y0,x1,y1].allSatisfy({$0.isFinite && abs($0)<=1_000_000}),x1>x0,y1>y0,x1-x0<=32768,y1-y0<=32768,(x1-x0)*(y1-y0)<=8_388_608 else{throw CraftError.invalid("Live shape exceeds the8MP rasterization budget.")}
    let geometry=IntRect(x:Int(x0),y:Int(y0),width:Int(x1-x0),height:Int(y1-y0))
    return try inversionBounds.map{try ShapeBounds.union(geometry,$0)} ?? geometry
  }
}
extension ShapeContent {
  public init(definition:ShapeDefinition)throws{
    try definition.validate();let bounds=try definition.renderBounds()
    self.init(kind:.rectangle,width:bounds.width,height:bounds.height,color:definition.fill.color);self.definition=definition
  }
  public var editableDefinition:ShapeDefinition {definition ?? .init(geometry:.init(kind:kind == .ellipse ? .ellipse:.rectangle,width:Double(width),height:Double(height)),fill:.init(color:color))}
  public func validate(in document:CraftDocument)throws{
    guard importedAppearance == nil || definition != nil else{throw CraftError.invalid("Imported appearance requires editable shape geometry.")}
    guard width>0,height>0,width<=32768,height<=32768,color.isFinite else{throw CraftError.invalid("Invalid shape.")}
    if let definition {try definition.validate(in:document);try importedAppearance?.validate(in:document);let b=try renderBounds();guard width==b.width,height==b.height else{throw CraftError.invalid("Shape bounds do not match geometry.")}}
  }
}
extension Layer {
  public var shape:ShapeContent? {if case .shape(let shape)=content{return shape};return nil}
  public func shapeTransform()throws->Transform2D{
    guard let shape,shape.definition != nil else{return coordinateTransform};let b=try shape.renderBounds()
    return coordinateTransform * .translation(-Double(b.x),-Double(b.y))
  }
  public func shapePath()throws->VectorPath?{try shape?.editableDefinition.path().transformed(shapeTransform())}
}
public enum ShapeOutputMode:String,Codable,CaseIterable,Sendable{case shape,path,pixels}
public enum ShapeCommand:Sendable{
  case create(String,ShapeDefinition,Transform2D,patterns:[RasterPattern] = [])
  case configure(UUID,ShapeDefinition,patterns:[RasterPattern] = [])
  case append(UUID,ShapeComponent)
  public var label:String{switch self{case .create:"New Shape";case .configure:"Shape Properties";case .append:"Combine Shapes"}}
  static func install(_ patterns:[RasterPattern],definition:inout ShapeDefinition,document:inout CraftDocument)throws{
    guard patterns.count<=2 else{throw CraftError.invalid("A shape can embed two paint patterns.")}
    for pattern in patterns {let id=try document.installPattern(pattern);if definition.fill.pattern?.patternID==pattern.id{definition.fill.pattern?.patternID=id};if definition.stroke.paint.pattern?.patternID==pattern.id{definition.stroke.paint.pattern?.patternID=id}}
  }
  func apply(to d:inout CraftDocument)throws{
    switch self{
    case .create(let name,var definition,let placement,let patterns):
      try Self.install(patterns,definition:&definition,document:&d)
      try definition.validate(in:d);try placement.validated();let bounds=try definition.renderBounds()
      var layer=Layer(name:name,content:.shape(try .init(definition:definition)))
      let full=placement * .translation(Double(bounds.x),Double(bounds.y));layer.x=Int(floor(full.tx));layer.y=Int(floor(full.ty));layer.affine = .translation(-Double(layer.x),-Double(layer.y)) * full
      if layer.affine == .identity{layer.affine=nil};try Command.addLayer(layer).apply(to:&d)
    case .configure(let id,var definition,let patterns):
      guard let i=d.layers.firstIndex(where:{$0.id==id}),let old=d.layers[i].shape,!d.isImageLocked(id),!d.isLocked(id) else{throw CraftError.invalid("Choose an unlocked shape layer.")}
      for i in definition.components.indices where old.editableDefinition.components.indices.contains(i) {
        let previous=old.editableDefinition.components[i]
        if definition.components[i].geometry != previous.geometry,definition.components[i].pathOverride == previous.pathOverride {definition.components[i].pathOverride=nil;definition.components[i].pathReferenceTransform=nil}
      }
      if old.editableDefinition.components != definition.components,definition.paintFrame==old.editableDefinition.paintFrame,definition.paintFrame != nil {definition.paintFrame=try definition.controlPaintFrame()}
      try Self.install(patterns,definition:&definition,document:&d)
      try definition.validate(in:d)
      // Merely accepting unchanged Properties must preserve original cache samples.
      if definition==old.editableDefinition{return}
      guard old.editableDefinition.components==definition.components || !d.isPositionLocked(id) else{throw CraftError.invalid("Unlock shape position before changing its geometry.")}
      let previous=d.layers[i],origin=try previous.shapeTransform(),bounds=try definition.renderBounds(),full=origin * .translation(Double(bounds.x),Double(bounds.y))
      d.layers[i].content = .shape(try .init(definition:definition));d.layers[i].x=Int(floor(full.tx));d.layers[i].y=Int(floor(full.ty));d.layers[i].affine = .translation(-Double(d.layers[i].x),-Double(d.layers[i].y)) * full
      if d.layers[i].affine == .identity{d.layers[i].affine=nil}
      if previous.mask != nil {var props=previous.effectiveMaskProperties;props.transform=try full.inverted() * previous.maskCoordinateTransform;d.layers[i].maskProperties=props}
    case .append(let id,let component):
      guard let layer=d.layers.first(where:{$0.id==id}),var definition=layer.shape?.editableDefinition else{throw CraftError.invalid("Choose a shape to combine.")}
      definition.components.append(component);try ShapeCommand.configure(id,definition).apply(to:&d)
    }
  }
}
