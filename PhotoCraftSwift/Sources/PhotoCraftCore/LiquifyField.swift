import Foundation

/// Inverse displacement: output p samples the source at p+d(p). Freeze is0...1.
public struct LiquifyField: Sendable, Equatable {
  public let width: Int, height: Int, columns: Int, rows: Int
  public let cell: Double
  public private(set) var displacement: [SIMD2<Float>]
  public private(set) var freeze: [Float]
  private var visitedNodes = 0
  public init(width: Int, height: Int, cell: Double = 0) throws {
    guard width > 0, height > 0, width <= 65536, height <= 65536, width <= RasterFilterEngine.maximumPixels / height,
      cell.isFinite, cell == 0 || (1...64).contains(cell) else { throw CraftError.invalid("Invalid Liquify field dimensions or spacing.") }
    let spacing = cell == 0 ? (width*height <= 4_200_000 ? 2.0 : 4.0) : cell
    let w = Int(ceil(Double(width)/spacing))+2, h = Int(ceil(Double(height)/spacing))+2
    guard w <= 4_300_000/h else { throw CraftError.invalid("Liquify mesh exceeds4.3million nodes. Use a larger meshSize.") }
    self.width = width; self.height = height; self.cell = spacing; columns = w; rows = h
    displacement = Array(repeating:.zero,count:w*h); freeze = Array(repeating:0,count:w*h)
  }
  public var isIdentity: Bool { displacement.allSatisfy { $0 == .zero } }
  public var maximumDisplacement: Float { displacement.reduce(0) { max($0,hypot($1.x,$1.y)) } }
  public func node(x: Int, y: Int) -> SIMD2<Double> { SIMD2(0.5+Double(x)*cell,0.5+Double(y)*cell) }
  private static func bilinear(_ values: [SIMD2<Float>], _ width: Int, _ height: Int, _ x: Double, _ y: Double) -> SIMD2<Double> {
    guard x > -1, y > -1, x < Double(width), y < Double(height) else { return .zero }
    let x = min(Double(width-1),max(0,x)), y = min(Double(height-1),max(0,y))
    let i = min(width-2,Int(x)), j = min(height-2,Int(y)), fx = x-Double(i), fy = y-Double(j)
    func at(_ x: Int,_ y: Int) -> SIMD2<Double> { let v = values[y*width+x]; return SIMD2(Double(v.x),Double(v.y)) }
    return (at(i,j)*(1-fx)+at(i+1,j)*fx)*(1-fy)+(at(i,j+1)*(1-fx)+at(i+1,j+1)*fx)*fy
  }
  public func sample(x: Double,y: Double) -> SIMD2<Double> {
    Self.bilinear(displacement,columns,rows,(x-0.5)/cell,(y-0.5)/cell)
  }
  public func frozen(x: Double,y: Double) -> Float {
    guard x.isFinite,y.isFinite else { return 0 }
    let gx = min(Double(columns-1),max(0,(x-0.5)/cell)), gy = min(Double(rows-1),max(0,(y-0.5)/cell))
    let i = min(columns-2,Int(gx)), j = min(rows-2,Int(gy)), fx = Float(gx-Double(i)), fy = Float(gy-Double(j))
    func at(_ x: Int,_ y: Int) -> Float { freeze[y*columns+x] }
    return (at(i,j)*(1-fx)+at(i+1,j)*fx)*(1-fy)+(at(i,j+1)*(1-fx)+at(i+1,j+1)*fx)*fy
  }
  public mutating func apply(_ stroke: LiquifyStroke) throws {
    try stroke.validate(); try Task.checkCancellation()
    if stroke.tool.global {
      guard visitedNodes <= 250_000_000-displacement.count else { throw CraftError.invalid("Liquify exceeds its computation budget.") }; visitedNodes += displacement.count
    }
    switch stroke.tool {
    case .freezeAll: freeze = Array(repeating:1,count:freeze.count)
    case .thawAll: freeze = Array(repeating:0,count:freeze.count)
    case .invertFreeze: for i in freeze.indices { freeze[i] = 1-freeze[i] }
    case .reconstructAll:
      let k = Float((stroke.amount ?? 100)/100)
      for i in displacement.indices { displacement[i] *= 1-k*(1-freeze[i]) }
    case .lassoMask: try lasso(stroke)
    default:
      guard let first = stroke.points.first else { return }
      if stroke.tool.stationary { try dab(stroke,center:SIMD2(first[0],first[1]),delta:.zero,pointPressure:first.count == 3 ? first[2] : 1) }
      for (a,b) in zip(stroke.points,stroke.points.dropFirst()) { try segment(stroke,from:a,to:b) }
    }
  }
  public mutating func segment(_ s: LiquifyStroke, from a: [Double], to b: [Double]) throws {
    var validation = s; validation.points = [a,b]; try validation.validate()
    let pa = a.count == 3 ? a[2] : 1, pb = b.count == 3 ? b[2] : 1
    let delta = SIMD2(b[0]-a[0],b[1]-a[1]), length = hypot(delta.x,delta.y)
    if length == 0 {
      if s.tool.stationary { try dab(s,center:SIMD2(b[0],b[1]),delta:.zero,pointPressure:pb) }; return
    }
    let steps = Int(ceil(length/max(0.5,s.size*0.1)))
    guard steps <= 100_000 else { throw CraftError.invalid("Liquify stroke has too many interpolated dabs.") }
    for i in 1...steps {
      try Task.checkCancellation()
      let t = Double(i)/Double(steps), motion = delta/Double(steps)
      let current = SIMD2(a[0],a[1])+delta*t
      try dab(s,center:s.tool.stationary ? current : current-motion,delta:motion,pointPressure:pa+(pb-pa)*t)
    }
  }
  private mutating func lasso(_ s: LiquifyStroke) throws {
    guard s.points.count >= 3 else { return }
    let lower = max(0,Int(ceil((s.points.map { $0[1] }.min()!-0.5)/cell)))
    let upper = min(rows-1,Int(floor((s.points.map { $0[1] }.max()!-0.5)/cell)))
    guard lower <= upper else { return }
    let work = (upper-lower+1)*s.points.count
    guard visitedNodes <= 250_000_000-work else { throw CraftError.invalid("Liquify lasso exceeds its computation budget.") }; visitedNodes += work
    for j in lower...upper {
      try Task.checkCancellation(); let y = node(x:0,y:j).y
      var intersections = [Double](), last = s.points.last!
      for p in s.points {
        if (p[1] > y) != (last[1] > y) { intersections.append(p[0]+(y-p[1])*(last[0]-p[0])/(last[1]-p[1])) }; last = p
      }
      intersections.sort()
      for k in stride(from:0,to:intersections.count-1,by:2) {
        let start = max(0,Int(ceil((intersections[k]-0.5)/cell))), end = min(columns-1,Int(ceil((intersections[k+1]-0.5)/cell))-1)
        if start <= end { for i in start...end { freeze[j*columns+i] = (s.amount ?? 1) > 0.5 ? 1 : 0 } }
      }
    }
  }
  private mutating func dab(_ s: LiquifyStroke, center c: SIMD2<Double>, delta: SIMD2<Double>, pointPressure: Double) throws {
    if s.tool == .lassoMask || s.tool.global { return }
    let r = s.size/2, strength = s.pressure/100*pointPressure, rate = s.rate/100, density = s.density/100
    guard strength > 0 else { return }
    let i0 = max(0,Int(floor((c.x-r-0.5)/cell))), j0 = max(0,Int(floor((c.y-r-0.5)/cell)))
    let i1 = min(columns-1,Int(ceil((c.x+r-0.5)/cell))), j1 = min(rows-1,Int(ceil((c.y+r-0.5)/cell)))
    guard i0 <= i1, j0 <= j1 else { return }
    let count = (i1-i0+1)*(j1-j0+1)
    guard visitedNodes <= 250_000_000-count else { throw CraftError.invalid("Liquify stroke program exceeds its computation budget.") }; visitedNodes += count
    let margin = Int(ceil((max(abs(delta.x),abs(delta.y))+r*0.2)/cell))+2
    let sx = max(0,i0-margin), sy = max(0,j0-margin), ex = min(columns-1,i1+margin), ey = min(rows-1,j1+margin)
    let sw = ex-sx+1, sh = ey-sy+1
    var snapshot = [SIMD2<Float>](); snapshot.reserveCapacity(sw*sh)
    for j in sy...ey { snapshot.append(contentsOf:displacement[(j*columns+sx)...(j*columns+ex)]) }
    func old(_ x: Double,_ y: Double) -> SIMD2<Double> {
      let lx = x-Double(sx), ly = y-Double(sy)
      if lx >= 0,ly >= 0,lx <= Double(sw-1),ly <= Double(sh-1) { return Self.bilinear(snapshot,sw,sh,lx,ly) }
      return Self.bilinear(displacement,columns,rows,x,y)
    }
    var writes = [(Int,SIMD2<Float>,Float)](); writes.reserveCapacity(count)
    for j in j0...j1 {
      try Task.checkCancellation()
      for i in i0...i1 {
        let p = node(x:i,y:j), diff = p-c, distance = (diff.x*diff.x+diff.y*diff.y)/(r*r)
        if distance >= 1 { continue }
        let fall = 1-density+density*(1-distance)*(1-distance), index = j*columns+i, raw = strength*fall
        if s.tool == .freeze || s.tool == .thaw {
          let f = Double(freeze[index])+(s.tool == .freeze ? raw : -raw)
          writes.append((index,displacement[index],Float(min(1,max(0,f))))); continue
        }
        let k = raw*(1-Double(freeze[index])); if k <= 0 { continue }
        let current = displacement[index], value: SIMD2<Float>
        if s.tool == .reconstruct { value = current*Float(1-k*(0.1+0.4*rate)) }
        else if s.tool == .smooth {
          var mean = SIMD2<Float>.zero
          for (dx,dy) in [(-1,0),(1,0),(0,-1),(0,1),(-1,-1),(1,-1),(-1,1),(1,1)] {
            let x = min(sw-1,max(0,i-sx+dx)), y = min(sh-1,max(0,j-sy+dy)); mean += snapshot[y*sw+x]/8
          }
          value = current+(mean-current)*Float(k*(0.1+0.4*rate))
        } else {
          let q: SIMD2<Double>
          switch s.tool {
          case .forwardWarp: q = p-delta*k
          case .pushLeft: q = SIMD2(p.x-k*delta.y,p.y+k*delta.x)
          case .twirlCw,.twirlCcw:
            let theta = -k*rate*0.12*(s.tool == .twirlCw ? 1.0 : -1.0), sn = sin(theta), cs = cos(theta)
            q = c+SIMD2(diff.x*cs-diff.y*sn,diff.x*sn+diff.y*cs)
          case .pucker: q = c+diff*(1+k*rate*0.06)
          default: q = c+diff*(1-k*rate*0.06)
          }
          let previous = old((q.x-p.x)/cell+Double(i),(q.y-p.y)/cell+Double(j)), d = q+previous-p
          guard d.x.isFinite,d.y.isFinite,abs(d.x) < 1_000_000,abs(d.y) < 1_000_000 else { throw CraftError.invalid("Liquify displacement exceeds its numeric range.") }
          value = SIMD2(Float(d.x),Float(d.y))
        }
        writes.append((index,value,freeze[index]))
      }
    }
    for (i,d,f) in writes { displacement[i] = d; freeze[i] = f }
  }
  static func weights(_ t: Double) -> [Double] {
    let a = t*t, b = a*t
    return [-0.5*b+a-0.5*t,1.5*b-2.5*a+1,-1.5*b+2*a+0.5*t,0.5*b-0.5*a]
  }
  public func cubicSample(x: Double,y: Double) -> SIMD2<Double> {
    guard x.isFinite,y.isFinite,abs(x) <= 1_000_000,abs(y) <= 1_000_000 else { return .zero }
    let gx = (x-0.5)/cell, gy = (y-0.5)/cell, ix = Int(floor(gx)), iy = Int(floor(gy))
    let wx = Self.weights(gx-floor(gx)), wy = Self.weights(gy-floor(gy)); var result = SIMD2<Double>.zero
    for j in 0..<4 { for i in 0..<4 {
      let d = displacement[min(rows-1,max(0,iy-1+j))*columns+min(columns-1,max(0,ix-1+i))]
      result += SIMD2(Double(d.x),Double(d.y))*(wx[i]*wy[j])
    } }; return result
  }
  func resample(_ input: [SIMD4<Double>], width w: Int, height h: Int, preview: Bool = false) throws -> [SIMD4<Double>] {
    if isIdentity { return input }
    let scaleX = Double(w)/Double(width), scaleY = Double(h)/Double(height); var output = input
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        let px = (Double(x)+0.5)/scaleX, py = (Double(y)+0.5)/scaleY
        let offset = preview ? sample(x:px,y:py) : cubicSample(x:px,y:py)
        if offset == .zero { continue }
        let u = Double(x)+offset.x*scaleX, v = Double(y)+offset.y*scaleY
        let ix = Int(floor(u)), iy = Int(floor(v)), fx = u-floor(u), fy = v-floor(v)
        func at(_ x: Int,_ y: Int) -> SIMD4<Double> { input[min(h-1,max(0,y))*w+min(w-1,max(0,x))] }
        var result = SIMD4<Double>.zero
        if preview { result = (at(ix,iy)*(1-fx)+at(ix+1,iy)*fx)*(1-fy)+(at(ix,iy+1)*(1-fx)+at(ix+1,iy+1)*fx)*fy }
        else {
          let wx = Self.weights(fx), wy = Self.weights(fy)
          for j in 0..<4 { for i in 0..<4 { result += at(ix-1+i,iy-1+j)*(wx[i]*wy[j]) } }
        }
        result.w = min(1,max(0,result.w)); if result.w <= 1e-15 { result = .zero }
        output[y*w+x] = result
      }
    }
    return output
  }
}

