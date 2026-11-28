import Foundation

extension CameraRawEngine {
  struct DetailSettings {
    let luminanceRadius: Int
    let luminanceEpsilon: Float
    let luminanceKeep: Float
    let colorSigma: Float
    let colorKeep: Float
    let sharpenSigma: Float
    let maskSigma: Float
    let sharpenLimit: Float
    let sharpenAmount: Float
    let maskThreshold: Float
    let sharpenDetail: Float

    init(_ settings: CameraRawSettings) {
      let noise = settings.noiseLuminance / 100
      luminanceRadius = max(1, Int(((1 + 3 * noise) * settings.pixelScale).rounded()))
      luminanceEpsilon = pow(noise * 0.06, 2) + 1e-6
      luminanceKeep = settings.noiseLuminanceDetail / 100 * 0.5
      colorSigma = max(settings.noiseColor / 100 * 6 * settings.pixelScale, 0.3)
      colorKeep = settings.noiseColorDetail / 100 * 0.3
      sharpenSigma = max(settings.sharpenRadius * settings.pixelScale, 0.3)
      maskSigma = max(settings.pixelScale, 0.5)
      sharpenLimit = 0.03 + settings.sharpenDetail / 100 * 0.3
      sharpenAmount = settings.sharpenAmount / 100 * 1.2
      maskThreshold = settings.sharpenMasking / 100 * 0.08
      sharpenDetail = 0.5 + 0.5 * settings.sharpenDetail / 100
    }

    func sharpen(_ sample: Float, blurred: Float, index: Int, width: Int, height: Int,
      mask: UnsafeBufferPointer<Float>) -> Float {
      var weight: Float = 1
      if maskThreshold > 0 {
        let x = index % width, y = index / width
        let gx = (mask[y * width + min(width - 1, x + 1)] - mask[y * width + max(0, x - 1)]) / 2
        let gy = (mask[min(height - 1, y + 1) * width + x] - mask[max(0, y - 1) * width + x]) / 2
        weight = M.smooth(maskThreshold * 0.5, maskThreshold + 1e-4, sqrt(gx * gx + gy * gy))
      }
      let high = min(sharpenLimit, max(-sharpenLimit, sample - blurred)) * sharpenDetail
      return sample + sharpenAmount * high * weight
    }
  }

  static func hasDetailAdjustments(_ settings: CameraRawSettings) -> Bool {
    settings.noiseLuminance > 0 || settings.noiseColor > 0 || settings.sharpenAmount > 0
  }

  static func detailRGB(luma: Float, cb: Float, cr: Float) -> RGB {
    let r = cr + luma, b = cb + luma, g = (luma - 0.2126 * r - 0.0722 * b) / 0.7152
    return RGB(r, g, b)
  }

  static func detail(_ p: inout [RGB], _ w: Int, _ h: Int, _ s: CameraRawSettings) throws {
    let detail = DetailSettings(s)
    var y = p.map(M.luma), cb = p.indices.map { p[$0].z - y[$0] }, cr = p.indices.map { p[$0].x - y[$0] }
    if s.noiseLuminance > 0 {
      let sm = try M.guided(y, y, w, h, detail.luminanceRadius, detail.luminanceEpsilon)
      for i in y.indices { y[i] = sm[i] + (y[i] - sm[i]) * detail.luminanceKeep }
    }
    if s.noiseColor > 0 {
      let b = try M.gaussian(cb, w, h, detail.colorSigma), r = try M.gaussian(cr, w, h, detail.colorSigma)
      for i in cb.indices {
        cb[i] = b[i] + (cb[i] - b[i]) * detail.colorKeep
        cr[i] = r[i] + (cr[i] - r[i]) * detail.colorKeep
      }
    }
    if s.sharpenAmount > 0 {
      let blur = try M.gaussian(y, w, h, detail.sharpenSigma)
      let mask = s.sharpenMasking > 0 ? try M.gaussian(y, w, h, detail.maskSigma) : y
      try mask.withUnsafeBufferPointer { mask in
        for py in 0..<h {
          try Task.checkCancellation()
          for px in 0..<w {
            let i = py * w + px
            y[i] = detail.sharpen(y[i], blurred: blur[i], index: i, width: w, height: h, mask: mask)
          }
        }
      }
    }
    for i in p.indices {
      if i % w == 0 { try Task.checkCancellation() }
      p[i] = detailRGB(luma: y[i], cb: cb[i], cr: cr[i])
    }
  }

