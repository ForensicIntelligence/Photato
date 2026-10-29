import Foundation

/// Focus and minimum-cost panorama seam algorithms adapted from PhotoCraft
/// algo/pyramid.rs and algo/panorama.rs (MIT OR Apache-2.0).
enum PhotoBlendWeights {
  static func focus(width w: Int,height h: Int,luma: [[Float]],alpha: [[Float]]) throws -> [[Float]] {
    let count = w*h,r = min(12,max(2,min(w,h)/64))
    var scores = [[Float]]()
    for l in luma {
      var lap = [Float](repeating:0,count:count)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        lap[y*w+x] = abs(l[y*w+max(0,x-1)]+l[y*w+min(w-1,x+1)]+l[max(0,y-1)*w+x]+l[min(h-1,y+1)*w+x]-4*l[y*w+x])
      } }
      scores.append(try blur(lap,width:w,height:h,radius:r))
    }
    var result = Array(repeating:[Float](repeating:0,count:count),count:luma.count)
    for p in 0..<count {
      if p%w == 0 { try Task.checkCancellation() }
      var best = -1,value: Float = -.infinity
      for i in scores.indices where alpha[i][p] > 0 {
        if scores[i][p] > value { value = scores[i][p];best = i }
      }
      if best >= 0 { result[best][p] = 1 }
    }
    return result
  }
  static func blur(_ input: [Float],width w: Int,height h: Int,radius r: Int) throws -> [Float] {
    var source = input
    for horizontal in [true,false] {
      let lines = horizontal ? h:w,len = horizontal ? w:h
      var out = source
      for line in 0..<lines {
        try Task.checkCancellation()
        func at(_ k: Int) -> Float { let j = min(len-1,max(0,k));return source[horizontal ? line*w+j:j*w+line] }
        var sum: Float = 0;for k in -r...r { sum += at(k) }
        for k in 0..<len { out[horizontal ? line*w+k:k*w+line] = sum/Float(2*r+1);sum += at(k+r+1)-at(k-r) }
      }
      source = out
    }
    return source
  }
  static func panorama(width w: Int,height h: Int,luma: [[Float]],alpha: [[Float]]) throws -> [[Float]] {
    // Route seams on a reduced grid; restore full-resolution coverage below.
    let scale = max(1,(max(w,h)+999)/1000),gw = (w+scale-1)/scale,gh = (h+scale-1)/scale
    var light = Array(repeating:[Float](repeating:0,count:gw*gh),count:luma.count)
    var cover = light.map { _ in [Bool](repeating:false,count:gw*gh) }
    for k in luma.indices {
      var area = [Float](repeating:0,count:gw*gh)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
        let p = y*w+x,g = (y/scale)*gw+x/scale,a = alpha[k][p]
        light[k][g] += luma[k][p]*a;area[g] += a
      } }
      for g in area.indices where area[g] > 0 { light[k][g] /= area[g];cover[k][g] = true }
    }
    let labels = try seams(width:gw,height:gh,luma:light,cover:cover)
    var result = Array(repeating:[Float](repeating:0,count:w*h),count:luma.count)
    for y in 0..<h { try Task.checkCancellation();for x in 0..<w {
      let p = y*w+x,g = (y/scale)*gw+x/scale,label = labels[g]
      if label >= 0,alpha[label][p] > 0 { result[label][p] = 1 }
      else if let first = alpha.indices.first(where:{ alpha[$0][p] > 0 }) { result[first][p] = 1 }
    } }
    return result
  }
  static func seams(width w: Int,height h: Int,luma: [[Float]],cover: [[Bool]]) throws -> [Int] {
    var label = [Int](repeating:-1,count:w*h)
    for image in luma.indices {
      try Task.checkCancellation()
      var overlap = [Bool](repeating:false,count:w*h)
      var sx = 0.0,sy = 0.0,nx = 0.0,ny = 0.0,no = 0,nn = 0
      for i in label.indices where cover[image][i] {
        nx += Double(i%w);ny += Double(i/w);nn += 1
        if label[i] >= 0 { overlap[i] = true;sx += Double(i%w);sy += Double(i/w);no += 1 }
        else { label[i] = image }
      }
      if no == 0 || no == nn { continue }
      let ox = sx/Double(no),oy = sy/Double(no),cx = nx/Double(nn),cy = ny/Double(nn)
      let vertical = abs(cx-ox) >= abs(cy-oy),positive = vertical ? cx > ox:cy > oy
      let lines = vertical ? h:w,len = vertical ? w:h
      func index(_ line: Int,_ k: Int) -> Int { vertical ? line*w+k:k*w+line }
      var cost = [Float](repeating:.infinity,count:w*h),from = [Int](repeating:-1,count:w*h)
      var previous: Int?
      for line in 0..<lines {
        try Task.checkCancellation()
        guard (0..<len).contains(where:{ overlap[index(line,$0)] }) else { continue }
        for k in 0..<len {
          let i = index(line,k);guard overlap[i] else { continue }
          var best: Float = 0,origin = -1
          if let p = previous,p+1 == line {
            best = .infinity
            for kk in max(0,k-1)...min(len-1,k+1) where cost[index(p,kk)] < best { best = cost[index(p,kk)];origin = kk }
            if origin < 0 { best = 0 }
          }
          cost[i] = best+0.002+abs(luma[image][i]-luma[label[i]][i]);from[i] = origin
        }
        previous = line
      }
      var seam = [Int](repeating:-1,count:lines)
      for line in (0..<lines).reversed() where seam[line] < 0 {
        guard let start = (0..<len).filter({overlap[index(line,$0)]}).min(by:{cost[index(line,$0)] < cost[index(line,$1)]}) else { continue }
        var l = line,k = start
        while true { seam[l] = k;let next = from[index(l,k)];if next < 0 || l == 0 { break };l -= 1;if seam[l] >= 0 { break };k = next }
      }
      for line in 0..<lines where seam[line] >= 0 { for k in 0..<len {
        let i = index(line,k)
        if overlap[i] && (positive ? k > seam[line]:k < seam[line]) { label[i] = image }
      } }
    }
    return label
  }
}