extension LiquifyField {
  /// Independent native face deformation; Adobe's proprietary face mesh is not reproduced.
  mutating func applyFace(_ face: LiquifyFaceAdjustment) throws {
    try face.validate()
    func rect(_ a: [Double]) -> (center: SIMD2<Double>, size: SIMD2<Double>) {
      (SIMD2((a[0]+a[2]/2)*Double(width),(a[1]+a[3]/2)*Double(height)),SIMD2(a[2]*Double(width),a[3]*Double(height)))
    }
    let box = rect(face.geometry.bounds)
    for (side,eye) in [(true,face.geometry.leftEye),(false,face.geometry.rightEye)] {
      let r = rect(eye), size = face[side ? .leftEyeSize : .rightEyeSize]/100
      let horizontal = face[side ? .leftEyeWidth : .rightEyeWidth]/100, vertical = face[side ? .leftEyeHeight : .rightEyeHeight]/100
      let tilt = face[side ? .leftEyeTilt : .rightEyeTilt]/100
      let distance = face[.eyeDistance]/100 * box.size.x*0.1 * (r.center.x < box.center.x ? -1.0 : 1.0)
      try warpFeature(center:r.center,radius:r.size*2,scale:SIMD2(1+0.35*(size+horizontal),1+0.35*(size+vertical)),shift:SIMD2(distance,0),angle:tilt*Double.pi/12)
    }
    let nose = rect(face.geometry.nose), mouth = rect(face.geometry.mouth)
    try warpFeature(center:nose.center,radius:nose.size*1.8,scale:SIMD2(1+face[.noseWidth]/250,1+face[.noseHeight]/250))
    try warpFeature(center:mouth.center,radius:mouth.size*1.6,scale:SIMD2(1+face[.mouthWidth]/250,1+face[.mouthHeight]/250))
    for direction in [-1.0,1.0] {
      try warpFeature(center:mouth.center+SIMD2(direction*mouth.size.x*0.42,0),radius:SIMD2(mouth.size.x*0.5,mouth.size.y*1.2),shift:SIMD2(0,-face[.smile]/100*mouth.size.y*0.3))
    }
    try warpFeature(center:mouth.center-SIMD2(0,mouth.size.y*0.2),radius:SIMD2(mouth.size.x*0.7,mouth.size.y*0.6),shift:SIMD2(0,-face[.upperLip]/100*mouth.size.y*0.18))
    try warpFeature(center:mouth.center+SIMD2(0,mouth.size.y*0.2),radius:SIMD2(mouth.size.x*0.7,mouth.size.y*0.6),shift:SIMD2(0,face[.lowerLip]/100*mouth.size.y*0.18))
    try warpFeature(center:box.center,radius:box.size*0.75,scale:SIMD2(1+face[.faceWidth]/500,1))
    try warpFeature(center:box.center+SIMD2(0,box.size.y*0.28),radius:SIMD2(box.size.x*0.65,box.size.y*0.35),scale:SIMD2(1+face[.jawline]/400,1))
    try warpFeature(center:box.center+SIMD2(0,box.size.y*0.42),radius:SIMD2(box.size.x*0.55,box.size.y*0.28),shift:SIMD2(0,face[.chinHeight]/100*box.size.y*0.1))
    try warpFeature(center:box.center-SIMD2(0,box.size.y*0.38),radius:SIMD2(box.size.x*0.6,box.size.y*0.35),shift:SIMD2(0,-face[.forehead]/100*box.size.y*0.1))
  }
  private mutating func warpFeature(center: SIMD2<Double>, radius: SIMD2<Double>, scale: SIMD2<Double> = SIMD2(repeating:1), shift: SIMD2<Double> = .zero, angle: Double = 0) throws {
    guard scale != SIMD2(repeating:1) || shift != .zero || angle != 0 else { return }
    let rx = max(1,radius.x), ry = max(1,radius.y)
    let x0 = max(0,Int(floor((center.x-rx-0.5)/cell))), x1 = min(columns-1,Int(ceil((center.x+rx-0.5)/cell)))
    let y0 = max(0,Int(floor((center.y-ry-0.5)/cell))), y1 = min(rows-1,Int(ceil((center.y+ry-0.5)/cell)))
    guard x0 <= x1,y0 <= y1 else { return }
    let count = (x1-x0+1)*(y1-y0+1)
    guard visitedNodes <= 250_000_000-count else { throw CraftError.invalid("Face Liquify exceeds its computation budget.") }; visitedNodes += count
    var writes = [(Int,SIMD2<Float>)](); writes.reserveCapacity(count)
    for y in y0...y1 {
      try Task.checkCancellation()
      for x in x0...x1 {
        let p = node(x:x,y:y), d = p-center, t = d.x*d.x/(rx*rx)+d.y*d.y/(ry*ry), i = y*columns+x
        if t >= 1 || freeze[i] >= 1 { continue }
        let weight = (1-t)*(1-t)*Double(1-freeze[i]), v = (d-shift)/scale
        let q = center+SIMD2(v.x*cos(-angle)-v.y*sin(-angle),v.x*sin(-angle)+v.y*cos(-angle))
        let from = p+(q-p)*weight, old = sample(x:from.x,y:from.y), result = from+old-p
        writes.append((i,SIMD2(Float(result.x),Float(result.y))))
      }
    }
    for (i,d) in writes { displacement[i] = d }
  }
  /// Preview input is a downsampled surface; displacement scales from its saved domain.
  public func render(_ source: Surface, preview: Bool = false) throws -> Surface {
    guard source.width <= RasterFilterEngine.maximumPixels/source.height else { throw CraftError.invalid("Liquify preview exceeds its pixel limit.") }
    if isIdentity { return source }
    let linear = source.depth == .f32
    var samples = [SIMD4<Double>](); samples.reserveCapacity(source.width*source.height)
    for y in 0..<source.height {
      try Task.checkCancellation()
      for x in 0..<source.width {
        let p = linear ? source.linearPixel(x:x,y:y) : source.pixel(x:x,y:y)
        guard p.isFinite else { throw CraftError.invalid("Nonfinite Liquify input.") }
        samples.append(SIMD4(Double(p.r*p.a),Double(p.g*p.a),Double(p.b*p.a),Double(p.a)))
      }
    }
    let values = try resample(samples,width:source.width,height:source.height,preview:preview); var result = source
    for y in 0..<source.height {
      try Task.checkCancellation()
      for x in 0..<source.width {
        let v = values[y*source.width+x], p = v.w > 1e-15 ? Pixel(Float(v.x/v.w),Float(v.y/v.w),Float(v.z/v.w),Float(v.w)) : .clear
        if linear { result.setLinearPixel(x:x,y:y,p) } else { result.setPixel(x:x,y:y,p) }
      }
    }; return result
  }
}