  static func effects(_ p: inout [RGB], _ w: Int, _ h: Int, _ s: CameraRawSettings,
    canvasHeight: Int, top: Int) throws {
    guard s.vignetteAmount != 0 || s.grainAmount != 0 else { return }
    let cx = Float(w)/2, cy = Float(canvasHeight)/2, round = s.vignetteRoundness/100
    let radius = min(cx,cy)+(max(cx,cy)-min(cx,cy))*(1-max(0,round))
    let ax = round >= 0 && cx >= cy ? radius : cx, ay = round >= 0 && cy > cx ? radius : cy
    let power = 2+max(-round,0)*6, inner = 1-s.vignetteMidpoint/100*0.8, feather = s.vignetteFeather/100
    let edge0 = inner-feather*0.5*inner, edge1 = inner+feather*0.5*(1.4-inner)+0.02
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let absoluteY = y + top
      let i = y*w+x; var c = p[i]
      if s.vignetteAmount != 0 {
        let dx = abs((Float(x)+0.5-cx)/ax), dy = abs((Float(absoluteY)+0.5-cy)/ay)
        let r = pow(pow(dx,power)+pow(dy,power),1/power), m = M.smooth(edge0,edge1,r), amount = s.vignetteAmount/100
        if s.vignetteStyle == "paintOverlay" { c += (RGB(repeating:amount < 0 ? 0 : 1)-c)*(m*abs(amount)) }
        else {
          var k = pow(2,amount*2*m)
          if amount < 0 { k += (1-k)*M.smooth(0.6,1,M.luma(c))*s.vignetteHighlights/100 }
          if s.vignetteStyle == "colorPriority" { c += RGB(repeating:M.luma(c)*(k-1)) } else { c *= k }
        }
      }
      if s.grainAmount > 0 {
        let cell = (1+s.grainSize/25)*s.pixelScale, fx = Float(x)/cell, fy = Float(absoluteY)/cell, rough = s.grainRoughness/100
        let n = M.noise(fx,fy,s.seed)*(1-rough)+M.noise(fx*2.3,fy*2.3,s.seed &+ 7)*rough, l = unit(M.luma(c))
        c += RGB(repeating:(n-0.5)*2*s.grainAmount/100*0.12*(0.4+2.4*l*(1-l)))
      }
      p[i] = c
    } }
  }
  struct HazeModel {
    let width: Int
    let height: Int
    let scale: Float
    let airlight: RGB
    let transmission: [Float]

    func corrected(_ pixel: RGB, x: Int, y: Int, amount: Float) -> RGB {
      let t = min(1, max(0.1, M.sample(transmission, width, height,
        (Float(x) + 0.5) / scale - 0.5, (Float(y) + 0.5) / scale - 0.5)))
      if amount > 0 { return pixel + ((pixel - airlight) / t + airlight - pixel) * amount }
      return pixel + (airlight - pixel) * (-amount) * 0.5 * (1 - t * 0.5)
    }
  }

  static func estimateHaze(width w: Int, height h: Int, pixel: (Int) -> RGB) throws -> HazeModel {
    let scale = max(1,(max(w,h)+767)/768), sw = (w+scale-1)/scale, sh = (h+scale-1)/scale
    var small = [RGB](repeating:.zero,count:sw*sh)
    for y in 0..<sh { try Task.checkCancellation(); for x in 0..<sw {
      var c = RGB.zero; var count: Float = 0
      for py in y*scale..<min(h,(y+1)*scale) { for px in x*scale..<min(w,(x+1)*scale) { let v = pixel(py*w+px); c += RGB(unit(v.x),unit(v.y),unit(v.z)); count += 1 } }
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
    return HazeModel(width: sw, height: sh, scale: Float(scale), airlight: air, transmission: trans)
  }

  static func dehaze(_ pixels: [RGB], _ w: Int, _ h: Int, _ amount: Float) throws -> [RGB] {
    let model = try estimateHaze(width: w, height: h, pixel: { pixels[$0] })
    var corrected = pixels
    for y in 0..<h {
      try Task.checkCancellation()
      for x in 0..<w {
        let i = y * w + x
        corrected[i] = model.corrected(pixels[i], x: x, y: y, amount: amount)
      }
    }
    return corrected
  }
}
