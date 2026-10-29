import Accelerate
import Foundation

/// PhotoCraft's guided-filter and morphology building blocks (MIT OR Apache-2.0).
/// Public entry points in SelectionMatting validate dimensions before using these buffers.
enum MattingFilters {
  static func box(_ input: [Float],_ w: Int,_ h: Int,_ radius: Int) throws -> [Float] {
    var temp = input, result = input
    var prefix = [Double](repeating:0,count:max(w,h)+1)
    for y in 0..<h {
      try Task.checkCancellation(); prefix[0] = 0
      for x in 0..<w { prefix[x+1] = prefix[x]+Double(input[y*w+x]) }
      for x in 0..<w { let lo = max(0,x-radius), hi = min(w,x+radius+1); temp[y*w+x] = Float((prefix[hi]-prefix[lo])/Double(hi-lo)) }
    }
    for x in 0..<w {
      try Task.checkCancellation(); prefix[0] = 0
      for y in 0..<h { prefix[y+1] = prefix[y]+Double(temp[y*w+x]) }
      for y in 0..<h { let lo = max(0,y-radius), hi = min(h,y+radius+1); result[y*w+x] = Float((prefix[hi]-prefix[lo])/Double(hi-lo)) }
    }
    return result
  }
  static func gaussian(_ input: [Float],_ w: Int,_ h: Int,_ sigma: Float) throws -> [Float] {
    guard sigma >= 0.1 else { return input }
    let radius = Int(ceil(sigma*3))
    var kernel = (-radius...radius).map { exp(-Float($0*$0)/(2*sigma*sigma)) }
    let total = kernel.reduce(0,+); kernel = kernel.map { $0/total }
    var temp = input, result = input
    func filtered(_ line: [Float]) -> [Float] {
      let padded = Array(repeating:line[0],count:radius)+line+Array(repeating:line.last!,count:radius)
      var output = [Float](repeating:0,count:line.count)
      vDSP_conv(padded,1,kernel,1,&output,1,vDSP_Length(line.count),vDSP_Length(kernel.count))
      return output
    }
    for y in 0..<h {
      try Task.checkCancellation(); let row = filtered(Array(input[y*w..<(y+1)*w])); temp.replaceSubrange(y*w..<(y+1)*w,with:row)
    }
    for x in 0..<w {
      try Task.checkCancellation(); let line = filtered((0..<h).map { temp[$0*w+x] })
      for y in 0..<h { result[y*w+x] = line[y] }
    }
    return result
  }
  static func extreme(_ input: [Float],_ w: Int,_ h: Int,_ radius: Int,maximum: Bool) throws -> [Float] {
    var temp = input, result = input
    func line(_ values: [Float]) -> [Float] {
      var deque = [Int](repeating:0,count:values.count), head = 0, tail = 0, next = 0
      var out = values
      for i in values.indices {
        let end = min(values.count-1,i+radius)
        while next <= end {
          while tail > head && (maximum ? values[deque[tail-1]] <= values[next] : values[deque[tail-1]] >= values[next]) { tail -= 1 }
          deque[tail] = next; tail += 1; next += 1
        }
        while head < tail && deque[head] < i-radius { head += 1 }
        out[i] = values[deque[head]]
      }
      return out
    }
    for y in 0..<h { try Task.checkCancellation(); temp.replaceSubrange(y*w..<(y+1)*w,with:line(Array(input[y*w..<(y+1)*w]))) }
    for x in 0..<w { try Task.checkCancellation(); let column = line((0..<h).map { temp[$0*w+x] }); for y in 0..<h { result[y*w+x] = column[y] } }
    return result
  }
  static func morph(_ input: [Float],_ w: Int,_ h: Int,_ radius: Int,grow: Bool) throws -> [Float] {
    var current = input, next = input
    for k in 0..<radius {
      for y in 0..<h {
        try Task.checkCancellation()
        for x in 0..<w {
          var value = current[y*w+x]
          for dy in -1...1 { for dx in -1...1 where (k%2 == 0 || dx == 0 || dy == 0) {
            let nx = x+dx, ny = y+dy
            if nx >= 0 && ny >= 0 && nx < w && ny < h { value = grow ? max(value,current[ny*w+nx]) : min(value,current[ny*w+nx]) }
          } }
          next[y*w+x] = value
        }
      }
      swap(&current,&next)
    }
    return current
  }
  static func distance(_ inside: [Bool],_ w: Int,_ h: Int) throws -> [Float] {
    var result = inside.map { $0 ? Float(0) : Float(1e20) }
    func line(_ f: [Float]) -> [Float] {
      let n = f.count; var v = [Int](repeating:0,count:n), z = [Double](repeating:0,count:n+1), k = 0
      z[0] = -.infinity; z[1] = .infinity
      for q in 1..<n {
        var s = 0.0
        while true {
          let j = v[k]; s = (Double(f[q])-Double(f[j])+Double(q*q-j*j))/Double(2*(q-j))
          if s > z[k] || k == 0 { break }; k -= 1
        }
        k += 1; v[k] = q; z[k] = s; z[k+1] = .infinity
      }
      k = 0; var out = f
      for q in 0..<n { while z[k+1] < Double(q) { k += 1 }; let d = q-v[k]; out[q] = Float(d*d)+f[v[k]] }
      return out
    }
    for x in 0..<w { try Task.checkCancellation(); let col = line((0..<h).map { result[$0*w+x] }); for y in 0..<h { result[y*w+x] = col[y] } }
    for y in 0..<h { try Task.checkCancellation(); let row = line(Array(result[y*w..<(y+1)*w])); for x in 0..<w { result[y*w+x] = sqrt(row[x]) } }
    return result
  }
  static func guided(_ guide: [SIMD3<Float>],_ mask: [Float],_ w: Int,_ h: Int,_ radius: Int,epsilon:Double = 1e-4) throws -> [Float] {
    let n = mask.count, channels = (0..<3).map { c in guide.map { $0[c] } }
    let mean = try channels.map { try box($0,w,h,radius) }, mp = try box(mask,w,h,radius)
    let mip = try channels.map { c in try box(zip(c,mask).map(*),w,h,radius) }
    let pairs = [(0,0),(0,1),(0,2),(1,1),(1,2),(2,2)]
    let mii = try pairs.map { a,b in try box(zip(channels[a],channels[b]).map(*),w,h,radius) }
    var av = Array(repeating:[Float](repeating:0,count:n),count:3), bv = [Float](repeating:0,count:n)
    for i in 0..<n {
      if i%w == 0 { try Task.checkCancellation() }
      let mu = SIMD3(Double(mean[0][i]),Double(mean[1][i]),Double(mean[2][i]))
      func s(_ k: Int,_ a: Int,_ b: Int) -> Double { Double(mii[k][i])-mu[a]*mu[b] }
      let rr = s(0,0,0)+epsilon, rg = s(1,0,1), rb = s(2,0,2), gg = s(3,1,1)+epsilon, gb = s(4,1,2), bb = s(5,2,2)+epsilon
      let cov = SIMD3(Double(mip[0][i]),Double(mip[1][i]),Double(mip[2][i]))-mu*Double(mp[i])
      let i00 = gg*bb-gb*gb, i01 = gb*rb-rg*bb, i02 = rg*gb-gg*rb, i11 = rr*bb-rb*rb, i12 = rb*rg-rr*gb, i22 = rr*gg-rg*rg
      let det = rr*i00+rg*i01+rb*i02
      let a = abs(det) < 1e-30 ? SIMD3<Double>.zero : SIMD3((i00*cov.x+i01*cov.y+i02*cov.z)/det,(i01*cov.x+i11*cov.y+i12*cov.z)/det,(i02*cov.x+i12*cov.y+i22*cov.z)/det)
      for c in 0..<3 { av[c][i] = Float(a[c]) }; bv[i] = Float(Double(mp[i])-a.x*mu.x-a.y*mu.y-a.z*mu.z)
    }
    let ma = try av.map { try box($0,w,h,radius) }, mb = try box(bv,w,h,radius)
    return (0..<n).map { ma[0][$0]*channels[0][$0]+ma[1][$0]*channels[1][$0]+ma[2][$0]*channels[2][$0]+mb[$0] }
  }
  static func edgeWidths(_ guide: [SIMD3<Float>],_ w: Int,_ h: Int,_ radius: Int) throws -> [Float] {
    let luminance = guide.map { $0.x*0.2126+$0.y*0.7152+$0.z*0.0722 }; var gradient = luminance
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let dx = (luminance[y*w+min(w-1,x+1)]-luminance[y*w+max(0,x-1)])/2
      let dy = (luminance[min(h-1,y+1)*w+x]-luminance[max(0,y-1)*w+x])/2
      gradient[y*w+x] = hypot(dx,dy)
    } }
    let g = try extreme(gradient,w,h,radius,maximum:true), hi = try extreme(luminance,w,h,radius,maximum:true), lo = try extreme(luminance,w,h,radius,maximum:false)
    return (0..<w*h).map { (hi[$0]-lo[$0])/max(1e-4,g[$0]) }
  }
}
