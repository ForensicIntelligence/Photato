import Foundation

/// Nine-stage RGB development pipeline ported from the retained PhotoCraft Rust source.
public enum CameraRawEngine {
  typealias M = CameraRawMath
  typealias RGB = SIMD3<Float>
  public static func develop(_ source: Surface, settings s: CameraRawSettings, maximumPixels: Int = RasterFilterEngine.maximumPixels) throws -> Surface {
    try s.validate(); try Task.checkCancellation()
    guard (1...Surface.maxPixels).contains(maximumPixels), source.width <= maximumPixels/source.height else { throw CraftError.unsupported("Camera Raw exceeds its pixel budget.") }
    if s.isIdentity { return source }
    if source.width * source.height > Surface.maximumDensePixels {
      return try developPaged(source, settings: s)
    }
    return try developBand(source, settings: s, canvasHeight: source.height, top: 0)
  }

  private static func developBand(_ source: Surface, settings s: CameraRawSettings,
    canvasHeight: Int, top: Int) throws -> Surface {
    let adjustsLightGains = s.temperature != 0 || s.tint != 0 || s.exposure != 0
    if adjustsLightGains, source.colorEncoding == .sRGB, source.depth != .f32,
      usesOnlyLightGains(s) {
      return try applyLightGains(source, gains: lightGains(s))
    }
    var pixels = try prepareRGB(source, settings: s)
    if hasDetailAdjustments(s) { try detail(&pixels, source.width, source.height, s) }
    return try finishBand(&pixels, source: source, settings: s, canvasHeight: canvasHeight, top: top)
  }

