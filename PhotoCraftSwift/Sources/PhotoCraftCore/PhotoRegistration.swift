import Foundation

public struct PhotoAlignSettings: Codable, Equatable, Sendable {
  public enum Projection: String, CaseIterable, Codable, Sendable { case auto,perspective,cylindrical,spherical,collage,reposition
    public var title: String { rawValue.capitalized }
    var motion: PhotoMotion { switch self { case .auto,.perspective:.homography;case .cylindrical,.spherical:.euclidean;case .collage:.similarity;case .reposition:.translation } }
    var planar: Bool { self != .cylindrical && self != .spherical }
  }
  public var projection: Projection = .auto
  public var referenceLayerID: UUID?
  public var focalLengthPixels: Double?
  public init() {}
  public func validate() throws { if let focalLengthPixels,(!focalLengthPixels.isFinite || focalLengthPixels < 10 || focalLengthPixels > 1_000_000) { throw CraftError.invalid("Focal length must be between 10 and 1,000,000 pixels.") } }
}
struct PhotoPlacement: Sendable {
  var projection: PhotoAlignSettings.Projection
  var focal: Double
  var center: PhotoPoint
  var h: PhotoHomography = .identity
  func project(_ p: PhotoPoint) -> PhotoPoint {
    let d = p-center
    switch projection {
    case .cylindrical:return PhotoPoint(focal*atan2(d.x,focal),focal*d.y/hypot(d.x,focal))
    case .spherical:return PhotoPoint(focal*atan2(d.x,focal),focal*atan2(d.y,hypot(d.x,focal)))
    default:return d
    }
  }
  func unproject(_ p: PhotoPoint) -> PhotoPoint? {
    if projection.planar { return p+center }
    let t = p.x/focal,v = p.y/focal
    guard abs(t) < 1.55,projection != .spherical || abs(v) < 1.55 else { return nil }
    return PhotoPoint(focal*tan(t),projection == .cylindrical ? p.y/cos(t):focal*tan(v)/cos(t))+center
  }
  func forward(_ p: PhotoPoint) -> PhotoPoint { h.apply(project(p)) }
  func scaled(_ k: Double) -> Self { Self(projection:projection,focal:focal*k,center:center*k,h:.scale(k)*h * .scale(1/k)) }
  func bounds(width: Double,height: Double) throws -> IntRect {
    var lo = PhotoPoint(repeating:Double.infinity),hi = PhotoPoint(repeating:-Double.infinity)
    for i in 0...64 { let t = Double(i)/64;for p in [PhotoPoint(t*width,0),PhotoPoint(t*width,height),PhotoPoint(0,t*height),PhotoPoint(width,t*height)] {
      let q = project(p),denominator = h.m[6]*q.x+h.m[7]*q.y+h.m[8],v = h.apply(q)
      guard denominator > 1e-9,v.x.isFinite,v.y.isFinite,abs(v.x) <= 1_000_000,abs(v.y) <= 1_000_000 else { throw CraftError.invalid("Alignment projection crosses an unstable horizon.") }
      lo = PhotoPoint(min(lo.x,v.x),min(lo.y,v.y));hi = PhotoPoint(max(hi.x,v.x),max(hi.y,v.y))
    } }
    let x = Int(floor(lo.x)),y = Int(floor(lo.y))
    return IntRect(x:x,y:y,width:max(1,Int(ceil(hi.x))-x),height:max(1,Int(ceil(hi.y))-y))
  }
}
enum PhotoRegistration {
  struct Pair { var a: Int;var b: Int;var pa: [PhotoPoint];var pb: [PhotoPoint];var h: PhotoHomography }
  struct Result { var projection: PhotoAlignSettings.Projection;var placements: [PhotoPlacement];var matches: Int;var rms: Double }
  static func pairs(_ features: [PhotoFeatures]) throws -> [Pair] {
    var pairs = [Pair]()
    for a in features.indices { for b in (a+1)..<features.count {
      let matches = try PhotoFeatures.match(features[b].descriptors,features[a].descriptors)
      guard matches.count >= 10 else { continue }
      let pa = matches.map{features[a].points[$0.1]},pb = matches.map{features[b].points[$0.0]}
      let threshold = max(1.5,min(4,Double(max(features[a].width,features[a].height))/300))
      guard let (h,indices) = try PhotoMotion.homography.ransac(pb,pa,iterations:1200,threshold:threshold,seed:UInt64(a*131+b)),indices.count >= 10,Double(indices.count) >= 8+0.3*Double(matches.count) else { continue }
      pairs.append(Pair(a:a,b:b,pa:indices.map{pa[$0]},pb:indices.map{pb[$0]},h:h))
    } };return pairs
  }
  static func focal(_ h: PhotoHomography,_ ca: PhotoPoint,_ cb: PhotoPoint) -> Double? {
    let m = (PhotoHomography.translation(-ca.x,-ca.y)*h * .translation(cb.x,cb.y)).m
    func choose(_ candidates: [(Double,Double)]) -> Double? { candidates.filter{abs($0.1) > 1e-12 && $0.0/$0.1 > 0}.max{abs($0.1) < abs($1.1)}.map{$0.0/$0.1} }
    let a = choose([(-(m[0]*m[1]+m[3]*m[4]),m[6]*m[7]),(m[1]*m[1]+m[4]*m[4]-m[0]*m[0]-m[3]*m[3],m[6]*m[6]-m[7]*m[7])])
    let b = choose([(-m[2]*m[5],m[0]*m[3]+m[1]*m[4]),(m[5]*m[5]-m[2]*m[2],m[0]*m[0]+m[1]*m[1]-m[3]*m[3]-m[4]*m[4])])
    if let a,let b { return sqrt(sqrt(a*b)) };return (a ?? b).map{sqrt($0)}
  }
  static func align(_ features: [PhotoFeatures],projection: PhotoAlignSettings.Projection,reference: Int,focal supplied: Double?) throws -> Result {
    let pairs = try pairs(features)
    guard !pairs.isEmpty else { throw CraftError.invalid("Auto-Align could not find enough shared detail. Use overlapping images with visible texture.") }
    let side = Double(features.map{max($0.width,$0.height)}.max() ?? 1)
    let estimates = pairs.compactMap { p in focal(p.h,PhotoPoint(Double(features[p.a].width)/2,Double(features[p.a].height)/2),PhotoPoint(Double(features[p.b].width)/2,Double(features[p.b].height)/2)) }.filter{$0.isFinite && $0 >= side*0.2 && $0 <= side*20}.sorted()
    let focal = supplied ?? (estimates.isEmpty ? side:estimates[estimates.count/2])
    if projection != .auto { return try layout(features,pairs,projection,reference,focal) }
    if let plane = try? layout(features,pairs,.perspective,reference,focal),!stretched(plane,features) { return plane }
    try Task.checkCancellation()
    return try layout(features,pairs,.cylindrical,reference,focal)
  }
  static func stretched(_ result: Result,_ f: [PhotoFeatures]) -> Bool {
    var minX = Double.infinity,maxX = -Double.infinity
    for (i,p) in result.placements.enumerated() {
      let w = Double(f[i].width),h = Double(f[i].height),c = [PhotoPoint(0,0),PhotoPoint(w,0),PhotoPoint(w,h),PhotoPoint(0,h)].map{p.forward($0)}
      var area = 0.0;for j in 0..<4 { area += c[j].x*c[(j+1)%4].y-c[j].y*c[(j+1)%4].x }
      let ratio = area/(2*w*h)
      guard ratio.isFinite,ratio >= 0.3,ratio <= 3,(try? p.bounds(width:w,height:h)) != nil else { return true }
      for q in c { minX = min(minX,q.x);maxX = max(maxX,q.x) }
    };return 2*atan((maxX-minX)/(2*result.placements[0].focal)) > 110*Double.pi/180
  }
  static func layout(_ f: [PhotoFeatures],_ pairs: [Pair],_ projection: PhotoAlignSettings.Projection,_ reference: Int,_ focal: Double) throws -> Result {
    let motion = projection.motion
    var placements = f.map { PhotoPlacement(projection:projection,focal:focal,center:PhotoPoint(Double($0.width)/2,Double($0.height)/2)) }
    var edges = [(a:Int,b:Int,weight:Int,h:PhotoHomography)](),verified = [Pair]()
    for p in pairs {
      let qa = p.pa.map{placements[p.a].project($0)},qb = p.pb.map{placements[p.b].project($0)}
      let threshold = max(2,min(5,Double(max(f[p.a].width,f[p.a].height))/250))
      guard let (h,indices) = try motion.ransac(qb,qa,iterations:600,threshold:threshold,seed:UInt64(p.a*977+p.b)),indices.count >= 8,indices.count*2 >= p.pa.count else { continue }
      edges.append((p.a,p.b,indices.count,h));verified.append(Pair(a:p.a,b:p.b,pa:indices.map{p.pa[$0]},pb:indices.map{p.pb[$0]},h:h))
    }
    var tf = [PhotoHomography?](repeating:nil,count:f.count);tf[reference] = .translation(placements[reference].center.x,placements[reference].center.y)
    while true {
      var best: (Int,Int,PhotoHomography)?
      for e in edges {
        var candidate: (Int,PhotoHomography)?
        if let a = tf[e.a],tf[e.b] == nil { candidate = (e.b,a*e.h) }
        else if let b = tf[e.b],tf[e.a] == nil,let inverse = e.h.inverse() { candidate = (e.a,b*inverse) }
        if let c = candidate,best == nil || e.weight > best!.1 { best = (c.0,e.weight,c.1) }
      }
      guard let b = best else { break };tf[b.0] = b.2
    }
    guard tf.allSatisfy({$0 != nil}) else { throw CraftError.invalid("Some layers could not be aligned. Every selected layer must overlap a matching layer; no changes were applied.") }
    for i in placements.indices { placements[i].h = tf[i]! }
    // Jointly refine all placed transforms, fixing the reference. Bounded samples keep
    // this cancellable and suitable for interactive previews; lens fitting is separate.
    let movable = f.indices.filter{$0 != reference},mp = motion.parameterCount
    let samples = verified.map { p in let ids = Array(stride(from:0,to:p.pa.count,by:max(1,(p.pa.count+79)/80)));return Pair(a:p.a,b:p.b,pa:ids.map{p.pa[$0]},pb:ids.map{p.pb[$0]},h:p.h) }
    var params = movable.flatMap{motion.parameters(placements[$0].h)}
    func decode(_ values: [Double]) -> [PhotoPlacement] { var p = placements;for (k,i) in movable.enumerated() { p[i].h = motion.matrix(Array(values[k*mp..<(k+1)*mp])) };return p }
    func residual(_ values: [Double]) -> [Double] {
      let p = decode(values);var r = [Double]()
      for pair in samples { for i in pair.pa.indices { let delta = p[pair.a].forward(pair.pa[i])-p[pair.b].forward(pair.pb[i]);r.append(delta.x);r.append(delta.y) } };return r
    }
    var r = residual(params),cost = r.reduce(0){$0+$1*$1},lambda = 1e-3
    let n = params.count
    for _ in 0..<20 {
      try Task.checkCancellation();var jacobian = [[Double]]()
      for j in 0..<n {
        let step = 1e-6*(1+abs(params[j]));var plus = params,minus = params;plus[j] += step;minus[j] -= step
        let a = residual(plus),b = residual(minus);jacobian.append(zip(a,b).map{($0-$1)/(2*step)})
      }
      var a = [Double](repeating:0,count:n*n),b = [Double](repeating:0,count:n)
      for j in 0..<n { b[j] = -zip(jacobian[j],r).reduce(0){$0+$1.0*$1.1};for k in 0..<n { a[j*n+k] = zip(jacobian[j],jacobian[k]).reduce(0){$0+$1.0*$1.1} } }
      var improved = false
      for _ in 0..<8 {
        var damped = a;for j in 0..<n { damped[j*n+j] += lambda*(a[j*n+j]+1e-9) }
        guard let delta = PhotoLinearAlgebra.solve(n,damped,b) else { lambda *= 10;continue }
        let next = zip(params,delta).map(+),nr = residual(next),nc = nr.reduce(0){$0+$1*$1}
        if nc.isFinite,nc < cost { improved = cost-nc > 1e-10*max(cost,1e-12);params = next;r = nr;cost = nc;lambda = max(1e-9,lambda*0.3);break };lambda *= 10
      }
      if !improved { break }
    }
    placements = decode(params)
    guard cost.isFinite else { throw CraftError.invalid("Alignment did not converge.") }
    return Result(projection:projection,placements:placements,matches:edges.reduce(0){$0+$1.weight},rms:sqrt(cost/Double(max(1,r.count/2))))
  }
}
