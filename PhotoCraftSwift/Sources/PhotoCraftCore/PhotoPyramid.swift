import Foundation

/// Native translation of PhotoCraft algo/pyramid.rs (MIT OR Apache-2.0).
/// Binomial Gaussian/Laplacian pyramids; source holes are filled before blending.
public enum PhotoPyramid {
  public struct Level: Sendable {
    public var width: Int
    public var height: Int
    public var pixels: [Float]
    public init(width: Int,height: Int,pixels: [Float]) { self.width = width;self.height = height;self.pixels = pixels }
  }
  static let kernel: [Float] = [1/16,4/16,6/16,4/16,1/16]
  public static func reduce(_ l: Level,channels: Int) throws -> Level {
    let w = (l.width+1)/2,h = (l.height+1)/2,c = channels
    var tmp = [Float](repeating:0,count:w*l.height*c),out = [Float](repeating:0,count:w*h*c)
    for y in 0..<l.height { try Task.checkCancellation();for x in 0..<w { for k in 0..<5 {
      let sx = min(l.width-1,max(0,2*x+k-2))
      for n in 0..<c { tmp[(y*w+x)*c+n] += kernel[k]*l.pixels[(y*l.width+sx)*c+n] }
    } } }
    for y in 0..<h { try Task.checkCancellation();for k in 0..<5 {
      let sy = min(l.height-1,max(0,2*y+k-2))
      for x in 0..<w { for n in 0..<c { out[(y*w+x)*c+n] += kernel[k]*tmp[(sy*w+x)*c+n] } }
    } }
    return Level(width:w,height:h,pixels:out)
  }
  public static func expand(_ l: Level,channels: Int,width w: Int,height h: Int) throws -> [Float] {
    let c = channels
    var tmp = [Float](repeating:0,count:w*l.height*c),out = [Float](repeating:0,count:w*h*c)
    for y in 0..<l.height { try Task.checkCancellation();for x in 0..<w { for k in 0..<5 {
      let t = x+k-2;guard t%2 == 0 else { continue };let sx = min(l.width-1,max(0,t/2))
      for n in 0..<c { tmp[(y*w+x)*c+n] += 2*kernel[k]*l.pixels[(y*l.width+sx)*c+n] }
    } } }
    for y in 0..<h { try Task.checkCancellation();for k in 0..<5 {
      let t = y+k-2;guard t%2 == 0 else { continue };let sy = min(l.height-1,max(0,t/2))
      for x in 0..<w { for n in 0..<c { out[(y*w+x)*c+n] += 2*kernel[k]*tmp[(sy*w+x)*c+n] } }
    } }
    return out
  }
  public static func gaussian(_ base: Level,channels: Int,levels: Int) throws -> [Level] {
    var result = [base]
    while result.count < levels,let last = result.last,last.width > 1 || last.height > 1 { result.append(try reduce(last,channels:channels)) }
    return result
  }
  public static func laplacian(_ base: Level,channels: Int,levels: Int) throws -> [Level] {
    let g = try gaussian(base,channels:channels,levels:levels)
    var result = g
    for i in 0..<max(0,g.count-1) {
      let up = try expand(g[i+1],channels:channels,width:g[i].width,height:g[i].height)
      for k in up.indices { result[i].pixels[k] -= up[k] }
    }
    return result
  }
  public static func collapse(_ pyramid: [Level],channels: Int) throws -> [Float] {
    guard var current = pyramid.last else { return [] }
    for l in pyramid.dropLast().reversed() {
      let up = try expand(current,channels:channels,width:l.width,height:l.height)
      current = l;for i in up.indices { current.pixels[i] += up[i] }
    }
    return current.pixels
  }
  static func levels(_ w: Int,_ h: Int) -> Int {
    var size = min(w,h),n = 1
    while size > 8 && n < 7 { size /= 2;n += 1 };return n
  }
  /// Fill unavailable color samples by normalized push-pull, without changing coverage.
  static func extend(_ base: Level,channels: Int,coverage: [Float]) throws -> [Float] {
    if base.width == 1 && base.height == 1 { return base.pixels }
    let w = base.width,h = base.height,c = channels,nw = (w+1)/2,nh = (h+1)/2
    var px = [Float](repeating:0,count:nw*nh*c),a = [Float](repeating:0,count:nw*nh)
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let i = y*w+x,j = (y/2)*nw+x/2,k: Float = coverage[i] > 0 ? 1:0
      a[j] += k;for n in 0..<c { px[j*c+n] += k*base.pixels[i*c+n] }
    } }
    for j in a.indices where a[j] > 0 { for n in 0..<c { px[j*c+n] /= a[j] };a[j] = 1 }
    if a.contains(0),a.contains(1) { px = try extend(Level(width:nw,height:nh,pixels:px),channels:c,coverage:a) }
    var out = base.pixels
    for y in 0..<h { for x in 0..<w where coverage[y*w+x] <= 0 {
      for n in 0..<c { out[(y*w+x)*c+n] = px[((y/2)*nw+x/2)*c+n] }
    } }
    return out
  }
  static func blend(width w: Int,height h: Int,images: [[Float]],coverage: [[Float]],weights: [[Float]],seamless: Bool) throws -> [Float] {
    var acc: [Level] = [],sums: [Level] = []
    for i in images.indices {
      try Task.checkCancellation()
      let filled = try extend(Level(width:w,height:h,pixels:images[i]),channels:3,coverage:coverage[i])
      let n = seamless ? levels(w,h):1
      let lp = try laplacian(Level(width:w,height:h,pixels:filled),channels:3,levels:n)
      let gp = try gaussian(Level(width:w,height:h,pixels:weights[i]),channels:1,levels:n)
      if acc.isEmpty {
        acc = lp.map { Level(width:$0.width,height:$0.height,pixels:[Float](repeating:0,count:$0.pixels.count)) }
        sums = gp.map { Level(width:$0.width,height:$0.height,pixels:[Float](repeating:0,count:$0.pixels.count)) }
      }
      for l in lp.indices { for p in gp[l].pixels.indices {
        let k = gp[l].pixels[p];sums[l].pixels[p] += k
        for c in 0..<3 { acc[l].pixels[p*3+c] += k*lp[l].pixels[p*3+c] }
      } }
    }
    for l in acc.indices { for p in sums[l].pixels.indices {
      let k = sums[l].pixels[p]
      for c in 0..<3 { acc[l].pixels[p*3+c] = k > 1e-6 ? acc[l].pixels[p*3+c]/k:0 }
    } }
    return try collapse(acc,channels:3) // Preserve negative and >1 HDR samples.
  }
}
