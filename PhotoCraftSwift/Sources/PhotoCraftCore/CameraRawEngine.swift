import Foundation

/// Nine-stage RGB development pipeline ported from the retained PhotoCraft Rust source.
public enum CameraRawEngine {
  typealias M = CameraRawMath
  typealias RGB = SIMD3<Float>
  public static func develop(_ source: Surface, settings s: CameraRawSettings, maximumPixels: Int = RasterFilterEngine.maximumPixels) throws -> Surface {
    try s.validate(); try Task.checkCancellation()
    guard (1...Surface.maxPixels).contains(maximumPixels), source.width <= maximumPixels/source.height else { throw CraftError.unsupported("Camera Raw exceeds its pixel budget.") }
    if s.isIdentity { return source }
    let w = source.width, h = source.height, n = w*h
    var pixels = [RGB](); pixels.reserveCapacity(n)
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let p = source.pixel(x:x,y:y)
      guard p.isFinite, max(abs(p.r),abs(p.g),abs(p.b)) <= 1e6 else { throw CraftError.invalid("Camera Raw input exceeds its numeric range.") }
      pixels.append(p.rgb)
    } }
    if s.temperature != 0 || s.tint != 0 || s.exposure != 0 {
      var gains = RGB(1+0.35*s.temperature/100,1-0.25*s.tint/100,1-0.35*s.temperature/100)
      gains *= pow(2,s.exposure)/M.luma(gains)
      for i in 0..<n {
        if i%w == 0 { try Task.checkCancellation() }
        for c in 0..<3 { pixels[i][c] = SRGBTransfer.encoded(max(0,SRGBTransfer.linear(pixels[i][c])*gains[c])) }
      }
    }
    if s.dehaze != 0 { pixels = try dehaze(pixels,w,h,s.dehaze/100) }
    if [s.contrast,s.highlights,s.shadows,s.whites,s.blacks,s.texture,s.clarity].contains(where: { $0 != 0 }) {
      let l = pixels.map { max(M.luma($0),0) }, lc = l.map { min($0,1) }, long = Float(max(w,h))
      let base = s.highlights != 0 || s.shadows != 0 ? try M.guided(lc,lc,w,h,max(2,Int(long*0.015)),0.02) : lc
      let clarity = s.clarity != 0 ? try M.guided(lc,lc,w,h,max(3,Int(long*0.02)),0.005) : lc
      let texture = s.texture != 0 ? try M.gaussian(lc,w,h,max(long*0.002,1.5*s.pixelScale)) : lc
      for i in 0..<n {
        if i%w == 0 { try Task.checkCancellation() }
        var v = lc[i]
        let hm = M.smooth(0.45,0.95,base[i]), sm = 1-M.smooth(0.05,0.5,base[i])
        v *= pow(2,s.highlights/100*1.2*hm+s.shadows/100*1.4*sm)
        let mid = 2*unit(v)-1
        v += s.clarity/100*0.8*(lc[i]-clarity[i])*(1-mid*mid)
        v += s.texture/100*0.9*min(0.1,max(-0.1,lc[i]-texture[i]))
        v += s.whites/100*0.25*M.smooth(0.4,1,v)
        v += s.blacks/100*0.15*(1-M.smooth(0,0.45,v))
        v -= s.contrast/100*0.6*sin(2*Float.pi*unit(v))/(2*Float.pi)
        v = max(0,v)+(l[i]-lc[i])
        if l[i] > 1e-5 { pixels[i] *= v/l[i] } else { pixels[i] += RGB(repeating:v-l[i]) }
      }
    }
    try color(&pixels,s,w)
    if s.sharpenAmount != 0 || s.noiseLuminance != 0 || s.noiseColor != 0 { try detail(&pixels,w,h,s) }
    try effects(&pixels,w,h,s)
    var result = source
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let p = pixels[y*w+x], alpha = source.pixel(x:x,y:y).a
      guard p.x.isFinite,p.y.isFinite,p.z.isFinite else { throw CraftError.invalid("Nonfinite Camera Raw result.") }
      result.setPixel(x:x,y:y,Pixel(p.x,p.y,p.z,alpha))
    } }
    return result
  }
  static func color(_ p: inout [RGB],_ s: CameraRawSettings,_ w: Int) throws {
    let master = M.curve(s.pointCurve), channels = [M.curve(s.pointCurveRed),M.curve(s.pointCurveGreen),M.curve(s.pointCurveBlue)]
    let splits = [Float(0)] + s.curveSplits.map { $0/100 } + [1]
    let amounts = [s.curveShadows,s.curveDarks,s.curveLights,s.curveHighlights]
    var parametric = (0..<1024).map { Float($0)/1023 }
    for i in parametric.indices {
      let x = parametric[i]; var v = x
      for j in 0..<4 { let center = (splits[j]+splits[j+1])/2, width = max(0.1,splits[j+1]-splits[j]), d = (x-center)/width
        v += amounts[j]/100*0.25*exp(-d*d*2)*x*(1-x)*4
      }
      parametric[i] = max(i > 0 ? parametric[i-1] : 0,unit(v))
    }
    let hasCurves = amounts.contains { $0 != 0 } || [s.pointCurve,s.pointCurveRed,s.pointCurveGreen,s.pointCurveBlue].contains { !$0.isEmpty }
    let mixer = [s.hslHue,s.hslSat,s.hslLum].joined().contains { $0 != 0 }
    let centers: [Float] = [0,30,60,120,180,240,270,300,360]
    let wheels = [s.gradeShadows,s.gradeMidtones,s.gradeHighlights,s.gradeGlobal]
    let grading = wheels.contains { $0.sat != 0 || $0.lum != 0 }
    let tints = wheels.map { v -> RGB in let c = M.rgb(v.hue,1,1); return (c-RGB(repeating:M.luma(c)))*(v.sat/100*0.3) }
    for i in p.indices {
      if i%w == 0 { try Task.checkCancellation() }
      var c = p[i]
      if s.vibrance != 0 || s.saturation != 0 {
        let hsv = M.hsv(c), l = M.luma(c), skin = max(0,1-abs(hsv.x-25)/25)*0.5
        let k = max(0,1+s.saturation/100+s.vibrance/100*(1-hsv.y)*(1-skin))
        c = RGB(repeating:l)+(c-RGB(repeating:l))*k
      }
      if hasCurves { for j in 0..<3 { c[j] = M.lut(channels[j],M.lut(master,M.lut(parametric,c[j]))) } }
      if mixer {
        let hsv = M.hsv(c), j = min(7,(0..<8).first { hsv.x < centers[$0+1] } ?? 7), k = (j+1)%8
        let t = (hsv.x-centers[j])/(centers[j+1]-centers[j])
        let dh = s.hslHue[j]*(1-t)+s.hslHue[k]*t, ds = s.hslSat[j]*(1-t)+s.hslSat[k]*t, dl = s.hslLum[j]*(1-t)+s.hslLum[k]*t
        var adjusted = M.rgb(hsv.x+dh/100*30,unit(hsv.y*(1+ds/100)),hsv.z)
        let l = M.luma(adjusted); if l > 1e-6 { adjusted *= M.luma(c)/l }
        c = adjusted*pow(2,dl/100*hsv.y)
      }
      if grading {
        let l = unit(M.luma(c)), blend = 0.15+s.gradeBlending/100*0.35, bal = s.gradeBalance/100*0.25
        let sh = 1-M.smooth(0,0.5+bal+blend,l), hi = M.smooth(0.5+bal-blend,1,l)
        let masks = [sh,max(0,1-sh-hi),hi,1]
        for j in 0..<4 { c += tints[j]*masks[j]; c *= pow(2,masks[j]*wheels[j].lum/100*0.6) }
      }
      p[i] = c
    }
  }
}
