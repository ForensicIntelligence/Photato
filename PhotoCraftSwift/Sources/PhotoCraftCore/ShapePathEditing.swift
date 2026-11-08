import Foundation

extension ShapeDefinition {
  public func controlPaintFrame()throws->ShapePaintFrame? {
    let points=try path().components.flatMap(\.knots).flatMap{[$0.anchor,$0.incoming,$0.outgoing]}
    guard !points.isEmpty else{return nil}
    let x=points.map(\.x).min()!,y=points.map(\.y).min()!
    return .init(x:x,y:y,width:points.map(\.x).max()!-x,height:points.map(\.y).max()!-y)
  }
  /// Bound actual contour joins instead of allocating the maximum miter-limit
  /// expansion around every ordinary source rectangle. Legacy bounds stay exact.
  func contourStrokePadding()throws->Double {
    guard stroke.paint.kind != .none,stroke.width>0,(stroke.opacity ?? 1)>0 else{return 1}
    let parts=try path().components,closed=parts.allSatisfy(\.closed)
    let alignment=closed ? stroke.alignment:.center
    if alignment == .inside{return 1}
    let half=stroke.width*(alignment == .center ? 0.5:1)
    var ratio=stroke.cap == .square ? sqrt(2.0):1
    if stroke.join == .miter {
      for part in parts where part.knots.count>2 {
        let n=part.knots.count
        for i in part.knots.indices where part.closed || (i>0 && i<n-1) {
          let p=part.knots[(i+n-1)%n],v=part.knots[i],next=part.knots[(i+1)%n]
          func direction(_ choices:[PathPoint])->PathPoint {
            choices.first{hypot($0.x,$0.y)>1e-12} ?? .init(0,0)
          }
          let a=direction([.init(v.anchor.x-v.incoming.x,v.anchor.y-v.incoming.y),.init(v.anchor.x-p.outgoing.x,v.anchor.y-p.outgoing.y),.init(v.anchor.x-p.anchor.x,v.anchor.y-p.anchor.y)])
          let b=direction([.init(v.outgoing.x-v.anchor.x,v.outgoing.y-v.anchor.y),.init(next.incoming.x-v.anchor.x,next.incoming.y-v.anchor.y),.init(next.anchor.x-v.anchor.x,next.anchor.y-v.anchor.y)])
          let lengths=hypot(a.x,a.y)*hypot(b.x,b.y)
          guard lengths>0 else{continue}
          let cosine=sqrt(max(0,(1+min(1,max(-1,(a.x*b.x+a.y*b.y)/lengths)))/2))
          let miter=cosine>1e-12 ? 1/cosine:Double.infinity
          if miter<=stroke.miterLimit {ratio=max(ratio,miter)}
        }
      }
    }
    return ceil(half*ratio)+2
  }
  public static func regularPathComponent(_ path:VectorPath)throws->ShapeComponent {
    try path.validate()
    var source=path;source.inverted=false
    if source.components.first?.operation == .subtract { _ = try VectorPathGeometry.filledPath(source) }
    let points=source.components.flatMap(\.knots).flatMap{[$0.anchor,$0.incoming,$0.outgoing]}
    var geometry=ShapeGeometry(width:1,height:1)
    if !points.isEmpty {
      let x=points.map(\.x).min()!,y=points.map(\.y).min()!,w=max(1,points.map(\.x).max()!-x),h=max(1,points.map(\.y).max()!-y)
      geometry = .init(kind:.custom,width:w,height:h)
      geometry.customPath=source.transformed(.scale(1/w,1/h) * .translation(-x,-y))
    }
    var component=ShapeComponent(geometry:geometry)
    component.pathOverride=source;component.pathReferenceTransform = .identity
    return component
  }
  public static func inversionFrame(canvas:IntRect,transform:Transform2D)throws->IntRect {
    guard canvas.width>0,canvas.height>0,canvas.width<=300_000,canvas.height<=300_000,abs(Double(canvas.x))<=1_000_000,abs(Double(canvas.y))<=1_000_000 else{throw CraftError.invalid("Invalid canvas for shape inversion.")}
    let inverse=try transform.inverted()
    let points=[(canvas.x,canvas.y),(canvas.x+canvas.width,canvas.y),(canvas.x,canvas.y+canvas.height),(canvas.x+canvas.width,canvas.y+canvas.height)].map{inverse.point(Double($0.0),Double($0.1))}
    let x=floor(points.map(\.x).min()!),y=floor(points.map(\.y).min()!),right=ceil(points.map(\.x).max()!),bottom=ceil(points.map(\.y).max()!)
    guard [x,y,right,bottom].allSatisfy({$0.isFinite && abs($0)<=1_000_000}),right>x,bottom>y,right-x<=32768,bottom-y<=32768,(right-x)*(bottom-y)<=8_388_608 else{throw CraftError.invalid("Inverted shape frame exceeds the8MP budget.")}
    return .init(x:Int(x),y:Int(y),width:Int(right-x),height:Int(bottom-y))
  }
}
extension Layer {
  /// Direct-selection coordinates are document pixels. The original logical
  /// placement and independent masks survive conversion from a live primitive.
  public func replacingShapePath(_ path:VectorPath,canvas:IntRect)throws->ShapeDefinition {
    guard let shape else{throw CraftError.invalid("Choose a shape layer.")}
    let transform=try shapeTransform(),local=path.transformed(try transform.inverted())
    var definition=shape.editableDefinition
    definition.components=[try ShapeDefinition.regularPathComponent(local)]
    definition.fillRule=path.fillRule;definition.inverted=path.inverted ? true:nil
    definition.inversionBounds=try path.inverted ? ShapeDefinition.inversionFrame(canvas:canvas,transform:transform):nil
    let points=local.components.flatMap(\.knots).flatMap{[$0.anchor,$0.incoming,$0.outgoing]}
    if !points.isEmpty {
      let x=points.map(\.x).min()!,y=points.map(\.y).min()!
      definition.paintFrame = .init(x:x,y:y,width:points.map(\.x).max()!-x,height:points.map(\.y).max()!-y)
    }else{definition.paintFrame=nil}
    try definition.validate();return definition
  }
}
