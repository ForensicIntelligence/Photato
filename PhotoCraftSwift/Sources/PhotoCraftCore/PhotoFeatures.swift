import Foundation

// Harris and steered BRIEF, translated from PhotoCraft features.rs (MIT OR Apache-2.0).
struct PhotoFeatures: Sendable {
  struct Corner: Sendable { var x: Float;var y: Float;var score: Float;var point: PhotoPoint { PhotoPoint(Double(x),Double(y)) } }
  var width: Int;var height: Int;var points: [PhotoPoint];var descriptors: [[UInt64]]
  static let pairs: [[Float]] = {
    var rng = PhotoRandom(state:0x0B21_EF00)
    func gaussian() -> Float { let u = max(rng.unit(),1e-12),v = rng.unit();return Float(max(-13,min(13,sqrt(-2*log(u))*cos(2*Double.pi*v)*31/5))) }
    return (0..<256).map { _ in [gaussian(),gaussian(),gaussian(),gaussian()] }
  }()
  static func blur(_ w: Int,_ h: Int,_ values: [Float],_ radius: Int) -> [Float] {
    func pass(_ src: [Float],_ horizontal: Bool) -> [Float] {
      var dst = src;let n = horizontal ? h:w,m = horizontal ? w:h
      for line in 0..<n {
        func at(_ k: Int) -> Float { let k = max(0,min(m-1,k));return src[horizontal ? line*w+k:k*w+line] }
        var sum: Float = 0;for k in -radius...radius { sum += at(k) }
        for k in 0..<m { dst[horizontal ? line*w+k:k*w+line] = sum/Float(2*radius+1);sum += at(k+radius+1)-at(k-radius) }
      };return dst
    };return pass(pass(values,true),false)
  }
  static func harris(_ w: Int,_ h: Int,_ img: [Float],maximum: Int = 800,spacing: Float,valid: [Bool]? = nil) throws -> [Corner] {
    guard w >= 33,h >= 33 else { return [] }
    var xx = [Float](repeating:0,count:w*h),yy = xx,xy = xx
    for y in 1..<h-1 { try Task.checkCancellation();for x in 1..<w-1 {
      func p(_ dx: Int,_ dy: Int) -> Float { img[(y+dy)*w+x+dx] }
      let gx = (p(1,-1)+2*p(1,0)+p(1,1))-(p(-1,-1)+2*p(-1,0)+p(-1,1))
      let gy = (p(-1,1)+2*p(0,1)+p(1,1))-(p(-1,-1)+2*p(0,-1)+p(1,-1)),i = y*w+x
      xx[i] = gx*gx;yy[i] = gy*gy;xy[i] = gx*gy
    } }
    xx = blur(w,h,blur(w,h,xx,1),1);yy = blur(w,h,blur(w,h,yy,1),1);xy = blur(w,h,blur(w,h,xy,1),1)
    let response = xx.indices.map { i in let sum = xx[i]+yy[i];return xx[i]*yy[i]-xy[i]*xy[i]-0.04*sum*sum },peak = response.max() ?? 0
    guard peak > 0 else { return [] };var candidates = [Corner]()
    for y in 16..<h-16 { try Task.checkCancellation();for x in 16..<w-16 {
      let value = response[y*w+x];guard value >= peak*0.01 else { continue }
      guard (-1...1).allSatisfy({ dy in (-1...1).allSatisfy { dx in response[(y+dy)*w+x+dx] <= value } }) else { continue }
      if let valid,!stride(from:y-15,through:y+15,by:5).allSatisfy({ yy in stride(from:x-15,through:x+15,by:5).allSatisfy { valid[yy*w+$0] } }) { continue }
      candidates.append(Corner(x:Float(x),y:Float(y),score:value))
    } }
    candidates.sort { a,b in a.score != b.score ? a.score > b.score:(a.y != b.y ? a.y < b.y:a.x < b.x) }
    var result = [Corner]()
    for c in candidates where !result.contains(where:{hypot($0.x-c.x,$0.y-c.y) < spacing}) { result.append(c);if result.count >= maximum { break } }
    return result
  }
  static func describe(_ w: Int,_ h: Int,_ img: [Float],_ corners: [Corner],upright: Bool = false) throws -> [[UInt64]] {
    let smooth = blur(w,h,img,2)
    func at(_ x: Float,_ y: Float) -> Float { smooth[max(0,min(h-1,Int(y.rounded())))*w+max(0,min(w-1,Int(x.rounded())))] }
    return try corners.map { c in
      try Task.checkCancellation();var angle: Float = 0
      if !upright { var mx: Float = 0,my: Float = 0;for dy in -15...15 { for dx in -15...15 where dx*dx+dy*dy <= 225 {
        let value = at(c.x+Float(dx),c.y+Float(dy));mx += Float(dx)*value;my += Float(dy)*value
      } };angle = atan2(my,mx) }
      let s = sin(angle),co = cos(angle);var bits = [UInt64](repeating:0,count:4)
      for (i,p) in pairs.enumerated() {
        if at(c.x+p[0]*co-p[1]*s,c.y+p[0]*s+p[1]*co) < at(c.x+p[2]*co-p[3]*s,c.y+p[2]*s+p[3]*co) { bits[i/64] |= UInt64(1) << (i%64) }
      };return bits
    }
  }
  static func detect(width: Int,height: Int,luma: [Float],valid: [Bool]) throws -> Self {
    let corners = try harris(width,height,luma,spacing:Float(max(3,min(20,max(width,height)/70))),valid:valid)
    return Self(width:width,height:height,points:corners.map(\.point),descriptors:try describe(width,height,luma,corners))
  }
  static func match(_ a: [[UInt64]],_ b: [[UInt64]],ratio: Float = 0.8) throws -> [(Int,Int)] {
    func best(_ d: [UInt64],_ set: [[UInt64]]) -> (Int,Int,Int)? {
      var first = (index:-1,distance:Int.max),second = Int.max
      for (i,v) in set.enumerated() {
        let distance = zip(d,v).reduce(0) { $0+($1.0 ^ $1.1).nonzeroBitCount }
        if distance < first.distance { second = first.distance;first = (i,distance) } else if distance < second { second = distance }
      };return first.index < 0 ? nil:(first.index,first.distance,second)
    }
    var result = [(Int,Int)]()
    for i in a.indices { try Task.checkCancellation()
      guard let (j,d1,d2) = best(a[i],b),d1 <= 80,(d2 == Int.max || Float(d1) <= ratio*Float(d2)),best(b[j],a)?.0 == i else { continue }
      result.append((i,j))
    };return result
  }
}
