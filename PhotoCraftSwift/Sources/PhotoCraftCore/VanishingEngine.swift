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

  init(center: PathPoint, radius: Double, hardness: Double, layout: VanishingSurfaceChart,
    clip: Bool, extensionPlane: Int, charge: (Int) throws -> Void
  ) throws {
    contours = try Self.falloff.flatMap { falloff in
      let level = radius * (1 - (1 - hardness) * falloff)
      let polygon = Self.circle.map { PathPoint(center.x+level*$0.x,center.y+level*$0.y) }
      let pieces = try layout.projectedPieces(polygon,clip:clip,extending:extensionPlane,charge:charge)
      return try pieces.enumerated().flatMap { index,piece -> [[PathPoint]] in
        var visible = [piece.corners]
        for front in pieces.prefix(index) where piece.xExtent.overlaps(front.xExtent) && piece.yExtent.overlaps(front.yExtent) {
          guard !visible.isEmpty else { break }
          let orientation = Self.signedArea(front.corners) >= 0 ? 1.0 : -1.0
          var exposed: [[PathPoint]] = []
          for polygon in visible {
            var remainder = polygon
            for i in front.corners.indices {
              guard !remainder.isEmpty else { break }
              try charge(remainder.count*2)
              let a = front.corners[i], b = front.corners[(i+1)%front.corners.count]
              func side(_ p: PathPoint) -> Double {
                orientation*((b.x-a.x)*(p.y-a.y)-(b.y-a.y)*(p.x-a.x))
              }
              let outside = Self.cut(remainder) { -side($0) }
              if !outside.isEmpty { exposed.append(outside) }
              remainder = Self.cut(remainder,distance:side)
            }
          }
          visible = exposed
        }
        return visible
      }
    }
  }

  func forEachPixel(in region: IntRect, charge: (Int) throws -> Void,
    paint: (Int, Int, Double) throws -> Void) throws {
    guard !contours.isEmpty, region.width > 0, region.height > 0 else { return }
    let vertical = contours.flatMap { $0.map(\.y) }
    let firstRow = max(region.y, Int(floor(vertical.min()!)))
    let lastRow = min(region.y + region.height, Int(ceil(vertical.max()!)))
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

private enum VanishingHealing {
  struct Coverage {
    private(set) var bounds: IntRect?
    let mode: VanishingOperation.Heal
    private var pixels: Surface

    init(mode: VanishingOperation.Heal, canvas: Surface) throws {
      self.mode = mode
      pixels = try Surface(width: canvas.width, height: canvas.height, depth: .f32)
    }

    func alpha(_ x: Int, _ y: Int) -> Float { pixels.pixel(x: x, y: y).a }

    mutating func add(_ alpha: Float, atX x: Int, y: Int) throws {
      let a = unit(alpha)
      guard a > 0 else { return }
      if let bounds, !bounds.contains(x, y) {
        let left = min(bounds.x, x), top = min(bounds.y, y)
        let right = max(bounds.x + bounds.width, x + 1), bottom = max(bounds.y + bounds.height, y + 1)
        let expanded = IntRect(x: left, y: top, width: right - left, height: bottom - top)
        guard expanded.width + 2 <= HealingSolver.maxPixels / (expanded.height + 2) else {
          throw CraftError.unsupported("The healed perspective edit exceeds the 4-megapixel local repair budget.")
        }
        self.bounds = expanded
      } else if bounds == nil {
        bounds = IntRect(x: x, y: y, width: 1, height: 1)
      }
      let old = self.alpha(x, y)
      pixels.setPixel(x: x, y: y, Pixel(0, 0, 0, a + old * (1 - a)))
    }
  }

  static func apply(_ coverage: Coverage, sample: Surface, previous: Surface, output: inout Surface,
    charge: (Int) throws -> Void, sourceAt: (Int, Int) -> Pixel) throws {
    guard let bounds = coverage.bounds else { return }
    let region = IntRect(x: bounds.x - 1, y: bounds.y - 1, width: bounds.width + 2, height: bounds.height + 2)
    let count = region.width * region.height
    let channels = coverage.mode == .luminance ? 1 : 3
    try charge(count * channels)
    var source = [Float](repeating: 0, count: count * channels)
    var destination = source
    var unknown = [Bool](repeating: false, count: count)
    var support = [Float](repeating: 0, count: count)
    let canvas = IntRect(x: 0, y: 0, width: sample.width, height: sample.height)
    func luminance(_ p: Pixel) -> Float { 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b }

    for row in 0..<region.height {
      try Task.checkCancellation()
      let y = region.y + row
      for column in 0..<region.width {
        let x = region.x + column, i = row * region.width + column
        let a = sourceAt(x, y)
        let b = canvas.contains(x, y)
          ? VanishingEngine.over(VanishingEngine.read(previous, x, y), VanishingEngine.read(sample, x, y)) : .clear
        unknown[i] = bounds.contains(x, y) && coverage.alpha(x, y) > 0
        support[i] = min(a.a, b.a)
        if channels == 1 {
          source[i] = luminance(a)
          destination[i] = luminance(b)
        } else {
          source[i * 3] = a.r; source[i * 3 + 1] = a.g; source[i * 3 + 2] = a.b
          destination[i * 3] = b.r; destination[i * 3 + 1] = b.g; destination[i * 3 + 2] = b.b
        }
      }
    }

    try matchTransparentBoundary(width: region.width, height: region.height, channels: channels,
      source: source, destination: &destination, unknown: unknown, support: support, charge: charge)
    let healed = try HealingSolver.seamlessClone(width: region.width, height: region.height,
      channels: channels, source: source, destination: destination, mask: unknown)
    for row in 1..<(region.height - 1) {
      try Task.checkCancellation()
      let y = region.y + row
      for column in 1..<(region.width - 1) {
        let x = region.x + column, i = row * region.width + column
        guard unknown[i] else { continue }
        let color: SIMD3<Float>
        if channels == 1 {
          color = sourceAt(x, y).rgb + SIMD3(repeating: healed[i] - source[i])
        } else {
          color = SIMD3(healed[i * 3], healed[i * 3 + 1], healed[i * 3 + 2])
        }
        let ink = Pixel(color.x, color.y, color.z, coverage.alpha(x, y))
        guard ink.isFinite else { throw CraftError.invalid("Perspective healing produced nonfinite color.") }
        VanishingEngine.write(&output, x, y, VanishingEngine.over(ink, VanishingEngine.read(output, x, y)))
      }
    }
  }

  /// Transparent samples supply no color constraint. Estimate the difference from
  /// visible source/destination pairs at the same projected position.
  private static func matchTransparentBoundary(width: Int, height: Int, channels: Int,
    source: [Float], destination: inout [Float], unknown: [Bool], support: [Float],
    charge: (Int) throws -> Void) throws {
    let minimumSupport: Float = 0.00001
    var unpaired = [Int]()
    var measured = SIMD3<Float>.zero
    var reliability: Float = 0
    func difference(_ i: Int) -> SIMD3<Float> {
      let p = i * channels
      if channels == 1 { return SIMD3(destination[p] - source[p], 0, 0) }
      return SIMD3(destination[p] - source[p], destination[p + 1] - source[p + 1],
        destination[p + 2] - source[p + 2])
    }
    func nearestPair(_ x: Int, _ y: Int) throws -> (SIMD3<Float>, Float) {
      for radius in 1...3 {
        try charge(8 * radius)
        var sum = SIMD3<Float>.zero
        var weight: Float = 0
        for row in max(0, y - radius)...min(height - 1, y + radius) {
          for column in max(0, x - radius)...min(width - 1, x + radius)
            where max(abs(x - column), abs(y - row)) == radius {
            let i = row * width + column
            if support[i] > minimumSupport {
              sum += difference(i) * support[i]
              weight += support[i]
            }
          }
        }
        if weight > 0 { return (sum / weight, weight) }
      }
      return (.zero, 0)
    }
    for y in 0..<height {
      try Task.checkCancellation()
      for x in 0..<width {
        let i = y * width + x
        guard !unknown[i],
          (x > 0 && unknown[i - 1]) || (x < width - 1 && unknown[i + 1])
          || (y > 0 && unknown[i - width]) || (y < height - 1 && unknown[i + width])
        else { continue }
        if support[i] > minimumSupport {
          measured += difference(i) * support[i]
          reliability += support[i]
        } else {
          let (correction, weight) = try nearestPair(x, y)
          if weight > 0 {
            for c in 0..<channels { destination[i * channels + c] = source[i * channels + c] + correction[c] }
            measured += correction * weight
            reliability += weight
          } else {
            unpaired.append(i)
          }
        }
      }
    }
    let fallback = reliability > 0 ? measured / reliability : .zero
    for i in unpaired {
      for c in 0..<channels { destination[i * channels + c] = source[i * channels + c] + fallback[c] }
    }
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
    for (index, op) in program.operations.enumerated() {
      try Task.checkCancellation();let frame=scene.frames[op.plane],opacity=Float(op.opacity/100)
      if opacity==0 { continue }
      let mode = op.heal ?? .off
      var coverage = mode == .off ? nil : try VanishingHealing.Coverage(mode: mode, canvas: sample)
      func deposit(_ color: Pixel, x: Int, y: Int) throws {
        if coverage != nil { try coverage?.add(color.a, atX: x, y: y) }
        else { write(&output, x, y, over(color, read(output, x, y))) }
      }
      if op.kind == .paste {
        let source=try op.source!.converted(to:sample.depth),w=op.width*frame.width,h=w*Double(source.height)/Double(source.width),a=op.angle * .pi/180,c=cos(a),s=sin(a),origin=PathPoint(op.at.x*frame.width,op.at.y*frame.height)
        func metric(_ x:Double,_ y:Double)->PathPoint { .init(origin.x+x*c-y*s,origin.y+x*s+y*c) }
        let corners=[metric(0,0),metric(w,0),metric(w,h),metric(0,h)].map{frame.projected($0)},r=try region(corners)
        // Requiring a convex projected quad also detects a rectangle crossing the horizon.
        guard PerspectiveSettings.validQuad(corners) else { throw CraftError.invalid("Paste crosses the plane horizon.") }
        let previous = mode == .off ? nil : output
        func position(_ p: PathPoint) -> (Double, Double) {
          let m = frame.metric(p), dx = m.x - origin.x, dy = m.y - origin.y
          return ((dx * c + dy * s) / w, (-dx * s + dy * c) / h)
        }
        func sourceColor(_ u: Double, _ v: Double) -> Pixel {
          WarpRaster.sample(source, .init(u * Double(source.width), v * Double(source.height)), method: .bicubic)
        }
        for y in r.y..<(r.y+r.height) { try Task.checkCancellation();for x in r.x..<(r.x+r.width) {
          let p=PathPoint(Double(x)+0.5,Double(y)+0.5);if op.clip && !frame.contains(p) { continue }
          let (u, v) = position(p)
          guard (0...1).contains(u),(0...1).contains(v) else { continue }
          var pixel = sourceColor(u, v); pixel.a *= opacity
          try deposit(pixel, x: x, y: y)
        } }
        if let coverage, let previous {
          try VanishingHealing.apply(coverage, sample: sample, previous: previous, output: &output, charge: charge) { x, y in
            let (u, v) = position(.init(Double(x) + 0.5, Double(y) + 0.5))
            return sourceColor(clamped(u), clamped(v))
          }
        }
      } else if let patch = op.marquee {
        let footprint: ProjectedVanishingMarquee?
        let corners: [PathPoint]
        if patch.destination.wrap == true {
          guard let projection = ProjectedVanishingMarquee(rect:patch.destination,scene:scene,angle:op.angle,clip:op.clip) else {
            throw CraftError.invalid("The perspective marquee crosses a plane horizon.")
          }
          footprint = projection
          corners = projection.pieces.flatMap(\.corners)
        } else {
          guard let projected = patch.destination.projectedCorners(in:scene,angle:op.angle) else {
            throw CraftError.invalid("The perspective marquee crosses a plane horizon.")
          }
          footprint = nil
          corners = projected
        }
        guard patch.source.outlineSegments(in:scene,angle:0,clip:op.clip) != nil else {
          throw CraftError.invalid("The perspective marquee crosses a plane horizon.")
        }
        if corners.isEmpty { continue }
        let bounds = try region(corners)
        let pieces = footprint?.pieces ?? []
        let contour = footprint?.featherEdges ?? corners.indices.map { [corners[$0],corners[($0+1)%corners.count]] }
        let edges = contour.compactMap { points -> (PathPoint,Double,Double,Double)? in
          let a = points[0],b = points[1],dx = b.x-a.x,dy = b.y-a.y,distance = hypot(dx,dy)
          return distance > 1e-8 ? (a,dx/distance,dy/distance,distance) : nil
        }
        if footprint != nil {
          let visits = max(1,pieces.count + (patch.feather > 0 ? edges.count : 0))
          try charge((visits-1)*bounds.width*bounds.height)
        }
        let extent = footprint == nil ? (0.0...1.0) : (-1e-9...1+1e-9)
        let sourceFrame = scene.frames[patch.source.plane],previous = output
        func sourceColor(_ unit: PathPoint) -> Pixel {
          let uv = patch.source.point(.init(clamped(unit.x),clamped(unit.y)))
          let donor: PathPoint
          if patch.source.wrap == true {
            guard let projected = patch.source.wrappedPoint(uv,in:scene,clip:op.clip) else { return .clear }
            donor = projected
          } else {
            donor = sourceFrame.point(uv)
            if op.clip && !sourceFrame.contains(donor) { return .clear }
          }
          guard VanishingSettings.validPoint(donor) else { return .clear }
          let image = WarpRaster.sample(sample,donor,method:.bicubic,clampEdges:false)
          // The first operation has no prior marks to sample.
          let overlay = index == 0 ? .clear : WarpRaster.sample(previous,donor,method:.bicubic,clampEdges:false)
          return over(overlay,image)
        }
        for y in bounds.y..<(bounds.y+bounds.height) {
          try Task.checkCancellation()
          for x in bounds.x..<(bounds.x+bounds.width) {
            let point = PathPoint(Double(x)+0.5,Double(y)+0.5)
            let unit: PathPoint
            if footprint != nil {
              guard let piece = pieces.first(where:{ $0.contains(point) }) else { continue }
              unit = patch.destination.wrappedUnit(point,on:piece.plane,in:scene,angle:op.angle)
            } else {
              guard !op.clip || frame.contains(point) else { continue }
              unit = patch.destination.unitPoint(point,frame:frame,angle:op.angle)
            }
            guard extent.contains(unit.x),extent.contains(unit.y) else { continue }
            var pixel = sourceColor(unit)
            if patch.feather > 0 {
              let distance = edges.reduce(Double.infinity) { closest,edge in
                let (a,dx,dy,length) = edge
                let px = point.x-a.x,py = point.y-a.y
                if footprint == nil { return min(closest,abs(dx*py-dy*px)) }
                let along = min(length,max(0,px*dx+py*dy))
                return min(closest,hypot(px-along*dx,py-along*dy))
              }
              let t = clamped(distance/patch.feather)
              pixel.a *= Float(t*t*(3-2*t))
            }
            pixel.a *= opacity
            try deposit(pixel,x:x,y:y)
          }
        }
        if let coverage {
          try VanishingHealing.apply(coverage,sample:sample,previous:previous,output:&output,charge:charge) { x,y in
            let point = PathPoint(Double(x)+0.5,Double(y)+0.5)
            if footprint != nil {
              let plane = pieces.first(where:{ $0.contains(point) })?.plane
                ?? scene.marqueePlane(at:point,relativeTo:op.plane) ?? op.plane
              return sourceColor(patch.destination.wrappedUnit(point,on:plane,in:scene,angle:op.angle))
            }
            return sourceColor(patch.destination.unitPoint(point,frame:frame,angle:op.angle))
          }
        }
      } else {
        let first = op.points[0]
        let sourcePlane = op.sourcePlane ?? op.sourcePoint.flatMap { scene.plane(at:$0) }
        let wraps = op.wrap == true && (scene.hasMarqueeNeighbors(op.plane)
          || sourcePlane.map(scene.hasMarqueeNeighbors) == true)
        let layout = wraps ? VanishingSurfaceChart(scene:scene,anchor:op.plane) : nil
        func destinationCoordinate(_ image: PathPoint) -> PathPoint {
          guard let layout else { return frame.metric(image) }
          return layout.coordinates(image,on:layout.face(at:image))
        }
        let m0 = layout?.coordinates(first,on:op.plane) ?? frame.metric(first)
        let diameterProbe = PathPoint(first.x+op.diameter/2,first.y)
        let probe = layout?.coordinates(diameterProbe,on:op.plane) ?? frame.metric(diameterProbe)
        let radius = hypot(probe.x-m0.x,probe.y-m0.y)
        guard radius.isFinite,radius>1e-9,frame.contains(first) else { throw CraftError.invalid("Start the stroke inside its perspective plane.") }
        if op.kind == .clone && sourcePlane == nil {
          throw CraftError.invalid("Clone source must lie on a perspective plane.")
        }
        let sourceFrame = op.kind == .clone ? sourcePlane.map { scene.frames[$0] } : nil
        let donorLayout = wraps && op.kind == .clone ? sourcePlane.map { VanishingSurfaceChart(scene:scene,anchor:$0) } : nil
        let sourceOrigin = op.sourcePoint.flatMap { point in
          donorLayout.map { $0.coordinates(point,on:$0.anchor) } ?? sourceFrame?.metric(point)
        } ?? m0
        let offset = PathPoint(sourceOrigin.x-m0.x,sourceOrigin.y-m0.y)
        // A stroke samples an immutable pre-stroke image, including earlier operations.
        let previous=output
        let path = try layout?.strokePath(op.points,charge:charge)
          ?? op.points.map { Optional(VanishingSurfaceChart.StrokePoint(point:frame.metric($0),plane:op.plane)) }
        var centers: [VanishingSurfaceChart.StrokePoint] = []
        var continues = false
        for target in path {
          defer { continues = target != nil }
          guard let target else { continue }
          let m = target.point
          guard m.x.isFinite,m.y.isFinite else { throw CraftError.invalid("Stroke crosses a projective horizon.") }
          guard continues,let last = centers.last?.point else {
            guard centers.count < 16384 else { throw CraftError.unsupported("Perspective stroke has too many dabs.") }
            centers.append(target)
            continue
          }
          let distance = hypot(m.x-last.x,m.y-last.y)
          guard distance.isFinite,distance/radius<16384 else { throw CraftError.invalid("Stroke crosses a projective horizon.") }
          let steps=max(1,Int(ceil(distance/max(1e-9,radius*0.2))))
          guard centers.count+steps<=16384 else { throw CraftError.unsupported("Perspective stroke has too many dabs.") }
          for i in 1...steps {
            let t = Double(i)/Double(steps)
            centers.append(.init(point:.init(last.x+(m.x-last.x)*t,last.y+(m.y-last.y)*t),plane:target.plane))
          }
        }
        let hard = min(0.99, op.hardness / 100)
        let brush = linear ? SRGBTransfer.linear(op.color) : op.color
        func sourceColor(_ metric: PathPoint) -> Pixel? {
          guard let sourceFrame else { return brush }
          let donor = PathPoint(metric.x+offset.x,metric.y+offset.y)
          let mapped = donorLayout == nil ? sourceFrame.projected(donor) : donorLayout?.image(donor)?.point
          guard let q = mapped,VanishingSettings.validPoint(q) else { return nil }
          return over(WarpRaster.sample(previous, q, method: .bilinear, clampEdges: false),
            WarpRaster.sample(sample, q, method: .bilinear, clampEdges: false))
        }
        func paint(_ x: Int, _ y: Int, _ metric: PathPoint, _ fraction: Double) throws {
          guard var color = sourceColor(metric) else { throw CraftError.invalid("Clone sampling crosses a projective horizon.") }
          color.a *= Float(fraction) * opacity
          try deposit(color, x: x, y: y)
        }
        for dab in centers {
          let center = dab.point
          if let layout {
            let extent = radius/cos(.pi/32)
            let outline = (0..<32).map { k in
              let angle = Double(k)*2 * .pi/32
              return PathPoint(center.x+extent*cos(angle),center.y+extent*sin(angle))
            }
            let pieces = try layout.projectedPieces(outline,clip:op.clip,extending:dab.plane,charge:charge)
            guard !pieces.isEmpty else { continue }
            if pieces.allSatisfy({ ProjectedDabCoverage.isNarrow($0.corners) }) {
              try charge(ProjectedDabCoverage.projectionWork)
              let footprint = try ProjectedDabCoverage(center:center,radius:radius,hardness:hard,
                layout:layout,clip:op.clip,extensionPlane:dab.plane,charge:charge)
              try footprint.forEachPixel(in:.init(x:0,y:0,width:sample.width,height:sample.height),charge:charge) { x,y,fraction in
                let point = PathPoint(Double(x)+0.5,Double(y)+0.5)
                try charge(pieces.count+(donorLayout?.faces.count ?? 0))
                let face = pieces.min { $0.distance(point) < $1.distance(point) }?.plane ?? layout.anchor
                try paint(x,y,layout.coordinates(point,on:face),fraction)
              }
            } else {
              for (index,piece) in pieces.enumerated() {
                let r = try region(piece.corners)
                let earlier = pieces.prefix(index)
                try charge((index+(donorLayout?.faces.count ?? 0))*r.width*r.height)
                for y in r.y..<(r.y+r.height) {
                  try Task.checkCancellation()
                  for x in r.x..<(r.x+r.width) {
                    let p = PathPoint(Double(x)+0.5,Double(y)+0.5)
                    guard piece.contains(p) else { continue }
                    let m = layout.coordinates(p,on:piece.plane)
                    let d = hypot(m.x-center.x,m.y-center.y)/radius
                    guard d < 1,!earlier.contains(where:{ earlierPiece in
                      guard earlierPiece.contains(p) else { return false }
                      let at = layout.coordinates(p,on:earlierPiece.plane)
                      return hypot(at.x-center.x,at.y-center.y) < radius
                    }) else { continue }
                    let fall = d <= hard ? 1 : 1-(d-hard)/(1-hard)
                    try paint(x,y,m,fall*fall*(3-2*fall))
                  }
                }
              }
            }
            continue
          }
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
        if let coverage {
          try VanishingHealing.apply(coverage, sample: sample, previous: previous, output: &output, charge: charge) { x, y in
            let p = PathPoint(Double(x) + 0.5, Double(y) + 0.5)
            return sourceColor(destinationCoordinate(p)) ?? .clear
          }
        }
      }
    }
    if program.drawsMeasurements {
      try VanishingAnnotationRaster.apply(program.settings,scene:scene,to:&output,charge:charge)
    }
    return output
  }

  private static func clamped(_ value: Double) -> Double {
    value.isFinite ? min(max(value, 0), 1) : value
  }
}
public struct VanishingEdit:Sendable {
  public let source:CraftDocument,result:CraftDocument
  public let layerID:UUID
  public let program:VanishingProgram
  public func updatingDisplayMetadata(_ settings: VanishingSettings) throws -> Self {
    guard !program.drawsMeasurements else {
      throw CraftError.invalid("Rendered measurement pixels must be prepared again when their settings change.")
    }
    var program = program, result = result
    program.settings = program.settings.withDisplayMetadata(from: settings)
    _ = try VanishingScene(program.settings, width: source.width, height: source.height)
    if let stored = result.vanishingPoint {
      result.vanishingPoint = stored.withDisplayMetadata(from: settings)
    }
    return Self(source: source, result: result, layerID: layerID, program: program)
  }
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
    if !program.operations.isEmpty || program.drawsMeasurements {
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
      } else {
        let index = d.layers.firstIndex { $0.id == layerID }!
        result.layers[index] = try applying(overlay, to: layer, in: d)
      }
    }
    try result.validate();try Task.checkCancellation();return Self(source:d,result:result,layerID:layerID,program:program)
  }
  private static func applying(_ overlay: Surface, to layer: Layer, in document: CraftDocument) throws -> Layer {
    let canvas = IntRect(x: 0, y: 0, width: document.width, height: document.height)
    let clipping: IntRect
    if let selection = document.selectionMask {
      guard let bounds = selection.bounds else { return layer }
      clipping = bounds
    } else {
      clipping = (document.selection ?? canvas).clipped(toWidth: canvas.width, height: canvas.height)
    }
    guard let content = try overlay.contentBounds() else { return layer }

    let transform = layer.coordinateTransform
    // Bilinear reconstruction has a one-pixel fringe on nonintegral sample grids.
    let sameGrid = transform.a == 1 && transform.b == 0 && transform.c == 0 && transform.d == 1
      && transform.tx == transform.tx.rounded() && transform.ty == transform.ty.rounded()
    let halo = sameGrid ? 0 : 1
    let left = max(clipping.x, content.x - halo)
    let top = max(clipping.y, content.y - halo)
    let right = min(clipping.x + clipping.width, content.x + content.width + halo)
    let bottom = min(clipping.y + clipping.height, content.y + content.height + halo)
    guard right > left, bottom > top else { return layer }
    let bounds = IntRect(x: left, y: top, width: right - left, height: bottom - top)

    var result = layer
    let alphaLocked = document.isTransparencyLocked(layer.id)
    _ = try ClonePainter.paintTarget(mask: false, bounds: bounds, on: &result, clipping: clipping,
      preserveTransparency: alphaLocked) { pixels, transform, clipping in
      let local = IntRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
      let inverse = try transform.inverted()
      let support = try overlay.projectedGeometrySupport(inverse, bounds: local, halo: 1)
      var changed = false
      for patch in GeometryPatchRegions(width: local.width, height: local.height, rectangles: support) {
        try Task.checkCancellation()
        for y in patch.y..<(patch.y + patch.height) {
          for x in patch.x..<(patch.x + patch.width) {
            let point = PathPoint(Double(x) + 0.5, Double(y) + 0.5).transformed(transform)
            guard point.x >= Double(clipping.x), point.x < Double(clipping.x + clipping.width),
              point.y >= Double(clipping.y), point.y < Double(clipping.y + clipping.height) else { continue }
            let coverage = document.selectionCoverage(x: Int(floor(point.x)), y: Int(floor(point.y)))
            guard coverage > 0 else { continue }
            let ink = WarpRaster.sample(overlay, point, method: .bilinear, clampEdges: false)
            guard ink.a > 0 else { continue }
            let before = VanishingEngine.read(pixels, x, y)
            if alphaLocked && before.a == 0 { continue }
            var after = VanishingEngine.over(ink, before)
            if alphaLocked { after.a = before.a }
            let pixel = before.mixing(after, coverage: coverage)
            guard pixel.isFinite else { throw CraftError.invalid("Nonfinite Vanishing Point output.") }
            VanishingEngine.write(&pixels, x, y, pixel)
            changed = true
          }
        }
      }
      return changed
    }
    return result
  }

  public func applied(to document:CraftDocument) throws -> CraftDocument { guard document==source else { throw CraftError.invalid("Vanishing Point source changed; preview again.") };return result }
}
