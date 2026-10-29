import Foundation

// Native translation of PhotoCraft features.rs/panorama.rs/transform.rs numeric
// registration primitives (MIT OR Apache-2.0). Image coordinates have Y down.
typealias PhotoPoint = SIMD2<Double>
struct PhotoHomography: Equatable, Sendable {
  var m: [Double]
  init(_ values: [Double]) { precondition(values.count == 9);m = values }
  static let identity = Self([1,0,0,0,1,0,0,0,1])
  static func translation(_ x: Double,_ y: Double) -> Self { Self([1,0,x,0,1,y,0,0,1]) }
  static func scale(_ k: Double) -> Self { Self([k,0,0,0,k,0,0,0,1]) }
  func apply(_ p: PhotoPoint) -> PhotoPoint {
    let w = m[6]*p.x+m[7]*p.y+m[8]
    return PhotoPoint((m[0]*p.x+m[1]*p.y+m[2])/w,(m[3]*p.x+m[4]*p.y+m[5])/w)
  }
  static func * (a: Self,b: Self) -> Self {
    var r = [Double](repeating:0,count:9)
    for i in 0..<3 { for j in 0..<3 { for k in 0..<3 { r[i*3+j] += a.m[i*3+k]*b.m[k*3+j] } } };return Self(r)
  }
  func inverse() -> Self? {
    let c = [m[4]*m[8]-m[5]*m[7],m[2]*m[7]-m[1]*m[8],m[1]*m[5]-m[2]*m[4],
      m[5]*m[6]-m[3]*m[8],m[0]*m[8]-m[2]*m[6],m[2]*m[3]-m[0]*m[5],
      m[3]*m[7]-m[4]*m[6],m[1]*m[6]-m[0]*m[7],m[0]*m[4]-m[1]*m[3]]
    let det = m[0]*c[0]+m[1]*c[3]+m[2]*c[6]
    guard det.isFinite,abs(det) >= 1e-12 else { return nil }
    let values = c.map{$0/det};return values.allSatisfy(\.isFinite) ? Self(values):nil
  }
}
struct PhotoRandom {
  var state: UInt64
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state;z = (z ^ (z>>30)) &* 0xBF58_476D_1CE4_E5B9;z = (z ^ (z>>27)) &* 0x94D0_49BB_1331_11EB;return z ^ (z>>31)
  }
  mutating func unit() -> Double { Double(next()>>11)/Double(UInt64(1)<<53) }
  mutating func below(_ n: Int) -> Int { Int(next()%UInt64(max(1,n))) }
}
enum PhotoLinearAlgebra {
  static func solve(_ n: Int,_ matrix: [Double],_ rhs: [Double],epsilon: Double = 1e-14) -> [Double]? {
    guard n > 0,matrix.count == n*n,rhs.count == n else { return nil }
    var a = matrix,b = rhs
    for c in 0..<n {
      var p = c;for r in c..<n where abs(a[r*n+c]) >= abs(a[p*n+c]) { p = r }
      guard a[p*n+c].isFinite,abs(a[p*n+c]) >= epsilon else { return nil }
      if p != c { for k in 0..<n { a.swapAt(c*n+k,p*n+k) };b.swapAt(c,p) }
      for r in (c+1)..<n {
        let f = a[r*n+c]/a[c*n+c]
        for k in c..<n { a[r*n+k] -= f*a[c*n+k] };b[r] -= f*b[c]
      }
    }
    var x = [Double](repeating:0,count:n)
    for r in (0..<n).reversed() { var s = 0.0;for k in (r+1)..<n { s += a[r*n+k]*x[k] };x[r] = (b[r]-s)/a[r*n+r] }
    return x.allSatisfy(\.isFinite) ? x:nil
  }
  static func leastSquares(_ rows: [([Double],Double)],columns n: Int) -> [Double]? {
    var a = [Double](repeating:0,count:n*n),b = [Double](repeating:0,count:n)
    for (r,value) in rows { for i in 0..<n { b[i] += r[i]*value;for j in 0..<n { a[i*n+j] += r[i]*r[j] } } }
    return solve(n,a,b,epsilon:1e-12)
  }
  static func normalizer(_ points: [PhotoPoint]) -> PhotoHomography {
    let n = Double(max(1,points.count)),center = points.reduce(PhotoPoint.zero,+)/n
    let distance = points.reduce(0) { $0+hypot($1.x-center.x,$1.y-center.y) }/n
    let s = distance > 1e-12 ? sqrt(2)/distance:1
    return PhotoHomography([s,0,-s*center.x,0,s,-s*center.y,0,0,1])
  }
}
enum PhotoMotion: Sendable {
  case translation,euclidean,similarity,homography
  var minimumPoints: Int { switch self { case .translation:1;case .euclidean,.similarity:2;case .homography:4 } }
  var parameterCount: Int { switch self { case .translation:2;case .euclidean:3;case .similarity:4;case .homography:8 } }
  func parameters(_ h: PhotoHomography) -> [Double] {
    let m = h.m.map{$0/h.m[8]}
    switch self {
    case .translation:return [m[2],m[5]]
    case .euclidean:return [atan2(m[3],m[0]),m[2],m[5]]
    case .similarity:return [m[0],m[3],m[2],m[5]]
    case .homography:return Array(m.prefix(8))
    }
  }
  func matrix(_ p: [Double]) -> PhotoHomography {
    switch self {
    case .translation:return .translation(p[0],p[1])
    case .euclidean:return PhotoHomography([cos(p[0]),-sin(p[0]),p[1],sin(p[0]),cos(p[0]),p[2],0,0,1])
    case .similarity:return PhotoHomography([p[0],-p[1],p[2],p[1],p[0],p[3],0,0,1])
    case .homography:return PhotoHomography(p+[1])
    }
  }
  func fit(_ source: [PhotoPoint],_ destination: [PhotoPoint]) -> PhotoHomography? {
    let n = source.count
    guard n >= minimumPoints,n == destination.count else { return nil }
    switch self {
    case .translation:
      var delta = PhotoPoint.zero;for i in 0..<n { delta += destination[i]-source[i] };delta /= Double(n)
      return .translation(delta.x,delta.y)
    case .euclidean:
      let cs = source.reduce(PhotoPoint.zero,+)/Double(n),cd = destination.reduce(PhotoPoint.zero,+)/Double(n)
      var xx = 0.0,xy = 0.0
      for i in 0..<n { let a = source[i]-cs,b = destination[i]-cd;xx += a.x*b.x+a.y*b.y;xy += a.x*b.y-a.y*b.x }
      let theta = atan2(xy,xx),s = sin(theta),c = cos(theta)
      return PhotoHomography([c,-s,cd.x-(c*cs.x-s*cs.y),s,c,cd.y-(s*cs.x+c*cs.y),0,0,1])
    case .similarity:
      var rows = [([Double],Double)]()
      for i in 0..<n { let s = source[i],d = destination[i];rows.append(([s.x,-s.y,1,0],d.x));rows.append(([s.y,s.x,0,1],d.y)) }
      guard let v = PhotoLinearAlgebra.leastSquares(rows,columns:4) else { return nil }
      return PhotoHomography([v[0],-v[1],v[2],v[1],v[0],v[3],0,0,1])
    case .homography:
      let ts = PhotoLinearAlgebra.normalizer(source),td = PhotoLinearAlgebra.normalizer(destination)
      var rows = [([Double],Double)]()
      for i in 0..<n {
        let s = ts.apply(source[i]),d = td.apply(destination[i])
        rows.append(([s.x,s.y,1,0,0,0,-d.x*s.x,-d.x*s.y],d.x))
        rows.append(([0,0,0,s.x,s.y,1,-d.y*s.x,-d.y*s.y],d.y))
      }
      guard let h = PhotoLinearAlgebra.leastSquares(rows,columns:8),let inverse = td.inverse() else { return nil }
      let m = inverse * PhotoHomography(h+[1]) * ts,k = m.m[8]
      guard abs(k) > 1e-12 else { return nil };let values = m.m.map{$0/k}
      return values.allSatisfy(\.isFinite) ? PhotoHomography(values):nil
    }
  }
  func ransac(_ source: [PhotoPoint],_ destination: [PhotoPoint],iterations: Int,threshold: Double,seed: UInt64) throws -> (PhotoHomography,[Int])? {
    let k = minimumPoints,n = source.count
    guard n >= k,n == destination.count else { return nil }
    var rng = PhotoRandom(state:seed ^ 0x5EED_0FA1),best: (PhotoHomography,[Int])?
    func inliers(_ h: PhotoHomography) -> [Int] {
      source.indices.filter { i in let p = h.apply(source[i]);return p.x.isFinite && p.y.isFinite && hypot(p.x-destination[i].x,p.y-destination[i].y) <= threshold }
    }
    for _ in 0..<max(1,iterations) {
      try Task.checkCancellation();var indices = n == k ? Array(0..<n):[]
      while indices.count < k { let i = rng.below(n);if !indices.contains(i) { indices.append(i) } }
      guard let h = fit(indices.map{source[$0]},indices.map{destination[$0]}) else { continue }
      let selected = inliers(h)
      if best == nil || selected.count > best!.1.count { best = (h,selected) }
    }
    guard let (h,selected) = best,selected.count >= k else { return nil }
    let refined = fit(selected.map{source[$0]},selected.map{destination[$0]}) ?? h,inliers2 = inliers(refined)
    return inliers2.count >= selected.count ? (refined,inliers2):(h,selected)
  }
}
