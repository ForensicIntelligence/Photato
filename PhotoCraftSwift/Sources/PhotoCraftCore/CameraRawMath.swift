import Foundation

// Translated from PhotoCraft camera_raw.rs; MIT OR Apache-2.0. No Adobe kernel claims.
enum CameraRawMath {
  typealias RGB = SIMD3<Float>
  static func luma(_ p: RGB) -> Float { p.x * 0.2126 + p.y * 0.7152 + p.z * 0.0722 }
  static func smooth(_ a: Float,_ b: Float,_ x: Float) -> Float { let t = unit((x-a)/(b-a)); return t*t*(3-2*t) }
  static func hsv(_ p: RGB) -> RGB {
    let hi = max(p.x,p.y,p.z), lo = min(p.x,p.y,p.z), d = hi-lo
    var h: Float = 0
    if d > 1e-8 {
      if hi == p.x { h = (p.y-p.z)/d }
      else if hi == p.y { h = (p.z-p.x)/d+2 }
      else { h = (p.x-p.y)/d+4 }
      h = (h*60+360).truncatingRemainder(dividingBy:360)
    }
    return RGB(h,hi > 1e-8 ? d/hi : 0,hi)
  }
  static func rgb(_ h: Float,_ s: Float,_ v: Float) -> RGB {
    let h = (h.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360)/60
    let c = v*s, x = c*(1-abs(h.truncatingRemainder(dividingBy:2)-1)), m = v-c
    let p: RGB
    switch Int(h) { case 0: p = RGB(c,x,0); case 1: p = RGB(x,c,0); case 2: p = RGB(0,c,x); case 3: p = RGB(0,x,c); case 4: p = RGB(x,0,c); default: p = RGB(c,0,x) }
    return p + RGB(repeating:m)
  }
  static func box(_ a: [Float],_ w: Int,_ h: Int,_ radius: Int) throws -> [Float] {
    if radius < 1 { return a }
    var tmp = a, out = a
    for y in 0..<h {
      try Task.checkCancellation()
      var sum = 0.0
      for k in -radius...radius { sum += Double(a[y*w+min(w-1,max(0,k))]) }
      for x in 0..<w {
        tmp[y*w+x] = Float(sum/Double(2*radius+1))
        sum += Double(a[y*w+min(w-1,x+radius+1)])-Double(a[y*w+max(0,x-radius)])
      }
    }
    for x in 0..<w {
      try Task.checkCancellation()
      var sum = 0.0
      for k in -radius...radius { sum += Double(tmp[min(h-1,max(0,k))*w+x]) }
      for y in 0..<h {
        out[y*w+x] = Float(sum/Double(2*radius+1))
        sum += Double(tmp[min(h-1,y+radius+1)*w+x])-Double(tmp[max(0,y-radius)*w+x])
      }
    }
    return out
  }
  static func gaussian(_ a: [Float],_ w: Int,_ h: Int,_ sigma: Float) throws -> [Float] {
    var lower = max(1,Int(floor(sqrt(4*sigma*sigma+1)))); if lower%2 == 0 { lower -= 1 }
    let l = Float(lower), m = Int(((12*sigma*sigma-3*l*l-12*l-9)/(-4*l-4)).rounded())
    var out = a
    for i in 0..<3 { out = try box(out,w,h,((i < m ? lower : lower+2)-1)/2) }
    return out
  }
  static func guided(_ i: [Float],_ p: [Float],_ w: Int,_ h: Int,_ r: Int,_ eps: Float) throws -> [Float] {
    let mi = try box(i,w,h,r), mp = try box(p,w,h,r)
    let mip = try box(zip(i,p).map(*),w,h,r), mii = try box(i.map { $0*$0 },w,h,r)
    var a = i, b = i
    for k in i.indices { a[k] = (mip[k]-mi[k]*mp[k])/(max(0,mii[k]-mi[k]*mi[k])+eps); b[k] = mp[k]-a[k]*mi[k] }
    let ma = try box(a,w,h,r), mb = try box(b,w,h,r)
    return i.indices.map { ma[$0]*i[$0]+mb[$0] }
  }
  static func sample(_ a: [Float],_ w: Int,_ h: Int,_ x: Float,_ y: Float) -> Float {
    let x = min(Float(w-1),max(0,x)), y = min(Float(h-1),max(0,y)), xi = Int(x), yi = Int(y)
    let fx = x-Float(xi), fy = y-Float(yi), x1 = min(w-1,xi+1), y1 = min(h-1,yi+1)
    return (a[yi*w+xi]*(1-fx)+a[yi*w+x1]*fx)*(1-fy)+(a[y1*w+xi]*(1-fx)+a[y1*w+x1]*fx)*fy
  }
  static func curve(_ points: [[Float]]) -> [Float] {
    if points.isEmpty { return (0..<1024).map { Float($0)/1023 } }
    let x = points.map { $0[0]/255 }, y = points.map { $0[1]/255 }
    let d = (0..<x.count-1).map { (y[$0+1]-y[$0])/(x[$0+1]-x[$0]) }
    var t = [Float](repeating:0,count:x.count); t[0] = d[0]; t[t.count-1] = d.last!
    for i in 1..<x.count-1 { t[i] = d[i-1]*d[i] <= 0 ? 0 : (d[i-1]+d[i])/2 }
    for i in d.indices {
      if abs(d[i]) < 1e-8 { t[i] = 0; t[i+1] = 0 }
      else { let a = t[i]/d[i], b = t[i+1]/d[i], n = a*a+b*b
        if n > 9 { let z = 3/sqrt(n); t[i] = z*a*d[i]; t[i+1] = z*b*d[i] }
      }
    }
    return (0..<1024).map { index in
      let v = Float(index)/1023
      if v <= x[0] { return y[0] }; if v >= x.last! { return y.last! }
      let k = (0..<x.count-1).first { v <= x[$0+1] }!, dx = x[k+1]-x[k], u = (v-x[k])/dx
      let u2 = u*u, u3 = u2*u
      return unit((2*u3-3*u2+1)*y[k]+(u3-2*u2+u)*dx*t[k]+(-2*u3+3*u2)*y[k+1]+(u3-u2)*dx*t[k+1])
    }
  }
  static func lut(_ table: [Float],_ value: Float) -> Float {
    if value <= 0 { return table[0]+value }; if value >= 1 { return table.last!+value-1 }
    let f = value*Float(table.count-1), i = Int(f), t = f-Float(i)
    return table[i]*(1-t)+table[min(i+1,table.count-1)]*t
  }
  static func hash(_ x: Int,_ y: Int,_ seed: UInt32) -> Float {
    var z = UInt64(bitPattern:Int64(x)) &* 0x9E3779B97F4A7C15 ^ UInt64(bitPattern:Int64(y)) &* 0xC2B2AE3D27D4EB4F ^ UInt64(seed) &* 0x165667B19E3779F9
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; z ^= z >> 31
    return Float(z >> 40)/Float(1 << 24)
  }
  static func noise(_ x: Float,_ y: Float,_ seed: UInt32) -> Float {
    let ix = Int(floor(x)), iy = Int(floor(y)), fx = smooth(0,1,x-Float(ix)), fy = smooth(0,1,y-Float(iy))
    return (hash(ix,iy,seed)*(1-fx)+hash(ix+1,iy,seed)*fx)*(1-fy)+(hash(ix,iy+1,seed)*(1-fx)+hash(ix+1,iy+1,seed)*fx)*fy
  }
}
