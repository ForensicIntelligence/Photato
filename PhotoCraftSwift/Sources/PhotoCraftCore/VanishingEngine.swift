import Foundation

private struct ProjectedDabCoverage {
  private static let circle = (0..<64).map { i in
    let angle = Double(i) * (2 * .pi / 64)
    return PathPoint(cos(angle), sin(angle))
  }
  // Integrate smoothstep opacity by averaging its iso-opacity contours.
  private static let falloff = (0..<16).map { i in
    let opacity = (Double(i) + 0.5) / 16
    var lower = 0.0, upper = 1.0
    for _ in 0..<28 {
      let t = (lower + upper) / 2
      if t * t * (3 - 2 * t) < opacity { lower = t } else { upper = t }
    }
    return (lower + upper) / 2
  }
  static let projectionWork = circle.count * falloff.count
  private let contours: [[PathPoint]]

  static func isNarrow(_ outline: [PathPoint]) -> Bool {
    let count = outline.count
    let major = (0..<(count / 2)).reduce(0.0) { longest, index in
      let a = outline[index], b = outline[index + count / 2]
      return max(longest, hypot(a.x - b.x, a.y - b.y))
    }
    // The area-to-diameter ratio estimates the minor diameter for a rotated ellipse.
    return major > 0 && 4 * abs(signedArea(outline)) <= .pi * major
  }

  init(center: PathPoint, radius: Double, hardness: Double, frame: VanishingScene.Frame, clip: Bool) throws {
    let matrix = frame.map.m
    let u = matrix[6] / frame.width, v = matrix[7] / frame.height
    let denominator = u * center.x + v * center.y + matrix[8]
    guard denominator.isFinite, abs(denominator) > radius * hypot(u, v) else {
      throw CraftError.invalid("Operation crosses a projective horizon.")
    }
    let orientation = Self.signedArea(frame.corners) >= 0 ? 1.0 : -1.0
    contours = try Self.falloff.compactMap { falloff in
      let level = radius * (1 - (1 - hardness) * falloff)
      var polygon = Self.circle.map { frame.projected(.init(center.x + level * $0.x, center.y + level * $0.y)) }
      guard polygon.allSatisfy(VanishingSettings.validPoint) else {
        throw CraftError.invalid("Operation crosses a projective horizon.")
      }
      if clip {
        for i in frame.corners.indices {
          let a = frame.corners[i], b = frame.corners[(i + 1) % frame.corners.count]
          polygon = Self.cut(polygon) { p in
            orientation * ((b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x))
          }
        }
      }
      return polygon.count >= 3 ? polygon : nil
    }
  }

  func forEachPixel(in region: IntRect, charge: (Int) throws -> Void,
    paint: (Int, Int, Double) throws -> Void) throws {
    guard let outer = contours.first, region.width > 0, region.height > 0 else { return }
    let firstRow = max(region.y, Int(floor(outer.map(\.y).min()!)))
    let lastRow = min(region.y + region.height, Int(ceil(outer.map(\.y).max()!)))
    guard firstRow < lastRow else { return }
    let edges = contours.reduce(0) { $0 + $1.count }
    for y in firstRow..<lastRow {
      try Task.checkCancellation()
      try charge(edges)
      let top = Double(y), bottom = top + 1
      let strips = contours.compactMap { outline -> (points: [PathPoint], columns: Range<Int>)? in
        let upper = Self.cut(outline) { $0.y - top }
        let strip = Self.cut(upper) { bottom - $0.y }
        guard strip.count >= 3 else { return nil }
        let left = max(region.x, Int(floor(strip.map(\.x).min()!)))
        let right = min(region.x + region.width, Int(ceil(strip.map(\.x).max()!)))
        guard left < right else { return nil }
        return (strip, left..<right)
      }
      guard let left = strips.map({ $0.columns.lowerBound }).min(),
        let right = strips.map({ $0.columns.upperBound }).max() else { continue }
      try charge(strips.reduce(0) { $0 + $1.points.count * $1.columns.count })
      var area = [Double](repeating: 0, count: right - left)
      for strip in strips {
        for x in strip.columns {
          let start = Double(x), end = start + 1
          let first = Self.cut(strip.points) { $0.x - start }
          let cell = Self.cut(first) { end - $0.x }
          area[x - left] += abs(Self.signedArea(cell))
        }
      }
      for (column, coverage) in area.enumerated() where coverage > 0 {
        try paint(left + column, y, min(1, coverage / Double(Self.falloff.count)))
      }
    }
  }

