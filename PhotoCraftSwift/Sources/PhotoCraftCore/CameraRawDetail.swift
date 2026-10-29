import Foundation

extension CameraRawEngine {
  static func detail(_ p: inout [RGB],_ w: Int,_ h: Int,_ s: CameraRawSettings) throws {
    var y = p.map(M.luma), cb = p.indices.map { p[$0].z-y[$0] }, cr = p.indices.map { p[$0].x-y[$0] }
    if s.noiseLuminance > 0 {
      let n = s.noiseLuminance/100, r = max(1,Int(((1+3*n)*s.pixelScale).rounded()))
      let sm = try M.guided(y,y,w,h,r,pow(n*0.06,2)+1e-6), keep = s.noiseLuminanceDetail/100*0.5
      for i in y.indices { y[i] = sm[i]+(y[i]-sm[i])*keep }
    }
    if s.noiseColor > 0 {
      let sigma = max(s.noiseColor/100*6*s.pixelScale,0.3), keep = s.noiseColorDetail/100*0.3
      let b = try M.gaussian(cb,w,h,sigma), r = try M.gaussian(cr,w,h,sigma)
      for i in cb.indices { cb[i] = b[i]+(cb[i]-b[i])*keep; cr[i] = r[i]+(cr[i]-r[i])*keep }
    }
    if s.sharpenAmount > 0 {
      let blur = try M.gaussian(y,w,h,max(s.sharpenRadius*s.pixelScale,0.3))
      let mask = s.sharpenMasking > 0 ? try M.gaussian(y,w,h,max(s.pixelScale,0.5)) : y
      let limit = 0.03+s.sharpenDetail/100*0.3, amount = s.sharpenAmount/100*1.2, t = s.sharpenMasking/100*0.08
      for py in 0..<h { try Task.checkCancellation(); for px in 0..<w {
        let i = py*w+px
        let gx = (mask[py*w+min(w-1,px+1)]-mask[py*w+max(0,px-1)])/2
        let gy = (mask[min(h-1,py+1)*w+px]-mask[max(0,py-1)*w+px])/2
        let weight = s.sharpenMasking > 0 ? M.smooth(t*0.5,t+1e-4,sqrt(gx*gx+gy*gy)) : 1
        let high = min(limit,max(-limit,y[i]-blur[i]))*(0.5+0.5*s.sharpenDetail/100)
        y[i] += amount*high*weight
      } }
    }
    for i in p.indices { if i%w == 0 { try Task.checkCancellation() }
      let r = cr[i]+y[i], b = cb[i]+y[i], g = (y[i]-0.2126*r-0.0722*b)/0.7152
      p[i] = RGB(r,g,b)
    }
  }
  static func effects(_ p: inout [RGB],_ w: Int,_ h: Int,_ s: CameraRawSettings) throws {
    guard s.vignetteAmount != 0 || s.grainAmount != 0 else { return }
    let cx = Float(w)/2, cy = Float(h)/2, round = s.vignetteRoundness/100
    let radius = min(cx,cy)+(max(cx,cy)-min(cx,cy))*(1-max(0,round))
    let ax = round >= 0 && cx >= cy ? radius : cx, ay = round >= 0 && cy > cx ? radius : cy
    let power = 2+max(-round,0)*6, inner = 1-s.vignetteMidpoint/100*0.8, feather = s.vignetteFeather/100
    let edge0 = inner-feather*0.5*inner, edge1 = inner+feather*0.5*(1.4-inner)+0.02
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let i = y*w+x; var c = p[i]
      if s.vignetteAmount != 0 {
        let dx = abs((Float(x)+0.5-cx)/ax), dy = abs((Float(y)+0.5-cy)/ay)
        let r = pow(pow(dx,power)+pow(dy,power),1/power), m = M.smooth(edge0,edge1,r), amount = s.vignetteAmount/100
        if s.vignetteStyle == "paintOverlay" { c += (RGB(repeating:amount < 0 ? 0 : 1)-c)*(m*abs(amount)) }
        else {
          var k = pow(2,amount*2*m)
          if amount < 0 { k += (1-k)*M.smooth(0.6,1,M.luma(c))*s.vignetteHighlights/100 }
          if s.vignetteStyle == "colorPriority" { c += RGB(repeating:M.luma(c)*(k-1)) } else { c *= k }
        }
      }
      if s.grainAmount > 0 {
        let cell = (1+s.grainSize/25)*s.pixelScale, fx = Float(x)/cell, fy = Float(y)/cell, rough = s.grainRoughness/100
        let n = M.noise(fx,fy,s.seed)*(1-rough)+M.noise(fx*2.3,fy*2.3,s.seed &+ 7)*rough, l = unit(M.luma(c))
        c += RGB(repeating:(n-0.5)*2*s.grainAmount/100*0.12*(0.4+2.4*l*(1-l)))
      }
      p[i] = c
    } }
  }
  static func dehaze(_ p: [RGB],_ w: Int,_ h: Int,_ amount: Float) throws -> [RGB] {
    let scale = max(1,(max(w,h)+767)/768), sw = (w+scale-1)/scale, sh = (h+scale-1)/scale
    var small = [RGB](repeating:.zero,count:sw*sh)
    for y in 0..<sh { try Task.checkCancellation(); for x in 0..<sw {
      var c = RGB.zero; var count: Float = 0
      for py in y*scale..<min(h,(y+1)*scale) { for px in x*scale..<min(w,(x+1)*scale) { let v = p[py*w+px]; c += RGB(unit(v.x),unit(v.y),unit(v.z)); count += 1 } }
      small[y*sw+x] = c/count
    } }
    let r = max(max(sw,sh)/60,2)
    func minimum(_ source: [Float]) throws -> [Float] {
      var temp = source, out = source
      for y in 0..<sh { try Task.checkCancellation(); for x in 0..<sw {
        var v = Float.greatestFiniteMagnitude
        for k in max(0,x-r)...min(sw-1,x+r) { v = min(v,source[y*sw+k]) }; temp[y*sw+x] = v
      } }
      for y in 0..<sh { try Task.checkCancellation(); for x in 0..<sw {
        var v = Float.greatestFiniteMagnitude
        for k in max(0,y-r)...min(sh-1,y+r) { v = min(v,temp[k*sw+x]) }; out[y*sw+x] = v
      } }
      return out
    }
    let dark = try minimum(small.map { min($0.x,$0.y,$0.z) }), count = max(1,small.count/1000)
    let brightest = dark.indices.sorted { dark[$0] > dark[$1] }.prefix(count)
    var air = RGB.zero
    for i in brightest { air += small[i] }; air /= Float(count)
    for c in 0..<3 { air[c] = max(0.2,air[c]) }
    let normalized = try minimum(small.map { let c = $0/air; return min(c.x,c.y,c.z) })
    let trans = try M.guided(small.map(M.luma),normalized.map { 1-0.95*$0 },sw,sh,r*2,0.001)
    var out = p
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let t = min(1,max(0.1,M.sample(trans,sw,sh,(Float(x)+0.5)/Float(scale)-0.5,(Float(y)+0.5)/Float(scale)-0.5)))
      let i = y*w+x, c = p[i]
      if amount > 0 { out[i] = c+((c-air)/t+air-c)*amount }
      else { out[i] = c+(air-c)*(-amount)*0.5*(1-t*0.5) }
    } }
    return out
  }
}
