import Foundation

/// Native edge matting translated from PhotoCraft's algo/matting.rs.
public enum SelectionMatting {
  public static let maximumPixels = 8_388_608
  public static func checkSize(_ w: Int,_ h: Int) throws {
    guard w > 0, h > 0, w <= maximumPixels/h else { throw CraftError.invalid("Select and Mask supports up to 8,388,608 pixels.") }
  }
  public static func refine(_ mask: SelectionMask, guide: Surface, settings p: SelectionRefinement,
    edge: SelectionMask? = nil, excluded: SelectionMask? = nil) throws -> SelectionMask {
    try p.validate(); let w = mask.width, h = mask.height; try checkSize(w,h)
    guard guide.width == w, guide.height == h,
      [edge,excluded].allSatisfy({ $0 == nil || ($0!.width == w && $0!.height == h) }) else { throw CraftError.invalid("Refinement canvas sizes differ.") }
    try Task.checkCancellation()
    if p.neutral && edge?.bounds == nil { return mask }
    let input = mask.bytes.map { Float($0)/255 }; var result = input
    let radius = max(p.radius,edge?.bounds == nil ? 0 : 5)
    if radius > 0 {
      let r = min(64,max(1,Int(ceil(radius)))), halo = max(2*r+2,Int(ceil(radius))+2)
      for top in stride(from:0,to:h,by:256) { for left in stride(from:0,to:w,by:256) {
        try Task.checkCancellation()
        let x0 = max(0,left-halo), y0 = max(0,top-halo), x1 = min(w,left+256+halo), y1 = min(h,top+256+halo)
        let tw = x1-x0, th = y1-y0
        var m = [Float](); m.reserveCapacity(tw*th)
        var rgb = [SIMD3<Float>](); rgb.reserveCapacity(tw*th)
        for y in y0..<y1 { for x in x0..<x1 { m.append(input[y*w+x]); let p = guide.pixel(x:x,y:y); rgb.append(SIMD3(min(1,max(0,p.r)),min(1,max(0,p.g)),min(1,max(0,p.b)))) } }
        var boundary = [Bool](repeating:false,count:tw*th)
        for y in 0..<th { for x in 0..<tw {
          let i = y*tw+x, a = m[i] >= 0.5
          boundary[i] = (x > 0 && (m[i-1] >= 0.5) != a) || (x+1 < tw && (m[i+1] >= 0.5) != a)
            || (y > 0 && (m[i-tw] >= 0.5) != a) || (y+1 < th && (m[i+tw] >= 0.5) != a)
        } }
        let distance = try MattingFilters.distance(boundary,tw,th)
        let q = try MattingFilters.guided(rgb,m,tw,th,r)
        let widths = p.smartRadius ? try MattingFilters.edgeWidths(rgb,tw,th,r) : nil
        for y in top..<min(h,top+256) { for x in left..<min(w,left+256) {
          let i = y*w+x, j = (y-y0)*tw+x-x0
          let local = widths.map { min(Float(radius),max(1.5,$0[j])) } ?? Float(radius)
          var k = min(1,max(0,local+1-distance[j]))
          // Manual refinement extends the band; erase protects the original edge.
          if let edge { k = max(k,Float(edge.bytes[i])/255) }
          if let excluded { k *= 1-Float(excluded.bytes[i])/255 }
          result[i] = min(1,max(0,m[j]+(q[j]-m[j])*k))
        } }
      } }
    }
    if p.smooth > 0 {
      let sigma = Float(p.smooth/100*4)
      result = try MattingFilters.gaussian(result,w,h,sigma).map { min(1,max(0,($0-0.5)*(1+sigma)+0.5)) }
    }
    if p.feather > 0 { result = try MattingFilters.gaussian(result,w,h,Float(p.feather/2)) }
    if p.contrast > 0 {
      let gain = Float(1/(1-0.99*p.contrast/100)); result = result.map { min(1,max(0,($0-0.5)*gain+0.5)) }
    }
    let shift = Int((p.shiftEdge/100*max(p.radius,4)).rounded())
    if shift != 0 { result = try MattingFilters.morph(result,w,h,min(64,abs(shift)),grow:shift > 0) }
    return try SelectionMask(width:w,height:h,bytes:result.map { UInt8(min(255,max(0,($0*255).rounded()))) })
  }
  public static func decontaminate(_ source: Surface, mask: SelectionMask, settings p: SelectionRefinement) throws -> Surface {
    try p.validate(); try checkSize(source.width,source.height)
    guard source.width == mask.width, source.height == mask.height else { throw CraftError.invalid("Decontamination sizes differ.") }
    guard p.decontaminate && p.amount > 0 else { return source }
    let w = source.width, h = source.height, n = w*h
    var pixels = [Pixel](); pixels.reserveCapacity(n)
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w { pixels.append(source.depth == .f32 ? source.linearPixel(x:x,y:y) : source.pixel(x:x,y:y)) } }
    let weights = (0..<n).map { mask.bytes[$0] >= 250 ? pixels[$0].a : 0 }
    let radius = max(3,Int(ceil(p.radius)))
    let nearW = try MattingFilters.box(weights,w,h,radius), farW = try MattingFilters.box(weights,w,h,radius*4)
    let near = try (0..<3).map { c in try MattingFilters.box((0..<n).map { pixels[$0].rgb[c]*weights[$0] },w,h,radius) }
    let far = try (0..<3).map { c in try MattingFilters.box((0..<n).map { pixels[$0].rgb[c]*weights[$0] },w,h,radius*4) }
    var out = source
    for y in 0..<h { try Task.checkCancellation(); for x in 0..<w {
      let i = y*w+x, a = Float(mask.bytes[i])/255
      guard a > 0.02, a < 0.98 else { continue }
      let den = nearW[i] > 1e-5 ? nearW[i] : farW[i]
      guard den > 1e-5 else { continue }
      let values = nearW[i] > 1e-5 ? near : far
      let k = min(1,Float(p.amount/100)*(1-a)*4)
      let old = pixels[i], rgb = old.rgb*(1-k)+SIMD3(values[0][i],values[1][i],values[2][i])*(k/den)
      let pixel = Pixel(rgb.x,rgb.y,rgb.z,old.a)
      if source.depth == .f32 { out.setLinearPixel(x:x,y:y,pixel) } else { out.setPixel(x:x,y:y,pixel) }
    } }
    return out
  }
}
