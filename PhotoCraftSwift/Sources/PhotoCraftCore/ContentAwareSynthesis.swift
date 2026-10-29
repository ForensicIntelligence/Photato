import Foundation

/// Port of PhotoCraft algo/content_aware.rs; uses the existing native PatchMatch and membrane solvers.
public enum ContentAwareSynthesis {
  public static let maximumPixels = Inpainting.maxPixels
  private struct Variant { var w: Int; var h: Int; var image: [Float]; var usable: [Bool] }
  public static func fill(width w: Int,height h: Int,image: [Float],hole: [Bool],source: [Bool],settings: ContentAwareSettings,hdr: Bool = false) throws -> [Float] {
    let grid = Inpainting.Grid(w:w,h:h,ch:4,image:image,hole:hole)
    try Inpainting.validate(grid); try settings.validate()
    guard source.count == hole.count else { throw CraftError.invalid("Sampling area dimensions differ.") }
    guard hole.contains(true) else { return image }
    let usable = hole.indices.map { !hole[$0] && source[$0] && image[$0*4+3] > 0 }
    guard usable.contains(true) else { throw CraftError.invalid("No source pixels are available. Add to the sampling area.") }
    var extra: [Variant] = []
    var transforms: [(Double,Double,Bool)] = settings.mirror ? [(0,1,true)]:[]
    transforms += settings.rotation.angles.map { ($0,1,false) }
    if settings.scale { transforms += [(0,0.8,false),(0,1.25,false)] }
    let gap = 8
    var columnWidth = 0, columnHeight = 0
    for (angle,scale,mirror) in transforms {
      let rad = -angle * .pi/180, s = sin(rad), c = cos(rad)
      let ow = max(1,Int((Double(w)*scale*abs(c)+Double(h)*scale*abs(s)).rounded()))
      let oh = max(1,Int((Double(h)*scale*abs(c)+Double(w)*scale*abs(s)).rounded()))
      columnWidth = max(columnWidth,ow); columnHeight += oh+gap
      guard w+gap+columnWidth <= maximumPixels/max(h,columnHeight) else { throw CraftError.invalid("Sampling area with adaptation exceeds 4 megapixels. Use a smaller sampling region or fewer adaptations.") }
      var v = Variant(w:ow,h:oh,image:Array(repeating:0,count:ow*oh*4),usable:Array(repeating:false,count:ow*oh))
      for y in 0..<oh { try Task.checkCancellation(); for x in 0..<ow {
        let dx = (Double(x)-Double(ow-1)/2)/scale, dy = (Double(y)-Double(oh-1)/2)/scale
        var sx = Double(w-1)/2+dx*c-dy*s; let sy = Double(h-1)/2+dx*s+dy*c
        if mirror { sx = Double(w-1)-sx }
        guard sx >= 0, sy >= 0, sx <= Double(w-1), sy <= Double(h-1) else { continue }
        let x0 = Int(sx),y0 = Int(sy),x1 = min(w-1,x0+1),y1 = min(h-1,y0+1),tx = Float(sx-Double(x0)),ty = Float(sy-Double(y0))
        guard usable[y0*w+x0],usable[y0*w+x1],usable[y1*w+x0],usable[y1*w+x1] else { continue }
        let i = y*ow+x; v.usable[i] = true
        for k in 0..<4 { let a = image[(y0*w+x0)*4+k], b = image[(y0*w+x1)*4+k], c = image[(y1*w+x0)*4+k], d = image[(y1*w+x1)*4+k]
          v.image[i*4+k] = (a+(b-a)*tx)*(1-ty)+(c+(d-c)*tx)*ty
        }
      } }
      extra.append(v)
    }
    let mw = extra.isEmpty ? w:w+gap+columnWidth, mh = max(h,columnHeight)
    guard mw <= maximumPixels/mh else { throw CraftError.invalid("Content-Aware Fill sampling region exceeds 4 megapixels.") }
    var mosaic = [Float](repeating:0,count:mw*mh*4), unknown = [Bool](repeating:true,count:mw*mh)
    func copy(_ values: [Float],_ known: [Bool],_ width: Int,_ height: Int,_ ox: Int,_ oy: Int) throws {
      for y in 0..<height { try Task.checkCancellation(); for x in 0..<width {
        let src = y*width+x, dst = (y+oy)*mw+x+ox; unknown[dst] = !known[src]
        for c in 0..<4 { mosaic[dst*4+c] = values[src*4+c] }
      } }
    }
    try copy(image,usable,w,h,0,0); var y = 0
    for v in extra { try copy(v.image,v.usable,v.w,v.h,w+gap,y); y += v.h+gap }
    var p = Inpainting.Parameters(); p.seed = UInt64(settings.seed)
    let completed = try Inpainting.complete(width:mw,height:mh,channels:4,image:mosaic,hole:unknown,parameters:p)
    var out = image
    if let completed {
      for y in 0..<h { try Task.checkCancellation(); for x in 0..<w where hole[y*w+x] {
        for c in 0..<4 { out[(y*w+x)*4+c] = completed[(y*mw+x)*4+c] }
      } }
    } else {
      // Respect custom exclusions even when no complete patch is available.
      let fallback = try Inpainting.membrane(.init(w:w,h:h,ch:4,image:image,hole:usable.map { !$0 }))
      for i in hole.indices where hole[i] { for c in 0..<4 { out[i*4+c] = fallback[i*4+c] } }
    }
    if settings.colorAdaptation.amount > 0, let box = Inpainting.bbox(w,h,hole) {
      let smooth = try Inpainting.membrane(grid), radius = min(32,max(1,max(box.width,box.height)/6))
      let low = try blur(out,w:w,h:h,r:radius), amount = settings.colorAdaptation.amount
      for y in 0..<h { try Task.checkCancellation(); for x in 0..<w where hole[y*w+x] {
        for c in 0..<4 {
          let i = (y*w+x)*4+c, value = out[i]+amount*(smooth[i]-low[i])
          out[i] = hdr && c < 3 ? value:unit(value)
        }
      } }
    }
    guard out.allSatisfy(\.isFinite) else { throw CraftError.invalid("Content-Aware Fill produced non-finite pixels.") }
    return out
  }
  private static func blur(_ input: [Float],w: Int,h: Int,r: Int) throws -> [Float] {
    func pass(_ src: [Float],horizontal: Bool) throws -> [Float] {
      var out = src; let lines = horizontal ? h:w, n = horizontal ? w:h
      func index(_ line: Int,_ at: Int,_ c: Int) -> Int { (horizontal ? line*w+min(n-1,max(0,at)):min(n-1,max(0,at))*w+line)*4+c }
      for line in 0..<lines { try Task.checkCancellation(); for c in 0..<4 {
        var sum: Float = 0
        for k in -r...r { sum += src[index(line,k,c)] }
        for k in 0..<n { out[index(line,k,c)] = sum/Float(2*r+1); sum += src[index(line,k+r+1,c)]-src[index(line,k-r,c)] }
      } }
      return out
    }
    return try pass(pass(input,horizontal:true),horizontal:false)
  }
}