  static func exposedRGB(_ source: Surface, settings s: CameraRawSettings) throws -> [RGB] {
    let adjustsLightGains = s.temperature != 0 || s.tint != 0 || s.exposure != 0
    let w = source.width, h = source.height, n = w*h
    var pixels = [RGB](); pixels.reserveCapacity(n)
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let p = source.pixel(x:x,y:y)
      guard p.isFinite, max(abs(p.r),abs(p.g),abs(p.b)) <= 1e6 else { throw CraftError.invalid("Camera Raw input exceeds its numeric range.") }
      pixels.append(p.rgb)
    } }
    if adjustsLightGains {
      let gains = lightGains(s)
      for i in 0..<n {
        if i%w == 0 { try Task.checkCancellation() }
        for c in 0..<3 { pixels[i][c] = adjustedLightSample(pixels[i][c], gain: gains[c]) }
      }
    }
    return pixels
  }

  static func prepareRGB(_ source: Surface, settings s: CameraRawSettings) throws -> [RGB] {
    let w = source.width, h = source.height
    var pixels = try exposedRGB(source, settings: s)
    if s.dehaze != 0 { pixels = try dehaze(pixels, w, h, s.dehaze / 100) }
    if usesBaseTone(s) {
      let luma = pixels.map { max(M.luma($0), 0) }, clipped = luma.map { min($0, 1) }
      let longSide = Float(max(w, h))
      let base = usesLocalLight(s)
        ? try M.guided(clipped, clipped, w, h, localLightRadius(longSide), 0.02) : clipped
      let clarity = s.clarity != 0
        ? try M.guided(clipped, clipped, w, h, localClarityRadius(longSide), 0.005) : clipped
      let texture = s.texture != 0 ? try M.gaussian(clipped, w, h, localTextureSigma(longSide, s)) : clipped
      for i in pixels.indices {
        if i % w == 0 { try Task.checkCancellation() }
        pixels[i] = tonedPixel(pixels[i], luma: luma[i], clipped: clipped[i], base: base[i],
          clarity: clarity[i], texture: texture[i], settings: s)
      }
    }
    try color(&pixels, s, w)
    return pixels
  }

  static func finishBand(_ pixels: inout [RGB], source: Surface, settings: CameraRawSettings,
    canvasHeight: Int, top: Int) throws -> Surface {
    let w = source.width, h = source.height
    try effects(&pixels, w, h, settings, canvasHeight: canvasHeight, top: top)
    var result = source
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let p = pixels[y*w+x], alpha = source.pixel(x:x,y:y).a
      guard p.x.isFinite,p.y.isFinite,p.z.isFinite else { throw CraftError.invalid("Nonfinite Camera Raw result.") }
      result.setPixel(x:x,y:y,Pixel(p.x,p.y,p.z,alpha))
    } }
    return result
  }
  package static func developPaged(_ source: Surface, settings: CameraRawSettings) throws -> Surface {
    guard settings.dehaze == 0 else {
      throw CraftError.unsupported("Camera Raw Dehaze currently supports up to 36 megapixels.")
    }
    if hasDetailAdjustments(settings) { return try developPagedDetail(source, settings: settings) }
    if usesLocalTone(settings) { return try developPagedTone(source, settings: settings) }
    let paged = try Surface.PagedBuilder(width: source.width, height: source.height,
      depth: source.depth, fill: source.defaultPixel, colorEncoding: source.colorEncoding)
    let side = Surface.tileSide
    for y in stride(from: 0, to: source.height, by: side) {
      try Task.checkCancellation()
      let window = IntRect(x: 0, y: y, width: source.width, height: min(side, source.height - y))
      let band = try source.cropped(to: window)
      // The pointwise effects use absolute coordinates so their centers and
      // noise patterns agree across band boundaries.
      let developed = try developBand(band, settings: settings, canvasHeight: source.height, top: y)
      try paged.append(developed, atX: 0, atY: y)
    }
    return try paged.finish()
  }

  private static func usesOnlyLightGains(_ settings: CameraRawSettings) -> Bool {
    // Even a diagonal curve can apply a lookup and round or clamp its input.
    guard settings.pointCurve.isEmpty, settings.pointCurveRed.isEmpty,
      settings.pointCurveGreen.isEmpty, settings.pointCurveBlue.isEmpty else { return false }
    var remaining = settings
    remaining.temperature = 0
    remaining.tint = 0
    remaining.exposure = 0
    return remaining.isIdentity
  }

  private static func lightGains(_ settings: CameraRawSettings) -> RGB {
    var gains = RGB(1 + 0.35 * settings.temperature / 100, 1 - 0.25 * settings.tint / 100,
      1 - 0.35 * settings.temperature / 100)
    gains *= pow(2, settings.exposure) / M.luma(gains)
    return gains
  }

  private static func adjustedLightSample(_ sample: Float, gain: Float) -> Float {
    SRGBTransfer.encoded(max(0, SRGBTransfer.linear(sample) * gain))
  }

  private static func applyLightGains(_ source: Surface, gains: RGB) throws -> Surface {
    let levels = source.depth == .u8 ? 255 : 65_535
    let scale = Float(levels)
    var table: [RGB] = []
    if source.width * source.height >= 4 * (levels + 1) {
      table.reserveCapacity(levels + 1)
      for code in 0...levels {
        if code % 1024 == 0 { try Task.checkCancellation() }
        let sample = Float(code) / scale
        table.append(RGB(adjustedLightSample(sample, gain: gains.x),
          adjustedLightSample(sample, gain: gains.y), adjustedLightSample(sample, gain: gains.z)))
      }
    }
    func adjust(_ sample: Float, channel: Int) -> Float {
      if !table.isEmpty, (0...1).contains(sample) {
        let code = Int((sample * scale).rounded())
        // An old archive can retain floats outside the nominal integer grid.
        if (Float(code) / scale).bitPattern == sample.bitPattern { return table[code][channel] }
      }
      return adjustedLightSample(sample, gain: gains[channel])
    }
    let region = IntRect(x: 0, y: 0, width: source.width, height: source.height)
    return try source.compositingPixels(in: region) { _, _, pixel in
      guard pixel.isFinite, max(abs(pixel.r), abs(pixel.g), abs(pixel.b)) <= 1e6 else {
        throw CraftError.invalid("Camera Raw input exceeds its numeric range.")
      }
      return Pixel(adjust(pixel.r, channel: 0), adjust(pixel.g, channel: 1),
        adjust(pixel.b, channel: 2), pixel.a)
    }
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