  private static func cut(_ outline: [PathPoint], distance: (PathPoint) -> Double) -> [PathPoint] {
    guard var previous = outline.last else { return [] }
    var last = distance(previous)
    var result = [PathPoint]()
    result.reserveCapacity(outline.count + 1)
    for point in outline {
      let next = distance(point)
      if (last >= 0) != (next >= 0) {
        let t = last / (last - next)
        result.append(.init(previous.x + t * (point.x - previous.x), previous.y + t * (point.y - previous.y)))
      }
      if next >= 0 { result.append(point) }
      previous = point
      last = next
    }
    return result
  }

  private static func signedArea(_ outline: [PathPoint]) -> Double {
    guard outline.count >= 3 else { return 0 }
    let origin = outline[0]
    return (1..<(outline.count - 1)).reduce(0.0) { sum, i in
      let a = outline[i], b = outline[i + 1]
      return sum + (a.x - origin.x) * (b.y - origin.y) - (b.x - origin.x) * (a.y - origin.y)
    } / 2
  }
}

public enum VanishingEngine {
  static func over(_ foreground:Pixel,_ background:Pixel)->Pixel {
    let a=unit(foreground.a),b=unit(background.a),out=a+b*(1-a)
    guard out>1e-8 else { return .clear };return Pixel((foreground.r*a+background.r*b*(1-a))/out,(foreground.g*a+background.g*b*(1-a))/out,(foreground.b*a+background.b*b*(1-a))/out,out)
  }
  static func read(_ s:Surface,_ x:Int,_ y:Int)->Pixel { s.depth == .f32 ? s.linearPixel(x:x,y:y):s.pixel(x:x,y:y) }
  static func write(_ s:inout Surface,_ x:Int,_ y:Int,_ p:Pixel) { if s.depth == .f32 { s.setLinearPixel(x:x,y:y,p) } else { s.setPixel(x:x,y:y,p) } }
  public static func render(_ program:VanishingProgram,sample:Surface) throws -> Surface {
    try program.validate();try sample.validated()
    let scene=try VanishingScene(program.settings,width:sample.width,height:sample.height),linear=sample.depth == .f32
    var output=try Surface(width:sample.width,height:sample.height,depth:sample.depth,colorEncoding:linear ? .linearRGB:.sRGB),work=0
    func charge(_ amount: Int) throws {
      work += amount
      guard work <= 134_217_728 else { throw CraftError.unsupported("Vanishing Point exceeds the rendering work budget.") }
    }
    func region(_ points:[PathPoint]) throws -> IntRect {
      guard !points.isEmpty,points.allSatisfy({VanishingSettings.validPoint($0)}) else { throw CraftError.invalid("Operation crosses a projective horizon.") }
      let x=max(0,Int(floor(points.map(\.x).min()!))-1),y=max(0,Int(floor(points.map(\.y).min()!))-1),x1=min(sample.width,Int(ceil(points.map(\.x).max()!))+1),y1=min(sample.height,Int(ceil(points.map(\.y).max()!))+1)
      let r=IntRect(x:x,y:y,width:max(0,x1-x),height:max(0,y1-y))
      try charge(r.width * r.height)
      return r
    }
    for op in program.operations {
      try Task.checkCancellation();let frame=scene.frames[op.plane],opacity=Float(op.opacity/100)
      if opacity==0 { continue }
      if op.kind == .paste {
        let source=try op.source!.converted(to:sample.depth),w=op.width*frame.width,h=w*Double(source.height)/Double(source.width),a=op.angle * .pi/180,c=cos(a),s=sin(a),origin=PathPoint(op.at.x*frame.width,op.at.y*frame.height)
        func metric(_ x:Double,_ y:Double)->PathPoint { .init(origin.x+x*c-y*s,origin.y+x*s+y*c) }
        let corners=[metric(0,0),metric(w,0),metric(w,h),metric(0,h)].map{frame.projected($0)},r=try region(corners)
        // Requiring a convex projected quad also detects a rectangle crossing the horizon.
        guard PerspectiveSettings.validQuad(corners) else { throw CraftError.invalid("Paste crosses the plane horizon.") }
        for y in r.y..<(r.y+r.height) { try Task.checkCancellation();for x in r.x..<(r.x+r.width) {
          let p=PathPoint(Double(x)+0.5,Double(y)+0.5);if op.clip && !frame.contains(p) { continue }
          let m=frame.metric(p),dx=m.x-origin.x,dy=m.y-origin.y,u=(dx*c+dy*s)/w,v=(-dx*s+dy*c)/h
          guard (0...1).contains(u),(0...1).contains(v) else { continue }
          var pixel=WarpRaster.sample(source,.init(u*Double(source.width),v*Double(source.height)),method:.bicubic);pixel.a *= opacity
          write(&output,x,y,over(pixel,read(output,x,y)))
        } }
      } else {
        let first=op.points[0],m0=frame.metric(first),probe=frame.metric(.init(first.x+op.diameter/2,first.y)),radius=hypot(probe.x-m0.x,probe.y-m0.y)
        guard radius.isFinite,radius>1e-9,frame.contains(first) else { throw CraftError.invalid("Start the stroke inside its perspective plane.") }
        let sourceFrame:VanishingScene.Frame?,offset:PathPoint
        if op.kind == .clone {
          guard let sourcePoint=op.sourcePoint,let sourcePlane=scene.plane(at:sourcePoint) else { throw CraftError.invalid("Clone source must lie on a perspective plane.") }
          sourceFrame=scene.frames[sourcePlane];let m=sourceFrame!.metric(sourcePoint);offset = .init(m.x-m0.x,m.y-m0.y)
        } else { sourceFrame=nil;offset = .init(0,0) }
        // A stroke samples an immutable pre-stroke image, including earlier operations.
        let previous=output
        var centers=[m0]
        for p in op.points.dropFirst() {
          let m=frame.metric(p),last=centers.last!,distance=hypot(m.x-last.x,m.y-last.y)
          guard distance.isFinite,distance/radius<16384 else { throw CraftError.invalid("Stroke crosses a projective horizon.") }
          let steps=max(1,Int(ceil(distance/max(1e-9,radius*0.2))))
          guard centers.count+steps<=16384 else { throw CraftError.unsupported("Perspective stroke has too many dabs.") }
          for i in 1...steps { let t=Double(i)/Double(steps);centers.append(.init(last.x+(m.x-last.x)*t,last.y+(m.y-last.y)*t)) }
        }
        let hard = min(0.99, op.hardness / 100)
        let brush = linear ? SRGBTransfer.linear(op.color) : op.color
        func paint(_ x: Int, _ y: Int, _ metric: PathPoint, _ coverage: Double) throws {
          var color = brush
          if let sourceFrame {
            let q = sourceFrame.projected(.init(metric.x + offset.x, metric.y + offset.y))
            guard VanishingSettings.validPoint(q) else { throw CraftError.invalid("Clone sampling crosses a projective horizon.") }
            color = over(WarpRaster.sample(previous, q, method: .bilinear, clampEdges: false),
              WarpRaster.sample(sample, q, method: .bilinear, clampEdges: false))
          }
          color.a *= Float(coverage) * opacity
          write(&output, x, y, over(color, read(output, x, y)))
        }
        for center in centers {
          let ring=(0..<32).map { k in let a=Double(k)/32*2 * .pi;return frame.projected(.init(center.x+radius*cos(a),center.y+radius*sin(a))) },r=try region(ring)
          if ProjectedDabCoverage.isNarrow(ring) {
            try charge(ProjectedDabCoverage.projectionWork)
            let footprint = try ProjectedDabCoverage(center: center, radius: radius, hardness: hard, frame: frame, clip: op.clip)
            let canvas = IntRect(x: 0, y: 0, width: sample.width, height: sample.height)
            try footprint.forEachPixel(in: canvas, charge: charge) { x, y, coverage in
              let p = PathPoint(Double(x) + 0.5, Double(y) + 0.5)
              try paint(x, y, frame.metric(p), coverage)
            }
            continue
          }
          for y in r.y..<(r.y+r.height) { try Task.checkCancellation();for x in r.x..<(r.x+r.width) {
            let p=PathPoint(Double(x)+0.5,Double(y)+0.5);if op.clip && !frame.contains(p) { continue }
            let m=frame.metric(p),d=hypot(m.x-center.x,m.y-center.y)/radius;guard d<1 else { continue }
            let fall = d <= hard ? 1 : 1 - (d - hard) / (1 - hard)
            try paint(x, y, m, fall * fall * (3 - 2 * fall))
          } }
        }
      }
    };return output
  }
}
public struct VanishingEdit:Sendable {
  public let source:CraftDocument,result:CraftDocument
  public let layerID:UUID
  public let program:VanishingProgram
  public static func target(_ d:CraftDocument,layerID:UUID,newLayer:Bool=false) throws -> Layer {
    guard let layer = d.layers.first(where: { $0.id == layerID }), case .raster = layer.content,
      layer.smartObject == nil, newLayer || !d.isImageLocked(layerID)
    else {
      throw CraftError.unsupported("Vanishing Point requires a rasterized pixel layer. Unlock it for current-layer output.")
    }
    return layer
  }
  public static func prepare(_ d:CraftDocument,layerID:UUID,program:VanishingProgram,sample:Surface) throws -> Self {
    try program.validate();let layer=try target(d,layerID:layerID,newLayer:program.newLayer)
    guard sample.width==d.width,sample.height==d.height else { throw CraftError.invalid("Vanishing Point sample does not match its document.") }
    let scene = try VanishingScene(program.settings,width:d.width,height:d.height)
    var result=d,settings=program.settings;settings.center=scene.center;settings.focalLength=scene.focal
    result.vanishingPoint=settings.planes.isEmpty ? nil:settings
    if !program.operations.isEmpty {
      let overlay=try VanishingEngine.render(program,sample:sample.converted(to:d.depth))
      if program.newLayer {
        guard d.layers.count<LayerLimits.maximumLayers else { throw CraftError.invalid("Layer limit reached.") }
        var pixels = overlay
        if d.selection != nil || d.selectionMask != nil {
          let side = Surface.tileSide
          let columns = (d.width + side - 1) / side
          for key in overlay.storedTileKeys {
            try Task.checkCancellation()
            let x0 = key % columns * side, y0 = key / columns * side
            for y in y0..<min(d.height, y0 + side) {
              for x in x0..<min(d.width, x0 + side) {
                var pixel = VanishingEngine.read(overlay, x, y)
                pixel.a *= d.selectionCoverage(x: x, y: y)
                VanishingEngine.write(&pixels, x, y, pixel)
              }
            }
          }
        }
        var new=Layer(name:"Vanishing Point",content:.raster(pixels));new.parentID=layer.parentID
        let index=d.layers.firstIndex(where:{$0.id==layerID})!;result.layers.insert(new,at:index+1);result.activeLayerID=new.id
      } else if case .raster(let original)=layer.content {
        var pixels = original
        let alphaLocked = d.isTransparencyLocked(layerID)
        let transform = layer.coordinateTransform
        let originalBounds = IntRect(x: 0, y: 0, width: original.width, height: original.height)
        // Bilinear sampling can see the adjacent document pixel at a tile boundary.
        let support: [IntRect]
        if let inverse = try? transform.inverted() {
          support = try overlay.projectedGeometrySupport(inverse, bounds: originalBounds, halo: 1)
        } else {
          support = [originalBounds]
        }
        for patch in GeometryPatchRegions(width: original.width, height: original.height, rectangles: support) {
          try Task.checkCancellation()
          for y in patch.y..<(patch.y + patch.height) {
            for x in patch.x..<(patch.x + patch.width) {
              let q = PathPoint(Double(x) + 0.5, Double(y) + 0.5).transformed(transform)
              guard q.x >= 0, q.x < Double(d.width), q.y >= 0, q.y < Double(d.height) else { continue }
              let coverage = d.selectionCoverage(x: Int(floor(q.x)), y: Int(floor(q.y)))
              guard coverage > 0 else { continue }
              let ink = WarpRaster.sample(overlay, q, method: .bilinear, clampEdges: false)
              guard ink.a > 0 else { continue }
              let before = VanishingEngine.read(original, x, y)
              if alphaLocked && before.a == 0 { continue }
              var after = VanishingEngine.over(ink, before)
              if alphaLocked { after.a = before.a }
              let pixel = before.mixing(after, coverage: coverage)
              guard pixel.isFinite else { throw CraftError.invalid("Nonfinite Vanishing Point output.") }
              VanishingEngine.write(&pixels, x, y, pixel)
            }
          }
        }
        result.layers[result.layers.firstIndex(where: { $0.id == layerID })!].content = .raster(pixels)
      }
    }
    try result.validate();try Task.checkCancellation();return Self(source:d,result:result,layerID:layerID,program:program)
  }
  public func applied(to document:CraftDocument) throws -> CraftDocument { guard document==source else { throw CraftError.invalid("Vanishing Point source changed; preview again.") };return result }
}
