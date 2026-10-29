import Foundation

extension HDRMergeMath {
  /// PhotoCraft's four tone operators. Result is encoded sRGB; alpha is retained.
  public static func toneMap(_ pixels: [Sample],width w: Int,height h: Int,settings s: HDRMergeSettings) throws -> [Sample] {
    guard w > 0,h > 0,pixels.count == w*h else { throw CraftError.invalid("Invalid tone-map dimensions.") }
    var validation = s;validation.exposureSource = .estimate;validation.ghostBase = nil;try validation.validate(count:2);try Task.checkCancellation()
    let visible = pixels.filter{$0.w > 0},n = max(1,visible.count)
    let mean = Float(exp(visible.reduce(0.0){$0+log(Double(max(1e-6,luma($1))))}/Double(n)))
    var out = pixels
    switch s.method {
    case .exposureGamma:
      let k = pow(Float(2),s.exposure)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let i = y*w+x;for c in 0..<3 { out[i][c] = pow(SRGBTransfer.encoded(unit(pixels[i][c]*k)),1/s.gamma) } } }
    case .highlightCompression:
      let k = 0.18/max(1e-6,mean)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let i = y*w+x,l = luma(pixels[i])*k,ld = l/(1+l),r = l > 1e-9 ? ld/l*k:0
        for c in 0..<3 { out[i][c] = SRGBTransfer.encoded(unit(pixels[i][c]*r)) }
      } }
    case .equalizeHistogram:
      let lv = pixels.map{log(max(1e-7,luma($0)))},valid = pixels.indices.filter{pixels[$0].w > 0}
      let lo = valid.map{lv[$0]}.min() ?? 0,hi = valid.map{lv[$0]}.max() ?? 0,span = max(1e-6,hi-lo)
      func bin(_ v: Float) -> Int { min(1023,max(0,Int(unit((v-lo)/span)*1023))) }
      var histogram = [Double](repeating:0,count:1024),cdf = [Float](repeating:0,count:1024),acc = 0.0
      for i in valid { histogram[bin(lv[i])] += 1 }
      for b in 0..<1024 { acc += histogram[b];cdf[b] = Float(acc/Double(n)) }
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let i = y*w+x,tl = SRGBTransfer.linear(cdf[bin(lv[i])]),l = max(1e-7,luma(pixels[i]))
        for c in 0..<3 { out[i][c] = SRGBTransfer.encoded(unit(pixels[i][c]/l*tl)) }
      } }
    case .localAdaptation:
      let k = 0.18/max(1e-6,mean);for i in out.indices { for c in 0..<3 { out[i][c] *= k } }
      let logl = out.map{log(max(0,luma($0))+1e-4)},base = try CameraRawMath.gaussian(logl,w,h,max(1,s.radius)/2)
      let bm = pixels.indices.filter{pixels[$0].w > 0}.reduce(Float(0)){$0+base[$1]}/Float(n),compress = 1/(1+s.strength),detail = 1+s.detail/100,exposure = pow(Float(2),s.exposure)
      for y in 0..<h { try Task.checkCancellation();for x in 0..<w { let i = y*w+x;guard out[i].w > 0 else { continue }
        let original = out[i],l0 = max(0,luma(original))+1e-4,newLog = bm+(base[i]-bm)*compress+(logl[i]-base[i])*detail
        var l1 = pow(max(0,exp(newLog)*exposure),s.gamma)
        l1 += s.shadows/100*pow(1-l1,3)*0.5-s.highlights/100*pow(l1,3)*0.5
        let ratio = unit(l1)/l0;var q = original;for c in 0..<3 { q[c] *= ratio }
        let ll = luma(q),hi = max(q.x,q.y,q.z),lo = min(q.x,q.y,q.z),sat = hi > 0 ? (hi-lo)/hi:0,strength = max(0,1+s.saturation/100+s.vibrance/100*(1-sat))
        for c in 0..<3 { out[i][c] = SRGBTransfer.encoded(unit(ll+(q[c]-ll)*strength)) }
      } }
    }
    return out
  }
}
