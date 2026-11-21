import Foundation

extension ShapeDefinition {
  /// Keep each contiguous contour group editable when the first group subtracts.
  public static func editablePathComponents(_ path: VectorPath) throws -> [ShapeComponent] {
    guard path.components.first?.operation == .subtract else { return [try regularPathComponent(path)] }
    return try PathComponentEdit.groups(in: path).map { indices in
      var contours = Array(path.components[indices])
      let operation = contours[0].operation
      contours[0].operation = .combine
      var component = try regularPathComponent(.init(components: contours, fillRule: path.fillRule))
      component.operation = operation
      return component
    }
  }

  /// The affine mapping of the unit rectangle retains the exact canvas edges in
  /// shape-local coordinates, including fractional placement and rotation.
  public static func exteriorFrame(canvas: IntRect, transform: Transform2D) throws -> Transform2D {
    try transform.inverted() * .translation(Double(canvas.x), Double(canvas.y))
      * .scale(Double(canvas.width), Double(canvas.height))
  }

  mutating func prepareExterior(canvas: IntRect, transform: Transform2D) throws {
    if try path().components.first?.operation == .subtract {
      if exteriorFrame == nil { exteriorFrame = try Self.exteriorFrame(canvas: canvas, transform: transform) }
      inversionBounds = nil
    } else {
      exteriorFrame = nil
      if inverted == true, inversionBounds == nil {
        inversionBounds = try Self.inversionFrame(canvas: canvas, transform: transform)
      }
    }
  }

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
  public func replacingShapePath(_ path: VectorPath, canvas: IntRect,
                                 preservingTranslatedComponents: Bool = false) throws -> ShapeDefinition {
    guard let shape else{throw CraftError.invalid("Choose a shape layer.")}
    let transform=try shapeTransform(),local=path.transformed(try transform.inverted())
    var definition=shape.editableDefinition
    if preservingTranslatedComponents, let translated = try definition.translatedComponents(matching: local) {
      definition.components = translated
    } else {
      definition.components = try ShapeDefinition.editablePathComponents(local)
    }
    definition.fillRule=path.fillRule;definition.inverted=path.inverted ? true:nil
    definition.inversionBounds = nil
    try definition.prepareExterior(canvas: canvas, transform: transform)
    let points=local.components.flatMap(\.knots).flatMap{[$0.anchor,$0.incoming,$0.outgoing]}
    if !points.isEmpty {
      let x=points.map(\.x).min()!,y=points.map(\.y).min()!
      definition.paintFrame = .init(x:x,y:y,width:points.map(\.x).max()!-x,height:points.map(\.y).max()!-y)
    }else{definition.paintFrame=nil}
    try definition.validate();return definition
  }
}

private extension ShapeDefinition {
  func translatedComponents(matching destination: VectorPath) throws -> [ShapeComponent]? {
    let source = try path()
    guard source.components.count == destination.components.count else { return nil }
    var candidate = self
    var index = 0
    var groups: [Range<Int>] = []
    for primitive in components.indices {
      let end = index + (try components[primitive].path()).components.count
      groups.append(index..<end)
      if let first = (index..<end).first(where: { !source.components[$0].knots.isEmpty }),
         let start = source.components[first].knots.first?.anchor,
         let finish = destination.components[first].knots.first?.anchor,
         start != finish {
        candidate.components[primitive].transform = .translation(finish.x - start.x, finish.y - start.y)
          * candidate.components[primitive].transform
      }
      index = end
    }
    let recomputed = try candidate.path()
    for (primitive, group) in groups.enumerated() {
      let expected = destination.components[group]
      let actual = recomputed.components[group]
      guard actual != expected else { continue }
      guard zip(actual, expected).allSatisfy({ a, b in
        a.closed == b.closed && a.operation == b.operation && a.knots.count == b.knots.count
          && zip(a.knots, b.knots).allSatisfy { first, second in
            first.smooth == second.smooth
              && zip([first.anchor, first.incoming, first.outgoing], [second.anchor, second.incoming, second.outgoing])
              .allSatisfy { a, b in abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9 }
          }
      }) else { return nil }
      // Keep the exact translated knots when recomputing a primitive introduces roundoff.
      var contours = Array(expected)
      if candidate.components[primitive].operation != .combine { contours[0].operation = .combine }
      candidate.components[primitive].pathOverride = .init(components: contours, fillRule: destination.fillRule)
      candidate.components[primitive].pathReferenceTransform = candidate.components[primitive].transform
    }
    return try candidate.path() == destination ? candidate.components : nil
  }
}
